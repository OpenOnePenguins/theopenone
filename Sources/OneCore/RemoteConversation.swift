import Foundation
import CryptoKit

public enum PhoneConnection {
    /// Opens the installed iOS app. This is a pairing link, never an install link.
    public static func appURL(from connection: URL) -> URL? {
        guard var endpoint = URLComponents(url: connection, resolvingAgainstBaseURL: false),
              endpoint.scheme == "https", let host = endpoint.host, !host.isEmpty,
              endpoint.user == nil, endpoint.password == nil, endpoint.query == nil,
              ["", "/"].contains(endpoint.path), let token = endpoint.fragment,
              token.range(of: "^[A-Za-z0-9_-]{32,256}$", options: .regularExpression) != nil else { return nil }
        endpoint.fragment = nil
        guard let address = endpoint.url?.absoluteString else { return nil }
        var link = URLComponents()
        link.scheme = "open-one"; link.host = ""; link.path = "/"
        link.queryItems = [URLQueryItem(name: "endpoint", value: address)]
        link.fragment = token
        return link.url
    }
}

public extension Agent {
    /// Opaque recipient fence; paths and provider homes never leave the Mac.
    var remoteConversationKey: String {
        let fields = [id, provider, directory, sessionID ?? "", sourcePath ?? "", providerHome ?? ""]
        let data = (try? JSONEncoder().encode(fields)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var canReceiveRemotely: Bool {
        !isHerdr && (state != .working || canQueue) && (canReceive || canResume || canQueue)
    }
    var remoteReadOnlyReason: String {
        if isHerdr { return "Continue this terminal on your Mac." }
        if state == .working && !canQueue { return "The agent is working. Wait for its reply." }
        if !canReceiveRemotely { return "This conversation has no available reply channel. Open it on your Mac." }
        return ""
    }
}
