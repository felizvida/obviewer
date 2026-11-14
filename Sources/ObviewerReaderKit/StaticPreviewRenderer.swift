import Foundation
import JavaScriptCore

/// Renders a note to a self-contained, static HTML document using the bundled
/// renderer in JavaScriptCore. No WebKit, no DOM, no network. Used by the
/// Quick Look extension, which deliberately holds no network entitlement (a
/// sandboxed WKWebView would likely need one, as the app's does).
public enum StaticPreviewRenderer {
    public enum RenderError: LocalizedError {
        case bundleMissing
        case javaScript(String)

        public var errorDescription: String? {
            switch self {
            case .bundleMissing:
                return "The Quick Look renderer is missing from this build."
            case .javaScript(let message):
                return "The preview couldn't be rendered: \(message)"
            }
        }
    }

    /// Returns a complete HTML document for `payload` (its options are forced to static mode).
    public static func document(for payload: ReaderRenderPayload) throws -> String {
        var payload = payload
        payload.options.staticMode = true
        let body = try renderBody(json: payload.jsonString())
        let css = ReaderAssets.data(forRelativePath: "reader.css").map { String(decoding: $0, as: UTF8.self) } ?? ""
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(payload.title))</title>
        <style>\(css)</style>
        </head>
        <body class="ob-quicklook"><main class="ob-page">\(body)</main></body>
        </html>
        """
    }

    static func renderBody(json: String) throws -> String {
        guard let scriptData = ReaderAssets.data(forRelativePath: "quicklook.js") else {
            throw RenderError.bundleMissing
        }
        guard let context = JSContext() else {
            throw RenderError.javaScript("JavaScriptCore is unavailable")
        }
        var failure: String?
        context.exceptionHandler = { _, exception in
            failure = exception?.toString() ?? "unknown error"
        }
        context.evaluateScript(String(decoding: scriptData, as: UTF8.self))
        if let failure { throw RenderError.javaScript(failure) }

        guard let renderer = context.objectForKeyedSubscript("ObviewerQuickLook"),
              let result = renderer.invokeMethod("render", withArguments: [json]) else {
            throw RenderError.javaScript(failure ?? "renderer not found")
        }
        if let failure { throw RenderError.javaScript(failure) }
        guard result.isString, let html = result.toString() else {
            throw RenderError.javaScript("renderer returned no HTML")
        }
        return html
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
