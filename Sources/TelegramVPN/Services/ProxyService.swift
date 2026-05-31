import Foundation
import UIKit

enum ProxyChecker {
    static func check(_ proxy: Proxy) async -> TimeInterval {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let start = Date()

                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = CFSwapInt16HostToBig(UInt16(proxy.port))

                guard let host = CFHostCreateWithName(nil, proxy.server as CFString).takeRetainedValue() as CFHost? else {
                    continuation.resume(returning: -1)
                    return
                }

                var resolved = DarwinBoolean(false)
                CFHostStartInfoResolution(host, .addresses, nil)
                guard let addresses = CFHostGetAddressing(host, &resolved)?.takeUnretainedValue() as? [Data],
                      let firstAddress = addresses.first else {
                    continuation.resume(returning: -1)
                    return
                }

                firstAddress.withUnsafeBytes { ptr in
                    guard let base = ptr.baseAddress else { return }
                    memcpy(&addr, base, MemoryLayout<sockaddr_in>.size)
                }
                addr.sin_port = CFSwapInt16HostToBig(UInt16(proxy.port))

                let sock = socket(AF_INET, SOCK_STREAM, 0)
                guard sock >= 0 else { continuation.resume(returning: -1); return }

                var timeVal = timeval(tv_sec: 3, tv_usec: 0)
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeVal, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeVal, socklen_t(MemoryLayout<timeval>.size))

                let connectResult = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                close(sock)

                guard connectResult == 0 else { continuation.resume(returning: -1); return }
                continuation.resume(returning: Date().timeIntervalSince(start))
            }
        }
    }
}

actor ProxyService {
    static let shared = ProxyService()

    private let defaults = UserDefaults.standard
    private let proxiesKey = "saved_proxies"

    let builtinProxies: [Proxy] = [
        Proxy(server: "45.88.79.119", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 1 🇳🇱", country: "Netherlands"),
        Proxy(server: "185.230.162.201", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 2 🇳🇱", country: "Netherlands"),
        Proxy(server: "91.108.56.251", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 3 🇬🇧", country: "United Kingdom"),
        Proxy(server: "212.119.47.168", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 4 🇩🇪", country: "Germany"),
        Proxy(server: "149.154.167.91", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 5 🇷🇺", country: "Russia"),
        Proxy(server: "5.45.121.194", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 6 🇫🇮", country: "Finland"),
        Proxy(server: "95.161.225.3", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 7 🇩🇪", country: "Germany"),
        Proxy(server: "77.91.68.20", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 8 🇳🇱", country: "Netherlands"),
        Proxy(server: "91.108.56.100", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 9 🇬🇧", country: "United Kingdom"),
        Proxy(server: "185.126.255.1", port: 443, secret: "eeef0a6b0f3130303d30ad871b1cf4e1b4b2656f72616e67652e636f6d", title: "Proxy 10 🇷🇺", country: "Russia"),
    ]

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

    func loadProxies() -> [Proxy] {
        guard let data = defaults.data(forKey: proxiesKey),
              let proxies = try? JSONDecoder().decode([Proxy].self, from: data) else {
            return builtinProxies
        }
        return proxies + builtinProxies
    }

    func saveProxies(_ proxies: [Proxy]) {
        guard let data = try? JSONEncoder().encode(proxies) else { return }
        defaults.set(data, forKey: proxiesKey)
    }
}
