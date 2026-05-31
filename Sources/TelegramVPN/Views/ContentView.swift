import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ProxyViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)

                        Text("Бесплатный прокси для Telegram")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        Text("Нажмите на прокси, чтобы подключиться через Telegram")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }

                Section("Прокси серверы") {
                    if viewModel.proxies.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Загрузка прокси...")
                            Spacer()
                        }
                    }

                    ForEach(viewModel.proxies) { proxy in
                        ProxyRow(proxy: proxy)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.connect(to: proxy)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Проверить") {
                                    Task { await viewModel.checkProxy(proxy) }
                                }
                                .tint(.orange)
                            }
                    }
                }
            }
            .navigationTitle("Telegram VPN")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshProxies() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Проверить все") {
                        Task { await viewModel.checkAllProxies() }
                    }
                    .font(.subheadline)
                }
            }
            .overlay {
                if viewModel.isChecking {
                    VStack {
                        Spacer()
                        HStack {
                            ProgressView()
                            Text("Проверка прокси...")
                                .font(.caption)
                                .padding(.leading, 4)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 20)
                    }
                }
            }
        }
    }
}

struct ProxyRow: View {
    let proxy: Proxy

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(proxy.latency.map { $0 >= 0 ? Color.green : Color.red } ?? .gray)
                        .frame(width: 8, height: 8)

                    Text(proxy.title)
                        .font(.body)
                        .fontWeight(.medium)
                }

                Text("\(proxy.server):\(proxy.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let country = proxy.country {
                    Text(country)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(proxy.displayLatency)
                    .font(.caption)
                    .foregroundColor(proxy.latency.map { $0 >= 0 ? .green : .red } ?? .secondary)

                Text("Нажмите для подключения")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class ProxyViewModel: ObservableObject {
    @Published var proxies: [Proxy] = []
    @Published var isChecking = false

    private let service = ProxyService.shared

    init() {
        Task { await loadProxies() }
    }

    func loadProxies() async {
        proxies = await service.loadProxies()
        await checkAllProxies()
    }

    func connect(to proxy: Proxy) {
        Task {
            await service.connect(to: proxy)
        }
    }

    func checkProxy(_ proxy: Proxy) async {
        guard let idx = proxies.firstIndex(where: { $0.id == proxy.id }) else { return }
        let latency = await ProxyChecker.check(proxy)
        proxies[idx].latency = latency
    }

    func checkAllProxies() async {
        isChecking = true
        let currentProxies = proxies
        let results = await withTaskGroup(of: (Int, TimeInterval).self) { group in
            for (idx, proxy) in currentProxies.enumerated() {
                group.addTask {
                    let latency = await ProxyChecker.check(proxy)
                    return (idx, latency)
                }
            }

            var collected: [(Int, TimeInterval)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        for (idx, latency) in results {
            if idx < proxies.count {
                proxies[idx].latency = latency
            }
        }
        isChecking = false
    }

    func refreshProxies() async {
        proxies = await service.loadProxies()
        await checkAllProxies()
    }
}
