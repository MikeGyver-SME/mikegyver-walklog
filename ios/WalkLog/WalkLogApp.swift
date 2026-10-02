import SwiftUI

@main
struct WalkLogApp: App {
    @StateObject private var session = WalkSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}
