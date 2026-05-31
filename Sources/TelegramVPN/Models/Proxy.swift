import Foundation

struct Proxy: Identifiable, Codable {
    let id = UUID()
    let server: String
    let port: Int
    let secret: String
    let title: String
    let country: String?
    var latency: TimeInterval?
    var isActive: Bool = false

    var tgUrl: URL? {
        var components = URLComponents()
        components.scheme = "tg"
        components.host = "proxy"
        components.queryItems = [
            URLQueryItem(name: "server", value: server),
            URLQueryItem(name: "port", value: "\(port)"),
            URLQueryItem(name: "secret", value: secret)
        ]
        return components.url
    }

    var displayLatency: String {
        guard let latency else { return "—" }
        if latency < 0 { return "Недоступен" }
        return String(format: "%.0f мс", latency)
    }
}
