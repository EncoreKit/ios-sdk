//
//  SDUIElementRenderer.swift
//  Encore
//
//  Recursive view renderer for Server-Driven UI elements
//

import SwiftUI
import AVKit

// MARK: - Main Element Renderer

@available(iOS 17.0, *)
struct SDUIElementRenderer: View {
    let element: SDUIElement
    @ObservedObject var context: SDUIContext
    var offer: Offer? = nil
    var isCurrentPage: Bool = false
    
    var body: some View {
        renderElement(element)
    }
    
    @ViewBuilder
    private func renderElement(_ element: SDUIElement) -> some View {
        switch element {
        case .text(let config):
            renderText(config)
        case .systemImage(let config):
            renderSystemImage(config)
        case .asyncImage(let config):
            renderAsyncImage(config)
        case .asyncVideo(let config):
            renderAsyncVideo(config)
        case .button(let config):
            renderButton(config)
        case .vStack(let config):
            renderVStack(config)
        case .hStack(let config):
            renderHStack(config)
        case .zStack(let config):
            renderZStack(config)
        case .spacer(let config):
            renderSpacer(config)
        case .shape(let config):
            renderShape(config)
        case .gradient(let config):
            renderGradient(config)
        case .scrollView(let config):
            renderScrollView(config)
        case .forEach(let config):
            renderForEach(config)
        case .conditional(let config):
            renderConditional(config)
        case .group(let config):
            renderGroup(config)
        case .compactPageIndicator:
            renderCompactPageIndicator()
        case .empty:
            EmptyView()
        }
    }
    
    // MARK: - Text Renderer
    
    /// Resolves a text binding using the item-specific offer (for forEach loops) or falls back to context
    private func resolveTextBinding(_ binding: SDUITextBinding) -> String {
        // If we have an item-specific offer (inside a forEach loop), use it for offer-related bindings
        if let itemOffer = offer {
            switch binding {
            case .offerAdvertiserName:
                return itemOffer.advertiserName ?? ""
            case .offerDescription:
                return itemOffer.creativeAdvertiserDescription ?? ""
            case .offerCtaText:
                return itemOffer.displayCtaText ?? "Get"
            default:
                // For non-offer bindings, fall back to context
                return context.resolveText(binding)
            }
        }
        // No item-specific offer, use context (which uses currentOffer)
        return context.resolveText(binding)
    }
    
    private func resolveText(_ config: SDUIText) -> String {
        // First, check for textMapKey (dynamic text from text maps)
        if let mapKey = config.textMapKey {
            let valueKey = config.textMapValueKey ?? mapKey
            if let resolvedText = context.resolveTextMap(mapKey: mapKey, valueKey: valueKey) {
                return resolvedText
            }
            // Fall back to static text if map lookup fails
        }
        
        // Check for text binding
        if let binding = config.textBinding {
            return resolveTextBinding(binding)
        }
        
        // Resolve template placeholders (${variableName}) in the text
        return context.resolveTemplateText(config.text)
    }
    
    private func renderText(_ config: SDUIText) -> some View {
        // Calculate effective line spacing from lineHeight or lineSpacing
        let effectiveLineSpacing = calculateLineSpacing(config)
        
        // If we have segments, render concatenated text
        if let segments = config.segments, !segments.isEmpty {
            return renderConcatenatedText(config, segments: segments)
                .lineSpacing(effectiveLineSpacing)
                .lineLimit(config.lineLimit)
                .multilineTextAlignment(config.multilineAlignment?.textAlignment ?? .leading)
                .modifier(SDUIStyleModifier(style: config.style))
        }
        
        // Standard single text rendering
        var text = Text(resolveText(config))
        
        if let font = config.font {
            text = Text(resolveText(config)).font(font.font)
        }
        
        return text
            .foregroundColor(config.color?.color ?? Color(UIColor.label))
            .lineSpacing(effectiveLineSpacing)
            .lineLimit(config.lineLimit)
            .multilineTextAlignment(config.multilineAlignment?.textAlignment ?? .leading)
            .modifier(SDUIStyleModifier(style: config.style))
    }
    
    /// Calculates effective line spacing from lineHeight multiplier or direct lineSpacing value
    /// lineHeight is a multiplier (e.g., 1.2 = 120% of font size), lineSpacing is in points
    private func calculateLineSpacing(_ config: SDUIText) -> CGFloat {
        // If lineHeight is provided, calculate spacing from font size
        if let lineHeight = config.lineHeight, let font = config.font {
            // lineHeight is a multiplier, so additional spacing = (lineHeight - 1.0) * fontSize
            // For example: lineHeight 1.2 with fontSize 16 = 0.2 * 16 = 3.2pt additional spacing
            let additionalSpacing = (lineHeight - 1.0) * font.size
            return max(0, additionalSpacing)
        }
        
        // Fall back to direct lineSpacing value
        return config.lineSpacing ?? 0
    }
    
    /// Renders concatenated text segments (like SwiftUI's Text + Text)
    private func renderConcatenatedText(_ config: SDUIText, segments: [SDUITextSegment]) -> Text {
        // Use the shared font from config as default
        let defaultFont = config.font?.font ?? .body
        let defaultColor = config.color?.color ?? Color(UIColor.label)
        
        var result = TemplateText("", context: context.offerContext).text
        
        for segment in segments {
            let segmentText = resolveSegmentText(segment)
            let font = segment.font?.font ?? defaultFont
            let color = segment.color?.color ?? defaultColor
            
            result = result + TemplateText(segmentText, context: context.offerContext).text
                .font(font)
                .foregroundColor(color)
        }
        
        return result
    }
    
    /// Resolves text from a segment, checking for bindings and substituting template placeholders
    private func resolveSegmentText(_ segment: SDUITextSegment) -> String {
        if let binding = segment.textBinding {
            return resolveTextBinding(binding)
        }
        // Resolve template placeholders (${variableName}) in the text
        return context.resolveTemplateText(segment.text)
    }
    
    // MARK: - System Image Renderer
    
    private func renderSystemImage(_ config: SDUISystemImage) -> some View {
        Image(systemName: config.systemName)
            .font(config.font?.font)
            .foregroundColor(config.color?.color)
            .modifier(SDUIStyleModifier(style: config.style))
    }
    
    // MARK: - Async Image Renderer
    
    private func resolveImageUrl(_ config: SDUIAsyncImage) -> String? {
        if let binding = config.urlBinding {
            return context.resolveCreativeUrl(binding, for: offer)
        }
        return config.url
    }
    
    private func renderAsyncImage(_ config: SDUIAsyncImage) -> some View {
        let url = URL(string: resolveImageUrl(config) ?? "")
        let contentMode = config.contentMode?.contentMode ?? .fit
        // Default aspect ratio for placeholder: 1412x596 = 2.369
        let aspectRatio: CGFloat? = config.aspectRatio ?? (contentMode == .fit ? 1412.0/596.0 : nil)
        let placeholderColor = config.placeholderColor?.color ?? Color(UIColor.tertiarySystemFill)
        
        return AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure, .empty:
                placeholderColor.aspectRatio(aspectRatio, contentMode: contentMode)
            @unknown default:
                placeholderColor.aspectRatio(aspectRatio, contentMode: contentMode)
            }
        }
        .modifier(SDUIStyleModifier(style: config.style))
    }
    
    // MARK: - Async Video Renderer
    
    private func resolveVideoUrl(_ config: SDUIAsyncVideo) -> String? {
        if let binding = config.urlBinding {
            return context.resolveCreativeUrl(binding, for: offer)
        }
        return config.url
    }
    
    private func renderAsyncVideo(_ config: SDUIAsyncVideo) -> some View {
        let urlString = resolveVideoUrl(config)
        let contentMode = config.contentMode ?? .fill
        
        return SDUIVideoPlayerView(urlString: urlString, contentMode: contentMode)
            .modifier(SDUIStyleModifier(style: config.style))
    }
    
    // MARK: - Button Renderer
    
    private func renderButton(_ config: SDUIButton) -> some View {
        let isClaimDisabled = config.action.type == .claimOffer && !context.isClaimEnabled
        let isDisabled = (config.disabled ?? false) || isClaimDisabled

        return Button(action: {
            handleAction(config.action)
        }) {
            SDUIElementRenderer(element: config.content, context: context, offer: offer)
                .modifier(SDUIStyleModifier(style: config.style))
                .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .opacity(isClaimDisabled ? 0.4 : 1.0)
    }
    
    /// Handle button actions - state machine actions are handled internally, others are delegated
    private func handleAction(_ action: SDUIAction) {
        // Track button tap analytics
        context.trackButtonTap(actionType: action.type)
        
        switch action.type {
        case .setState:
            // Handle setState action internally (also tracks state transition)
            if let newState = action.setState {
                context.setState(newState)
            }
        case .setValue:
            // Handle setValue action internally (also tracks value set)
            if let key = action.setValueKey, let value = action.setValueValue {
                context.setValue(key: key, value: value)
            }
        case .claimOffer:
            // Increment offers claimed counter for analytics
            context.incrementOffersClaimed()
            // Delegate to external handler
            context.onAction(action, offer ?? context.currentOffer)
        case .close, .openUrl, .triggerIAP:
            // Delegate to external handler
            context.onAction(action, offer ?? context.currentOffer)
        }
    }
    
    // MARK: - Stack Renderers
    
    private func renderVStack(_ config: SDUIStack) -> some View {
        VStack(
            alignment: config.alignment?.horizontalAlignment ?? .center,
            spacing: config.spacing ?? 0
        ) {
            ForEach(Array(config.children.enumerated()), id: \.offset) { _, child in
                SDUIElementRenderer(element: child, context: context, offer: offer, isCurrentPage: isCurrentPage)
            }
        }
        .modifier(SDUIStyleModifier(style: config.style))
    }
    
    @ViewBuilder
    private func renderHStack(_ config: SDUIStack) -> some View {
        let hasScrollTargetLayout = config.style?.scrollTargetLayout == true
        
        if hasScrollTargetLayout {
            HStack(
                alignment: config.alignment?.verticalAlignment ?? .center,
                spacing: config.spacing ?? 0
            ) {
                ForEach(Array(config.children.enumerated()), id: \.offset) { _, child in
                    SDUIElementRenderer(element: child, context: context, offer: offer, isCurrentPage: isCurrentPage)
                }
            }
            .scrollTargetLayout()
            .modifier(SDUIStyleModifier(style: config.style))
        } else {
            HStack(
                alignment: config.alignment?.verticalAlignment ?? .center,
                spacing: config.spacing ?? 0
            ) {
                ForEach(Array(config.children.enumerated()), id: \.offset) { _, child in
                    SDUIElementRenderer(element: child, context: context, offer: offer, isCurrentPage: isCurrentPage)
                }
            }
            .modifier(SDUIStyleModifier(style: config.style))
        }
    }
    
    private func renderZStack(_ config: SDUIStack) -> some View {
        ZStack(alignment: config.alignment?.alignment ?? .center) {
            ForEach(Array(config.children.enumerated()), id: \.offset) { _, child in
                SDUIElementRenderer(element: child, context: context, offer: offer, isCurrentPage: isCurrentPage)
            }
        }
        .modifier(SDUIStyleModifier(style: config.style))
    }
    
    // MARK: - Spacer Renderer
    
    @ViewBuilder
    private func renderSpacer(_ config: SDUISpacer) -> some View {
        if let minLength = config.minLength {
            Spacer(minLength: minLength)
        } else {
            Spacer()
        }
    }
    
    // MARK: - Shape Renderer
    
    @ViewBuilder
    private func renderShape(_ config: SDUIShape) -> some View {
        let fillColor = config.fillColor?.color ?? Color.clear
        
        switch config.type {
        case .rectangle:
            Rectangle().fill(fillColor).modifier(SDUIStyleModifier(style: config.style))
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: config.cornerRadius ?? 0).fill(fillColor).modifier(SDUIStyleModifier(style: config.style))
        case .circle:
            Circle().fill(fillColor).modifier(SDUIStyleModifier(style: config.style))
        case .capsule:
            Capsule().fill(fillColor).modifier(SDUIStyleModifier(style: config.style))
        }
    }
    
    // MARK: - Gradient Renderer
    
    private func renderGradient(_ config: SDUIGradient) -> some View {
        let colors = config.colors.map { stop in
            stop.color.color.opacity(stop.opacity ?? 1.0)
        }
        
        return LinearGradient(
            colors: colors,
            startPoint: config.direction.startPoint,
            endPoint: config.direction.endPoint
        )
        .modifier(SDUIStyleModifier(style: config.style))
        .allowsHitTesting(false)
    }
    
    // MARK: - ScrollView Renderer
    
    @ViewBuilder
    private func renderScrollView(_ config: SDUIScrollView) -> some View {
        let axis = config.axis?.axis ?? .vertical
        let scrollAxis = config.axis ?? .vertical
        let hasScrollTarget = config.scrollTargetBehavior != nil
        let hasContentMargins = config.contentMargins != nil
        
        // Build scroll view with conditional modifiers
        ScrollView(axis, showsIndicators: config.showsIndicators ?? true) {
            if hasScrollTarget {
                SDUIElementRenderer(element: config.content, context: context, offer: offer)
                    .scrollTargetLayout()
            } else {
                SDUIElementRenderer(element: config.content, context: context, offer: offer)
            }
        }
        .applyScrollTargetBehavior(config.scrollTargetBehavior)
        .applyContentMargins(config.contentMargins, axis: axis)
        .scrollPosition(id: Binding(
            get: { context.currentIndex },
            set: { newIndex in
                let previousIndex = context.currentIndex
                context.currentIndex = newIndex

                // Track scroll analytics and offer impression if position actually changed
                if let newIndex = newIndex, newIndex != previousIndex {
                    context.trackScroll(axis: scrollAxis, position: newIndex)
                    context.onOfferVisible?(newIndex)
                }
            }
        ))
        .modifier(SDUIStyleModifier(style: config.style))
    }
    
    // MARK: - ForEach Renderer
    
    @ViewBuilder
    private func renderForEach(_ config: SDUIForEach) -> some View {
        switch config.dataSource {
        case .offers:
            let limitedOffers = config.limit.map { Array(context.offers.prefix($0)) } ?? context.offers
            ForEach(Array(limitedOffers.enumerated()), id: \.element.id) { index, offerItem in
                SDUIElementRenderer(
                    element: config.itemTemplate,
                    context: context,
                    offer: offerItem,
                    isCurrentPage: context.currentIndex == index
                )
                .id(index)
            }
        case .pageIndicators:
            ForEach(0..<context.offers.count, id: \.self) { index in
                SDUIElementRenderer(
                    element: config.itemTemplate,
                    context: context,
                    offer: nil,
                    isCurrentPage: context.currentIndex == index
                )
            }
        }
    }
    
    // MARK: - Compact Page Indicator Renderer
    
    @ViewBuilder
    private func renderCompactPageIndicator() -> some View {
        CompactPageIndicator(
            totalPages: context.offers.count,
            currentPage: context.currentIndex ?? 0,
            activeColor: context.offerContext.accentColor.map { Color(hex: $0) } ?? OfferSheetStyles.accentBlue,
            inactiveColor: OfferSheetStyles.indicatorGray
        )
    }
    
    // MARK: - Conditional Renderer
    
    private func evaluateCondition(_ condition: SDUICondition) -> Bool {
        switch condition {
        case .hasMultipleOffers:
            return context.offers.count > 1
        case .isCurrentPage(let index):
            return context.currentIndex == index
        case .isCurrentPageBinding:
            return isCurrentPage
        // NEW: Generic state machine conditions
        case .stateEquals(let state):
            return context.isState(state)
        case .valueEquals(let key, let value):
            return context.valueEquals(key: key, value: value)
        case .hasValue(let key):
            return context.hasValue(key: key)
        }
    }
    
    @ViewBuilder
    private func renderConditional(_ config: SDUIConditional) -> some View {
        if evaluateCondition(config.condition) {
            SDUIElementRenderer(element: config.ifTrue, context: context, offer: offer, isCurrentPage: isCurrentPage)
        } else if let ifFalse = config.ifFalse {
            SDUIElementRenderer(element: ifFalse, context: context, offer: offer, isCurrentPage: isCurrentPage)
        }
    }
    
    // MARK: - Group Renderer
    
    private func renderGroup(_ config: SDUIGroup) -> some View {
        Group {
            SDUIElementRenderer(element: config.content, context: context, offer: offer, isCurrentPage: isCurrentPage)
        }
        .modifier(SDUIStyleModifier(style: config.style))
    }
}

// MARK: - Video Player View

/// Observable wrapper for AVPlayer with preloading support
@available(iOS 17.0, *)
private class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isReady = false
    
    private var loopObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var asset: AVAsset?
    
    func preload(urlString: String?) {
        guard asset == nil else { return }
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        
        // Create asset and start preloading playable status
        let videoAsset = AVURLAsset(url: url)
        self.asset = videoAsset
        
        // Preload essential properties asynchronously
        Task {
            do {
                // Load playable status to start buffering
                let isPlayable = try await videoAsset.load(.isPlayable)
                guard isPlayable else { return }
                
                await MainActor.run {
                    setupPlayer(with: videoAsset)
                }
            } catch {
                // Silently fail - video just won't play
            }
        }
    }
    
    @MainActor
    private func setupPlayer(with asset: AVAsset) {
        guard player == nil else { return }
        
        let playerItem = AVPlayerItem(asset: asset)
        // Buffer more content for smoother playback
        // 5 is in seconds; this duration provides a small pre-buffer to reduce stalls
        // while avoiding excessive memory/network usage for typical short-form content.
        playerItem.preferredForwardBufferDuration = 5
        
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .none
        
        // Observe when player is ready to play
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .readyToPlay {
                    self?.isReady = true
                }
            }
        }
        
        // Loop the video when it ends
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero)
            avPlayer?.play()
        }
        
        self.player = avPlayer
        avPlayer.play()
    }
    
    func cleanup() {
        statusObserver?.invalidate()
        statusObserver = nil
        
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        player?.pause()
        player = nil
        asset = nil
        isReady = false
    }
    
    deinit {
        cleanup()
    }
}

/// A looping, muted video player for SDUI with preloading
@available(iOS 17.0, *)
struct SDUIVideoPlayerView: View {
    let urlString: String?
    let contentMode: SDUIContentMode
    
    @StateObject private var viewModel = VideoPlayerViewModel()
    
    var body: some View {
        ZStack {
            Color(UIColor.tertiarySystemFill)
            
            if let player = viewModel.player {
                VideoPlayerLayer(player: player, videoGravity: contentMode == .fill ? .resizeAspectFill : .resizeAspect)
                    .opacity(viewModel.isReady ? 1 : 0)
            }
            
            // Show loading indicator while buffering
            if !viewModel.isReady {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .onAppear {
            viewModel.preload(urlString: urlString)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

/// UIViewRepresentable wrapper for AVPlayerLayer
@available(iOS 17.0, *)
private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity
    
    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.player = player
        view.videoGravity = videoGravity
        return view
    }
    
    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.player = player
        uiView.videoGravity = videoGravity
    }
}

/// Custom UIView that hosts an AVPlayerLayer and auto-resizes it
private class PlayerContainerView: UIView {
    private let playerLayer = AVPlayerLayer()
    
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
    
    var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(playerLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - TemplateText

/// A SwiftUI Text view that supports template placeholder substitution.
///
/// Use `${variableName}` syntax in text to reference values from `RemoteConfig`.
/// Returns a SwiftUI `Text` view, so all text modifiers work directly.
///
/// ## Available Variables
///
/// All `RemoteConfig` fields are available:
/// - `${titleText}`, `${subtitleText}`, `${offerDescriptionText}`
/// - `${instructionsTitleText}`, `${lastStepHeaderText}`, `${lastStepDescriptionText}`
/// - `${creditClaimedTitleText}`, `${creditClaimedSubtitleText}`, `${applyCreditsButtonText}`
/// - `${accentTitleText}`, `${accentTitleColor}`, `${accentColor}`
/// - `${appearanceMode}`
/// - `${entitlementValue}`, `${entitlementUnit}`, `${appName}`
/// - `${trialValue}`, `${trialUnit}` (convenience aliases - use IAP trial if available, else native entitlement)
///
/// IAP-specific variables (from StoreKit):
/// - `${subscriptionPrice}` - e.g., "$4.99"
/// - `${subscriptionName}` - Product display name
/// - `${subscriptionPeriod}` - e.g., "/month", "/year"
/// - `${trialValue}` - e.g., "7", "1", "3" (from IAP free trial)
/// - `${trialUnit}` - e.g., "days", "month" (from IAP free trial)
/// - `${trialDuration}` - e.g., "7 days", "1 month" (formatted from IAP free trial)
///
/// Note: When IAP has a free trial, `${trialValue}` and `${trialUnit}` will use the trial duration
/// from StoreKit, overriding any native entitlement configuration.
///
/// ## Example
///
/// ```swift
/// TemplateText("Get ${value} ${unit} of ${appName}", context: offerContext)
///     .foregroundColor(.blue)
///     .font(.headline)
/// // With IAP free trial: "Get 7 days of Spotify Premium"
/// // Without IAP: "Get 1 month of Spotify Premium" (from native config)
/// ```
internal struct TemplateText: View {
    /// The original template string with placeholders
    let template: String
    
    /// The offer context providing variable values (remote config + IAP data)
    private let context: OfferContext?
    
    /// Creates a template text with the given template and context.
    ///
    /// - Parameters:
    ///   - template: The template string with `${variableName}` placeholders
    ///   - context: The OfferContext providing all variable values
    init(_ template: String, context: OfferContext?) {
        self.template = template
        self.context = context
    }
    
    /// The resolved text with all placeholders substituted.
    ///
    /// Uses `OfferContext.allVariables` to get all template variables.
    /// This includes both static values from RemoteConfig (appName, titleText, etc.)
    /// and dynamic values from IAPContext (subscriptionPrice, subscriptionName, etc.).
    ///
    /// If a placeholder references a variable that doesn't exist or is nil,
    /// the placeholder is left unchanged in the output.
    var resolved: String {
        guard let ctx = context else { return template }
        
        // Get all variables from context (remoteConfig + IAP)
        let variables = ctx.allVariables
        
        // Substitute placeholders
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        return result
    }
    
    var body: some View {
        Text(resolved)
    }
    
    /// Returns the resolved text as a SwiftUI Text for concatenation with other Text views.
    /// Use this when you need to combine template text with other text using `+`.
    var text: Text {
        Text(resolved)
    }
    
    /// Returns the resolved text, or a fallback if the template is empty.
    func resolved(or fallback: String) -> String {
        let result = resolved
        return result.isEmpty ? fallback : result
    }
}

// MARK: - TemplateText Convenience Extensions

extension TemplateText: ExpressibleByStringLiteral {
    /// Creates a template text from a string literal (without context).
    /// Useful for default values that don't need substitution.
    init(stringLiteral value: String) {
        self.template = value
        self.context = nil
    }
}

extension TemplateText: CustomStringConvertible {
    var description: String { resolved }
}

// MARK: - UIValues Extension

extension UIValues {
    /// Creates a TemplateText using this configuration for variable substitution.
    ///
    /// - Parameter template: The template string with `${variableName}` placeholders
    /// - Returns: A TemplateText that will resolve placeholders using this configuration
    func text(_ template: String) -> TemplateText {
        TemplateText(template, context: OfferContext(uiValues: self))
    }
    
    /// Creates a TemplateText from an optional template string.
    ///
    /// - Parameters:
    ///   - template: The optional template string
    ///   - fallback: The fallback value if template is nil
    /// - Returns: A TemplateText that will resolve placeholders using this configuration
    func text(_ template: String?, or fallback: String) -> TemplateText {
        TemplateText(template ?? fallback, context: OfferContext(uiValues: self))
    }
}

// MARK: - Optional UIValues Extension

extension Optional where Wrapped == UIValues {
    /// Creates a TemplateText using this optional configuration for variable substitution.
    ///
    /// - Parameter template: The template string with `${variableName}` placeholders
    /// - Returns: A TemplateText that will resolve placeholders if configuration exists
    func text(_ template: String) -> TemplateText {
        TemplateText(template, context: OfferContext(uiValues: self))
    }
    
    /// Creates a TemplateText from an optional template string.
    ///
    /// - Parameters:
    ///   - template: The optional template string
    ///   - fallback: The fallback value if template is nil
    /// - Returns: A TemplateText that will resolve placeholders if configuration exists
    func text(_ template: String?, or fallback: String) -> TemplateText {
        TemplateText(template ?? fallback, context: OfferContext(uiValues: self))
    }
}
