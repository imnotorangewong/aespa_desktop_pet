import AppKit
import ApplicationServices

enum CalendarCatalogPlayback {
    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    // Music puts the album and catalog song IDs in the track row's AX identifier.
    // Match the terminating delimiter too, so song 123 never selects song 1234.
    static func isTrackRow(_ identifier: String, songID: String) -> Bool {
        guard let start = identifier.range(of: "AlbumTrackLockup[id=track-lockup-") else { return false }
        let row = identifier[start.upperBound...].prefix { $0 != "," && $0 != "]" }
        return row.split(separator: "-").last.map(String.init) == songID
    }

    private static func row(in window: AXUIElement, songID: String) -> AXUIElement? {
        var pending = [window], checked = 0
        while let element = pending.popLast(), checked < 2400 {
            checked += 1
            if let id = attribute(element, kAXIdentifierAttribute) as? String, isTrackRow(id, songID: songID) { return element }
            pending.append(contentsOf: children(element))
        }
        return nil
    }

    private static func clickPoint(_ row: AXUIElement, pid: pid_t) -> CGPoint? {
        guard let origin = attribute(row, kAXPositionAttribute), CFGetTypeID(origin) == AXValueGetTypeID(),
              let dimensions = attribute(row, kAXSizeAttribute), CFGetTypeID(dimensions) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(origin as! AXValue, .cgPoint, &position), AXValueGetValue(dimensions as! AXValue, .cgSize, &size) else { return nil }
        let point = CGPoint(x: position.x + size.width * 0.45, y: position.y + size.height / 2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit = hit else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(hit, &owner) == .success, owner == pid else { return nil }
        var ancestor = hit
        for _ in 0..<12 {
            if CFEqual(ancestor, row) { return point }
            guard let parent = attribute(ancestor, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            ancestor = parent as! AXUIElement
        }
        return nil
    }

    static func play(_ entry: CalendarCatalogSong, song: CalendarSong) -> String {
        guard AXIsProcessTrusted() else {
            // Only called after a user-initiated catalog date click.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return "accessibility-needed"
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: MusicCalendarPlayback.bundleID).first else { return "catalog-open" }
        let target = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(target, 1)
        let until = Date().addingTimeInterval(5)
        while Date() < until {
            guard app.isActive else { return "catalog-open" }
            if let window = attribute(target, kAXFocusedWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID(),
               let track = row(in: window as! AXUIElement, songID: entry.songID),
               let point = clickPoint(track, pid: app.processIdentifier) {
                // Use the window-server hit test so clicks land on the verified, visible Music row.
                for count in 1...2 {
                    for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
                        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return "catalog-open" }
                        event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
                        event.post(tap: .cghidEventTap)
                        Thread.sleep(forTimeInterval: 0.03)
                    }
                }
                return MusicCalendarPlayback.request("confirm", song: song)
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return "catalog-open"
    }
}
