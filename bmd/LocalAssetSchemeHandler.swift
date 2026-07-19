import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves relative document assets to WebKit without broad `file:` URL access.
final class LocalAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "bmd-local"

    var documentDirectory: URL?
    var viewerDirectory: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let fileURL = LocalAssetResolver.resolve(
                requestURL,
                documentDirectory: documentDirectory,
                viewerDirectory: viewerDirectory
              ) else {
            urlSchemeTask.didFailWithError(Self.error(code: 1, description: "Invalid local asset URL"))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func error(code: Int, description: String) -> NSError {
        NSError(
            domain: "com.brennan.bmd.local-assets",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

enum LocalAssetResolver {
    static func resolve(
        _ requestURL: URL,
        documentDirectory: URL?,
        viewerDirectory: URL?
    ) -> URL? {
        let root: URL?
        switch requestURL.host {
        case "document":
            root = documentDirectory
        case "viewer":
            root = viewerDirectory
        default:
            root = nil
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
        guard candidate.path.hasPrefix(rootPath) else { return nil }
        return candidate
    }
}
