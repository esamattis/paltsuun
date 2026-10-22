import AppKit
import SwiftUI

/// Borderless panel floating above all windows and spaces, showing one meeting's countdown.
/// It can be dragged anywhere. The place the user drags a countdown to is where the next
/// countdown appears. Countdowns shown together are placed side by side in a row.
final class ReminderPanel: NSPanel, NSWindowDelegate {
    /// Top-left corner of the last countdown the user dragged.
    private static let positionKey = "reminderPanelTopLeft"
    private static let spacing: CGFloat = 12

    /// Origin set by `place(avoiding:)`, to tell it apart from the user dragging the panel.
    private var placedOrigin: NSPoint?
    /// Whether the place the panel is dragged to is where the next countdown appears.
    private var savesPosition = true

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

    /// Moves the panel to the saved position, or beside it in the same row when that would
    /// overlap one of the `occupied` frames. A new row is started below only when the row is full.
    func place(avoiding occupied: [NSRect]) {
        let anchor = self.anchor
        let size = frame.size
        let screen = (NSScreen.screens.first { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(anchor) } ?? NSScreen.main)?
            .visibleFrame ?? .infinite

        var top = anchor.y
        while top - size.height >= screen.minY {
            let row = NSRect(x: screen.minX, y: top - size.height, width: screen.width, height: size.height)
                .insetBy(dx: 0, dy: -Self.spacing / 2)
            let inRow = occupied.filter { $0.intersects(row) }
            if let x = Self.freeX(in: inRow, from: anchor.x, width: size.width, screen: screen) {
                return move(to: NSPoint(x: x, y: top - size.height))
            }
            // Each row starts below the lowest panel of the one above, so this ends.
            top = inRow.map(\.minY).min()! - Self.spacing
        }
        // The screen is full.
        move(to: NSPoint(x: anchor.x, y: anchor.y - size.height))
    }

    /// Moves the panel to the center of the main screen. Its position is never saved.
    func placeInCenter() {
        savesPosition = false
        guard let screen = NSScreen.main?.visibleFrame else { return }
        move(to: NSPoint(x: screen.midX - frame.width / 2, y: screen.midY - frame.height / 2))
    }

    /// A free spot in a row holding the `occupied` frames: at `anchorX`, else the nearest one
    /// to its right, else to its left.
    private static func freeX(in occupied: [NSRect], from anchorX: CGFloat, width: CGFloat, screen: NSRect) -> CGFloat? {
        func blocking(_ x: CGFloat) -> NSRect? {
            let candidate = NSRect(x: x, y: 0, width: width, height: 1).insetBy(dx: -spacing / 2, dy: 0)
            return occupied.first { $0.minX < candidate.maxX && $0.maxX > candidate.minX }
        }
        guard blocking(anchorX) != nil else { return anchorX }
        // Each step moves past the panel in the way, so these end.
        var x = anchorX
        while x + width <= screen.maxX {
            guard let panel = blocking(x) else { return x }
            x = panel.maxX + spacing
        }
        x = anchorX
        while x >= screen.minX {
            guard let panel = blocking(x) else { return x }
            x = panel.minX - spacing - width
        }
        return nil
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
        guard savesPosition, frame.origin != placedOrigin else { return }
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
