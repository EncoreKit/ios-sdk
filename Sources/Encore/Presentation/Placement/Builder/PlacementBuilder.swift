// Placement builder — fluent API for presenting offers.
// Lives in Presentation/ because it coordinates UI presentation.
// Async-first: delegates directly to OfferSheetCoordinator.present(placementId:).

import Foundation

// MARK: - Public Protocol

/// Fluent builder for presenting Encore offers.
/// Create via `Encore.placement(_:)` and call `show()` to present.
/// Main-actor isolated, like the ``Encore`` facade — build and show from UI code.
@MainActor
public protocol PlacementBuilderProtocol {
    var id: String { get }
    /// Presents the placement and returns the outcome. **Never throws** —
    /// failures arrive as `.notPresented(.error(…))`.
    func show() async -> PresentationResult
    /// Fire-and-forget present, then run `resume` on the main actor once the flow completes, with the PresentationResult. Delivers **every** outcome, including `.notPresented`.
    func show(resume: @escaping @Sendable (PresentationResult) -> Void)
    func onLoadingStateChange(_ callback: @escaping @Sendable (Bool) -> Void) -> Self

    /// Selects the use case this presentation belongs to. Defaults to `.reduceChurn`.
    ///
    /// ```swift
    /// Encore.shared.placement("streak_complete").useCase(.rewardUsers).show()
    /// ```
    func useCase(_ useCase: UseCase) -> Self

    /// Overrides the sheet's headline for this presentation.
    ///
    /// The full string is passed through as-is — the SDK never composes copy.
    /// Priority is SDK override → backend value → shipped template default.
    /// An empty string is ignored so it can't blank the shipped copy.
    func headline(_ text: String) -> Self

    /// Overrides the sheet's subheadline for this presentation.
    /// Same priority and empty-string rules as ``headline(_:)``.
    func subheadline(_ text: String) -> Self
}

public extension PlacementBuilderProtocol {
    func show(resume: @escaping @Sendable (PresentationResult) -> Void) {
        Task { @MainActor in
            let result = await show()
            Logger.debug(.presentation, "resume firing with \(result)")
            resume(result)
        }
    }
}

// MARK: - Internal Implementation

@MainActor
internal struct PlacementBuilder: PlacementBuilderProtocol {

    internal private(set) var id: String

    private var selectedUseCase: UseCase = .reduceChurn
    private var headlineOverride: String?
    private var subheadlineOverride: String?

    private var onLoadingStateChangeCallback: (@Sendable (Bool) -> Void)?

    internal init(id: String) {
        self.id = id
    }

    // MARK: - Present

    func show() async -> PresentationResult {
        // Outcome is delivered via the returned PresentationResult / show(resume:).
        Logger.debug(.presentation, "show(\(id)) — presenting")
        onLoadingStateChangeCallback?(true)
        defer { onLoadingStateChangeCallback?(false) }

        let result = await OfferSheetCoordinator.present(
            placementId: id,
            useCase: selectedUseCase,
            copyOverrides: copyOverrides
        )
        Logger.info(.presentation, "show(\(id)) → \(result) | advertiser=\(String(describing: result.advertiser)) publisher=\(String(describing: result.publisher))")
        return result
    }

    // MARK: - Builder Methods

    func useCase(_ useCase: UseCase) -> PlacementBuilder {
        var copy = self
        copy.selectedUseCase = useCase
        return copy
    }

    func headline(_ text: String) -> PlacementBuilder {
        var copy = self
        copy.headlineOverride = text
        return copy
    }

    func subheadline(_ text: String) -> PlacementBuilder {
        var copy = self
        copy.subheadlineOverride = text
        return copy
    }

    func onLoadingStateChange(_ callback: @escaping @Sendable (Bool) -> Void) -> PlacementBuilder {
        var copy = self
        copy.onLoadingStateChangeCallback = callback
        return copy
    }

    // MARK: - Internal

    /// The use case this builder presents under.
    internal var resolvedUseCase: UseCase { selectedUseCase }

    /// Copy overrides keyed by the template variable each one replaces.
    ///
    /// Resolved at `show()` time rather than inside `headline(_:)` so the chain
    /// is order-independent: `.headline(…).useCase(.rewardUsers)` and
    /// `.useCase(.rewardUsers).headline(…)` produce the same map.
    internal var copyOverrides: [String: String] {
        var overrides: [String: String] = [:]
        if let headlineOverride, !headlineOverride.isEmpty {
            overrides[selectedUseCase.headlineVariable] = headlineOverride
        }
        if let subheadlineOverride, !subheadlineOverride.isEmpty {
            overrides[selectedUseCase.subheadlineVariable] = subheadlineOverride
        }
        return overrides
    }
}
