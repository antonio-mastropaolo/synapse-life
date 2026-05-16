#if os(macOS)
import AppKit
import SwiftUI
import Models
import Features
import Networking
import DesignSystem

@MainActor
final class SpotlightPanelController {

    private var panel: NSPanel?
    private let viewModel: SpotlightViewModel
    private let auth: AuthViewModel

    init(viewModel: SpotlightViewModel, auth: AuthViewModel) {
        self.viewModel = viewModel
        self.auth = auth
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let size = panel.frame.size
            let origin = NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2 + 60
            )
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let root = SpotlightPanelHost(viewModel: viewModel, auth: auth)
            .identity(.editorial)
            .frame(minWidth: 720, minHeight: 480)
        let hosting = NSHostingView(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Spotlight"
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        return panel
    }
}

private struct SpotlightPanelHost: View {
    @Bindable var viewModel: SpotlightViewModel
    @Bindable var auth: AuthViewModel

    var body: some View {
        Group {
            if case .signedIn = auth.state {
                SpotlightPanelView(
                    state: viewModel.state,
                    selected: viewModel.selected,
                    query: viewModel.query,
                    onQueryChange: { viewModel.setQuery($0) },
                    onSelect: { viewModel.select($0) }
                )
                .task { await viewModel.refresh() }
            } else {
                SignedOutPanel()
            }
        }
    }
}

private struct SignedOutPanel: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = theme.tokens(for: scheme)
        ZStack {
            tokens.background.color
            VStack(spacing: 8) {
                Text("Sign in to use Spotlight")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tokens.foregroundPrimary.color)
                Text("Open Synnapse → Settings to sign in with Apple.")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foregroundSecondary.color)
            }
        }
    }
}
#endif
