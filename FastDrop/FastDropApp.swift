import SwiftUI

@main
struct FastDropApp: App {
    @StateObject private var settings = SettingsService.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(settings)
                .tint(.fdAccent)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
