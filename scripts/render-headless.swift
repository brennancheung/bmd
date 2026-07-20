#!/usr/bin/env swift

import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers
import WebKit

private enum HeadlessRenderError: LocalizedError {
    case usage
    case missingFile(URL)
    case unreadableResource(URL)
    case invalidViewerTemplate(String)
    case pngEncodingFailed
    case timedOut
    case invalidAppearance(String)
    case invalidLayout(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: scripts/render-headless.swift <markdown-file> [output.png]"
        case let .missingFile(url):
            return "File does not exist: \(url.path)"
        case let .unreadableResource(url):
            return "Could not read required resource: \(url.path)"
        case let .invalidViewerTemplate(marker):
            return "Viewer template is missing marker: \(marker)"
        case .pngEncodingFailed:
            return "Could not encode the WebKit snapshot as PNG"
        case .timedOut:
            return "Headless WebKit render timed out"
        case let .invalidAppearance(value):
            return "BMD_APPEARANCE must be light or dark, not: \(value)"
        case let .invalidLayout(message):
            return "Rendered layout failed verification: \(message)"
        }
    }
}

private struct RenderInputs {
    let markdownURL: URL
    let outputURL: URL
    let viewerDirectory: URL
    let appearance: String
    let verifyScroll: Bool

    init(arguments: [String]) throws {
        guard arguments.count == 2 || arguments.count == 3 else {
            throw HeadlessRenderError.usage
        }

        let workingDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let scriptURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = scriptURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        func resolve(_ path: String, relativeTo base: URL) -> URL {
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
            return base.appendingPathComponent(path).standardizedFileURL
        }

        markdownURL = resolve(arguments[1], relativeTo: workingDirectory)
        guard FileManager.default.fileExists(atPath: markdownURL.path) else {
            throw HeadlessRenderError.missingFile(markdownURL)
        }

        if arguments.count == 3 {
            outputURL = resolve(arguments[2], relativeTo: workingDirectory)
        } else {
            let outputDirectory = repositoryRoot
                .appendingPathComponent("build/headless", isDirectory: true)
            outputURL = outputDirectory
                .appendingPathComponent(markdownURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("png")
        }

        viewerDirectory = repositoryRoot
            .appendingPathComponent("Resources/viewer", isDirectory: true)

        appearance = ProcessInfo.processInfo.environment["BMD_APPEARANCE"] ?? "light"
        guard appearance == "light" || appearance == "dark" else {
            throw HeadlessRenderError.invalidAppearance(appearance)
        }
        verifyScroll = ProcessInfo.processInfo.environment["BMD_VERIFY_SCROLL"] == "1"
    }
}

private func read(_ url: URL) throws -> String {
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        throw HeadlessRenderError.unreadableResource(url)
    }
    return contents
}

private func makeInlinedViewer(from directory: URL) throws -> String {
    let index = try read(directory.appendingPathComponent("index.html"))
    let css = try read(directory.appendingPathComponent("style.css"))
    let marked = try read(directory.appendingPathComponent("vendor/marked.min.js"))
    let highlight = try read(directory.appendingPathComponent("vendor/highlight/highlight.min.js"))
    let katex = try read(directory.appendingPathComponent("vendor/katex/katex.min.js"))
    let katexAutoRender = try read(directory.appendingPathComponent("vendor/katex/auto-render.min.js"))
    let katexStyles = try read(directory.appendingPathComponent("vendor/katex/katex.min.css"))
    let mermaid = try read(directory.appendingPathComponent("vendor/mermaid/mermaid.min.js"))
    let app = try read(directory.appendingPathComponent("app.js"))

    let resolvedKatexStyles = katexStyles.replacingOccurrences(
        of: "url(fonts/",
        with: "url(bmd-local://viewer/vendor/katex/fonts/"
    )

    let replacements = [
        (#"<link rel="stylesheet" href="style.css" />"#, "<style>\(css)</style>"),
        (
            #"<link rel="stylesheet" href="vendor/katex/katex.min.css" />"#,
            "<style>\(resolvedKatexStyles)</style>"
        ),
        (#"<script src="vendor/marked.min.js"></script>"#, "<script>\(marked)</script>"),
        (
            #"<script src="vendor/highlight/highlight.min.js"></script>"#,
            "<script>\(highlight)</script>"
        ),
        (#"<script src="vendor/katex/katex.min.js"></script>"#, "<script>\(katex)</script>"),
        (
            #"<script src="vendor/katex/auto-render.min.js"></script>"#,
            "<script>\(katexAutoRender)</script>"
        ),
        (
            #"<script src="vendor/mermaid/mermaid.min.js"></script>"#,
            "<script>\(mermaid)</script>"
        ),
        (#"<script src="app.js"></script>"#, "<script>\(app)</script>"),
    ]

    return try replacements.reduce(index) { html, replacement in
        let (marker, value) = replacement
        guard html.contains(marker) else {
            throw HeadlessRenderError.invalidViewerTemplate(marker)
        }
        return html.replacingOccurrences(of: marker, with: value)
    }
}

private final class HeadlessLocalAssetHandler: NSObject, WKURLSchemeHandler {
    let documentDirectory: URL
    let viewerDirectory: URL

    init(documentDirectory: URL, viewerDirectory: URL) {
        self.documentDirectory = documentDirectory
        self.viewerDirectory = viewerDirectory
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let fileURL = resolvedFileURL(for: requestURL) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            urlSchemeTask.didReceive(
                URLResponse(
                    url: requestURL,
                    mimeType: mimeType,
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
            )
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func resolvedFileURL(for requestURL: URL) -> URL? {
        let root: URL?
        switch requestURL.host {
        case "document": root = documentDirectory
        case "viewer": root = viewerDirectory
        default: root = nil
        }
        guard let root else { return nil }

        let relativePath = requestURL.path.removingPercentEncoding?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? ""
        guard !relativePath.isEmpty else { return nil }

        let standardizedRoot = root
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let candidate = standardizedRoot
            .appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let rootPath = standardizedRoot.path.hasSuffix("/")
            ? standardizedRoot.path
            : standardizedRoot.path + "/"
        return candidate.path.hasPrefix(rootPath) ? candidate : nil
    }
}

@MainActor
private final class HeadlessRenderer: NSObject, WKNavigationDelegate {
    private let markdown: String
    private let title: String
    private let outputURL: URL
    private let appearance: String
    private let verifyScroll: Bool
    private let assetHandler: HeadlessLocalAssetHandler
    private let webView: WKWebView
    private var timeoutTimer: Timer?

    init(
        markdown: String,
        title: String,
        outputURL: URL,
        appearance: String,
        verifyScroll: Bool,
        documentDirectory: URL,
        viewerDirectory: URL
    ) {
        self.markdown = markdown
        self.title = title
        self.outputURL = outputURL
        self.appearance = appearance
        self.verifyScroll = verifyScroll
        assetHandler = HeadlessLocalAssetHandler(
            documentDirectory: documentDirectory,
            viewerDirectory: viewerDirectory
        )

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: "bmd-local")
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1320, height: 900),
            configuration: configuration
        )
        super.init()
        webView.appearance = NSAppearance(
            named: appearance == "dark" ? .darkAqua : .aqua
        )
        webView.navigationDelegate = self
    }

    func start(html: String) {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finish(with: .failure(HeadlessRenderError.timedOut))
            }
        }
        webView.loadHTMLString(html, baseURL: URL(string: "bmd-local://document/"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let body = """
                    if (typeof window.bmdRender !== "function") {
                      throw new Error("Bundled Markdown renderer did not load");
                    }
                    let scrollPreserved = true;
                    let newDocumentReset = true;
                    if (verifyScroll) {
                      const probeMarkdown = Array(120)
                        .fill(
                          "## Scroll preservation probe\\n\\n" +
                          "A paragraph long enough to create a stable reading position."
                        )
                        .join("\\n\\n");
                      await window.bmdRender(
                        probeMarkdown,
                        "scroll-probe.md",
                        appearance,
                        820,
                        1200,
                        false
                      );
                      const maximumScroll = Math.max(
                        0,
                        document.documentElement.scrollHeight - window.innerHeight
                      );
                      if (maximumScroll > 100) {
                        const targetScroll = Math.min(600, maximumScroll);
                        window.scrollTo(0, targetScroll);
                        await window.bmdRender(
                          probeMarkdown + "\\n\\n<!-- refreshed -->",
                          "scroll-probe.md",
                          appearance,
                          820,
                          1200,
                          true
                        );
                        scrollPreserved = Math.abs(window.scrollY - targetScroll) <= 1;
                      }
                    }
                    const summary = await window.bmdRender(
                      markdown,
                      title,
                      appearance,
                      820,
                      1200,
                      false
                    );
                    newDocumentReset = window.scrollY <= 1;
                    await document.fonts.ready;
                    await Promise.all(Array.from(document.images).map((image) => {
                      if (image.complete) return Promise.resolve();
                      return new Promise((resolve) => {
                        image.addEventListener("load", resolve, { once: true });
                        image.addEventListener("error", resolve, { once: true });
                      });
                    }));
                    const content = document.getElementById("content");
                    const table = content && content.querySelector(":scope > .table-wrap");
                    const prose = content && content.querySelector(":scope > :not(.table-wrap)");
                    const root = document.documentElement;
                    return {
                      ...summary,
                      failedImages: Array.from(document.images).filter((image) => !image.naturalWidth).length,
                      appearance: document.documentElement.dataset.appearance,
                      documentHeight: Math.ceil(document.documentElement.scrollHeight),
                      documentWidth: Math.ceil(root.scrollWidth),
                      viewportWidth: Math.ceil(root.clientWidth),
                      horizontalOverflow: root.scrollWidth > root.clientWidth + 1,
                      scrollPreserved,
                      newDocumentReset,
                      tableAligned: !table || !prose ||
                        Math.abs(table.getBoundingClientRect().left - prose.getBoundingClientRect().left) <= 1,
                    };
                    """
                let summary = try await webView.callAsyncJavaScript(
                    body,
                    arguments: [
                        "markdown": markdown,
                        "title": title,
                        "appearance": appearance,
                        "verifyScroll": verifyScroll,
                    ],
                    in: nil,
                    contentWorld: .page
                )

                let snapshotConfiguration = WKSnapshotConfiguration()
                if let values = summary as? [String: Any],
                   let documentHeight = values["documentHeight"] as? NSNumber {
                    if (values["horizontalOverflow"] as? NSNumber)?.boolValue == true {
                        throw HeadlessRenderError.invalidLayout(
                            "document is wider than its viewport"
                        )
                    }
                    if (values["tableAligned"] as? NSNumber)?.boolValue == false {
                        throw HeadlessRenderError.invalidLayout(
                            "table does not share the prose left edge"
                        )
                    }
                    if verifyScroll,
                       (values["scrollPreserved"] as? NSNumber)?.boolValue != true {
                        throw HeadlessRenderError.invalidLayout(
                            "automatic refresh did not preserve vertical scroll"
                        )
                    }
                    if verifyScroll,
                       (values["newDocumentReset"] as? NSNumber)?.boolValue != true {
                        throw HeadlessRenderError.invalidLayout(
                            "a new document did not reset vertical scroll"
                        )
                    }
                    let captureHeight = min(CGFloat(truncating: documentHeight), 12_000)
                    webView.setFrameSize(
                        NSSize(width: webView.bounds.width, height: captureHeight)
                    )
                    webView.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(100))
                    snapshotConfiguration.rect = CGRect(
                        x: 0,
                        y: 0,
                        width: webView.bounds.width,
                        height: captureHeight
                    )
                }
                let snapshot = try await webView.takeSnapshot(
                    configuration: snapshotConfiguration
                )
                guard let tiff = snapshot.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw HeadlessRenderError.pngEncodingFailed
                }

                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try png.write(to: outputURL, options: .atomic)
                if let summary {
                    print("Render summary: \(summary)")
                }
                finish(with: .success(outputURL))
            } catch {
                finish(with: .failure(error))
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: .failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(with: .failure(HeadlessRenderError.timedOut))
    }

    private func finish(with result: Result<URL, Error>) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        switch result {
        case let .success(url):
            print(url.path)
            Darwin.exit(EXIT_SUCCESS)
        case let .failure(error):
            let message = "Headless render failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }
}

@MainActor
private enum HeadlessProcess {
    static var renderer: HeadlessRenderer?

    static func start(
        markdown: String,
        title: String,
        outputURL: URL,
        appearance: String,
        verifyScroll: Bool,
        html: String,
        documentDirectory: URL,
        viewerDirectory: URL
    ) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.finishLaunching()

        let instance = HeadlessRenderer(
            markdown: markdown,
            title: title,
            outputURL: outputURL,
            appearance: appearance,
            verifyScroll: verifyScroll,
            documentDirectory: documentDirectory,
            viewerDirectory: viewerDirectory
        )
        renderer = instance
        instance.start(html: html)
    }
}

do {
    let inputs = try RenderInputs(arguments: CommandLine.arguments)
    let markdown = try read(inputs.markdownURL)
    let html = try makeInlinedViewer(from: inputs.viewerDirectory)

    Task { @MainActor in
        HeadlessProcess.start(
            markdown: markdown,
            title: inputs.markdownURL.lastPathComponent,
            outputURL: inputs.outputURL,
            appearance: inputs.appearance,
            verifyScroll: inputs.verifyScroll,
            html: html,
            documentDirectory: inputs.markdownURL.deletingLastPathComponent(),
            viewerDirectory: inputs.viewerDirectory
        )
    }
    RunLoop.main.run()
} catch {
    let message = "Headless render failed: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    Darwin.exit(EXIT_FAILURE)
}
