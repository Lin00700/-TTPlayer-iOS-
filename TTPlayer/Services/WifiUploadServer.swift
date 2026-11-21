import Combine
import Foundation
import Network

// MARK: - 本机地址

enum NetworkInfo {
    /// en0（Wi-Fi）上的 IPv4
    static func wifiIPv4() -> String? {
        var candidates: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interfacePointer = current {
            let interface = interfacePointer.pointee
            if let address = interface.ifa_addr,
               let namePointer = interface.ifa_name,
               address.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: namePointer)
                if name == "en0" || name.hasPrefix("en") || name.hasPrefix("bridge") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(
                        address,
                        socklen_t(address.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if result == 0 {
                        let ip = String(cString: hostname)
                        if !ip.isEmpty, ip != "0.0.0.0" {
                            candidates.append(ip)
                        }
                    }
                }
            }
            current = interface.ifa_next
        }

        if let privateIP = candidates.first(where: { $0.hasPrefix("192.168.") || $0.hasPrefix("10.") || $0.hasPrefix("172.") }) {
            return privateIP
        }
        return candidates.first
    }

    static func uploadURL(port: UInt16) -> String {
        if let ip = wifiIPv4() {
            return "http://\(ip):\(port)"
        }
        return "http://手机IP:\(port)"
    }
}

// MARK: - Wi-Fi 传歌服务

/// 轻量 HTTP 服务：GET / 返回中文拖拽上传页，POST /upload 落盘到 Documents/Music，
/// GET /api/files 列出手机曲库，POST /delete 删除单个文件。
final class WifiUploadServer: ObservableObject {
    struct UploadRecord: Identifiable {
        let id = UUID()
        let name: String
        let bytes: Int
    }

    @Published private(set) var isRunning = false
    @Published private(set) var address: String?
    @Published private(set) var lastError: String?
    @Published private(set) var uploads: [UploadRecord] = []
    @Published private(set) var receivedCount = 0

    var onLibraryChanged: (() -> Void)?

    private let destination: URL
    private let queue = DispatchQueue(label: "com.lin.ttplayer.wifi")
    private var listener: NWListener?
    private var activePort: UInt16 = 8088
    private let basePort: UInt16 = 8088
    private let maxPort: UInt16 = 8092

    init(destination: URL = Library.shared.musicDirectory) {
        self.destination = destination
    }

    // MARK: 生命周期

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard listener == nil else { return }
        lastError = nil
        attemptStart(port: basePort)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        address = nil
    }

    private func attemptStart(port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = true

            let newListener = try NWListener(using: parameters, on: nwPort)
            newListener.service = NWListener.Service(name: "TTPlayer", type: "_http._tcp")
            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.activePort = port
                    DispatchQueue.main.async {
                        self.isRunning = true
                        self.address = NetworkInfo.uploadURL(port: port)
                    }
                case .failed(let error):
                    let message = error.localizedDescription
                    newListener?.cancel()
                    DispatchQueue.main.async {
                        self.listener = nil
                        self.lastError = message
                        if port < self.maxPort {
                            self.attemptStart(port: port + 1)
                        } else {
                            self.isRunning = false
                            self.address = nil
                        }
                    }
                case .cancelled:
                    DispatchQueue.main.async {
                        self.isRunning = false
                    }
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener = newListener
            newListener.start(queue: queue)
        } catch {
            lastError = error.localizedDescription
            if port < maxPort {
                attemptStart(port: port + 1)
            } else {
                isRunning = false
            }
        }
    }

    // MARK: 连接

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                self.receive(on: connection, buffer: Data())
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var accumulated = buffer
            if let data = data, !data.isEmpty {
                accumulated.append(data)
            }

            if let error = error {
                NSLog("TTPlayer wifi: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            if let request = Self.parse(accumulated) {
                self.respond(to: request, on: connection)
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            if accumulated.count > 600 * 1024 * 1024 {
                self.send(
                    status: 413,
                    contentType: "application/json; charset=utf-8",
                    body: Data("{\"ok\":false,\"message\":\"单次上传过大\"}".utf8),
                    on: connection
                )
                return
            }

            self.receive(on: connection, buffer: accumulated)
        }
    }

    // MARK: 路由

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let path = String(request.path.split(separator: "?").first ?? Substring(request.path))

        switch (request.method, path) {
        case ("GET", "/"), ("GET", "/index.html"):
            send(status: 200, contentType: "text/html; charset=utf-8", body: Data(UploadPage.html.utf8), on: connection)
        case ("GET", "/api/files"):
            send(status: 200, contentType: "application/json; charset=utf-8", body: fileListJSON(), on: connection)
        case ("POST", "/upload"):
            handleUpload(request: request, on: connection)
        case ("POST", "/delete"):
            handleDelete(query: Self.queryItems(from: request.path), on: connection)
        case ("GET", "/favicon.ico"):
            send(status: 204, contentType: "text/plain", body: Data(), on: connection)
        default:
            send(status: 404, contentType: "text/plain; charset=utf-8", body: Data("Not Found".utf8), on: connection)
        }
    }

    // MARK: 上传

    private func handleUpload(request: HTTPRequest, on connection: NWConnection) {
        guard let contentType = request.headers["content-type"],
              let boundary = Self.boundary(from: contentType) else {
            send(
                status: 400,
                contentType: "application/json; charset=utf-8",
                body: Data("{\"ok\":false,\"message\":\"缺少 multipart boundary\"}".utf8),
                on: connection
            )
            return
        }

        let parts = Self.multipartParts(body: request.body, boundary: boundary)
        var saved: [String] = []
        var savedBytes: [Int] = []
        var rejected: [String] = []

        for part in parts {
            let name = sanitize(part.filename)
            guard !name.isEmpty else { continue }
            let ext = (name as NSString).pathExtension.lowercased()
            let allowed = AudioFormat.isAudio(ext)
                || AudioFormat.lyricsExtensions.contains(ext)
                || ["jpg", "jpeg", "png", "webp"].contains(ext)
            guard allowed else {
                rejected.append(name)
                continue
            }
            guard !part.data.isEmpty else { continue }

            let target = uniqueURL(for: name)
            do {
                try part.data.write(to: target, options: .atomic)
                saved.append(target.lastPathComponent)
                savedBytes.append(part.data.count)
            } catch {
                rejected.append(name)
            }
        }

        if !saved.isEmpty {
            DispatchQueue.main.async {
                for (index, name) in saved.enumerated() {
                    let bytes = index < savedBytes.count ? savedBytes[index] : 0
                    self.uploads.insert(UploadRecord(name: name, bytes: bytes), at: 0)
                }
                self.receivedCount += saved.count
                if self.uploads.count > 40 {
                    self.uploads = Array(self.uploads.prefix(40))
                }
                self.onLibraryChanged?()
            }
        }

        let payload: [String: Any] = [
            "ok": !saved.isEmpty,
            "saved": saved,
            "rejected": rejected
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        send(status: saved.isEmpty ? 400 : 200, contentType: "application/json; charset=utf-8", body: data, on: connection)
    }

    private func handleDelete(query: [String: String], on connection: NWConnection) {
        guard let raw = query["name"], !raw.isEmpty else {
            send(
                status: 400,
                contentType: "application/json; charset=utf-8",
                body: Data("{\"ok\":false,\"message\":\"缺少文件名\"}".utf8),
                on: connection
            )
            return
        }
        let name = sanitize(raw)
        let target = destination.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: target.path) else {
            send(
                status: 404,
                contentType: "application/json; charset=utf-8",
                body: Data("{\"ok\":false,\"message\":\"文件不存在\"}".utf8),
                on: connection
            )
            return
        }
        do {
            try FileManager.default.removeItem(at: target)
            DispatchQueue.main.async {
                self.uploads.removeAll { $0.name == name }
                self.onLibraryChanged?()
            }
            send(
                status: 200,
                contentType: "application/json; charset=utf-8",
                body: Data("{\"ok\":true}".utf8),
                on: connection
            )
        } catch {
            send(
                status: 500,
                contentType: "application/json; charset=utf-8",
                body: Data("{\"ok\":false,\"message\":\"删除失败\"}".utf8),
                on: connection
            )
        }
    }

    private func fileListJSON() -> Data {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let items: [[String: Any]] = contents
            .filter { AudioFormat.isAudio($0.pathExtension) || AudioFormat.lyricsExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return ["name": url.lastPathComponent, "size": size]
            }

        let payload: [String: Any] = ["ok": true, "files": items]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{\"ok\":true,\"files\":[]}".utf8)
    }

    // MARK: 响应

    private func send(status: Int, contentType: String, body: Data, on connection: NWConnection) {
        var header = "HTTP/1.1 \(status) \(Self.statusText(status))\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n\r\n"

        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: 解析工具

    private static func parse(_ buffer: Data) -> HTTPRequest? {
        let separator = Data([13, 10, 13, 10])
        guard let headerRange = buffer.range(of: separator) else { return nil }
        guard let headerText = String(data: buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound), encoding: .utf8) else {
            return nil
        }

        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        let method = String(requestLine[0]).uppercased()
        let path = String(requestLine[1])

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        let available = buffer.endIndex - bodyStart

        if contentLength > 0, available < contentLength {
            return nil
        }
        let bodyLength = min(max(0, contentLength), max(0, available))
        var body = Data()
        if bodyLength > 0 {
            body = buffer.subdata(in: bodyStart..<(bodyStart + bodyLength))
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    private static func boundary(from contentType: String) -> String? {
        for component in contentType.components(separatedBy: ";") {
            let piece = component.trimmingCharacters(in: .whitespaces)
            if piece.lowercased().hasPrefix("boundary=") {
                var value = String(piece.dropFirst("boundary=".count))
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count > 1 {
                    value = String(value.dropFirst().dropLast())
                }
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private static func multipartParts(body: Data, boundary: String) -> [(filename: String, data: Data)] {
        let delimiter = Data(("--" + boundary).utf8)
        var parts: [(filename: String, data: Data)] = []
        var segments: [Data] = []

        var cursor = body.startIndex
        while let range = body.range(of: delimiter, in: cursor..<body.endIndex) {
            if range.lowerBound > cursor {
                segments.append(body.subdata(in: cursor..<range.lowerBound))
            }
            cursor = range.upperBound
        }

        for segment in segments {
            var piece = Data(segment)
            if piece.count >= 2, piece.prefix(2).elementsEqual([13, 10]) {
                piece = Data(piece.dropFirst(2))
            }
            if piece.isEmpty || piece.starts(with: Data("--".utf8)) {
                continue
            }
            guard let headerEnd = piece.range(of: Data([13, 10, 13, 10])) else { continue }
            let headerText = String(
                decoding: piece.subdata(in: piece.startIndex..<headerEnd.lowerBound),
                as: UTF8.self
            )
            var content = Data(piece[headerEnd.upperBound..<piece.endIndex])
            if content.count >= 2, content.suffix(2).elementsEqual([13, 10]) {
                content = Data(content.dropLast(2))
            }
            guard let filename = filename(from: headerText) else { continue }
            parts.append((filename, content))
        }

        return parts
    }

    private static func filename(from headerText: String) -> String? {
        guard let range = headerText.range(of: "filename=\"") else { return nil }
        let remainder = headerText[range.upperBound...]
        guard let end = remainder.firstIndex(of: "\"") else { return nil }
        let name = String(remainder[remainder.startIndex..<end])
        return name.isEmpty ? nil : name
    }

    private static func queryItems(from path: String) -> [String: String] {
        guard let questionIndex = path.firstIndex(of: "?") else { return [:] }
        let query = path[path.index(after: questionIndex)...]
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }
            let rawKey = String(pieces[0])
            let rawValue = String(pieces[1]).replacingOccurrences(of: "+", with: " ")
            let key = rawKey.removingPercentEncoding ?? rawKey
            let value = rawValue.removingPercentEncoding ?? rawValue
            result[key] = value
        }
        return result
    }

    private static func statusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }

    private func sanitize(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: "\\", with: "/")
        name = (name as NSString).lastPathComponent
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        name = name.components(separatedBy: forbidden).joined(separator: "_")
        if name.hasPrefix(".") {
            name = "_" + String(name.dropFirst())
        }
        if name.count > 120 {
            name = String(name.prefix(120))
        }
        return name
    }

    private func uniqueURL(for name: String) -> URL {
        let fileManager = FileManager.default
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = destination.appendingPathComponent(name)
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let fileName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = destination.appendingPathComponent(fileName)
            counter += 1
        }
        return candidate
    }
}
