# M7 Integration Manifest — People + Inbox (read-only)

This worktree adds the People + Inbox surfaces. Test-first, all green.
194 → 249 tests; 41 → 50 suites; +20 snapshot reference PNGs (12 People,
8 Inbox; macOS + iOS, light + dark).

The agent kept everything inside the territory listed in its brief — no
edits to `Package.swift`, `project.yml`, the iOS/macOS app entry points, or
the Xcode project. This manifest is what the integrator needs to apply in a
follow-up serialized pass to wire the new views into the apps and into the
Xcode project.

## 1. Package.swift — no changes needed

The new test files live under existing test target paths
(`Tests/ModelsTests`, `Tests/NetworkingTests`,
`Tests/FeaturesTests/People`, `Tests/FeaturesTests/Inbox`,
`Tests/SnapshotTests`) which the existing test targets already pick up
recursively. The `Package.swift` declares these targets with `path:` only,
no `sources:` filter, so the additions are automatic.

Confirm with `swift test --package-path packages/SynnapseKit` after pulling
this worktree in — it should report 249 tests / 50 suites green.

## 2. Xcode project — Synnapse.xcodeproj

The new SwiftPM files are inside the `SynnapseKit` package, so the Xcode
project picks them up via the existing package reference. **No project
file changes required for the package layer.**

The two app targets (`Synnapse-iOS`, `Synnapse-macOS`) need the wiring
described in sections 3 + 4 below.

## 3. iOS app — `apps/Synnapse-iOS/SynnapseiOSApp.swift`

Replace the existing "People" placeholder tab with the real `PeopleView`,
and add a new "Inbox" destination. Suggested patch shape:

```swift
import Features  // already imported for prior milestones
import Networking
import Models

// Inside the iOS app's TabView (or NavigationStack split):

TabView(selection: $selectedTab) {
    // ... existing tabs (Spotlight, Approvals, Finance, Life) ...

    PeopleView(viewModel: peopleVM)
        .tabItem { Label("People", systemImage: "person.2") }
        .tag(Tab.people)

    InboxListView(viewModel: inboxVM)
        .tabItem { Label("Inbox", systemImage: "tray") }
        .tag(Tab.inbox)
        .badge(inboxVM.unreadCount)  // optional but recommended
}
```

`peopleVM` and `inboxVM` are constructed once per app launch:

```swift
@State private var peopleVM = PeopleViewModel(
    api: LivePeopleAPI(client: appClient)
)
@State private var inboxVM = InboxListViewModel(
    api: LiveInboxAPI(client: appClient)
)
```

If the iOS app uses a different navigation root (e.g. `NavigationStack`
with a sidebar on iPad regular width), add entries to the sidebar list
that push `PeopleView` / `InboxListView`. The view models themselves work
identically in either container.

### iOS deep link (optional)

People deep links should route on `synnapse://people/<email>` and call
`peopleVM.select(person)`. Inbox deep links on `synnapse://inbox/<message-id>`
should select the matching `InboxItem`. Wire these in
`SynnapseiOSApp.body`'s `.onOpenURL { ... }` modifier — pattern matches
M3's auth-callback handling.

## 4. macOS app — `apps/Synnapse-macOS/SynnapseMacApp.swift`

Add two new `WindowGroup`s and two menu commands. Suggested patch shape:

```swift
@main
struct SynnapseMacApp: App {
    @State private var peopleVM = PeopleViewModel(
        api: LivePeopleAPI(client: appClient)
    )
    @State private var inboxVM = InboxListViewModel(
        api: LiveInboxAPI(client: appClient)
    )

    var body: some Scene {
        // ... existing windows (Spotlight, Approvals, Finance, Life) ...

        WindowGroup("People", id: "people") {
            PeopleView(viewModel: peopleVM)
                .identity(.editorial)
                .frame(minWidth: 1100, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .windowList) {
                Button("People") {
                    NSWorkspace.shared.open(URL(string: "synnapse://window/people")!)
                }
                .keyboardShortcut("5", modifiers: [.command])
            }
        }

        WindowGroup("Inbox", id: "inbox") {
            InboxListView(viewModel: inboxVM)
                .identity(.editorial)
                .frame(minWidth: 1100, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .windowList) {
                Button("Inbox") {
                    NSWorkspace.shared.open(URL(string: "synnapse://window/inbox")!)
                }
                .keyboardShortcut("6", modifiers: [.command])
            }
        }
    }
}
```

If the existing app uses `Window` (singleton) rather than `WindowGroup`,
mirror that convention — People + Inbox are both single-window surfaces.

### macOS toolbar (recommended)

Add a toolbar to `PeopleView` and `InboxListView` from the app side rather
than baking it into the views (toolbar items can't reach env values
cleanly otherwise). Suggested:

```swift
PeopleView(viewModel: peopleVM)
    .toolbar {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await peopleVM.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
```

Same `.toolbar` shape applies to `InboxListView`.

## 5. Info.plist / entitlements

No new entitlements required. Both surfaces are read-only over existing
HTTP endpoints; no Keychain access, no microphone/camera, no network
extensions.

## 6. Resources

No new asset catalog entries. The avatar surface uses initials (text) as
the fallback; when the operator wires Gravatar/clearbit avatars later, the
`Person.avatarURL` field is already wired through.

## 7. Test target additions — no changes

As noted in section 1, the existing targets already pick up:

- `Tests/ModelsTests/PersonTests.swift`
- `Tests/ModelsTests/InboxItemTests.swift`
- `Tests/NetworkingTests/PeopleRepositoryTests.swift`
- `Tests/NetworkingTests/InboxRepositoryTests.swift`
- `Tests/FeaturesTests/People/PeopleSearchTests.swift`
- `Tests/FeaturesTests/People/PeopleViewModelTests.swift`
- `Tests/FeaturesTests/Inbox/InboxListViewModelTests.swift`
- `Tests/SnapshotTests/PeopleScreenSnapshotTests.swift`
- `Tests/SnapshotTests/InboxScreenSnapshotTests.swift`

## 8. Snapshot references

20 new reference PNGs are committed under:

- `Tests/SnapshotTests/__Snapshots__/PeopleScreenSnapshotTests/`
  (12 refs — empty / results / selected × light / dark × mac / ios)
- `Tests/SnapshotTests/__Snapshots__/InboxScreenSnapshotTests/`
  (8 refs — empty / results × light / dark × mac / ios)

These match the prior milestone convention (`ApprovalsFlatScreenSnapshotTests/`,
`SpotlightIOSScreenSnapshotTests/`, etc.). The `NavigationSplitView` macOS
sidebar baseline matches the existing M4 `ApprovalsFlatView` snapshot
(blank sidebar inside `NSHostingView` — this is established behavior, not
a regression).

## 9. Server contracts touched

### `/api/senders` — already live (read)
The People surface decodes the existing `SenderStats` shape (see
`lib/people.ts#listPeople`). Client tolerates an ETag if/when the route
adds one. No server changes required.

### `/api/senders/[identity]` — already live (read)
The dossier view decodes the existing dossier shape. No server changes
required.

### `/api/messages` — already live (read)
The Inbox list decodes the existing message envelope. Client adds
forward-compat query params (`?limit`, `?cursor`, `?source`) and tolerates
a server-emitted `nextCursor` field for pagination. The route today
returns all messages in one shot with no `nextCursor`; the client copes.

### `PATCH /api/messages/[id]` — NOT live yet (forward-compat)
The optimistic mark-read flow POSTs `{ read: true }` to this route. The
server has no `read` column today; the client treats a 404 as
"the route isn't wired yet" and keeps the local-only flag as source of
truth. When the server adds the column + handler, the existing client
flow just starts working.

## 10. Departures + notes for the integrator

- **Mock APIs moved from Networking to Features.** The brief listed
  `Networking/PeopleAPI.swift` + `Networking/InboxAPI.swift`. The Live
  implementations and the `PeopleAPI` / `InboxAPI` protocols live there as
  specified. But `MockPeopleAPI` / `MockInboxAPI` are in
  `Features/People/PeopleMockAPI.swift` /
  `Features/Inbox/InboxMockAPI.swift` instead — because the `SnapshotTests`
  target only depends on `Features / Models / DesignSystem`, not
  `Networking`. Same pattern as the existing `MockApprovalsAPI` and
  `MockSpotlightAPI` in M2 / M4. Stub comments in the Networking files
  point at the new locations.

- **macOS `NavigationSplitView` sidebar renders blank in snapshots.** This
  matches the existing `ApprovalsFlatView` baseline — `NSHostingView` does
  not give `NavigationSplitView` the window-class layout context it needs
  to compose the sidebar background. The list IS there logically; runtime
  rendering in the real macOS app is correct. If the integrator wants to
  tighten the snapshot baseline, the right fix is to wrap the test view in
  an `NSWindow` instead of `NSHostingView` — that's a cross-cutting change
  for all macOS snapshot tests and should be its own milestone, not a M7
  patch.

- **Inbox iOS "selected" state is identical to "results" state.** On
  iPhone, selection opens a `.sheet`; the sheet doesn't auto-present in
  snapshot rendering since there is no tap. The "selected" PNG references
  for People-iOS therefore look identical to "results"-iOS. This is
  intentional and matches the iOS interaction model — operators see the
  list, then tap to inspect.

- **Inbox is read-only.** Brief honored: no compose, no reply, no send
  affordances anywhere in the view tree. The only mutation is the
  optimistic mark-read flow, and the rollback path is covered.

- **People debounce uses an epoch counter, not pure Task cancellation.**
  `Task.cancel()` is cooperative; `Task.sleep(for:)` returns nil on cancel
  but the post-sleep code can still race. The view model bumps a
  `searchEpoch` on every `queueSearch` call and only the task whose
  captured epoch matches the current epoch is allowed to write
  `visiblePeople`. This is documented inline.

- **No memory edits.** No new entries to the agent memory store were
  required for this milestone — the patterns established in M2 / M4 / M5
  carried through cleanly.
