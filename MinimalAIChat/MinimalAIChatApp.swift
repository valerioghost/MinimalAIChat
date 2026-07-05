import SwiftUI
import UIKit

@main
struct MinimalAIChatApp: App {

    /// Using the `wrappedValue:` closure form guarantees that SwiftUI
    /// controls the exact moment these objects are first created — after
    /// its internal storage is ready — eliminating the first-launch white
    /// screen caused by a race between App.init() and the initial render.
    @StateObject private var settings = SettingsViewModel()

    /// ChatViewModel needs a reference to settings. We wire it up lazily
    /// in ContentView (which already receives settings via @EnvironmentObject)
    /// so we don't need to construct it here at all.
    @StateObject private var viewModel: ChatViewModel = {
        // SettingsViewModel is cheap to construct; we create a temporary one
        // just to satisfy ChatViewModel's init. The real one injected via
        // .environmentObject() is what the rest of the app reads.
        // NOTE: the shared instance below is replaced by the pattern in
        //       ChatViewModelFactory — see the note inside ChatViewModel.
        ChatViewModel(settings: SettingsViewModel())
    }()

    init() {
        MinimalAIChatApp.configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(viewModel)
        }
    }

    // MARK: - Navigation Bar Appearance (iOS 15 compatible)
    //
    // .toolbarBackground(.visible) requires iOS 16+.
    // On iOS 15 the only reliable way to force an opaque, non-transparent
    // navigation bar regardless of scroll position is UIAppearance, applied
    // once before any view is rendered (i.e. inside App.init).

    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()

        // Opaque background using the system's grouped background colour
        // so it adapts automatically to light / dark mode.
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground

        // Remove the 1 pt hairline separator — SwiftUI Divider() handles it
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.3)

        // Apply the same appearance to every navigation bar state:
        //  • standardAppearance  — normal scroll position
        //  • scrollEdgeAppearance — when the content is scrolled all the way up
        //  • compactAppearance   — landscape / compact height
        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance    = appearance
    }
}

// MARK: - RootView
// A thin wrapper whose sole job is to ensure both @EnvironmentObjects are
// present before delegating to ContentView. This eliminates the white-screen
// race on iOS 15 by deferring ContentView's appearance to the NEXT render
// cycle, at which point the objects are guaranteed to be in SwiftUI's graph.

private struct RootView: View {

    @EnvironmentObject private var settings: SettingsViewModel
    @EnvironmentObject private var viewModel: ChatViewModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                ContentView()
            } else {
                // Transparent placeholder so layout does not flash
                Color(.systemBackground)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            // Wire the real settings into the view model now that both
            // objects are fully injected into the environment.
            viewModel.configure(settings: settings)

            // Defer the reveal one frame so SwiftUI finishes committing
            // all @StateObject values before the real UI appears.
            DispatchQueue.main.async {
                isReady = true
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                viewModel.cancelInFlightTask()
            }
        }
    }
}
