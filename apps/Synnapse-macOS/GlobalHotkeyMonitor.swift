#if os(macOS)
import AppKit

/// Lightweight hotkey monitor. Registering a TRUE system-wide global hotkey
/// on modern macOS without an entitlement requires either `RegisterEventHotKey`
/// (Carbon) or the Accessibility permission — both add friction we'd rather
/// defer until M9 polish. The NSEvent-based monitor here fires whenever the
/// app has any focus (and globally if Accessibility is granted).
@MainActor
final class GlobalHotkeyMonitor {

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let onHit: @MainActor () -> Void
    private let modifiers: NSEvent.ModifierFlags
    private let keyCode: UInt16

    init(
        modifiers: NSEvent.ModifierFlags = [.command, .shift],
        keyCode: UInt16 = 49, // Space
        onHit: @escaping @MainActor () -> Void
    ) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.onHit = onHit
    }

    func start() {
        stop()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matches(event) {
                Task { @MainActor in self.onHit() }
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if self.matches(event) {
                Task { @MainActor in self.onHit() }
            }
        }
    }

    func stop() {
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        localMonitor = nil
        globalMonitor = nil
    }

    // Intentionally no deinit teardown: AppKit observers must be removed on
    // the main thread, and `deinit` on a `@MainActor` class is nonisolated.
    // The owning AppModel lives for the app's lifetime, so explicit `stop()`
    // is the right hook when we eventually rebind the hotkey at runtime.

    private nonisolated func matches(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return event.modifierFlags.intersection(relevant) == modifiers
            && event.keyCode == keyCode
    }
}
#endif
