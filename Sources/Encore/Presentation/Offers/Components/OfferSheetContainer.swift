//
//  OfferSheetContainer.swift
//  Encore
//
//  SwiftUI container that hosts the offer sheet and manages presentation states.
//  Renamed from OfferSheetPresenter to avoid confusion with OfferPresenter.
//

import SwiftUI

/// Container view that hosts the offer sheet presentation flow.
///
/// This is a pure SwiftUI view with no UIKit dependencies. The UIKit window
/// management is handled by `PresentationWindow`.
@available(iOS 17.0, *)
struct OfferSheetContainer: View {
    
    // MARK: - Presentation State
    
    enum PresentationState: Identifiable {
        case offers

        var id: String { "offers" }
    }
    
    // MARK: - Properties
    
    let offerResponse: OfferResponse
    let userId: String
    let presentationId: String
    let placementId: String
    /// Publisher-chosen label, or nil when the placement id was auto-generated.
    /// The only placement value stamped on this presentation's analytics.
    let placementLabel: String?
    let offerContext: OfferContext
    /// Resolved once by the coordinator, for the life of this presentation.
    /// Read as a computed property it re-queried the config cache on every body
    /// pass, so a remote refresh could switch the mode under a mounted sheet.
    let presentationStyle: SDUIPresentationStyle
    /// The layout and variant resolved with `presentationStyle`, for the whole presentation.
    var layout: PresentationLayout? = nil

    let initialStateOverride: String?
    /// True when the IAP-first flow completed a real purchase before this
    /// sheet appeared — staged as the `.purchased` result floor.
    var initiallyPurchased: Bool = false
    let onCompletion: (Result<PresentationResult, EncoreError>) -> Void
    
    @State private var presentationState: PresentationState? = .offers
    @Environment(\.dismiss) var dismiss
    
    // MARK: - Body
    
    var body: some View {
        Color.clear
            .modifier(PresentationStyleModifier(
                presentationStyle: presentationStyle,
                presentationState: $presentationState,
                content: { state in
                    presentationContent(for: state)
                }
            ))
            .onDisappear {
                // Coordinator's complete() owns cleanup.
                #if DEBUG
                if PresentationWindow.isPresented {
                    Logger.warn(.presentation, "Window still present after onDisappear")
                }
                #endif
            }
    }
    
    // MARK: - Presentation Content
    
    @ViewBuilder
    private func presentationContent(for state: PresentationState) -> some View {
        switch state {
        case .offers:
            OfferSheetView(
                offerResponse: offerResponse,
                userId: userId,
                presentationId: presentationId,
                placementId: placementId,
                placementLabel: placementLabel,
                offerContext: offerContext,
                initialStateOverride: initialStateOverride,
                initiallyPurchased: initiallyPurchased,
                layout: layout,
                onCompletion: { result in
                    handleOfferSheetCompletion(result)
                }
            )
            // Direction follows the copy, not the host: a host not localized
            // for Arabic would otherwise lay served Arabic out left-to-right.
            .modifier(ServedLayoutDirectionModifier(locale: offerContext.servedLocale))
            // No global safe-area ignore here. Safe-area policy is owned by the
            // SDUI root in OfferSheetView (SDUIRootSafeAreaModifier): on
            // fullScreenCover the root bleeds so a full-bleed background fills
            // all four safe areas, and the CONTENT re-insets itself via the
            // per-element `style.safeAreaPadding`; on sheet, natural behavior is
            // kept. `respectsSafeArea: false` opts the whole tree out.
        }
    }
    
    // MARK: - Handlers
    
    private func handleOfferSheetCompletion(_ result: Result<PresentationResult, EncoreError>) {
        onCompletion(result)
        dismiss()
    }
}

// MARK: - Presentation Style Modifier

/// A ViewModifier that conditionally presents content as either a sheet or fullScreenCover
@available(iOS 17.0, *)
struct PresentationStyleModifier<PresentationContent: View>: ViewModifier {
    let presentationStyle: SDUIPresentationStyle
    @Binding var presentationState: OfferSheetContainer.PresentationState?
    let content: (OfferSheetContainer.PresentationState) -> PresentationContent
    
    func body(content baseContent: Content) -> some View {
        switch presentationStyle {
        case .sheet:
            baseContent
                .sheet(item: $presentationState) { state in
                    self.content(state)
                }
        case .fullScreenCover:
            baseContent
                .fullScreenCover(item: $presentationState) { state in
                    self.content(state)
                }
        }
    }
}
