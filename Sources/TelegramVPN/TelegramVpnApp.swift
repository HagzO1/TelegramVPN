import SwiftUI

@main
struct TelegramVpnApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("Прокси", systemImage: "point.3.connected.trianglepath.dotted")
                    }

                VPNConfigView()
                    .tabItem {
                        Label("VPN", systemImage: "lock.shield")
                    }
            }
        }
    }
}
