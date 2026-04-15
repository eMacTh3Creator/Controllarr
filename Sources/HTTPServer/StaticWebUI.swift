//
//  StaticWebUI.swift
//  Controllarr — Phase 1
//
//  Serve the built React WebUI as static files from a directory on disk.
//  Path traversal is explicitly guarded. This is intentionally less
//  featured than Hummingbird's HBFileMiddleware because we want strict
//  control over the served set — assets are bundled at build time and
//  never user-supplied.
//

import Foundation
import Hummingbird
import NIOCore

enum StaticWebUI {

    static func install(on router: Router<BasicRequestContext>, rootDirectory: URL?) {
        // `/` is not matched by `/**` in Hummingbird's trie router, so we
        // register an explicit root handler that serves index.html.
        router.get("/") { _, _ -> Response in
            guard let rootDirectory else { return placeholderPage() }
            if let indexData = try? Data(contentsOf: rootDirectory.appendingPathComponent("index.html")) {
                return fileResponse(data: indexData, filename: "index.html")
            }
            return placeholderPage()
        }
        router.get("/**") { request, _ -> Response in
            let path = request.uri.path
            // /api/** is handled elsewhere; if we got here it means no
            // handler matched it, so we 404.
            if path.hasPrefix("/api/") {
                return Response(status: .notFound)
            }

            guard let rootDirectory else {
                return placeholderPage()
            }
            let relative = (path == "/" || path.isEmpty) ? "/index.html" : path
            // Guard against path traversal.
            if relative.contains("..") { return Response(status: .forbidden) }

            let fileURL = rootDirectory.appendingPathComponent(String(relative.dropFirst()))
            let resolvedPath = fileURL.standardizedFileURL.path
            let rootPath = rootDirectory.standardizedFileURL.path
            if !resolvedPath.hasPrefix(rootPath) {
                return Response(status: .forbidden)
            }

            guard let data = try? Data(contentsOf: fileURL) else {
                // SPA fallback: serve index.html for unknown client-side routes.
                if let indexData = try? Data(contentsOf: rootDirectory.appendingPathComponent("index.html")) {
                    return fileResponse(data: indexData, filename: "index.html")
                }
                return Response(status: .notFound)
            }
            return fileResponse(data: data, filename: fileURL.lastPathComponent)
        }
    }

    private static func fileResponse(data: Data, filename: String) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = mimeType(for: filename)
        headers[.cacheControl] = "public, max-age=3600"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    private static func placeholderPage() -> Response {
        let html = """
        <!doctype html>
        <html><head><title>Controllarr</title>
        <style>body{font-family:-apple-system,sans-serif;background:#0f1115;color:#e6e6e6;max-width:640px;margin:10vh auto;padding:2rem;}
        h1{margin:0 0 .25rem}h1 span{opacity:.6;font-weight:400;font-size:.6em}
        code{background:#1b1e26;padding:2px 6px;border-radius:4px}</style></head>
        <body>
        <h1>Controllarr <span>v0.1 Phase 1</span></h1>
        <p>The React WebUI has not been built yet. Run:</p>
        <pre><code>cd WebUI && npm install && npm run build</code></pre>
        <p>Then relaunch Controllarr. The qBittorrent Web API is live at
        <code>/api/v2/*</code>.</p>
        </body></html>
        """
        var headers = HTTPFields()
        headers[.contentType] = "text/html; charset=utf-8"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(string: html)))
    }

    private static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "js", "mjs":   return "application/javascript; charset=utf-8"
        case "json":        return "application/json"
        case "svg":         return "image/svg+xml"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "ico":         return "image/x-icon"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        case "map":         return "application/json"
        default:            return "application/octet-stream"
        }
    }
}
