import AppKit
import CoreGraphics
import os
import ApplicationServices
import IkkunaCore

enum WindowAction {
    case tile(Int, Int, Int, Int), center, maximize, restore
    case focus(Direction), moveDisplay(Direction), nextDisplay, centerMouse
    case fill(Bool, Int?), split, resize(Double), resizeHeight(Double), endResize
}

final class WindowEngine {
    let queue = DispatchQueue(label: "fi.iiro.Ikkuna.windows", qos: .userInteractive)
    let access = WindowAccess()
    var notice: ((String) -> Void)?
    private var configuration: Configuration
    private var history: [String: CGRect] = [:]
    private var returnMemory: [UInt32: [Direction: UInt32]] = [:]
    private var recentFocus: (AccessibleWindow, TimeInterval)?
    private var resizeTimer: DispatchSourceTimer?
    private var resizePlan: ResizePlan?
    private var resizeWindows: [UInt32: AccessibleWindow] = [:]
    private var enhancedApps: [AXUIElement] = []
    private var resizeLastFrames: [UInt32: CGRect] = [:]
    private var resizeStarted: TimeInterval = 0
    private var lastNextDisplay: TimeInterval = 0

    init(configuration: Configuration) { self.configuration = configuration }
    func configure(_ configuration: Configuration) {
        queue.async { self.stopResize(); self.configuration = configuration; self.access.invalidate() }
    }

    func submit(_ action: WindowAction) {
        // Capture AppKit display and focus state on the main thread.
        let displays = Display.snapshot()
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async {
            if case .endResize = action { self.stopResize(); return }
            guard let pid, !displays.isEmpty else { return }
            self.perform(action, pid: pid, displays: displays)
        }
    }

    private var stageManager: Bool {
        // Read the preference directly; no helper process or shell command.
        CFPreferencesAppSynchronize("com.apple.WindowManager" as CFString)
        return CFPreferencesCopyAppValue("GloballyEnabled" as CFString, "com.apple.WindowManager" as CFString) as? Bool ?? false
    }
    private func usable(_ display: Display, stage: Bool) -> CGRect {
        let left = configuration.stageManagerLeftInset, right = configuration.stageManagerRightInset
        guard stage, left + right < display.visible.width else { return display.visible }
        return CGRect(x: display.visible.minX+left, y: display.visible.minY,
                      width: display.visible.width-left-right, height: display.visible.height)
    }
    private func displayIndex(_ frame: CGRect, _ displays: [Display]) -> Int? {
        Geometry.screenIndex(for: frame, screens: displays.map(\.frame))
    }
    private func focused(pid: pid_t) -> AccessibleWindow? {
        if let recent = recentFocus, ProcessInfo.processInfo.systemUptime-recent.1 < 0.25,
           recent.0.pid == pid || NSRunningApplication(processIdentifier: recent.0.pid)?.isActive == true {
            guard let frame = AX.frame(recent.0.element) else { return access.focused(pid: pid) }
            return AccessibleWindow(element: recent.0.element, pid: recent.0.pid, title: recent.0.title, frame: frame)
        }
        return access.focused(pid: pid)
    }
    private func focus(_ window: AccessibleWindow) {
        if access.focus(window, mouse: true) { recentFocus = (window, ProcessInfo.processInfo.systemUptime) }
    }
    private func visible(_ all: [NativeWindow], screen: Int, displays: [Display], stage: Bool,
                         excluding: UInt32? = nil, includeCovered: Bool = false) -> [NativeWindow] {
        let local = all.filter { displayIndex($0.frame, displays) == screen &&
            NSRunningApplication(processIdentifier: $0.pid)?.activationPolicy == .regular }
        return local.enumerated().compactMap { index, window in
            // A Stage Manager thumbnail cannot be matched to its full-size AX
            // frame. Reject it; a genuinely small real window still matches.
            if (stage || includeCovered) && access.resolve(window) == nil { return nil }
            if !stage && !includeCovered {
                let front = local.prefix(index).filter { $0.id != excluding }.map(\.frame)
                if Geometry.coveredFraction(of: window.frame, by: front) > 0.5 { return nil }
            }
            return window
        }
    }
    private func write(_ window: AccessibleWindow, _ frame: CGRect) {
        if !AX.setFrame(frame, on: window.element, pid: window.pid) { report("Ikkunan siirto tai koon muuttaminen ei onnistunut.") }
        access.invalidate()
    }
    private func report(_ message: String) {
        Diagnostics.shared.record("ERROR \(message)")
        log.error("\(message, privacy: .public)")
        DispatchQueue.main.async { self.notice?(message) }
    }

    private func perform(_ action: WindowAction, pid: pid_t, displays: [Display]) {
        let started = ProcessInfo.processInfo.systemUptime
        defer {
            let elapsed = (ProcessInfo.processInfo.systemUptime-started)*1000
            log.debug("Ikkunakomento \(String(describing: action), privacy: .public): \(elapsed, privacy: .public) ms")
        }
        switch action {
        case .resize, .resizeHeight: break
        default: stopResize()
        }
        guard let current = focused(pid: pid), let screen = displayIndex(current.frame, displays) else { return }
        if AX.value(current.element, "AXFullScreen") as? Bool == true { return }
        let stage = stageManager, display = displays[screen], gap = configuration.windowGap
        let sf = usable(display, stage: stage), raw = display.visible, f = current.frame
        func cycle(_ inset: CGRect, _ extended: CGRect) -> CGRect {
            stage && Geometry.approximatelyEqual(f, inset) && !Geometry.approximatelyEqual(inset, extended) ? extended : inset
        }
        switch action {
        case .tile(let columns, let rows, let column, let row):
            write(current, cycle(Geometry.tile(in: sf, columns: columns, rows: rows, column: column, row: row, gap: gap),
                                 Geometry.tile(in: raw, columns: columns, rows: rows, column: column, row: row, gap: gap)))
        case .center:
            write(current, Geometry.centerCycle(from: f, in: sf, centeredOn: raw.midX, gap: gap))
        case .maximize:
            let inset = Geometry.tile(in: sf, columns: 1, rows: 1, column: 0, row: 0, gap: gap)
            if !Geometry.approximatelyEqual(f, raw) && !Geometry.approximatelyEqual(f, inset) { history[current.identity] = f }
            write(current, stage ? cycle(inset, raw) : raw)
        case .restore:
            if let previous = history[current.identity] { write(current, previous) }
        case .centerMouse:
            CGWarpMouseCursorPosition(CGPoint(x: f.midX, y: f.midY))
        case .moveDisplay(let direction):
            let candidates = displays.indices.filter { index in
                index != screen && direction.distances(from: display.frame, to: displays[index].frame).primary > 1
            }
            if let target = candidates.min(by: {
                let a = direction.distances(from: display.frame, to: displays[$0].frame)
                let b = direction.distances(from: display.frame, to: displays[$1].frame)
                return a.primary+2*a.cross < b.primary+2*b.cross
            }) { write(current, Geometry.moved(f, from: raw, to: displays[target].visible)) }
        case .nextDisplay:
            let now = ProcessInfo.processInfo.systemUptime
            guard displays.count > 1, now-lastNextDisplay > 0.15 else { return }
            lastNextDisplay = now
            let all = NativeWindow.snapshot()
            let next = (screen+1) % displays.count
            for window in visible(all, screen: next, displays: displays, stage: stage) {
                if let resolved = access.resolve(window) { focus(resolved); break }
            }
        case .focus(let direction):
            let all = NativeWindow.snapshot()
            guard let native = access.native(for: current, in: all) else { return }
            // Focus navigation must reach buried windows too, even if the
            // WindowManager preference temporarily reports Stage Manager off.
            var candidates = visible(all, screen: screen, displays: displays, stage: stage, includeCovered: true)
            func targetID() -> UInt32? {
                if let id = Geometry.directionalTarget(from: native.rect, candidates: candidates.map(\.rect), direction: direction,
                                                       remembered: returnMemory[native.id]?[direction]) { return id }
                // Co-centred windows have no direction on this axis. Keep them
                // reachable within the active stage when spatial navigation has no target.
                let stack = candidates.sorted { $0.id < $1.id }
                guard stack.count > 1, let index = stack.firstIndex(where: { $0.id == native.id }) else { return nil }
                let offset = direction == .left || direction == .up ? stack.count-1 : 1
                return stack[(index+offset) % stack.count].id
            }
            while let id = targetID(),
                  let target = candidates.first(where: { $0.id == id }) {
                if let resolved = access.resolve(target) {
                    if access.focus(resolved, mouse: true) {
                        recentFocus = (resolved, ProcessInfo.processInfo.systemUptime)
                        returnMemory[id, default: [:]][direction.opposite] = native.id
                    }
                    break
                }
                candidates.removeAll { $0.id == id }
            }
        case .fill(let left, let row):
            let all = NativeWindow.snapshot()
            let id = access.native(for: current, in: all)?.id
            let neighbors = visible(all, screen: screen, displays: displays, stage: stage, excluding: id).filter { $0.id != id }.map(\.frame)
            write(current, cycle(Geometry.fill(f, in: sf, neighbors: neighbors, left: left, row: row, gap: gap),
                                 Geometry.fill(f, in: raw, neighbors: neighbors, left: left, row: row, gap: gap)))
        case .split:
            split(current, screen: screen, displays: displays, stage: stage)
        case .resize(let sign):
            beginResize(current, screen: screen, displays: displays, stage: stage, sign: sign)
        case .resizeHeight(let sign):
            beginResize(current, screen: screen, displays: displays, stage: stage, sign: sign, vertical: true)
        case .endResize: break
        }
    }

    private func split(_ current: AccessibleWindow, screen: Int, displays: [Display], stage: Bool) {
        let all = NativeWindow.snapshot()
        guard let native = access.native(for: current, in: all) else { return }
        let visibleWindows = visible(all, screen: screen, displays: displays, stage: stage, excluding: native.id)
        let others = visibleWindows.filter { $0.id != native.id }
        let aligned = others.filter { abs($0.frame.minX-current.frame.minX) < 20 && abs($0.frame.maxX-current.frame.maxX) < 20 }
        var neighbors = others.filter { window in
            !aligned.contains(where: { $0.id == window.id }) && window.frame.maxY > current.frame.minY &&
            window.frame.minY < current.frame.maxY &&
            (abs(window.frame.minX-current.frame.maxX) < 24 || abs(window.frame.maxX-current.frame.minX) < 24)
        }
        if neighbors.isEmpty, let nearest = others.filter({
            !aligned.contains($0) && $0.frame.maxY > current.frame.minY && $0.frame.minY < current.frame.maxY
        }).min(by: { abs($0.frame.midX-current.frame.midX) < abs($1.frame.midX-current.frame.midX) }) { neighbors = [nearest] }
        guard !neighbors.isEmpty else { return }
        let right = neighbors.filter { $0.frame.midX > current.frame.midX }
        let left = neighbors.filter { $0.frame.midX <= current.frame.midX }
        let primaryLeft = right.count >= left.count
        let own = ([native]+aligned).sorted { $0.frame.minY < $1.frame.minY }
        let opposite = (primaryLeft ? right : left).sorted { $0.frame.minY < $1.frame.minY }
        let columns = primaryLeft ? [own, opposite] : [opposite, own]
        func layout(_ base: CGRect) -> [UInt32: CGRect] {
            var result: [UInt32: CGRect] = [:]
            for (column, windows) in columns.enumerated() {
                for (row, window) in windows.enumerated() {
                    result[window.id] = Geometry.tile(in: base, columns: 2, rows: windows.count, column: column, row: row, gap: configuration.windowGap)
                }
            }
            return result
        }
        let inset = layout(usable(displays[screen], stage: stage)), full = layout(displays[screen].visible)
        let frames = stage && inset[native.id].map({ Geometry.approximatelyEqual($0, current.frame) }) == true ? full : inset
        // Resolve all participants before writing: a partial scan must not move
        // a window into an unresolved neighbor.
        let selected = columns.flatMap { $0 }
        let resolved = selected.compactMap { access.resolve($0) }
        guard resolved.count == selected.count else { report("Kaikkia jaon ikkunoita ei saatu käyttöön."); return }
        for (nativeWindow, window) in zip(selected, resolved) {
            if let frame = frames[nativeWindow.id] { write(window, frame) }
        }
    }

    private func beginResize(_ current: AccessibleWindow, screen: Int, displays: [Display], stage: Bool, sign: Double, vertical: Bool = false) {
        guard resizeTimer == nil else { return }
        let all = NativeWindow.snapshot()
        guard let native = access.native(for: current, in: all) else { return }
        let windows = visible(all, screen: screen, displays: displays, stage: stage, excluding: native.id)
        let plan = ResizePlan(focused: native.rect, windows: windows.map(\.rect), screen: usable(displays[screen], stage: stage), vertical: vertical)
        var participants: [UInt32: AccessibleWindow] = [:]
        for id in plan.originals.keys {
            guard let record = all.first(where: { $0.id == id }), let window = access.resolve(record) else { return }
            participants[id] = window
        }
        Diagnostics.shared.record("RESIZE START axis=\(vertical ? "vertical" : "horizontal") sign=\(sign) stage=\(stage) screen=\(usable(displays[screen], stage: stage)) primary=\(plan.primary.sorted()) neighbors=\(plan.neighbors.sorted())")
        for (id, window) in participants.sorted(by: { $0.key < $1.key }) {
            Diagnostics.shared.record("WINDOW id=\(id) pid=\(window.pid) frame=\(window.frame)")
        }
        resizePlan = plan; resizeWindows = participants; resizeLastFrames = plan.originals
        for pid in Set(participants.values.map(\.pid)) {
            if let app = AX.suspendEnhancedUI(for: pid) { enhancedApps.append(app) }
        }
        resizeStarted = ProcessInfo.processInfo.systemUptime
        applyResize(sign*50)
        guard resizePlan != nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        resizeTimer = timer
        timer.schedule(deadline: .now()+0.18, repeating: 1.0/60.0, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard NSRunningApplication(processIdentifier: current.pid)?.isActive == true else { self.stopResize(); return }
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime-self.resizeStarted-0.18)
            // Integrate a 120 ms linear acceleration. Wall time avoids queued
            // movement when an application is slower than the desired 60 Hz.
            let ramp = min(elapsed, 0.12)
            let distance = 900*(ramp*ramp/0.24 + max(0, elapsed-0.12))
            self.applyResize(sign*(50+distance))
        }
        timer.resume()
    }
    private func applyResize(_ delta: Double) {
        guard let plan = resizePlan else { return }
        let frames = plan.frames(delta: delta)
        let previousFrames = resizeLastFrames
        var failed = false
        // Resize, move, then resize again: macOS may clamp a growing window
        // against its old bottom/right edge before its origin has moved.
        for id in frames.keys.sorted() {
            guard let frame = frames[id], let previous = previousFrames[id],
                  let window = resizeWindows[id] else { failed = true; continue }
            if Geometry.approximatelyEqual(previous, frame, tolerance: 0.5) { continue }
            let ok = AX.setFrame(frame, on: window.element, pid: window.pid)
            if !ok { failed = true }
            Diagnostics.shared.record("RESIZE WRITE id=\(id) delta=\(delta) previous=\(previous) requested=\(frame) AXok=\(ok)")
        }
        // Verify the entire group before committing the new shared boundary.
        // A successful AX return does not guarantee the requested size was used.
        for id in frames.keys.sorted() {
            guard let frame = frames[id], let window = resizeWindows[id] else { failed = true; continue }
            let actual = AX.frame(window.element)
            let mismatch = actual.map { !Geometry.approximatelyEqual($0, frame, tolerance: 3) } ?? true
            Diagnostics.shared.record("RESIZE CHECK id=\(id) requested=\(frame) actual=\(actual.map { NSStringFromRect($0) } ?? "unavailable") mismatch=\(mismatch)")
            if mismatch { failed = true }
        }
        if failed {
            // Restore every participant, including ones already changed this tick.
            var restored = true
            for id in previousFrames.keys.sorted() {
                guard let frame = previousFrames[id], let window = resizeWindows[id] else { restored = false; continue }
                let ok = AX.setFrame(frame, on: window.element, pid: window.pid)
                let actual = AX.frame(window.element)
                let matches = actual.map { Geometry.approximatelyEqual($0, frame, tolerance: 3) } ?? false
                restored = restored && ok && matches
                Diagnostics.shared.record("RESIZE ROLLBACK id=\(id) requested=\(frame) actual=\(actual.map { NSStringFromRect($0) } ?? "unavailable") AXok=\(ok) restored=\(matches)")
            }
            stopResize()
            report(restored ? "Koonsäätö saavutti sovelluksen rajan. Edellinen asettelu palautettiin." : "Koonsäätö keskeytettiin. Asettelun palautus jäi vajaaksi; tarkista diagnostiikkaloki.")
            return
        }
        resizeLastFrames = frames
    }
    private func stopResize() {
        if resizePlan != nil {
            for (id, window) in resizeWindows.sorted(by: { $0.key < $1.key }) {
                Diagnostics.shared.record("RESIZE END id=\(id) actual=\(AX.frame(window.element).map { NSStringFromRect($0) } ?? "unavailable")")
            }
        }
        resizeTimer?.cancel(); resizeTimer = nil; resizePlan = nil; resizeWindows.removeAll(); resizeLastFrames.removeAll()
        for app in enhancedApps { AX.set(app, "AXEnhancedUserInterface", kCFBooleanTrue) }
        enhancedApps.removeAll()
        access.invalidate()
    }
}
