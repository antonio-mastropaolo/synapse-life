import SwiftUI
import SwiftData
import AppKit
import Auth
import Features
import Networking
import Models
import DesignSystem
import AppLifecycle

@main
struct SynnapseMacApp: App {

    /// Single construction seam shared with the iOS shell. Owns every VM and
    /// the persistence stores; the scene below is just platform glue.
    @State private var core = AppCore(
        useDemoData: ProcessInfo.processInfo.environment["SYNNAPSE_USE_DEMO"] == "1"
    )
    @State private var routing = RootShellViewModel()
    /// Whether the Ask sheet is currently presented. The keystroke
    /// (`⌘K`) and the legacy command-bar entry points both flip this
    /// flag; the sheet itself is rendered as a centered overlay so it
    /// can use the same focus / dim semantics as the previous
    /// `CommandBarView` while delivering the richer
    /// `IntelligenceAskView` answer surface.
    @State private var isAskPresented: Bool = false

    var body: some Scene {
        WindowGroup("Synapse") {
            ZStack(alignment: .top) {
                CopilotShellMac(
                    routing: routing,
                    personal: core.financePersonal,
                    accounts: core.financeAccounts,
                    transactions: core.financeTransactions,
                    investments: core.financeInvestments,
                    lifeAPI: core.lifeAPI,
                    advisors: core.advisors,
                    dashboard: core.dashboard,
                    categories: core.categories,
                    digest: core.digest,
                    forecast: core.forecast,
                    smartAlerts: core.smartAlerts,
                    subscriptions: core.subscriptions,
                    recurrings: core.recurrings,
                    memberships: core.memberships,
                    goals: core.goals,
                    showsDemoDataFooter: core.usesDemoData
                )

                if isAskPresented {
                    // Dim and absorb taps so a click outside the sheet
                    // dismisses — same affordance the legacy command
                    // bar used. The new Ask surface itself owns the
                    // dismiss control inside its header.
                    Color.black.opacity(0.30)
                        .ignoresSafeArea()
                        .onTapGesture { closeAsk() }
                        .transition(.opacity)

                    IntelligenceAskView(
                        viewModel: core.intelligenceAsk,
                        onCitationTap: { citation in
                            routeCitation(citation)
                        },
                        onDismiss: { closeAsk() }
                    )
                    .padding(.top, 84)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isAskPresented)
            .frame(minWidth: 1080, minHeight: 720)
            .task { await core.bootstrap() }
            .onOpenURL { url in
                core.lifecycle.handle(url: url)
            }
            // Inject the shared SwiftData container so a future widget /
            // share-extension and any `@Query`-driven descendant read the
            // same store the persistence actors write through.
            .modelContainer(core.modelContainer)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            // Sidebar keyboard shortcuts. Each command targets the
            // routing VM so the main window updates in place — no
            // secondary windows.
            CommandGroup(after: .toolbar) {
                Button("Ask Synapse") { openAsk() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Dashboard") { routing.select(.dashboard) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Transactions") { routing.select(.transactions) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Accounts") { routing.select(.accounts) }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Investments") { routing.select(.investments) }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Life") { routing.select(.life) }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Advisors") { routing.select(.advisors) }
                    .keyboardShortcut("7", modifiers: [.command])
                Button("Categories") { routing.select(.categories) }
                    .keyboardShortcut("8", modifiers: [.command])
                // INTELLIGENCE section
                Button("Weekly Digest") { routing.select(.digest) }
                    .keyboardShortcut("9", modifiers: [.command])
                Button("Forecast") { routing.select(.forecast) }
                    .keyboardShortcut("0", modifiers: [.command])
                Button("Smart Alerts") { routing.select(.smartAlerts) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsScene(settings: core.settings, auth: core.auth)
        }
    }

    // MARK: - Ask sheet

    private func openAsk() {
        // Refresh the route badge in case the system intelligence
        // availability flipped (e.g. user toggled Apple Intelligence
        // in System Settings between launches).
        isAskPresented = true
    }

    private func closeAsk() {
        core.intelligenceAsk.cancel()
        isAskPresented = false
    }

    /// Route an Ask citation chip tap to the matching sidebar
    /// destination. Per the AI++ manifest section 5: transactions and
    /// accounts route through Transactions / Accounts, category chips
    /// land on Categories, and insight chips dismiss the sheet (they
    /// will route to the Insights surface once it lands).
    private func routeCitation(_ citation: AskCitation) {
        switch citation.kind {
        case .transaction, .account:
            routing.select(.transactions)
        case .category:
            routing.select(.categories)
        case .insight:
            break
        }
        closeAsk()
    }
}
