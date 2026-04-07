//
//  OfferSheetView.swift
//  Encore
//
//  Unified offer sheet view that uses server-driven UI by default,
//  with hardcoded fallback layout when SDUI config is unavailable.
//

import SwiftUI

// MARK: - Main Sheet View

@available(iOS 17.0, *)
struct OfferSheetView: View {
    @StateObject private var viewModel: OfferSheetViewModel
    @StateObject private var sduiContext: SDUIContext
    @Environment(\.dismiss) var dismiss
    
    private let userId: String
    
    /// SDUI config from SDUIConfigurationManager (pre-fetched on identify)
    private var config: SDUIConfig? {
        sduiConfigManager?.layout
    }

    /// Computed property to determine the preferred color scheme based on appearance mode
    private var preferredColorScheme: ColorScheme? {
        switch viewModel.offerContext.appearanceMode {
        case .light:
            return .light
        case .dark:
            return .dark
        case .auto:
            return nil // Follow system settings
        }
    }

    private let initialStateOverride: String?
    private let placementId: String?

    init(
        offerResponse: OfferResponse,
        userId: String,
        presentationId: String,
        placementId: String? = nil,
        offerContext: OfferContext,
        initialStateOverride: String? = nil,
        entitlement: Entitlement = .freeTrial(value: 3, unit: .months),
        onCompletion: @escaping (Result<PresentationResult, EncoreError>) -> Void
    ) {
        self.userId = userId
        self.initialStateOverride = initialStateOverride
        self.placementId = placementId

        let handler = SheetDismissHandler(onCompletion: onCompletion)
        _viewModel = StateObject(wrappedValue: OfferSheetViewModel(
            offerResponse: offerResponse,
            userId: userId,
            presentationId: presentationId,
            placementId: placementId,
            offerContext: offerContext,
            entitlement: entitlement,
            completionHandler: handler
        ))
        
        // Create SDUI context with offer context (includes remote config + IAP data)
        _sduiContext = StateObject(wrappedValue: SDUIContext(
            offers: offerResponse.offerList,
            currentIndex: 0,
            offerContext: offerContext,
            onAction: { _, _ in } // Will be set up properly in onAppear
        ))
    }
    
    var body: some View {
        Group {
            if let loadedConfig = config {
                sduiContent(loadedConfig)
            } else {
                FallbackOfferSheetView(
                    viewModel: viewModel,
                    preferredColorScheme: preferredColorScheme,
                    isClaimDisabled: !sduiContext.isClaimEnabled,
                    onClose: {
                        viewModel.completionHandler.prepareDismiss(with: .success(.notGranted(.userTappedClose)))
                        dismiss()
                    },
                    onSafariEvent: viewModel.handleSafariTrackingEvent,
                    onSafariDismiss: viewModel.handleSafariDismiss
                )
            }
        }
        .onAppear {
            setupContext()
            
            // Set variant metadata for analytics
            viewModel.setVariantMetadata(
                variantId: sduiConfigManager?.variantId,
                context: sduiContext
            )
            
            // Initialize state machine if SDUI config available
            if let loadedConfig = config {
                let onEnterAction = sduiContext.initializeFromConfig(loadedConfig)
                
                // Apply state override if provided (e.g., from triggerIAPFirst success)
                if let stateOverride = initialStateOverride {
                    Logger.info("🔄 [SDUI] Applying initial state override: \(stateOverride)")
                    sduiContext.setState(stateOverride)
                } else if let onEnterAction = onEnterAction {
                    // Execute onEnter action for initial state (only if no override)
                    Logger.info("🚀 [SDUI] Executing onEnter action for initial state: \(sduiContext.currentState)")
                    handleAction(onEnterAction, offer: sduiContext.currentOffer)
                }
            }
            
            viewModel.trackOfferImpression(at: 0)
            viewModel.startTimeTracking()
        }
        .onDisappear {
            Logger.info("🔄 [SHEET] onDisappear fired")
            
            let dismissReason: OfferDismissReason
            if viewModel.offerWasClaimed {
                dismissReason = .offerClaimed
            } else if viewModel.completionHandler.isSwipeDismiss {
                dismissReason = .swipeDismiss
            } else {
                dismissReason = .closeButton
            }
            
            viewModel.trackOfferClose(reason: dismissReason)            
            viewModel.completionHandler.handleOnDisappear()
        }
    }
    
    // MARK: - SDUI Content
    
    @ViewBuilder
    private func sduiContent(_ loadedConfig: SDUIConfig) -> some View {
        ZStack(alignment: .top) {
            SDUIElementRenderer(element: loadedConfig.root, context: sduiContext)
        }
        .presentationDetents(detentsForCurrentState(loadedConfig))
        .applyCornerRadius(loadedConfig.cornerRadius)
        .presentationDragIndicator(loadedConfig.showDragIndicator == true ? .visible : .hidden)
        .presentationBackground(Color(UIColor.systemGroupedBackground))
        .interactiveDismissDisabled(false)
        .preferredColorScheme(preferredColorScheme)
        .sheet(item: $viewModel.safariWrapper) { wrapper in
            safariSheet(for: wrapper)
        }
        .onChange(of: sduiContext.currentIndex) { oldValue, newValue in
            viewModel.currentOfferIndex = newValue
            if let newIndex = newValue {
                viewModel.trackOfferSwipe(from: oldValue, to: newIndex)
                viewModel.trackOfferImpression(at: newIndex)
            }
        }
    }
    
    // MARK: - Context Setup
    
    private func setupContext() {
        sduiContext.isClaimEnabled = Encore.shared.placements.isClaimEnabled
        sduiContext.onAction = { [self] action, offer in
            handleAction(action, offer: offer)
        }
        sduiContext.onOfferVisible = { [self] index in
            viewModel.trackOfferImpression(at: index)
        }
    }
    
    private func handleAction(_ action: SDUIAction, offer: Offer?) {
        switch action.type {
        case .close:
            viewModel.completionHandler.prepareDismiss(with: .success(.notGranted(.userTappedClose)))
            dismiss()
        case .claimOffer:
            if let offer = offer {
                viewModel.handleOfferTap(offer)
            }
        case .openUrl:
            break
        case .setState, .setValue:
            break
        case .triggerIAP:
            handleTriggerIAP(action: action)
        }
    }

    
    // MARK: - Trigger IAP Handling
    
    private func handleTriggerIAP(action: SDUIAction) {
        // Prioritize remote config's iapProductId, fallback to user attributes
        let iapProductId = remoteConfigManager?.iapProductId ?? entitlementsManager?.userAttributes.iapProductId
        guard let iapProductId else {
            Logger.warn("🛒 [TriggerIAP] No iapProductId configured")
            return
        }

        Logger.info("🛒 [TriggerIAP] Triggering IAP for product: \(iapProductId)")

        Task {
            let purchaseSucceeded = await IAPClient.delegatePurchase(productId: iapProductId, placementId: placementId)

            await MainActor.run {
                if purchaseSucceeded {
                    Logger.info("✅ [TriggerIAP] Purchase successful!")

                    if let successState = action.onSuccessState {
                        Logger.info("🔄 [TriggerIAP] Transitioning to state: \(successState)")
                        sduiContext.setState(successState)
                    }
                } else {
                    Logger.info("🚫 [TriggerIAP] Purchase cancelled or failed")

                    if let cancelAction = action.onCancelAction {
                        if cancelAction == "close" {
                            Logger.info("🚪 [TriggerIAP] Closing sheet on cancel")
                            viewModel.completionHandler.prepareDismiss(with: .success(.notGranted(.dismissed)))
                            dismiss()
                        } else {
                            Logger.info("🔄 [TriggerIAP] Transitioning to cancel state: \(cancelAction)")
                            sduiContext.setState(cancelAction)
                        }
                    } else {
                        Logger.info("🚫 [TriggerIAP] No cancel action specified - staying on current screen")
                    }
                }
            }
        }
    }
    
    // MARK: - Detents
    
    private func detentsFromConfig(_ config: SDUIConfig) -> Set<PresentationDetent> {
        guard let detents = config.presentationDetents else {
            return [.fraction(0.48), .fraction(0.95)]
        }
        return Set(detents.map { PresentationDetent.fraction($0) })
    }
    
    private func detentsForCurrentState(_ config: SDUIConfig) -> Set<PresentationDetent> {
        let currentState = sduiContext.currentState
        
        if let stateDetents = config.stateDetents?[currentState] {
            return Set(stateDetents.map { PresentationDetent.fraction($0) })
        }
        
        return detentsFromConfig(config)
    }
    
    // MARK: - Safari Sheet
    
    private func safariSheet(for wrapper: SafariURLWrapper) -> some View {
        SafariView(url: wrapper.url) { event in
            viewModel.handleSafariTrackingEvent(event)
        }
        .presentationDetents([.fraction(0.95)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(OfferSheetStyles.safariCornerRadius)
        .interactiveDismissDisabled(false)
        .onDisappear {
            Logger.info("✅ Safari dismissed")
            viewModel.handleSafariDismiss()
        }
    }
}

// MARK: - View Extensions

@available(iOS 17.0, *)
private extension View {
    @ViewBuilder
    func applyCornerRadius(_ radius: CGFloat?) -> some View {
        if let radius = radius {
            self.presentationCornerRadius(radius)
        } else {
            self
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, *)
#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            Text("Offer Sheet Preview")
        }
}
