#!/usr/bin/env swift

import AppKit
import Darwin
import Foundation
import WebKit

private enum HeadlessRenderError: LocalizedError {
    case usage
    case missingFile(URL)
    case unreadableResource(URL)
    case invalidViewerTemplate(String)
    case pngEncodingFailed
    case timedOut

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
        }
    }
}

private struct RenderInputs {
    let markdownURL: URL
    let outputURL: URL
    let viewerDirectory: URL

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
    let app = try read(directory.appendingPathComponent("app.js"))

    let replacements = [
        (#"<link rel="stylesheet" href="style.css" />"#, "<style>\(css)</style>"),
        (#"<script src="vendor/marked.min.js"></script>"#, "<script>\(marked)</script>"),
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

@MainActor
private final class HeadlessRenderer: NSObject, WKNavigationDelegate {
    private let markdown: String
    private let title: String
    private let outputURL: URL
    private let webView: WKWebView
    private var timeoutTimer: Timer?

    init(markdown: String, title: String, outputURL: URL) {
        self.markdown = markdown
        self.title = title
        self.outputURL = outputURL

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1100, height: 750),
            configuration: configuration
        )
        super.init()
        webView.navigationDelegate = self
    }

    func start(html: String, baseURL: URL) {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finish(with: .failure(HeadlessRenderError.timedOut))
            }
        }
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let body = """
                    if (typeof window.bmdRender !== "function") {
                      throw new Error("Bundled Markdown renderer did not load");
                    }
                    window.bmdRender(markdown, title);
                    """
                _ = try await webView.callAsyncJavaScript(
                    body,
                    arguments: ["markdown": markdown, "title": title],
                    in: nil,
                    contentWorld: .page
                )

                let snapshot = try await webView.takeSnapshot(configuration: nil)
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
        html: String,
        baseURL: URL
    ) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.finishLaunching()

        let instance = HeadlessRenderer(
            markdown: markdown,
            title: title,
            outputURL: outputURL
        )
        renderer = instance
        instance.start(html: html, baseURL: baseURL)
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
            html: html,
            baseURL: inputs.viewerDirectory
        )
    }
    RunLoop.main.run()
} catch {
    let message = "Headless render failed: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    Darwin.exit(EXIT_FAILURE)
}
