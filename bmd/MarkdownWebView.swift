import SwiftUI
import WebKit
import OSLog

/// Thin bridge: load bundled viewer, inject markdown via `window.bmdRender`.
struct MarkdownWebView: NSViewRepresentable {
    var markdown: String
    var title: String
    var baseDirectory: URL?
    var renderToken: UInt64

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.loadViewer(webView: webView, readRoot: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pendingMarkdown = markdown
        coordinator.pendingTitle = title
        coordinator.pendingToken = renderToken

        if let baseDirectory {
            let path = baseDirectory.standardizedFileURL.path
            if coordinator.grantedReadRoot?.path != path {
                coordinator.grantedReadRoot = baseDirectory
                coordinator.loadViewer(webView: webView, readRoot: baseDirectory)
                return
            }
        }

        coordinator.flushRenderIfPossible()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let logger = Logger(subsystem: "com.brennan.bmd", category: "MarkdownWebView")

        weak var webView: WKWebView?
        var viewerReady = false
        var grantedReadRoot: URL?

        var pendingMarkdown: String = ""
        var pendingTitle: String = "bmd"
        var pendingToken: UInt64 = 0
        private var renderedToken: UInt64?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewerReady = true
            flushRenderIfPossible()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            logger.error("Viewer navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            logger.error("Viewer provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.error("Viewer WebContent process terminated")
        }

        func flushRenderIfPossible() {
            guard viewerReady, let webView else { return }
            guard renderedToken != pendingToken else { return }
            renderedToken = pendingToken

            let js = """
                if (typeof window.bmdRender !== "function") {
                  throw new Error("Bundled Markdown renderer did not load");
                }
                window.bmdRender(markdown, title);
                """
            let arguments = ["markdown": pendingMarkdown, "title": pendingTitle]
            Task { @MainActor [weak self, weak webView] in
                guard let webView else { return }
                do {
                    _ = try await webView.callAsyncJavaScript(
                        js,
                        arguments: arguments,
                        in: nil,
                        contentWorld: .page
                    )
                    self?.logger.debug("Markdown render completed")
                } catch {
                    self?.logger.error(
                        "Markdown render failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        func loadViewer(webView: WKWebView, readRoot: URL?) {
            guard let viewerDir = Bundle.main.resourceURL?.appendingPathComponent("viewer", isDirectory: true) else {
                return
            }
            let index = viewerDir.appendingPathComponent("index.html")
            viewerReady = false
            renderedToken = nil

            if let html = try? String(contentsOf: index, encoding: .utf8),
               let marked = try? String(contentsOf: viewerDir.appendingPathComponent("vendor/marked.min.js"), encoding: .utf8),
               let app = try? String(contentsOf: viewerDir.appendingPathComponent("app.js"), encoding: .utf8),
               let css = try? String(contentsOf: viewerDir.appendingPathComponent("style.css"), encoding: .utf8) {
                let inlined = html
                    .replacingOccurrences(
                        of: #"<link rel="stylesheet" href="style.css" />"#,
                        with: "<style>\(css)</style>"
                    )
                    .replacingOccurrences(
                        of: #"<script src="vendor/marked.min.js"></script>"#,
                        with: "<script>\(marked)</script>"
                    )
                    .replacingOccurrences(
                        of: #"<script src="app.js"></script>"#,
                        with: "<script>\(app)</script>"
                    )
                webView.loadHTMLString(inlined, baseURL: viewerDir)
                return
            }

            webView.loadFileURL(index, allowingReadAccessTo: viewerDir)
        }

    }
}
