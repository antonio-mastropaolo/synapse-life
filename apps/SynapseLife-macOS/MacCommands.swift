#if os(macOS)
import SwiftUI
import AppKit
import Features
import Auth
import DesignSystem

/// Menu-bar `Commands` for the macOS shell. Polish pass: replaces the
/// flat `CommandGroup(after: .toolbar)` block with proper menus so the
/// Mac shell reads as a native citizen — "Surfaces" appears alongside
/// File / Edit / View / Window / Help, and the operator can discover
/// every keyboard shortcut from the menu bar itself.
///
/// The commands target the routing VM (`RootShellViewModel`) and the
/// shell flags owned by the @main scene (`isAskPresented`,
/// `sidebarVisible`). Wiring is by `@Binding` rather than reaching for
/// global state so the @main scene stays the single owner of those
/// flags.
struct MacCommands: Commands {

    @Bindable var routing: RootShellViewModel
    @Binding var isAskPresented: Bool
    @Binding var sidebarVisible: Bool
    @Bindable var auth: AuthViewModel

    var body: some Commands {

        // File > New is meaningless for Synapse — the app has no
        // document model. Replacing the slot keeps the menu honest.
        CommandGroup(replacing: .newItem) {}

        // Surfaces menu. Cmd-1..5 mirror what most Mac apps with a
        // sidebar expose (Mail, Messages, Notes). Cmd-K is the
        // command-palette / Ask entry point; the Ask sheet is the live
        // intelligence surface and the command palette is its
        // sidebar-routing sibling, both reachable from the same
        // muscle-memory keystroke.
        CommandMenu("Surfaces") {
            Button("Dashboard") { routing.select(.dashboard) }
                .keyboardShortcut("1", modifiers: [.command])
            Button("Activity") { routing.select(.activity) }
                .keyboardShortcut("2", modifiers: [.command])
            Button("Finance") { routing.select(.transactions) }
                .keyboardShortcut("3", modifiers: [.command])
            Button("Advisors") { routing.select(.advisors) }
                .keyboardShortcut("4", modifiers: [.command])
            // Cmd-5 opens Settings (mirrors macOS' system Settings
            // shortcut feel without colliding with the system one,
            // Cmd-,, which we leave to AppKit).
            Button("Settings") { openSystemSettings() }
                .keyboardShortcut("5", modifiers: [.command])

            Divider()

            // Sub-section for the deeper sidebar destinations. These
            // do not carry their own shortcut because the top five
            // already absorb the muscle-memory range; the menu is the
            // discoverability surface for them.
            Button("Transactions")  { routing.select(.transactions) }
            Button("Goals")         { routing.select(.goals) }
            Button("Accounts")      { routing.select(.accounts) }
            Button("Investments")   { routing.select(.investments) }
            Button("Categories")    { routing.select(.categories) }
            Button("Recurrings")    { routing.select(.recurrings) }
            Button("Memberships")   { routing.select(.memberships) }
            Button("Digest")        { routing.select(.digest) }
            Button("Forecast")      { routing.select(.forecast) }
            Button("Smart alerts")  { routing.select(.smartAlerts) }

            Divider()

            Button("Command Palette…") { isAskPresented = true }
                .keyboardShortcut("k", modifiers: [.command])
        }

        // Window > Toggle Sidebar — slots in after the system
        // `windowSize` group so it lives right where AppKit hosts the
        // built-in "Minimize / Zoom / Bring All To Front" cluster.
        // Cmd-Ctrl-S mirrors Mail / Notes' sidebar toggle and avoids
        // the Cmd-S "Save" muscle.
        CommandGroup(after: .windowSize) {
            Divider()
            Button(sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                withAnimation(DS.Motion.smooth) {
                    sidebarVisible.toggle()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .accessibilityIdentifier("mac.commands.toggleSidebar")
        }

        // Account menu (replaces the NSToolbar trailing identity menu,
        // which `.windowStyle(.hiddenTitleBar)` precludes). Surfaces
        // the signed-in user + the same actions the toolbar button
        // would carry: Settings, Sign Out, Delete Account.
        CommandMenu("Account") {
            switch auth.state {
            case .signedOut, .signingIn, .error:
                Text("Not signed in").foregroundStyle(.secondary)
                Divider()
                Button("Sign In…") { openSystemSettings() }
            case .signedIn(let session):
                Text(session.userId).foregroundStyle(.secondary)
                Divider()
                Button("Settings…") { openSystemSettings() }
                    .keyboardShortcut(",", modifiers: [.command])
                Divider()
                Button("Sign Out") {
                    Task { await auth.signOut() }
                }
                Button("Delete Account…") {
                    Task { await auth.deleteAccount() }
                }
            }
        }

        // Help additions — link to the backend the desktop app reads
        // from so the operator can pop the relevant web surface open
        // for cross-checks.
        CommandGroup(after: .help) {
            Divider()
            Link(
                "Open synapse-v2 backend",
                destination: URL(string: "https://synapse.tech")!
            )
        }
    }

    /// macOS 14+ `openSettings()` requires an `Environment` value; we
    /// cannot inject one into a `Commands` value, so we route through
    /// the AppKit equivalent. `showSettingsWindow:` is the modern
    /// selector used by `NSApp` when the `Settings { ... }` scene is
    /// declared.
    private func openSystemSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
#endif
