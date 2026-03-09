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
/// Manages transitions between:
/// - Offers view (carousel of available offers)
/// - Credit claimed view (success confirmation)
///
/// This is a pure SwiftUI view with no UIKit dependencies. The UIKit window
/// management is handled by `PresentationWindow`.
@available(iOS 17.0, *)
struct OfferSheetContainer: View {
    
    // MARK: - Presentation State
    
    enum PresentationState: Identifiable {
        case offers
        case creditClaimed(amount: Double, result: Result<PresentationResult, EncoreError>)
        
        var id: String {
            switch self {
            case .offers: return "offers"
            case .creditClaimed: return "creditClaimed"
            }
        }
    }
    
    // MARK: - Properties
    
    let offerResponse: OfferResponse
    let userId: String
    let presentationId: String
    let placementId: String?
    let offerContext: OfferContext
    let initialStateOverride: String?
    let onCompletion: (Result<PresentationResult, EncoreError>) -> Void
    
    @State private var presentationState: PresentationState? = .offers
    @Environment(\.dismiss) var dismiss
    
    /// Presentation style from cached server config (pre-fetched on identify)
    private var presentationStyle: SDUIPresentationStyle {
        sduiConfigManager?.layout?.presentationStyle ?? .sheet
    }
    
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
                PresentationWindow.cleanup()
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
                offerContext: offerContext,
                initialStateOverride: initialStateOverride,
                onCompletion: { result in
                    handleOfferSheetCompletion(result)
                }
            )
            .ignoresSafeArea()
            
        case .creditClaimed(let amount, let result):
            CreditClaimedView(
                credit: CreditData(amount: amount),
                offerContext: offerContext
            ) {
                handleCreditClaimedDismiss(result: result)
            }
            .presentationDetents([.fraction(0.32)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(OfferSheetStyles.cornerRadius)
            .presentationBackground(OfferSheetStyles.backgroundColor)
        }
    }
    
    // MARK: - Handlers
    
    private func handleOfferSheetCompletion(_ result: Result<PresentationResult, EncoreError>) {
        onCompletion(result)
        dismiss()
    }
    
    private func handleCreditClaimedDismiss(result: Result<PresentationResult, EncoreError>) {
        dismiss()
    }
}

// MARK: - Supporting Types

struct CreditData: Identifiable {
    let id = UUID()
    let amount: Double
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
