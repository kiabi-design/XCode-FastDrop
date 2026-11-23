import SwiftUI

@main
struct FastDropApp: App {
    @StateObject private var settings = SettingsService.shared
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(settings.isWhiteTheme ? .light : .dark)
                .environmentObject(settings)
        }
    }
}
