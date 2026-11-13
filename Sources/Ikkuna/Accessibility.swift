import AppKit
import CoreGraphics
import ApplicationServices
import Darwin
import IkkunaCore

// All AX requests run on WindowEngine.queue, never in the keyboard callback.
enum AX {
    // This optional system symbol distinguishes windows with identical bounds
    // and titles. Keep geometry matching available if macOS does not expose it.
    private typealias WindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let windowIDFunction: WindowIDFunction? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: WindowIDFunction.self)
    }()
    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let function = windowIDFunction, function(element, &id) == .success, id != 0 else { return nil }
        return id
    }
    static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
    static func string(_ element: AXUIElement, _ name: String) -> String {
        (value(element, name) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = value(element, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        value(element, name) as? [AXUIElement] ?? []
    }
    @discardableResult static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    /// Return the app only when its enabled state was successfully suspended.
    /// Callers must restore that state after the frame writes finish.
    static func suspendEnhancedUI(for pid: pid_t) -> AXUIElement? {
        let app = application(pid)
        guard value(app, "AXEnhancedUserInterface") as? Bool == true,
              set(app, "AXEnhancedUserInterface", kCFBooleanFalse) else { return nil }
        return app
    }
    @discardableResult static func setFrame(_ frame: CGRect, on element: AXUIElement, pid: pid_t) -> Bool {
        guard frame.width > 0, frame.height > 0, !frame.isInfinite, !frame.isNull else { return false }
        var point = frame.origin, size = frame.size
        guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size) else { return false }
        // Firefox's title discovery enables Enhanced UI. Suspend it for discrete
        // placements too, matching the continuous resize path's animation guard.
        let suspendedApp = suspendEnhancedUI(for: pid)
        defer {
            if let suspendedApp { set(suspendedApp, "AXEnhancedUserInterface", kCFBooleanTrue) }
        }
        // Resize first to permit moves from a small display to a larger one.
        let sizeOK = set(element, kAXSizeAttribute, s)
        let positionOK = set(element, kAXPositionAttribute, p)
        let finalSizeOK = set(element, kAXSizeAttribute, s)
        return positionOK && (sizeOK || finalSizeOK)
    }
    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        return app
    }
}

struct Display {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visible: CGRect
    static func snapshot() -> [Display] {
        // AX and CG use a top-left origin; AppKit uses bottom-left.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: top-r.maxY, width: r.width, height: r.height) }
            return Display(id: id, frame: flip(screen.frame), visible: flip(screen.visibleFrame))
        }
    }
}

struct NativeWindow: Equatable {
    let id: UInt32
    let pid: pid_t
    let frame: CGRect
    let title: String
    var rect: WindowRect { WindowRect(id, frame) }
    static func snapshot() -> [NativeWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let dict = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: dict as CFDictionary), frame.width > 0, frame.height > 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return NativeWindow(id: id, pid: pid, frame: frame, title: info[kCGWindowName as String] as? String ?? "")
        }
    }
}

struct AccessibleWindow {
    let element: AXUIElement
    let pid: pid_t
    let title: String
    let frame: CGRect
    // AX equality/hash is stable across freshly returned references to one window.
    var identity: String { "\(pid):\(CFHash(element))" }
    var minimized: Bool { AX.value(element, kAXMinimizedAttribute) as? Bool ?? false }
}

final class WindowAccess {
    private var cache: [pid_t: (Date, [AccessibleWindow])] = [:]
    private var preparedFirefox = Set<pid_t>()
    func invalidate() { cache.removeAll() }

    func windows(pid: pid_t, fresh: Bool = false) -> [AccessibleWindow] {
        if !fresh, let cached = cache[pid], Date().timeIntervalSince(cached.0) < 0.25 { return cached.1 }
        let app = AX.application(pid)
        let running = NSRunningApplication(processIdentifier: pid)
        let firefox = (running?.bundleIdentifier ?? "").hasPrefix("org.mozilla.firefox")
        if firefox && preparedFirefox.insert(pid).inserted {
            _ = AX.value(app, kAXRoleAttribute)
            AX.set(app, "AXEnhancedUserInterface", kCFBooleanTrue)
        }
        let windows = AX.elements(app, kAXWindowsAttribute).compactMap { element -> AccessibleWindow? in
            AXUIElementSetMessagingTimeout(element, 0.15)
            let role = AX.string(element, kAXSubroleAttribute)
            guard ["AXStandardWindow", "AXDialog", "AXSystemDialog"].contains(role),
                  let frame = AX.frame(element) else { return nil }
            var title = AX.string(element, kAXTitleAttribute)
            if title.isEmpty && firefox { title = firefoxTitle(element) }
            return AccessibleWindow(element: element, pid: pid, title: title, frame: frame)
        }
        cache[pid] = (Date(), windows)
        return windows
    }

    func focused(pid: pid_t) -> AccessibleWindow? {
        let app = AX.application(pid)
        guard let window = AX.element(app, kAXFocusedWindowAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.15)
        guard let frame = AX.frame(window) else { return nil }
        return AccessibleWindow(element: window, pid: pid, title: AX.string(window, kAXTitleAttribute), frame: frame)
    }

    func resolve(_ native: NativeWindow) -> AccessibleWindow? {
        // Require matching bounds even with an ID: Stage Manager thumbnails must
        // not resolve to their full-size accessibility windows.
        let candidates = windows(pid: native.pid)
        let exact = candidates.filter { Geometry.approximatelyEqual($0.frame, native.frame, tolerance: 3) && !$0.minimized }
        if let identified = exact.first(where: { AX.windowID($0.element) == native.id }) { return identified }
        let unidentified = exact.filter { AX.windowID($0.element) == nil }
        if unidentified.count == 1 { return unidentified[0] }
        let titled = unidentified.filter { !$0.title.isEmpty && $0.title == native.title }
        if titled.count == 1 { return titled[0] }
        return nil
    }

    func native(for window: AccessibleWindow, in list: [NativeWindow]) -> NativeWindow? {
        let candidates = list.filter { $0.pid == window.pid && Geometry.approximatelyEqual($0.frame, window.frame, tolerance: 3) }
        if let id = AX.windowID(window.element) { return candidates.first { $0.id == id } }
        if candidates.count == 1 { return candidates[0] }
        let titled = candidates.filter { !window.title.isEmpty && $0.title == window.title }
        return titled.count == 1 ? titled[0] : nil
    }

    @discardableResult func focus(_ window: AccessibleWindow, mouse: Bool = false) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else { return false }
        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps])
        if window.minimized { AX.set(window.element, kAXMinimizedAttribute, kCFBooleanFalse) }
        AX.set(AX.application(window.pid), kAXFocusedWindowAttribute, window.element)
        AX.set(window.element, kAXMainAttribute, kCFBooleanTrue)
        let result = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success
        if result && mouse { CGWarpMouseCursorPosition(CGPoint(x: window.frame.midX, y: window.frame.midY)) }
        return result
    }

    private func firefoxTitle(_ root: AXUIElement) -> String {
        if let title = AX.element(root, kAXTitleUIElementAttribute) {
            let text = AX.string(title, kAXValueAttribute)
            if !text.isEmpty { return text }
        }
        let started = ProcessInfo.processInfo.systemUptime
        var queue: [(AXUIElement, Int)] = [(root, 0)], index = 0
        while index < queue.count && index < 80 && ProcessInfo.processInfo.systemUptime-started < 0.06 {
            let (element, depth) = queue[index]; index += 1
            let role = AX.string(element, kAXRoleAttribute)
            if role == "AXTabGroup" {
                for tab in AX.elements(element, kAXSelectedChildrenAttribute) {
                    let title = AX.string(tab, kAXTitleAttribute)
                    if !title.isEmpty { return title }
                }
            }
            let selected = AX.value(element, "AXSelected") as? Bool ?? false
            let activeTab = (role == "AXRadioButton" || role == "AXTab") && (selected || (AX.value(element, kAXValueAttribute) as? Int == 1))
            if role == "AXWebArea" || activeTab {
                let title = AX.string(element, kAXTitleAttribute)
                if !title.isEmpty { return title }
                let description = AX.string(element, kAXDescriptionAttribute)
                if !description.isEmpty { return description }
            }
            if role != "AXWebArea" && depth < 6 {
                queue.append(contentsOf: AX.elements(element, kAXChildrenAttribute).prefix(max(0, 80-queue.count)).map { ($0, depth+1) })
            }
        }
        return ""
    }
}
