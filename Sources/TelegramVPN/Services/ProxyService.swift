import Foundation
import UIKit
import Network

enum ProxyChecker {
    static func check(_ proxy: Proxy) async -> TimeInterval {
        let start = Date()
        let connection = NWConnection(
            host: NWEndpoint.Host(proxy.server),
            port: NWEndpoint.Port(integerLiteral: UInt16(proxy.port)),
            using: .tcp
        )

        return await withCheckedContinuation { continuation in
            var didResume = false
            connection.stateUpdateHandler = { state in
                guard !didResume else { return }
                switch state {
                case .ready:
                    didResume = true
                    let latency = Date().timeIntervalSince(start)
                    connection.cancel()
                    continuation.resume(returning: latency)
                case .failed:
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: -1)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                guard !didResume else { return }
                didResume = true
                connection.cancel()
                continuation.resume(returning: -1)
            }
        }
    }
}

enum ProxyFetcher {
    static func fetchFromSources() async -> [Proxy] {
        await withTaskGroup(of: [Proxy].self) { group in
            for source in sources {
                group.addTask { await source.fetch() }
            }
            var all: [Proxy] = []
            for await proxies in group {
                all.append(contentsOf: proxies)
            }
            return all
        }
    }

    private static let sources: [ProxySource] = [
        MTSocksAPI(),
        Proxy6Source(),
    ]
}

protocol ProxySource {
    func fetch() async -> [Proxy]
}

struct MTSocksAPI: ProxySource {
    func fetch() async -> [Proxy] {
        guard let url = URL(string: "https://mtproto-socks5.vercel.app/api/v1/proxies") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([APIProxy].self, from: data)
            return decoded.enumerated().map { (i, p) in
                Proxy(
                    server: p.server,
                    port: p.port,
                    secret: p.secret,
                    title: "MTProto #\(i + 1) \(flag(from: p.country))",
                    country: p.country
                )
            }
        } catch {
            return []
        }
    }

    struct APIProxy: Codable {
        let server: String
        let port: Int
        let secret: String
        let country: String
    }
}

struct Proxy6Source: ProxySource {
    func fetch() async -> [Proxy] {
        let servers: [(String, Int, String, String)] = [
            ("45.88.79.119", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Netherlands"),
            ("185.230.162.201", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Netherlands"),
            ("91.108.56.251", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "United Kingdom"),
            ("212.119.47.168", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Germany"),
            ("149.154.167.91", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Russia"),
            ("5.45.121.194", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Finland"),
            ("95.161.225.3", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Germany"),
            ("77.91.68.20", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Netherlands"),
            ("91.108.56.100", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "United Kingdom"),
            ("185.126.255.1", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Russia"),
            ("91.108.56.150", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "United Kingdom"),
            ("91.108.56.170", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "United Kingdom"),
            ("91.108.56.115", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "United Kingdom"),
            ("5.45.121.195", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Finland"),
            ("5.45.121.196", 443, "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", "Finland"),
        ]
        return servers.enumerated().map { (i, s) in
            Proxy(server: s.0, port: s.1, secret: s.2, title: "Proxy #\(i + 1) \(flag(from: s.3))", country: s.3)
        }
    }
}

actor ProxyService {
    static let shared = ProxyService()

    private let defaults = UserDefaults.standard
    private let proxiesKey = "cached_proxies"

    func getProxies() async -> [Proxy] {
        let cached = loadCached()
        let fetched = await ProxyFetcher.fetchFromSources()
        let all = cached + fetched.filter { f in !cached.contains(where: { $0.server == f.server }) }
        cache(all)
        return all
    }

    func connect(to proxy: Proxy) async {
        guard let url = proxy.tgUrl else { return }
        await MainActor.run {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    print("Не удалось открыть Telegram. Убедитесь, что Telegram установлен.")
                }
            }
        }
    }

    private func loadCached() -> [Proxy] {
        guard let data = defaults.data(forKey: proxiesKey),
              let proxies = try? JSONDecoder().decode([Proxy].self, from: data) else {
            return []
        }
        return proxies
    }

    private func cache(_ proxies: [Proxy]) {
        guard let data = try? JSONEncoder().encode(proxies) else { return }
        defaults.set(data, forKey: proxiesKey)
    }
}

private func flag(from country: String) -> String {
    switch country.lowercased() {
    case "netherlands": return "🇳🇱"
    case "united kingdom", "uk": return "🇬🇧"
    case "germany": return "🇩🇪"
    case "russia": return "🇷🇺"
    case "finland": return "🇫🇮"
    case "france": return "🇫🇷"
    case "usa", "united states": return "🇺🇸"
    case "japan": return "🇯🇵"
    case "singapore": return "🇸🇬"
    default: return "🌍"
    }
}
