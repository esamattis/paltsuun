import CoreGraphics
import Foundation

/// Notices when the user comes back to the computer after being away for `AppSettings.awayTime`.
final class ActivityMonitor {
    private static let pollInterval: TimeInterval = 5

    private let onReturn: () -> Void
    private var timer: Timer?
    /// When the user last used the keyboard, mouse or trackpad.
    private var lastActivity = Date()
    /// The user came back, but the screen is still locked.
    private var returnPending = false

    init(onReturn: @escaping () -> Void) {
        self.onReturn = onReturn
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        // Any input event, the same as kCGAnyInputEventType.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let activity = Date().addingTimeInterval(-idle)
        // Also covers sleep: the gap includes the time the computer was asleep.
        if let awayTime = AppSettings.awayTime, activity.timeIntervalSince(lastActivity) >= awayTime {
            returnPending = true
        }
        lastActivity = max(lastActivity, activity)

        if returnPending, Self.isUserAtScreen {
            returnPending = false
            onReturn()
        }
    }

    /// The screen is unlocked and the session isn't switched out by fast user switching.
    private static var isUserAtScreen: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        let onConsole = session[kCGSessionOnConsoleKey] as? Bool ?? true
        let locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        return onConsole && !locked
    }
}
