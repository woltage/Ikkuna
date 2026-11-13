import AppKit
import CoreGraphics
import ApplicationServices
import IkkunaCore

/// The tap makes routing decisions only. AX work and UI drawing run after it returns.
final class Hotkeys {
    private let engine: WindowEngine
    private let switcher: AppSwitcher
    private let overlay: Overlay
    private var configuration: Configuration
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consumed = Set<CGKeyCode>()
    private var resizeKey: CGKeyCode?
    private let replayMarker: Int64 = 0x494b4b554e41
    private var passthroughTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var parallelsPID: pid_t?
    private var parallelsCaptures = true
    private var gatePending = false
    private var switcherMode: AppSwitcher.Mode?
    var onReload: (() -> Void)?
    var onStagePicker: (() -> Void)?
    var stagePickerOpen: (() -> Bool)?
    var closeStagePicker: (() -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var forceLocal = false
    private(set) var paused = false
    var running: Bool { tap != nil }

    init(engine: WindowEngine, switcher: AppSwitcher, overlay: Overlay, configuration: Configuration) {
        self.engine = engine; self.switcher = switcher; self.overlay = overlay; self.configuration = configuration
    }
    func cancelTransientActions() {
        closeStagePicker?()
        engine.submit(.endResize); switcherMode = nil; switcher.end()
    }
    func configure(_ configuration: Configuration) { self.configuration = configuration; refreshPassthrough() }
    func setPaused(_ value: Bool) {
        closeStagePicker?()
        paused = value
        engine.submit(.endResize); updateSwitcher(nil); onStateChange?()
    }
    func toggleOverride() {
        forceLocal.toggle()
        overlay.message(forceLocal ? "Paikalliset pikanäppäimet päällä" : "Paikalliset pikanäppäimet automaattisia")
        onStateChange?()
    }
    @discardableResult func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<Hotkeys>.fromOpaque(pointer).takeUnretainedValue()
            return owner.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        refreshPassthrough()
        passthroughTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.refreshPassthrough() }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshPassthrough()
                if self?.enabled == false { self?.updateSwitcher(nil); self?.engine.submit(.endResize) }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateSwitcher(nil); self?.engine.submit(.endResize)
        })
        onStateChange?()
        return true
    }
    func stop() {
        closeStagePicker?()
        passthroughTimer?.invalidate(); passthroughTimer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; consumed.removeAll()
        updateSwitcher(nil); engine.submit(.endResize)
    }
    private var enabled: Bool {
        if paused { return false }
        if forceLocal { return true }
        guard let app = NSWorkspace.shared.frontmostApplication else { return true }
        let bundle = app.bundleIdentifier ?? ""
        if app.localizedName == "Parallels Desktop" {
            return parallelsPID == app.processIdentifier && !parallelsCaptures
        }
        return !configuration.captureBundleIDs.contains(bundle)
    }
    private func refreshPassthrough() {
        guard !gatePending, let app = NSWorkspace.shared.frontmostApplication,
              app.localizedName == "Parallels Desktop" else { return }
        gatePending = true
        let pid = app.processIdentifier, excluded = configuration.parallelsExcludedTitles
        engine.queue.async { [weak self] in
            guard let self else { return }
            let title = self.engine.access.focused(pid: pid)?.title ?? ""
            let captures = !excluded.contains(where: { title.contains($0) })
            DispatchQueue.main.async {
                self.gatePending = false; self.parallelsPID = pid; self.parallelsCaptures = captures
                if !self.enabled { self.updateSwitcher(nil); self.engine.submit(.endResize) }
            }
        }
    }
    private func updateSwitcher(_ mode: AppSwitcher.Mode?) {
        guard switcherMode != mode else { return }
        switcherMode = mode
        // Keep panel creation and AX requests outside the tap callback.
        DispatchQueue.main.async { [weak self] in self?.switcher.setMode(mode) }
    }
    private func mode(for flags: CGEventFlags) -> AppSwitcher.Mode? {
        let raw = flags.rawValue
        // NX_DEVICERCMDKEYMASK, NX_DEVICELCMDKEYMASK, right/left Option.
        guard raw & 0x10 != 0, raw & 0x08 == 0, flags.contains(.maskCommand),
              !flags.contains(.maskControl), !flags.contains(.maskShift), !flags.contains(.maskSecondaryFn) else { return nil }
        if flags.contains(.maskAlternate) { return raw & 0x40 != 0 && raw & 0x20 == 0 ? .windows : nil }
        return .apps
    }
    private func text(_ event: CGEvent) -> String {
        guard let copy = event.copy() else { return "" }
        // Resolve the current keyboard layout, without Option's dead-key glyphs.
        copy.flags = []
        return NSEvent(cgEvent: copy)?.charactersIgnoringModifiers?.lowercased() ?? ""
    }
    private func later(_ action: @escaping () -> Void) { DispatchQueue.main.async(execute: action) }

    private func replay(_ event: CGEvent, originatingPID: pid_t?) {
        guard originatingPID == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        guard let down = event.copy(), let up = event.copy() else { return }
        down.setIntegerValueField(.eventSourceUserData, value: replayMarker)
        up.setIntegerValueField(.eventSourceUserData, value: replayMarker)
        up.type = .keyUp
        down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == replayMarker { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            consumed.removeAll(); resizeKey = nil
            later { self.cancelTransientActions() }
            return false
        }
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            if resizeKey == code { resizeKey = nil; later { self.engine.submit(.endResize) } }
            return consumed.remove(code) != nil
        }
        let flags = event.flags
        var mods = flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn])
        // macOS marks navigation keys as function keys even without physical Fn.
        // Keep Fn significant for letters, but allow the declared arrow chords.
        if type == .keyDown && (123...126).contains(code) {
            mods.remove(.maskSecondaryFn)
        }
        let ca: CGEventFlags = [.maskControl, .maskAlternate]
        let hyper: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        if stagePickerOpen?() == true { return false }
        if type == .flagsChanged {
            if mods != ca && mods != [.maskShift, .maskControl, .maskAlternate] && mods != [.maskShift, .maskControl, .maskCommand] { later { self.engine.submit(.endResize) } }
            updateSwitcher(enabled ? mode(for: flags) : nil)
            return false
        }
        guard type == .keyDown else { return false }
        if consumed.contains(code) {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return true
            }
            // Recover if a keyUp was lost during a session/tap transition.
            consumed.remove(code)
        }
        let key = text(event)
        // This toggle remains available during capture and while paused.
        if mods == hyper && key == "s" {
            consumed.insert(code); later { self.toggleOverride() }; return true
        }
        guard enabled else { updateSwitcher(nil); return false }
        if let mode = mode(for: flags) {
            updateSwitcher(mode)
            let selected = code == 48 ? "tab" : key
            // Replay an unmatched window shortcut after its AX lookup, keeping
            // the original modifier flags and pairing both key events.
            if switcher.canSelect(selected, mode: mode) {
                guard let original = event.copy() else { return false }
                consumed.insert(code)
                let originatingPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                later {
                    self.switcher.requestSelection(selected) { matched in
                        if !matched { self.replay(original, originatingPID: originatingPID) }
                    }
                }
                return true
            }
            return false
        }
        updateSwitcher(nil)
        var action: WindowAction?
        if mods == [.maskAlternate] {
            switch key { case "h": action = .focus(.left); case "j": action = .focus(.down)
            case "k": action = .focus(.up); case "l": action = .focus(.right); default: break }
        } else if mods == ca {
            switch code {
            case 123: action = .tile(2, 1, 0, 0)
            case 124: action = .tile(2, 1, 1, 0)
            case 36, 76: action = .maximize
            case 51, 117: action = .restore
            case 69: action = .resize(1)
            case 78: action = .resize(-1)
            default:
                switch key {
                case "u": action = .tile(2, 2, 0, 0); case "i": action = .tile(2, 2, 1, 0)
                case "j": action = .tile(2, 2, 0, 1); case "k": action = .tile(2, 2, 1, 1)
                case "c": action = .center; case "0": action = .split
                case "+", "=": action = .resize(1); case "-": action = .resize(-1)
                default: break
                }
            }
        } else if mods == [.maskControl, .maskAlternate, .maskShift] {
            if code == 69 || key == "+" || key == "=" { action = .resizeHeight(1) }
            else if code == 78 || key == "-" { action = .resizeHeight(-1) }
            else if code == 123 { action = .fill(true, nil) }
            else if code == 124 { action = .fill(false, nil) }
            else {
                switch key {
                case "u": action = .fill(true, 0); case "i": action = .fill(false, 0)
                case "j": action = .fill(true, 1); case "k": action = .fill(false, 1); default: break
                }
            }
        } else if mods == [.maskShift, .maskControl, .maskCommand] {
            if code == 69 || key == "+" || key == "=" { action = .resizeHeight(1) }
            if code == 78 || key == "-" { action = .resizeHeight(-1) }
        } else if mods == [.maskControl, .maskAlternate, .maskCommand] {
            if code == 123 { action = .moveDisplay(.left) }
            if code == 124 { action = .moveDisplay(.right) }
        } else if mods == hyper {
            if key == "j" { consumed.insert(code); later { self.onStagePicker?() }; return true }
            if code == 48 { action = .nextDisplay }
            if key == "m" { action = .centerMouse }
            if key == "r" { consumed.insert(code); later { self.onReload?() }; return true }
        }
        guard let action else { return false }
        consumed.insert(code)
        if case .resize = action { resizeKey = code }
        if case .resizeHeight = action { resizeKey = code }
        later { self.engine.submit(action) }
        return true
    }
}
