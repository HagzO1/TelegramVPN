import Foundation
import NetworkExtension

@MainActor
class VPNManager: ObservableObject {
    static let shared = VPNManager()

    @Published var status: NEVPNStatus = .invalid
    @Published var isConnecting = false

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            self?.status = connection.status
            self?.isConnecting = (connection.status == .connecting || connection.status == .disconnecting)
        }
        status = manager.connection.status
    }

    private var manager: NEVPNManager {
        NEVPNManager.shared()
    }

    func configure(server: String, remoteId: String, localId: String? = nil, username: String? = nil, password: String? = nil) async throws {
        try await manager.loadFromPreferences()

        let protocolConfig = NEVPNProtocolIKEv2()
        protocolConfig.serverAddress = server
        protocolConfig.remoteIdentifier = remoteId
        protocolConfig.localIdentifier = localId ?? remoteId
        protocolConfig.authenticationMethod = .none
        protocolConfig.useExtendedAuthentication = username != nil
        protocolConfig.disconnectOnSleep = false
        protocolConfig.enablePFS = true
        protocolConfig.deadPeerDetectionRate = .low
        protocolConfig.childSecurityAssociationParameters.encryptionAlgorithm = .algorithmAES256
        protocolConfig.childSecurityAssociationParameters.integrityAlgorithm = .SHA256
        protocolConfig.childSecurityAssociationParameters.diffieHellmanGroup = .group14
        protocolConfig.childSecurityAssociationParameters.lifetimeMinutes = 1440
        protocolConfig.ikeSecurityAssociationParameters.encryptionAlgorithm = .algorithmAES256
        protocolConfig.ikeSecurityAssociationParameters.integrityAlgorithm = .SHA256
        protocolConfig.ikeSecurityAssociationParameters.diffieHellmanGroup = .group14
        protocolConfig.ikeSecurityAssociationParameters.lifetimeMinutes = 1440

        if let username = username {
            protocolConfig.username = username
            let keychainEntry = "\(username)@\(server)"
            if let password = password {
                protocolConfig.passwordReference = try await addToKeychain(account: keychainEntry, password: password)
            }
        }

        manager.protocolConfiguration = protocolConfig
        manager.isEnabled = true

        try await manager.saveToPreferences()
    }

    func connect() throws {
        try manager.connection.startVPNTunnel()
    }

    func disconnect() {
        manager.connection.stopVPNTunnel()
    }

    func removeConfig() async throws {
        try await manager.loadFromPreferences()
        manager.isEnabled = false
        manager.protocolConfiguration = nil
        try await manager.saveToPreferences()
    }

    private func addToKeychain(account: String, password: String) async throws -> Data {
        let persistentRef = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DispatchQueue.global().async {
                let keychainQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: account,
                    kSecAttrService as String: "VPNPassword",
                    kSecValueData as String: password.data(using: .utf8)!,
                    kSecReturnPersistentRef as String: true,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                ]

                SecItemDelete(keychainQuery as CFDictionary)
                var ref: CFTypeRef?
                let status = SecItemAdd(keychainQuery as CFDictionary, &ref)
                if status == errSecSuccess, let data = ref as? Data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "VPNManager", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain error: \(status)"]))
                }
            }
        }
        return persistentRef
    }
}
