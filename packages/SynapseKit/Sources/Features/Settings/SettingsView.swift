import SwiftUI
import Auth
import DesignSystem

/// macOS Settings scene content. The integrator wires this into the
/// `Settings { ... }` scene at the app shell; on iOS the same view model
/// drives `SettingsForm` (a plain `Form` rooted under the "More" tab).
@MainActor
public struct SettingsScene: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var settings: SettingsViewModel
    private let auth: AuthViewModel

    public init(settings: SettingsViewModel, auth: AuthViewModel) {
        self.settings = settings
        self.auth = auth
    }

    /// Drives the optional Sign in with Apple sheet surfaced from the
    /// Account section. The boot path no longer gates the app on auth,
    /// so signing in is a user-initiated action that lives in
    /// Settings — exactly where macOS conventions expect it.
    @State private var showSignInSheet: Bool = false
    @State private var showDeleteAccountConfirm: Bool = false

    public var body: some View {
        #if os(macOS)
        TabView {
            accountTab
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            intelligenceTab
                .tabItem { Label("Intelligence", systemImage: "sparkles") }
            networkTab
                .tabItem { Label("Network", systemImage: "network") }
            privacyTab
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 520, height: 400)
        .sheet(isPresented: $showSignInSheet) {
            SignInView(
                onComplete: { result in
                    Task {
                        if case .success(let cred) = result {
                            await auth.signIn(with: cred)
                        }
                        showSignInSheet = false
                    }
                },
                onTapDebugBypass: {
                    #if DEBUG
                    Task {
                        await auth.signInForDebugBypass()
                        showSignInSheet = false
                    }
                    #endif
                },
                errorMessage: {
                    if case .error(let reason) = auth.state { return reason }
                    return nil
                }()
            )
            .frame(minWidth: 480, minHeight: 360)
        }
        #else
        SettingsForm(settings: settings, auth: auth)
        #endif
    }

    // MARK: - macOS tabs

    private var accountTab: some View {
        Form {
            Section("Account") {
                switch auth.state {
                case .signedIn(let session):
                    LabeledContent("User", value: session.userId)
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                    .controlSize(.regular)
                    .accessibilityHint("Signs out of Synapse on this device")
                case .signedOut, .error:
                    Text("Signed out. Synapse runs locally with demo data until you sign in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Sign in with Apple") {
                        showSignInSheet = true
                    }
                    .controlSize(.regular)
                    .accessibilityIdentifier("settings.account.signInButton")
                case .signingIn:
                    ProgressView()
                }
            }
            if case .signedIn = auth.state {
                Section("Delete account") {
                    Text("Permanently deletes your Synapse account and removes your data from this device. This cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Delete account", role: .destructive) {
                        showDeleteAccountConfirm = true
                    }
                    .controlSize(.regular)
                    .accessibilityIdentifier("settings.account.deleteAccountButton")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog(
            "Delete your Synapse account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await auth.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and on-device data will be removed. This cannot be undone.")
        }
    }

    private var networkTab: some View {
        Form {
            Section {
                TextField("API base URL",
                          text: $settings.apiBaseURL,
                          prompt: Text("http://localhost:3000/"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("API base URL")
                if !settings.apiBaseURLIsValid {
                    Text("Must be an http or https URL.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("API base URL is invalid")
                }
                Text("Override the API endpoint Synapse talks to. Leave blank to use the bundled default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Endpoint")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var privacyTab: some View {
        Form {
            Section("Balances") {
                Toggle("Conceal balances in Finance",
                       isOn: $settings.concealBalances)
                    .accessibilityHint("Hides numeric balances on the Finance surfaces.")
                Text("Mirrors the iOS app-switcher snapshot policy: numeric balances render as bullets while this is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var appearanceTab: some View {
        Form {
            Section("Motion") {
                Toggle("Preview Reduce Motion",
                       isOn: $settings.reduceMotionPreview)
                    .accessibilityHint("Forces the LIFE terminal to skip its scanline animation.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// "Synapse Intelligence" — the AI-side preferences pane. Model
    /// picker is the load-bearing control; the two placeholder toggles
    /// stay off until the on-device transcription and Apple Intelligence
    /// digest pipelines actually exist.
    private var intelligenceTab: some View {
        Form {
            Section("Model") {
                Picker("Reasoning model", selection: $settings.aiModel) {
                    ForEach(SettingsViewModel.aiModelChoices, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.ai.modelPicker")
                Text("All load-bearing reasoning runs on Opus 4.7 by default. The other entries are surfaced for transparency.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Anomaly sensitivity") {
                HStack {
                    Text("1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(settings.aiAnomalySensitivity) },
                            set: { settings.aiAnomalySensitivity = Int($0.rounded()) }
                        ),
                        in: 1...5,
                        step: 1
                    )
                    .accessibilityIdentifier("settings.ai.sensitivity")
                    Text("5")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Current: \(settings.aiAnomalySensitivity). Higher = more flags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Apple Intelligence") {
                Toggle("Use on-device transcription for journal voice input",
                       isOn: $settings.aiOnDeviceTranscription)
                    .disabled(true)
                Text("Reserved for the LIFE journal voice composer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Send insights digest to Apple Intelligence",
                       isOn: $settings.aiInsightsDigest)
                    .disabled(true)
                Text("Reserved for the Apple Intelligence summary integration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// iOS Settings form. Rooted under the "More" tab in `RootTabView`.
@MainActor
public struct SettingsForm: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var settings: SettingsViewModel
    private let auth: AuthViewModel

    public init(settings: SettingsViewModel, auth: AuthViewModel) {
        self.settings = settings
        self.auth = auth
    }

    @ViewBuilder
    private var urlField: some View {
        #if os(iOS)
        TextField("API base URL", text: $settings.apiBaseURL)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .frame(minHeight: 44)
            .accessibilityLabel("API base URL")
        #else
        TextField("API base URL", text: $settings.apiBaseURL)
            .frame(minHeight: 44)
            .accessibilityLabel("API base URL")
        #endif
    }

    @State private var showSignInSheet: Bool = false
    @State private var showDeleteAccountConfirm: Bool = false

    public var body: some View {
        Form {
            Section("Account") {
                switch auth.state {
                case .signedIn(let session):
                    LabeledContent("User", value: session.userId)
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                    .frame(minHeight: 44)
                case .signedOut, .error:
                    Text("Signed out. Synapse runs locally with demo data until you sign in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Sign in with Apple") {
                        showSignInSheet = true
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("settings.account.signInButton")
                case .signingIn:
                    ProgressView()
                }
            }
            if case .signedIn = auth.state {
                Section {
                    Button("Delete account", role: .destructive) {
                        showDeleteAccountConfirm = true
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("settings.account.deleteAccountButton")
                } header: {
                    Text("Delete account")
                } footer: {
                    Text("Permanently deletes your Synapse account and removes your data from this device. This cannot be undone.")
                }
            }
            Section("Endpoint") {
                urlField
                if !settings.apiBaseURLIsValid {
                    Text("Must be an http or https URL.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Privacy") {
                Toggle("Conceal balances",
                       isOn: $settings.concealBalances)
                    .frame(minHeight: 44)
                    .accessibilityHint("Hides numeric balances on the Finance surfaces.")
            }
            Section("Synapse Intelligence") {
                Picker("Reasoning model", selection: $settings.aiModel) {
                    ForEach(SettingsViewModel.aiModelChoices, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings.ai.modelPicker")
                VStack(alignment: .leading) {
                    Text("Anomaly sensitivity: \(settings.aiAnomalySensitivity)")
                    Slider(
                        value: Binding(
                            get: { Double(settings.aiAnomalySensitivity) },
                            set: { settings.aiAnomalySensitivity = Int($0.rounded()) }
                        ),
                        in: 1...5,
                        step: 1
                    )
                    .accessibilityIdentifier("settings.ai.sensitivity")
                }
                .frame(minHeight: 60)
                Toggle("On-device transcription (journal)",
                       isOn: $settings.aiOnDeviceTranscription)
                    .disabled(true)
                    .frame(minHeight: 44)
                Toggle("Send insights digest to Apple Intelligence",
                       isOn: $settings.aiInsightsDigest)
                    .disabled(true)
                    .frame(minHeight: 44)
            }
            Section("Appearance") {
                Toggle("Preview Reduce Motion",
                       isOn: $settings.reduceMotionPreview)
                    .frame(minHeight: 44)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete your Synapse account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await auth.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and on-device data will be removed. This cannot be undone.")
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInView(
                onComplete: { result in
                    Task {
                        if case .success(let cred) = result {
                            await auth.signIn(with: cred)
                        }
                        showSignInSheet = false
                    }
                },
                onTapDebugBypass: {
                    #if DEBUG
                    Task {
                        await auth.signInForDebugBypass()
                        showSignInSheet = false
                    }
                    #endif
                },
                errorMessage: {
                    if case .error(let reason) = auth.state { return reason }
                    return nil
                }()
            )
        }
    }
}
