import SwiftUI
import NetworkExtension

struct VPNServer: Identifiable {
    let id = UUID()
    let title: String
    let server: String
    let remoteId: String
    let country: String
    let description: String
}

struct VPNConfigView: View {
    @StateObject private var vpn = VPNManager.shared
    @State private var showAddSheet = false
    @State private var selectedServer: VPNServer?
    @State private var errorMessage: String?
    @State private var showError = false

    let presetServers: [VPNServer] = [
        VPNServer(title: "VPN 🇳🇱 Amsterdam", server: "ams.vpn.example.com", remoteId: "ams.vpn.example.com", country: "Netherlands", description: "Бесплатный тестовый сервер (замените на свой)"),
        VPNServer(title: "VPN 🇩🇪 Frankfurt", server: "fra.vpn.example.com", remoteId: "fra.vpn.example.com", country: "Germany", description: "Бесплатный тестовый сервер (замените на свой)"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: vpn.status == .connected ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 48))
                            .foregroundColor(vpn.status == .connected ? .green : .secondary)

                        StatusBadge(status: vpn.status)

                        if vpn.status == .connected {
                            Text("Всё защищено")
                                .font(.headline)
                                .foregroundColor(.green)
                        }

                        Button(action: toggleVPN) {
                            HStack {
                                if vpn.isConnecting {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(vpn.status == .connected ? "Отключиться" : "Подключиться")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(vpn.status == .connected ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(vpn.isConnecting)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }

                Section("Серверы VPN") {
                    ForEach(presetServers) { server in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.title)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(server.server)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(server.description)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            if selectedServer?.id == server.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedServer = server
                        }
                    }
                }

                Section {
                    Button(action: { showAddSheet = true }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Добавить свой сервер")
                        }
                    }
                }
            }
            .navigationTitle("VPN")
            .sheet(isPresented: $showAddSheet) {
                CustomServerView { server, remoteId in
                    selectedServer = VPNServer(
                        title: "VPN \(server)",
                        server: server,
                        remoteId: remoteId,
                        country: "Custom",
                        description: "Пользовательский сервер"
                    )
                }
            }
            .alert("Ошибка", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
        }
    }

    private func toggleVPN() {
        Task {
            if vpn.status == .connected {
                vpn.disconnect()
            } else {
                await connectVPN()
            }
        }
    }

    private func connectVPN() async {
        guard let server = selectedServer else {
            errorMessage = "Выберите сервер"
            showError = true
            return
        }

        do {
            try await vpn.configure(server: server.server, remoteId: server.remoteId)
            try vpn.connect()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

struct StatusBadge: View {
    let status: NEVPNStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    var color: Color {
        switch status {
        case .connected: return .green
        case .connecting, .disconnecting: return .orange
        case .disconnected, .invalid: return .gray
        @unknown default: return .gray
        }
    }

    var text: String {
        switch status {
        case .connected: return "Подключено"
        case .connecting: return "Подключение..."
        case .disconnecting: return "Отключение..."
        case .disconnected: return "Отключено"
        case .invalid: return "Не настроено"
        @unknown default: return "Неизвестно"
        }
    }
}

struct CustomServerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var server = ""
    @State private var remoteId = ""
    let onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Параметры IKEv2") {
                    TextField("Адрес сервера (IP или домен)", text: $server)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Remote ID", text: $remoteId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section("Где взять сервер?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Купите VPS на DigitalOcean / Vultr / Hetzner")
                            .font(.caption)
                        Text("2. Установите StrongSwan: sudo apt install strongswan")
                            .font(.caption)
                        Text("3. Настройте IKEv2 сервер (есть готовые скрипты)")
                            .font(.caption)
                        Text("4. Введите IP и Remote ID здесь")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Свой сервер")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard !server.isEmpty, !remoteId.isEmpty else { return }
                        onSave(server, remoteId)
                        dismiss()
                    }
                    .disabled(server.isEmpty || remoteId.isEmpty)
                }
            }
        }
    }
}
