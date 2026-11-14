import AppKit
import OSLog

/// Reader text size, stored where the views' @AppStorage reads it.
enum ReaderTextSize {
    static let minimum = 0.8
    static let maximum = 1.5
    static let step = 0.1

    static func increase(in defaults: UserDefaults = .standard) {
        set(current(in: defaults) + step, in: defaults)
    }

    static func decrease(in defaults: UserDefaults = .standard) {
        set(current(in: defaults) - step, in: defaults)
    }

    static func current(in defaults: UserDefaults = .standard) -> Double {
        let value = defaults.object(forKey: ReaderPreferenceKeys.textScale) as? Double ?? 1.0
        return clamp(value)
    }

    static func set(_ value: Double, in defaults: UserDefaults = .standard) {
        // Round to one decimal so repeated steps don't drift (1.0999999...).
        defaults.set((clamp(value) * 10).rounded() / 10, forKey: ReaderPreferenceKeys.textScale)
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    /// True for ⌘= and ⌘+ (⇧⌘= on US keyboards, or the keypad plus).
    static func isBiggerTextShortcut(characters: String?, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let flags = modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command || flags == [.command, .shift] else { return false }
        return characters == "=" || characters == "+"
    }
}

/// Handles ⌘= / ⌘+ before the key window's views see them. A focused WKWebView
/// is offered key equivalents before the main menu, and "+" doesn't match a menu
/// item registered as "=", so the menu shortcut alone was unreliable.
@MainActor
final class ReaderKeyMonitor {
    private var monitor: Any?
    private let log = Logger(subsystem: "com.felizvida.obviewer", category: "keys")

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [log] event in
            guard ReaderTextSize.isBiggerTextShortcut(
                characters: event.charactersIgnoringModifiers,
                modifierFlags: event.modifierFlags
            ) else {
                return event
            }
            ReaderTextSize.increase()
            log.info("Bigger Text via shortcut -> \(ReaderTextSize.current(), privacy: .public)")
            return nil
        }
    }
}
