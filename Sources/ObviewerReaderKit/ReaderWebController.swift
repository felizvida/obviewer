import AppKit
import OSLog
import WebKit

let readerLog = Logger(subsystem: "com.felizvida.obviewer", category: "reader")

/// Reader appearance settings forwarded to the page.
public struct ReaderAppearance: Equatable, Sendable {
    public var textScale: Double
    /// Line length in characters.
    public var measure: Int
    /// "system", "light" or "dark".
    public var theme: String

    public init(textScale: Double = 1.0, measure: Int = 68, theme: String = "system") {
        self.textScale = textScale
        self.measure = measure
        self.theme = theme
    }
}

public struct ReaderExport: Sendable {
    public let html: String
    public let text: String
}

/// Owns the reader's WKWebView and enforces its limits:
/// - only `obviewer-asset://` content loads (content rules + CSP in reader.html),
/// - the page can't navigate itself or open windows,
/// - messages from the page are parsed into `ReaderEvent`s; none of them writes anything.
@MainActor
public final class ReaderWebController: NSObject, ObservableObject {
    public let webView: WKWebView
    public let schemeHandler: ReaderSchemeHandler

    @Published public private(set) var isReady = false
    @Published public private(set) var headings: [ReaderHeading] = []
    @Published public private(set) var renderedNoteID: String?
    @Published public private(set) var failureMessage: String?

    public var onEvent: ((ReaderEvent) -> Void)?

    private var pendingPayload: ReaderRenderPayload?
    private var lastPayload: ReaderRenderPayload?
    private var appearance = ReaderAppearance()
    private var printContinuation: CheckedContinuation<Bool, Never>?
    private var trail = [String]()
    private var lastStage = "created"
    private var watchdog: Task<Void, Never>?
    private var terminationCount = 0

    /// Seconds to wait for the page's "ready" message before showing an error.
    public static let startupTimeout: Double = 8

    public override init() {
        let handler = ReaderSchemeHandler()
        let messageProxy = WeakScriptMessageHandler()
        let userContentController = WKUserContentController()
        // Register the message handler before the web view exists so the page can never start without it.
        userContentController.add(messageProxy, name: "obviewer")

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: ReaderSchemeHandler.scheme)
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController = userContentController

        schemeHandler = handler
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        messageProxy.target = self
        handler.onLog = { [weak self] line in
            Task { @MainActor [weak self] in self?.note(line) }
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .textBackgroundColor
        if #available(macOS 13.3, *) {
            webView.isInspectable = Self.isInspectionEnabled
        }

        note("controller created; resources available: \(ReaderAssets.isAvailable), dir: \(ReaderAssets.directoryURL?.path ?? "nil")")
        loadReaderPage()
    }

    /// Web Inspector is on in Debug builds, or when `obviewer.reader.inspectable` is set.
    static var isInspectionEnabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "obviewer.reader.inspectable")
        #endif
    }

    /// A timestamped record of the reader's startup and recent events, for bug reports.
    public var diagnostics: String {
        let header = [
            "Obviewer reader diagnostics",
            "ready: \(isReady), last stage: \(lastStage), failure: \(failureMessage ?? "none")",
            "page URL: \(webView.url?.absoluteString ?? "nil"), loading: \(webView.isLoading)",
            "web content terminations: \(terminationCount)",
        ]
        return (header + ["--"] + trail).joined(separator: "\n")
    }

    func note(_ line: String, stage: String? = nil) {
        if let stage { lastStage = stage }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withFractionalSeconds]
        trail.append("\(formatter.string(from: Date())) \(line)")
        if trail.count > 200 { trail.removeFirst(trail.count - 200) }
        readerLog.info("\(line, privacy: .public)")
    }

    // MARK: - Public API

    public func setAssetResolver(_ resolver: (any VaultAssetResolving)?) {
        schemeHandler.setResolver(resolver)
    }

    public func render(_ payload: ReaderRenderPayload) {
        lastPayload = payload
        guard isReady else {
            pendingPayload = payload
            return
        }
        send(payload)
    }

    /// Re-renders the last payload (e.g. after the file changed on disk the caller passes a new one instead).
    public func rerender() {
        guard let lastPayload else { return }
        render(lastPayload)
    }

    public func apply(_ appearance: ReaderAppearance) {
        self.appearance = appearance
        guard isReady else { return }
        call(
            "window.obviewer.setAppearance({ textScale: textScale, lineWidth: measure, theme: theme });",
            arguments: ["textScale": appearance.textScale, "measure": appearance.measure, "theme": appearance.theme]
        )
    }

    @discardableResult
    public func scrollTo(anchor: String) async -> Bool {
        guard isReady else { return false }
        let result = try? await webView.callAsyncJavaScript(
            "return window.obviewer.scrollToAnchor(anchor);",
            arguments: ["anchor": anchor],
            contentWorld: .page
        )
        let found = (result as? Bool) ?? false
        note("scroll to anchor \(anchor): \(found ? "found" : "not found")")
        return found
    }

    public func exportRichText() async throws -> ReaderExport {
        try await export(function: "exportRich")
    }

    public func exportForSlack() async throws -> ReaderExport {
        try await export(function: "exportSlack")
    }

    public func selectedText() async -> String {
        let result = try? await webView.callAsyncJavaScript("return window.obviewer.getSelectedText();", contentWorld: .page)
        return (result as? String) ?? ""
    }

    /// Finds and selects the next match. Returns whether a match was found.
    public func find(_ text: String, backwards: Bool = false) async -> Bool {
        guard text.isEmpty == false else { return false }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        return await withCheckedContinuation { continuation in
            webView.find(text, configuration: configuration) { result in
                continuation.resume(returning: result.matchFound)
            }
        }
    }

    /// Shows the system print panel. Its "Save as PDF" can't open a save panel in a
    /// read-only sandbox; the app offers "Open as PDF in Preview" instead.
    public func printDocument(in window: NSWindow?, jobTitle: String) {
        let operation = makePrintOperation(jobTitle: jobTitle)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        guard let window = window ?? webView.window ?? NSApp.keyWindow else { return }
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Writes a paginated PDF of the note into `url` (inside the app's own container).
    public func writePDF(to url: URL, in window: NSWindow?, jobTitle: String) async -> Bool {
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = url
        let operation = makePrintOperation(jobTitle: jobTitle, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard let window = window ?? webView.window else { return false }
        return await withCheckedContinuation { continuation in
            printContinuation = continuation
            operation.runModal(
                for: window,
                delegate: self,
                didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    // MARK: - Internals

    private func loadReaderPage() {
        guard ReaderAssets.isAvailable else {
            note("reader resources missing", stage: "resources-missing")
            failureMessage = "The reader resources are missing from this build. Run `npm run build` in Renderer/."
            return
        }
        note("compiling content rules", stage: "rules-compiling")
        startWatchdog()
        ReaderContentRules.install(on: webView.configuration.userContentController) { [weak self] installed, errorText in
            guard let self else { return }
            guard installed else {
                // Fail closed: without the network block, don't show web content at all.
                self.note("content rules failed: \(errorText ?? "unknown error")", stage: "rules-failed")
                self.failureMessage = "The reader's offline protection couldn't be set up, so notes aren't shown (\(errorText ?? "unknown error")). Quit and reopen Obviewer; if it keeps happening, reinstall it."
                return
            }
            self.note("content rules installed; loading \(ReaderSchemeHandler.readerPageURL.absoluteString)", stage: "page-loading")
            self.webView.load(URLRequest(url: ReaderSchemeHandler.readerPageURL))
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.startupTimeout))
            guard Task.isCancelled == false, let self, self.isReady == false, self.failureMessage == nil else { return }
            self.note("startup timed out", stage: self.lastStage)
            self.failureMessage = "The reader didn't start (last step: \(self.lastStage)). Choose Help › Copy Reader Diagnostics and include it in a bug report."
        }
    }

    private func send(_ payload: ReaderRenderPayload) {
        guard let json = try? payload.jsonString() else {
            failureMessage = "Obviewer couldn't prepare this note for display."
            return
        }
        failureMessage = nil
        note("render \(payload.noteID) (\(payload.flavor.rawValue), \(json.utf8.count) bytes)", stage: "rendering")
        webView.callAsyncJavaScript(
            "return await window.obviewer.render(JSON.parse(payloadJSON));",
            arguments: ["payloadJSON": json],
            in: nil,
            in: .page
        ) { [weak self] result in
            let failure: String?
            if case .failure(let error) = result {
                failure = "\(error)"
            } else {
                failure = nil
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let failure {
                    self.note("render failed: \(failure)", stage: "render-failed")
                    self.failureMessage = "This note couldn't be rendered: \(failure)"
                } else {
                    self.note("render returned", stage: "rendered")
                }
            }
        }
    }

    private func call(_ script: String, arguments: [String: Any] = [:]) {
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page, completionHandler: nil)
    }

    private func export(function: String) async throws -> ReaderExport {
        let result = try await webView.callAsyncJavaScript(
            "return await window.obviewer.\(function)();",
            contentWorld: .page
        )
        guard let dictionary = result as? [String: Any] else {
            throw ReaderControllerError.exportFailed
        }
        return ReaderExport(
            html: dictionary["html"] as? String ?? "",
            text: dictionary["text"] as? String ?? ""
        )
    }

    private func makePrintOperation(jobTitle: String, printInfo: NSPrintInfo? = nil) -> NSPrintOperation {
        let info = printInfo ?? (NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo())
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 42
        info.bottomMargin = 42
        info.leftMargin = 48
        info.rightMargin = 48
        let operation = webView.printOperation(with: info)
        operation.jobTitle = jobTitle
        // WKWebView print operations render blank without an explicit view frame.
        operation.view?.frame = webView.bounds
        return operation
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printContinuation?.resume(returning: success)
        printContinuation = nil
    }

    fileprivate func handle(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.scheme == ReaderSchemeHandler.scheme,
              let event = ReaderEvent(messageBody: message.body) else {
            return
        }

        switch event {
        case .jsError(let text):
            note("page error: \(text)")
        case .cspViolation(let text):
            note("blocked by Content-Security-Policy: \(text)")
        default:
            break
        }

        switch event {
        case .ready:
            note("page ready", stage: "ready")
            watchdog?.cancel()
            isReady = true
            apply(appearance)
            if let payload = pendingPayload ?? lastPayload {
                pendingPayload = nil
                send(payload)
            }
        case .rendered(let noteID, let headings):
            renderedNoteID = noteID
            self.headings = headings
        default:
            break
        }
        onEvent?(event)
    }
}

public enum ReaderControllerError: LocalizedError {
    case exportFailed

    public var errorDescription: String? {
        "Obviewer couldn't copy this note."
    }
}

extension ReaderWebController: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        let isReaderPage = url?.scheme == ReaderSchemeHandler.scheme
            && url?.host == "app"
            && url?.path == "/reader.html"
            && navigationAction.targetFrame?.isMainFrame == true
            && navigationAction.navigationType != .linkActivated
        if isReaderPage {
            decisionHandler(.allow)
            return
        }

        note("navigation refused: \(url?.absoluteString ?? "nil") (type \(navigationAction.navigationType.rawValue))")
        decisionHandler(.cancel)
        // A link that slipped past the page's click handler: treat web links as external.
        if navigationAction.navigationType == .linkActivated,
           let url,
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme) {
            onEvent?(.link(ReaderLinkRequest(kind: .external, target: url.absoluteString)))
        }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        note("navigation started: \(webView.url?.absoluteString ?? "nil")", stage: "navigation-started")
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        note("navigation committed", stage: "navigation-committed")
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        note("navigation finished", stage: isReady ? lastStage : "page-loaded-waiting-for-ready")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        note("navigation failed: \(error)", stage: "navigation-failed")
        failureMessage = error.localizedDescription
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        note("provisional navigation failed: \(error)", stage: "provisional-navigation-failed")
        failureMessage = error.localizedDescription
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        terminationCount += 1
        note("web content process terminated (#\(terminationCount))", stage: "web-content-terminated")
        isReady = false
        pendingPayload = lastPayload
        guard terminationCount <= 2 else {
            failureMessage = "The reader's web content process keeps stopping. Choose Help › Copy Reader Diagnostics and include it in a bug report."
            return
        }
        loadReaderPage()
    }
}

extension ReaderWebController: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}

/// Breaks the WKUserContentController -> handler retain cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: ReaderWebController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            target?.handle(message)
        }
    }
}

/// Blocks every load that isn't bundled or vault content, in addition to the
/// page's Content-Security-Policy.
public enum ReaderContentRules {
    public static let identifier = "obviewer.reader.offline.v1"
    public static let json = """
    [
      {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^obviewer-asset:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}
    ]
    """

    @MainActor private static var compiled: WKContentRuleList?
    @MainActor private static var waiters: [(WKContentRuleList?) -> Void] = []
    @MainActor private static var isCompiling = false
    @MainActor private(set) static var lastError: String?

    @MainActor
    public static func install(on controller: WKUserContentController, then load: @escaping (Bool, String?) -> Void) {
        withRuleList { list in
            guard let list else {
                load(false, lastError)
                return
            }
            controller.removeAllContentRuleLists()
            controller.add(list)
            load(true, nil)
        }
    }

    @MainActor
    static func withRuleList(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let compiled {
            completion(compiled)
            return
        }
        waiters.append(completion)
        guard isCompiling == false else { return }
        isCompiling = true
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
            Task { @MainActor in
                if let error {
                    lastError = "\(error)"
                    readerLog.error("content rules failed to compile: \(String(describing: error), privacy: .public)")
                }
                compiled = list
                isCompiling = false
                let pending = waiters
                waiters = []
                pending.forEach { $0(list) }
            }
        }
    }
}
