import SwiftUI
import WebKit
import OSLog

/// Thin bridge: load bundled viewer, inject markdown via `window.bmdRender`.
struct MarkdownWebView: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    var markdown: String
    var title: String
    var documentIdentifier: String?
    var baseDirectory: URL?
    var renderToken: UInt64
    var zoomScale: Double
    var proseWidth: Double
    var tableWidth: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(
            context.coordinator.localAssetHandler,
            forURLScheme: LocalAssetSchemeHandler.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.loadViewer(webView: webView, readRoot: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pendingMarkdown = markdown
        coordinator.pendingTitle = title
        coordinator.pendingDocumentIdentifier = documentIdentifier
        coordinator.pendingToken = renderToken
        coordinator.pendingAppearance = colorScheme == .dark ? "dark" : "light"
        coordinator.pendingProseWidth = proseWidth
        coordinator.pendingTableWidth = tableWidth
        if abs(webView.pageZoom - zoomScale) > 0.001 {
            webView.pageZoom = zoomScale
        }

        if let baseDirectory {
            let path = baseDirectory.standardizedFileURL.path
            if coordinator.grantedReadRoot?.path != path {
                coordinator.grantedReadRoot = baseDirectory
                coordinator.localAssetHandler.documentDirectory = baseDirectory
                if coordinator.renderedDocumentIdentifier == nil {
                    coordinator.loadViewer(webView: webView, readRoot: baseDirectory)
                    return
                }
            }
        }

        coordinator.flushRenderIfPossible()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let logger = Logger(subsystem: "com.brennan.bmd", category: "MarkdownWebView")
        let localAssetHandler = LocalAssetSchemeHandler()

        weak var webView: WKWebView?
        var viewerReady = false
        var grantedReadRoot: URL?

        var pendingMarkdown: String = ""
        var pendingTitle: String = "bmd"
        var pendingDocumentIdentifier: String?
        var pendingToken: UInt64 = 0
        var pendingAppearance: String = "light"
        var pendingProseWidth: Double = AppPreferences.Defaults.proseWidth
        var pendingTableWidth: Double = AppPreferences.Defaults.tableWidth
        private var renderedToken: UInt64?
        fileprivate var renderedDocumentIdentifier: String?
        private var renderedAppearance: String?
        private var renderedProseWidth: Double?
        private var renderedTableWidth: Double?
        private var scrollPositions: [String: Double] = [:]
        private var renderGeneration: UInt64 = 0

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
            guard renderedToken != pendingToken
                    || renderedDocumentIdentifier != pendingDocumentIdentifier
                    || renderedAppearance != pendingAppearance
                    || renderedProseWidth != pendingProseWidth
                    || renderedTableWidth != pendingTableWidth else {
                return
            }
            let preserveScroll = renderedDocumentIdentifier != nil
                && renderedDocumentIdentifier == pendingDocumentIdentifier
            let previousDocumentIdentifier = renderedDocumentIdentifier
            let nextDocumentIdentifier = pendingDocumentIdentifier
            renderedToken = pendingToken
            renderedDocumentIdentifier = pendingDocumentIdentifier
            renderedAppearance = pendingAppearance
            renderedProseWidth = pendingProseWidth
            renderedTableWidth = pendingTableWidth

            renderGeneration &+= 1
            let generation = renderGeneration
            let js = """
                if (typeof window.bmdRender !== "function") {
                  throw new Error("Bundled Markdown renderer did not load");
                }
                return await window.bmdRender(
                  markdown,
                  title,
                  appearance,
                  proseWidth,
                  tableWidth,
                  preserveScroll
                );
                """
            let arguments: [String: Any] = [
                "markdown": pendingMarkdown,
                "title": pendingTitle,
                "appearance": pendingAppearance,
                "proseWidth": pendingProseWidth,
                "tableWidth": pendingTableWidth,
                "preserveScroll": preserveScroll,
            ]
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    if !preserveScroll, let previousDocumentIdentifier {
                        let captured = try await webView.callAsyncJavaScript(
                            "return window.scrollY || 0;",
                            arguments: [:],
                            in: nil,
                            contentWorld: .page
                        )
                        if let position = captured as? NSNumber {
                            self.scrollPositions[previousDocumentIdentifier] = position.doubleValue
                        }
                    }
                    guard generation == self.renderGeneration else { return }
                    _ = try await webView.callAsyncJavaScript(
                        js,
                        arguments: arguments,
                        in: nil,
                        contentWorld: .page
                    )
                    if !preserveScroll,
                       let nextDocumentIdentifier,
                       let position = self.scrollPositions[nextDocumentIdentifier] {
                        _ = try await webView.callAsyncJavaScript(
                            "window.scrollTo(0, scrollPosition); return window.scrollY;",
                            arguments: ["scrollPosition": position],
                            in: nil,
                            contentWorld: .page
                        )
                    }
                    self.logger.debug("Markdown render completed")
                } catch {
                    self.logger.error(
                        "Markdown render failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        func loadViewer(webView: WKWebView, readRoot: URL?) {
            guard let viewerDir = Bundle.main.resourceURL?.appendingPathComponent("viewer", isDirectory: true) else {
                return
            }
            localAssetHandler.viewerDirectory = viewerDir
            let index = viewerDir.appendingPathComponent("index.html")
            viewerReady = false
            renderedToken = nil
            renderedDocumentIdentifier = nil
            renderedAppearance = nil
            renderedProseWidth = nil
            renderedTableWidth = nil

            if let html = try? String(contentsOf: index, encoding: .utf8),
               let marked = try? String(contentsOf: viewerDir.appendingPathComponent("vendor/marked.min.js"), encoding: .utf8),
               let highlight = try? String(contentsOf: viewerDir.appendingPathComponent("vendor/highlight/highlight.min.js"), encoding: .utf8),
               let katex = try? String(contentsOf: viewerDir.appendingPathComponent("vendor/katex/katex.min.js"), encoding: .utf8),
               let katexAutoRender = try? String(contentsOf: viewerDir.appendingPathComponent("vendor/katex/auto-render.min.js"), encoding: .utf8),
               let katexStyles = try? String(contentsOf: viewerDir.appendingPathComponent("vendor/katex/katex.min.css"), encoding: .utf8),
               let mermaid = try? String(contentsOf: viewerDir.appendingPathComponent("vendor/mermaid/mermaid.min.js"), encoding: .utf8),
               let app = try? String(contentsOf: viewerDir.appendingPathComponent("app.js"), encoding: .utf8),
               let css = try? String(contentsOf: viewerDir.appendingPathComponent("style.css"), encoding: .utf8) {
                let resolvedKatexStyles = katexStyles.replacingOccurrences(
                    of: "url(fonts/",
                    with: "url(\(LocalAssetSchemeHandler.scheme)://viewer/vendor/katex/fonts/"
                )
                let inlined = html
                    .replacingOccurrences(
                        of: #"<link rel="stylesheet" href="style.css" />"#,
                        with: "<style>\(css)</style>"
                    )
                    .replacingOccurrences(
                        of: #"<link rel="stylesheet" href="vendor/katex/katex.min.css" />"#,
                        with: "<style>\(resolvedKatexStyles)</style>"
                    )
                    .replacingOccurrences(
                        of: #"<script src="vendor/marked.min.js"></script>"#,
                        with: "<script>\(marked)</script>"
                    )
                    .replacingOccurrences(
                        of: #"<script src="vendor/highlight/highlight.min.js"></script>"#,
                        with: "<script>\(highlight)</script>"
                    )
                    .replacingOccurrences(
                        of: #"<script src="vendor/katex/katex.min.js"></script>"#,
                        with: "<script>\(katex)</script>"
                    )
                    .replacingOccurrences(
                        of: #"<script src="vendor/katex/auto-render.min.js"></script>"#,
                        with: "<script>\(katexAutoRender)</script>"
                    )
                    .replacingOccurrences(
                        of: #"<script src="vendor/mermaid/mermaid.min.js"></script>"#,
                        with: "<script>\(mermaid)</script>"
                    )
                    .replacingOccurrences(
                        of: #"<script src="app.js"></script>"#,
                        with: "<script>\(app)</script>"
                    )

                let baseURL = readRoot == nil
                    ? URL(string: "\(LocalAssetSchemeHandler.scheme)://viewer/")
                    : URL(string: "\(LocalAssetSchemeHandler.scheme)://document/")
                webView.loadHTMLString(inlined, baseURL: baseURL)
                return
            }

            webView.loadFileURL(index, allowingReadAccessTo: viewerDir)
        }

    }
}
