import OSLog
import SwiftUI
import WebKit

/// Bridge for the bundled Markdown renderer and CodeMirror editor.
struct MarkdownWebView: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    var markdown: String
    var title: String
    var documentIdentifier: String?
    var baseDirectory: URL?
    var presentationMode: DocumentPresentationMode
    var contentToken: UInt64
    var usesVimBindings: Bool
    var zoomScale: Double
    var proseWidth: Double
    var tableWidth: Double
    var onEditorTextChange: (String) -> Void
    var onSaveRequest: () -> Void
    var onSaveAndPreviewRequest: () -> Void
    var onPreviewIfCleanRequest: () -> Void

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
        config.userContentController.add(context.coordinator, name: "bmdEditor")

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
        coordinator.pendingMode = presentationMode
        coordinator.pendingToken = contentToken
        coordinator.pendingAppearance = colorScheme == .dark ? "dark" : "light"
        coordinator.pendingUsesVimBindings = usesVimBindings
        coordinator.pendingProseWidth = proseWidth
        coordinator.pendingTableWidth = tableWidth
        coordinator.onEditorTextChange = onEditorTextChange
        coordinator.onSaveRequest = onSaveRequest
        coordinator.onSaveAndPreviewRequest = onSaveAndPreviewRequest
        coordinator.onPreviewIfCleanRequest = onPreviewIfCleanRequest
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

        coordinator.flushIfPossible()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let logger = Logger(subsystem: "com.brennan.bmd", category: "MarkdownWebView")
        let localAssetHandler = LocalAssetSchemeHandler()

        weak var webView: WKWebView?
        var viewerReady = false
        var grantedReadRoot: URL?

        var pendingMarkdown = ""
        var pendingTitle = "bmd"
        var pendingDocumentIdentifier: String?
        var pendingMode: DocumentPresentationMode = .preview
        var pendingToken: UInt64 = 0
        var pendingAppearance = "light"
        var pendingUsesVimBindings = false
        var pendingProseWidth = AppPreferences.Defaults.proseWidth
        var pendingTableWidth = AppPreferences.Defaults.tableWidth
        var onEditorTextChange: (String) -> Void = { _ in }
        var onSaveRequest: () -> Void = {}
        var onSaveAndPreviewRequest: () -> Void = {}
        var onPreviewIfCleanRequest: () -> Void = {}

        private var renderedToken: UInt64?
        fileprivate var renderedDocumentIdentifier: String?
        private var renderedMode: DocumentPresentationMode?
        private var renderedAppearance: String?
        private var renderedUsesVimBindings: Bool?
        private var renderedProseWidth: Double?
        private var renderedTableWidth: Double?
        private var previewScrollPositions: [String: Double] = [:]
        private var renderGeneration: UInt64 = 0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewerReady = true
            flushIfPossible()
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

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "bmdEditor",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  let documentIdentifier = body["documentIdentifier"] as? String,
                  documentIdentifier == pendingDocumentIdentifier else {
                return
            }
            let text = body["text"] as? String ?? ""
            switch type {
            case "change":
                onEditorTextChange(text)
            case "save":
                onEditorTextChange(text)
                onSaveRequest()
            case "saveAndPreview":
                onEditorTextChange(text)
                onSaveAndPreviewRequest()
            case "previewIfClean":
                onEditorTextChange(text)
                onPreviewIfCleanRequest()
            default:
                logger.warning("Unknown editor message: \(type, privacy: .public)")
            }
        }

        func flushIfPossible() {
            guard viewerReady, let webView else { return }
            guard renderedToken != pendingToken
                    || renderedDocumentIdentifier != pendingDocumentIdentifier
                    || renderedMode != pendingMode
                    || renderedAppearance != pendingAppearance
                    || renderedUsesVimBindings != pendingUsesVimBindings
                    || renderedProseWidth != pendingProseWidth
                    || renderedTableWidth != pendingTableWidth else {
                return
            }

            let previousIdentifier = renderedDocumentIdentifier
            let previousMode = renderedMode
            let nextIdentifier = pendingDocumentIdentifier
            let nextMode = pendingMode
            let preservePreviewScroll = previousMode == .preview
                && nextMode == .preview
                && previousIdentifier != nil
                && previousIdentifier == nextIdentifier

            renderedToken = pendingToken
            renderedDocumentIdentifier = nextIdentifier
            renderedMode = nextMode
            renderedAppearance = pendingAppearance
            renderedUsesVimBindings = pendingUsesVimBindings
            renderedProseWidth = pendingProseWidth
            renderedTableWidth = pendingTableWidth

            renderGeneration &+= 1
            let generation = renderGeneration
            let arguments: [String: Any] = [
                "markdown": pendingMarkdown,
                "title": pendingTitle,
                "appearance": pendingAppearance,
                "vimEnabled": pendingUsesVimBindings,
                "documentIdentifier": pendingDocumentIdentifier ?? "",
                "proseWidth": pendingProseWidth,
                "tableWidth": pendingTableWidth,
                "preserveScroll": preservePreviewScroll,
            ]

            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    if previousMode == .preview,
                       !preservePreviewScroll,
                       let previousIdentifier {
                        let captured = try await webView.callAsyncJavaScript(
                            "return window.scrollY || 0;",
                            arguments: [:],
                            in: nil,
                            contentWorld: .page
                        )
                        if let position = captured as? NSNumber {
                            self.previewScrollPositions[previousIdentifier] = position.doubleValue
                        }
                    }
                    guard generation == self.renderGeneration else { return }

                    if nextMode == .editing {
                        _ = try await webView.callAsyncJavaScript(
                            """
                            if (typeof window.bmdShowEditor !== "function") {
                              throw new Error("Bundled Markdown editor did not load");
                            }
                            return await window.bmdShowEditor(
                              markdown, title, appearance, vimEnabled, documentIdentifier
                            );
                            """,
                            arguments: arguments,
                            in: nil,
                            contentWorld: .page
                        )
                    } else {
                        _ = try await webView.callAsyncJavaScript(
                            """
                            if (typeof window.bmdRender !== "function") {
                              throw new Error("Bundled Markdown renderer did not load");
                            }
                            return await window.bmdRender(
                              markdown, title, appearance, proseWidth, tableWidth, preserveScroll
                            );
                            """,
                            arguments: arguments,
                            in: nil,
                            contentWorld: .page
                        )
                        if !preservePreviewScroll,
                           let nextIdentifier,
                           let position = self.previewScrollPositions[nextIdentifier] {
                            _ = try await webView.callAsyncJavaScript(
                                "window.scrollTo(0, scrollPosition); return window.scrollY;",
                                arguments: ["scrollPosition": position],
                                in: nil,
                                contentWorld: .page
                            )
                        }
                    }
                    self.logger.debug("Document surface update completed")
                } catch {
                    self.logger.error(
                        "Document surface update failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        func loadViewer(webView: WKWebView, readRoot: URL?) {
            guard let viewerDirectory = Bundle.main.resourceURL?
                .appendingPathComponent("viewer", isDirectory: true) else {
                return
            }
            localAssetHandler.viewerDirectory = viewerDirectory
            let index = viewerDirectory.appendingPathComponent("index.html")
            viewerReady = false
            renderedToken = nil
            renderedDocumentIdentifier = nil
            renderedMode = nil
            renderedAppearance = nil
            renderedUsesVimBindings = nil
            renderedProseWidth = nil
            renderedTableWidth = nil

            if let inlined = inlineViewer(in: viewerDirectory) {
                let baseURL = readRoot == nil
                    ? URL(string: "\(LocalAssetSchemeHandler.scheme)://viewer/")
                    : URL(string: "\(LocalAssetSchemeHandler.scheme)://document/")
                webView.loadHTMLString(inlined, baseURL: baseURL)
                return
            }

            webView.loadFileURL(index, allowingReadAccessTo: viewerDirectory)
        }

        private func inlineViewer(in directory: URL) -> String? {
            func read(_ relativePath: String) -> String? {
                try? String(
                    contentsOf: directory.appendingPathComponent(relativePath),
                    encoding: .utf8
                )
            }

            guard let html = read("index.html"),
                  let marked = read("vendor/marked.min.js"),
                  let highlight = read("vendor/highlight/highlight.min.js"),
                  let katex = read("vendor/katex/katex.min.js"),
                  let katexAutoRender = read("vendor/katex/auto-render.min.js"),
                  let katexStyles = read("vendor/katex/katex.min.css"),
                  let mermaid = read("vendor/mermaid/mermaid.min.js"),
                  let codeMirror = read("vendor/codemirror/editor.min.js"),
                  let app = read("app.js"),
                  let css = read("style.css") else {
                return nil
            }
            let resolvedKatexStyles = katexStyles.replacingOccurrences(
                of: "url(fonts/",
                with: "url(\(LocalAssetSchemeHandler.scheme)://viewer/vendor/katex/fonts/"
            )
            return html
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
                    of: #"<script src="vendor/codemirror/editor.min.js"></script>"#,
                    with: "<script>\(codeMirror)</script>"
                )
                .replacingOccurrences(
                    of: #"<script src="app.js"></script>"#,
                    with: "<script>\(app)</script>"
                )
        }
    }
}
