//
//  SheetDismissHandler.swift
//  Encore
//

import Foundation

/// Coordinates sheet dismiss events with result delivery.
/// Tracks whether dismiss was explicit (button tap) or implicit (swipe).
/// MainActor: Lives only during offer presentation, handles UI callbacks.
@MainActor
@available(iOS 17.0, *)
class SheetDismissHandler {
    private var completion: ((Result<PresentationResult, EncoreError>) -> Void)?
    private var pendingResult: Result<PresentationResult, EncoreError>?
    
    init(onCompletion: @escaping (Result<PresentationResult, EncoreError>) -> Void) {
        self.completion = onCompletion
    }
    
    /// Mark that dismiss is starting with a result, but don't fire yet
    func prepareDismiss(with result: Result<PresentationResult, EncoreError>) {
        pendingResult = result
    }
    
    /// Check if this is a swipe-to-dismiss (no pending result was explicitly set)
    var isSwipeDismiss: Bool {
        return pendingResult == nil
    }
    
    /// Fire completion after dismiss animation completes
    func handleOnDisappear() {
        guard let completion = completion else { return }
        let result = pendingResult ?? .success(.notGranted( .userSwipedDown))
        completion(result)
        self.completion = nil
        pendingResult = nil
    }
    
    /// Fire completion immediately (without waiting for dismiss)
    func handleImmediate(_ result: Result<PresentationResult, EncoreError>) {
        guard let completion = completion else { return }
        completion(result)
        self.completion = nil
    }
}

