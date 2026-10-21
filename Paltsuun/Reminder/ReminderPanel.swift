import AppKit
import SwiftUI

/// Borderless panel floating above all windows and spaces, showing one meeting's countdown.
/// It can be dragged anywhere. The place the user drags a countdown to is where the next
/// countdown appears.
final class ReminderPanel: NSPanel, NSWindowDelegate {
    /// Top-left corner of the last countdown the user dragged.
    private static let positionKey = "reminderPanelTopLeft"
    private static let spacing: CGFloat = 12

    /// Origin set by `place(avoiding:)`, to tell it apart from the user dragging the panel.
    private var placedOrigin: NSPoint?

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
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Moves the panel to the saved position, or below or beside it when that would overlap
    /// one of the `occupied` frames.
    func place(avoiding occupied: [NSRect]) {
        let anchor = self.anchor
        let size = frame.size
        let screen = (NSScreen.screens.first { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(anchor) } ?? NSScreen.main)?
            .visibleFrame ?? .infinite
        let step = size.width + Self.spacing
        let columns = [0, 1, -1, 2, -2, 3, -3, 4, -4]
            .map { anchor.x + CGFloat($0) * step }
            .filter { $0 == anchor.x || ($0 >= screen.minX && $0 + size.width <= screen.maxX) }

        for x in columns {
            var candidate = NSRect(x: x, y: anchor.y - size.height, width: size.width, height: size.height)
            // Each step moves the candidate below the panel it overlaps, so this ends.
            while candidate.minY >= screen.minY {
                let padded = candidate.insetBy(dx: -Self.spacing / 2, dy: -Self.spacing / 2)
                guard let blocking = occupied.first(where: { $0.intersects(padded) }) else {
                    return move(to: candidate.origin)
                }
                candidate.origin.y = blocking.minY - Self.spacing - size.height
            }
        }
        // The screen is full.
        move(to: NSPoint(x: anchor.x, y: anchor.y - size.height))
    }

    /// Fades the panel out and closes it.
    func fadeOut() {
        ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { self.close() }
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard frame.origin != placedOrigin else { return }
        placedOrigin = nil
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: Self.positionKey)
    }

    private func move(to origin: NSPoint) {
        placedOrigin = origin
        setFrameOrigin(origin)
    }

    /// The saved top-left corner if it's on a connected screen, otherwise the top center of the main screen.
    private var anchor: NSPoint {
        if let saved = UserDefaults.standard.string(forKey: Self.positionKey).map(NSPointFromString),
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(saved) })
        {
            return saved
        }
        guard let visible = NSScreen.main?.visibleFrame else { return .zero }
        return NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - 24)
    }
}

/// Lets the buttons work with the first click even though the panel isn't key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
