import AppKit
import SwiftUI

/// Borderless panel floating above all windows and spaces. It can be dragged but not closed.
final class ReminderPanel: NSPanel {
    private static let autosaveName = "ReminderPanel"

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let hostingView = FirstMouseHostingView(rootView: rootView)
        contentView = hostingView
        setContentSize(hostingView.fittingSize)

        if !setFrameUsingName(Self.autosaveName) {
            placeAtTopCenter()
        }
        setFrameAutosaveName(Self.autosaveName)

        // Background drags don't always trigger the autosave, so save explicitly.
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveFrame(usingName: Self.autosaveName) }
        }
    }

    override func orderOut(_ sender: Any?) {
        if isVisible { saveFrame(usingName: Self.autosaveName) }
        super.orderOut(sender)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func placeAtTopCenter() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 24))
    }
}

/// Lets the join button work with the first click even though the panel isn't key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
