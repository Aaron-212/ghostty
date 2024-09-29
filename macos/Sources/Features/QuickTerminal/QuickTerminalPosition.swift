import Cocoa

enum QuickTerminalPosition : String {
    case top
    case bottom
    case left
    case right

    /// Set the loaded state for a window.
    func setLoaded(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        switch (self) {
        case .top, .bottom:
            window.setFrame(.init(
                origin: window.frame.origin,
                size: .init(
                    width: screen.frame.width,
                    height: screen.frame.height / 4)
            ), display: false)

        case .left, .right:
            window.setFrame(.init(
                origin: window.frame.origin,
                size: .init(
                    width: screen.frame.width / 4,
                    height: screen.frame.height)
            ), display: false)
        }
    }

    /// Set the initial state for a window for animating out of this position.
    func setInitial(in window: NSWindow, on screen: NSScreen) {
        // We always start invisible
        window.alphaValue = 0

        // Position depends
        window.setFrame(.init(
            origin: initialOrigin(for: window, on: screen),
            size: window.frame.size
        ), display: false)
    }

    /// Set the final state for a window in this position.
    func setFinal(in window: NSWindow, on screen: NSScreen) {
        // We always end visible
        window.alphaValue = 1

        // Position depends
        window.setFrame(.init(
            origin: finalOrigin(for: window, on: screen),
            size: window.frame.size
        ), display: true)
    }

    /// Restrict the frame size during resizing.
    func restrictFrameSize(_ size: NSSize, on screen: NSScreen) -> NSSize {
        var finalSize = size
        switch (self) {
        case .top, .bottom:
            finalSize.width = screen.frame.width

        case .left, .right:
            finalSize.height = screen.frame.height
        }

        return finalSize
    }

    /// The initial point origin for this position.
    func initialOrigin(for window: NSWindow, on screen: NSScreen) -> CGPoint {
        switch (self) {
        case .top:
            return .init(x: 0, y: screen.frame.maxY)

        case .bottom:
            return .init(x: 0, y: -window.frame.height)

        case .left:
            return .init(x: -window.frame.width, y: 0)

        case .right:
            return .init(x: screen.frame.maxX, y: 0)
        }
    }

    /// The final point origin for this position.
    func finalOrigin(for window: NSWindow, on screen: NSScreen) -> CGPoint {
        switch (self) {
        case .top:
            return .init(x: window.frame.origin.x, y: screen.visibleFrame.maxY - window.frame.height)

        case .bottom:
            return .init(x: window.frame.origin.x, y: 0)

        case .left:
            return .init(x: 0, y: window.frame.origin.y)

        case .right:
            return .init(x: screen.visibleFrame.maxX - window.frame.width, y: window.frame.origin.y)
        }
    }
}
