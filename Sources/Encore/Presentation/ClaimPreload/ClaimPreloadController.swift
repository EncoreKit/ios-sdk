// State for the `inAppPreload` claim: a claim screen from the tap, a WKWebView
// created and loaded once AFTER the transaction starts, and the reveal rule.

import SwiftUI
import WebKit

/// Owns one `inAppPreload` claim, from the tap to the browser's ×.
///
/// Money path: the destination is an affiliate click link, so the web view is
/// never built before `load(_:)`, and `load(_:)` navigates at most once.
@MainActor
@available(iOS 17.0, *)
final class ClaimPreloadController: ObservableObject, Identifiable {

    enum Phase: Equatable {
        /// Claim screen up, transaction in flight, no web view yet.
        case claiming
        /// Web view built and loading behind the claim screen.
        case loading
        /// Claim screen faded out, the in-app browser is showing.
        case revealed
    }

    /// What the claim screen draws, read off the offer at tap time.
    struct Content: Equatable {
        /// Nil draws no logo box and no gap.
        let logoUrl: URL?
        /// "Finish on <domain>", nil draws no line.
        let domain: String?
        /// At most `ClaimPreloadTokens.maxCheckRows` rows.
        let checks: [String]

        init(logoUrl: URL?, domain: String?, checks: [String]) {
            self.logoUrl = logoUrl
            self.domain = domain
            self.checks = Array(checks.prefix(ClaimPreloadTokens.maxCheckRows))
        }

        init(offer: Offer) {
            self.init(
                logoUrl: offer.displayLogoUrl.flatMap(URL.init(string:)),
                domain: offer.displayExpectedDomain,
                checks: offer.displayInstructions
                    .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }
    }

    struct Timing: Equatable {
        /// The claim screen stays up at least this long, even if the page is ready.
        let minimum: TimeInterval
        /// Reveal regardless once the claim screen has been up this long.
        let cap: TimeInterval

        static let standard = Timing(
            minimum: ClaimPreloadTokens.minClaimScreenSeconds,
            cap: ClaimPreloadTokens.maxClaimScreenSeconds
        )
    }

    typealias WebViewFactory = @MainActor () -> WKWebView

    let id = UUID()
    let content: Content
    /// The tapped campaign, so an abandoned claim can still name it on the funnel.
    let offerId: String?
    @Published private(set) var phase: Phase = .claiming
    /// Nil until `load(_:)`. Never built before the transaction returns.
    private(set) var webView: WKWebView?
    /// The host the browser chrome shows; follows redirects.
    @Published private(set) var currentHost: String?
    /// The chrome's lock is shown only for https; follows redirects with the host.
    @Published private(set) var isSecure = false
    /// The cap passed with no transaction yet: the claim screen offers an ×.
    @Published private(set) var canEscape = false
    /// The user left through that ×. A late transaction must not load anything.
    private(set) var isAbandoned = false
    /// Torn down (failed start, cooldown, abandon or close). Never loads after this.
    private(set) var isCancelled = false

    var onTrackingEvent: SafariTrackingHandler?
    /// The page left for the system (App Store, a deep link). Its navigation is cancelled,
    /// so no load or redirect reports it.
    var onSystemHandoff: ((URL, _ opened: Bool) -> Void)?
    /// The page's process died with nothing safe to reload. The owner closes the browser.
    var onPageGone: (() -> Void)?

    private let timing: Timing
    private let makeWebView: WebViewFactory
    private let shownAt: Date
    private var pageSettled = false
    private var loadStartedAt: Date?
    private var requestedURL: URL?
    /// Where the initial load currently is, so a redirect reports its real origin.
    private var lastInitialURL: URL?
    /// The last page that committed (was shown), as opposed to a redirect hop in flight.
    private var committedURL: URL?
    private var reportedInitialLoad = false
    private var timers: [Task<Void, Never>] = []
    private lazy var observer = NavigationObserver(owner: self)

    /// `makeWebView` nil means `makeDefaultWebView`. It is resolved in the body, not as a default
    /// argument: Swift 6.0 evaluates default arguments nonisolated and rejects the main-actor reference.
    init(content: Content, offerId: String? = nil, timing: Timing = .standard, makeWebView: WebViewFactory? = nil) {
        self.content = content
        self.offerId = offerId
        self.timing = timing
        self.makeWebView = makeWebView ?? Self.makeDefaultWebView
        self.shownAt = Date()
        schedule(after: timing.minimum)
        schedule(after: timing.cap)
    }

    deinit {
        timers.forEach { $0.cancel() }
    }

    /// The reveal rule: loaded (or failed) AND the minimum elapsed, or the cap.
    nonisolated static func shouldReveal(pageSettled: Bool, elapsed: TimeInterval, timing: Timing) -> Bool {
        elapsed >= timing.cap || (pageSettled && elapsed >= timing.minimum)
    }

    // MARK: - Claim lifecycle

    /// Builds the web view and navigates to the claim link. Only the first call acts.
    func load(_ url: URL) {
        guard webView == nil, phase == .claiming, !isCancelled else { return }
        let view = makeWebView()
        view.navigationDelegate = observer
        view.uiDelegate = observer
        webView = view
        requestedURL = url
        lastInitialURL = url
        noteLocation(url)
        phase = .loading
        onTrackingEvent?(.attemptingToOpen(url: url))
        let now = Date()
        loadStartedAt = now
        view.load(URLRequest(url: url))
        onTrackingEvent?(.didOpen(url: url, openedAt: now))
        evaluateReveal()
    }

    /// Tears down before a web view exists or mid-load. Idempotent.
    func cancel() {
        isCancelled = true
        timers.forEach { $0.cancel() }
        timers.removeAll()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
    }

    /// The claim screen's ×, before any web view exists. Permanent.
    func abandon() {
        guard phase == .claiming else { return }
        isAbandoned = true
        canEscape = false
        cancel()
    }

    /// The browser's × was tapped. Reports time spent like the Safari path.
    func noteClosed() {
        if let loadStartedAt {
            onTrackingEvent?(.dismissed(timeSpentSeconds: Date().timeIntervalSince(loadStartedAt)))
        }
        cancel()
    }

    // MARK: - Reveal

    private func schedule(after seconds: TimeInterval) {
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.evaluateReveal()
        }
        timers.append(task)
    }

    private func evaluateReveal() {
        let elapsed = Date().timeIntervalSince(shownAt)
        if phase == .claiming, !isAbandoned, elapsed >= timing.cap {
            canEscape = true
        }
        guard phase == .loading else { return }
        if Self.shouldReveal(pageSettled: pageSettled, elapsed: elapsed, timing: timing) {
            phase = .revealed
        }
    }

    fileprivate func pageDidSettle(url: URL?, success: Bool) {
        // A provisional failure never commits, so the web view has no url of its own.
        if !reportedInitialLoad, let url = url ?? webView?.url ?? requestedURL {
            reportedInitialLoad = true
            onTrackingEvent?(.initialLoadCompleted(url: url, didLoadSuccessfully: success))
        }
        pageSettled = true
        evaluateReveal()
    }

    func didRedirect(to url: URL) {
        noteLocation(url)
        // By now webView.url is already the target, so the origin comes from our own record.
        if !reportedInitialLoad, let from = lastInitialURL, from != url {
            onTrackingEvent?(.initialRedirect(from: from, to: url))
        }
        lastInitialURL = url
    }

    /// Always overwrites both, so a hostless page (about:blank) never keeps the last domain's lock.
    private func noteLocation(_ url: URL) {
        let chrome = Self.chrome(for: url)
        currentHost = chrome.host
        isSecure = chrome.isSecure
    }

    /// What the browser chrome shows for a URL: its host, and the lock only for an https host.
    nonisolated static func chrome(for url: URL) -> (host: String?, isSecure: Bool) {
        let host = url.host.flatMap { $0.isEmpty ? nil : $0 }
        return (host, host != nil && isSecure(url))
    }

    nonisolated static func isSecure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }

    /// iOS reclaimed the page's process. Only a page that committed past the claim link reloads:
    /// the link itself, or a redirect hop not yet shown, could book a second click. With nothing
    /// safe to reload the browser closes, as on Android, rather than revealing a blank page.
    func webContentProcessDidTerminate() {
        guard let webView, !isCancelled else { return }
        guard let committed = committedURL, committed != requestedURL else {
            onPageGone?()
            return
        }
        webView.reload()
        pageDidSettle(url: webView.url, success: false)
    }

    /// A navigation replaced by another (a JS redirect, or a hand-off to another app) is not a failure.
    nonisolated static func isSupersededNavigation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        // WebKitErrorFrameLoadInterruptedByPolicyChange
        return nsError.domain == WKErrorDomain && nsError.code == 102
    }

    /// Reported before the open (the app can background before its completion runs), and
    /// again with `opened: false` if the system could not open it.
    /// The affiliate click link this claim loaded. Requesting it again books a second click.
    func isClaimLink(_ url: URL) -> Bool {
        url == requestedURL
    }

    func didHandOffToSystem(_ url: URL, opened: Bool = true) {
        onSystemHandoff?(url, opened)
    }

    func didCommit(url: URL?) {
        guard let url else { return }
        committedURL = url
        noteLocation(url)
    }

    // MARK: - Web view

    /// The claim page's own persistent website data store. Fixed, so advertiser sign-ins survive
    /// from one claim to the next, and never the host app's `.default()` store: the app can't read
    /// the advertiser's cookies, and none of the app's cookies go out with the click. That is the
    /// isolation SFSafariViewController gives the other presentations. (Everything here is
    /// iOS 17+, where `WKWebsiteDataStore(forIdentifier:)` exists.)
    static let claimPageStoreIdentifier = UUID(uuidString: "6B1C5E0A-3F2D-4C8E-9A71-5D2E8F4B7C13")!

    static func makeDefaultWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: claimPageStoreIdentifier)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        return view
    }
}

// MARK: - Navigation observer

/// Navigation and UI delegate held by the controller; weak back-reference, no cycle.
@available(iOS 17.0, *)
private final class NavigationObserver: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var owner: ClaimPreloadController?

    init(owner: ClaimPreloadController) {
        self.owner = owner
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        MainActor.assumeIsolated { owner?.didRedirect(to: url) }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let url = webView.url
        MainActor.assumeIsolated { owner?.didCommit(url: url) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated { owner?.webContentProcessDidTerminate() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url
        MainActor.assumeIsolated { owner?.pageDidSettle(url: url, success: true) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !ClaimPreloadController.isSupersededNavigation(error) else { return }
        let url = webView.url
        MainActor.assumeIsolated { owner?.pageDidSettle(url: url, success: false) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !ClaimPreloadController.isSupersededNavigation(error) else { return }
        let url = webView.url
        MainActor.assumeIsolated { owner?.pageDidSettle(url: url, success: false) }
    }

    /// Non-web schemes (App Store, tel:, deep links) leave for the system, as Safari would.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        // A back swipe or history.back() onto the click link would request it again unless the
        // page cache still holds it. That is a second click, so history never returns there.
        if navigationAction.navigationType == .backForward, let url = navigationAction.request.url,
           MainActor.assumeIsolated({ self.owner?.isClaimLink(url) ?? false }) {
            decisionHandler(.cancel)
            return
        }
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              scheme != "http", scheme != "https", scheme != "about", scheme != "data", scheme != "blob"
        else {
            decisionHandler(.allow)
            return
        }
        if Self.isWebKitHandledScheme(scheme, in: webView) {
            decisionHandler(.allow)
            return
        }
        // Only the page itself may leave for an app. An iframe (an ad, a pixel) never launches one.
        guard Self.isFromThePage(navigationAction) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.cancel)
        let owner = owner
        MainActor.assumeIsolated { owner?.didHandOffToSystem(url) }
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened else { return }
            MainActor.assumeIsolated { owner?.didHandOffToSystem(url, opened: false) }
        }
    }

    /// `target=_blank` and `window.open` have no second window here; open them in place, as Safari would in one tab.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    /// The main frame, or a new window (`target=_blank`, `window.open`) the main frame opened.
    private static func isFromThePage(_ action: WKNavigationAction) -> Bool {
        if let target = action.targetFrame { return target.isMainFrame }
        return action.sourceFrame.isMainFrame
    }

    /// A scheme a `WKURLSchemeHandler` on this web view serves (tests register one).
    private static func isWebKitHandledScheme(_ scheme: String, in webView: WKWebView) -> Bool {
        webView.configuration.urlSchemeHandler(forURLScheme: scheme) != nil
    }
}
