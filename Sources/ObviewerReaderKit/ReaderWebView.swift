import SwiftUI
import WebKit

/// Hosts a `ReaderWebController`'s web view in SwiftUI.
public struct ReaderWebView: NSViewRepresentable {
    @ObservedObject private var controller: ReaderWebController

    public init(controller: ReaderWebController) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
