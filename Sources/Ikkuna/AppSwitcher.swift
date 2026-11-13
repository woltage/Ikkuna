import AppKit
import os
import ApplicationServices
import IkkunaCore

final class AppSwitcher {
    enum Mode: Equatable { case apps, windows }
    private struct Entry {
        let key: String
        let name: String
        let id: String
        let app: NSRunningApplication?
        let window: AccessibleWindow?
        var score: Int = 0
    }
    private let engine: WindowEngine
    private let overlay: Overlay
    private var configuration: Configuration
    private var mode: Mode?
    private var windowPID: pid_t?
    private var windowDisplays: [Display] = []
    private var stageSession = -1 // Accessed only on engine.queue.
    private var stageScreen: Int?
    private var entries: [Entry] = []
    private var usage: [String: Int] = loadJSON([String: Int].self, name: "app-usage.json") ?? [:]
    private var pendingApp: NSRunningApplication?
    private var selectedID: String?
    private var selectedKey: String?
    private var generation = 0
    private var windowSelectionSession = -1 // Accessed only on engine.queue.
    private var windowSelectionID: String?
    private var refresh: DispatchWorkItem?

    init(engine: WindowEngine, overlay: Overlay, configuration: Configuration) {
        self.engine = engine; self.overlay = overlay; self.configuration = configuration
    }
    func configure(_ configuration: Configuration) { end(); self.configuration = configuration }

    func setMode(_ newMode: Mode?) {
        guard newMode != mode else { return }
        refresh?.cancel(); generation += 1
        if newMode == nil { end(); return }
        mode = newMode; selectedKey = nil
        if newMode == .apps {
            windowPID = nil
            refreshApps()
            selectedID = NSWorkspace.shared.frontmostApplication.map { "\($0.processIdentifier)" }
            draw()
        } else {
            windowPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            windowDisplays = Display.snapshot()
            entries = []; selectedID = nil
            draw()
            refreshWindows()
            let work = DispatchWorkItem { [weak self] in self?.refreshWindows() }
            refresh = work
            DispatchQueue.main.asyncAfter(deadline: .now()+0.2, execute: work)
        }
    }

    func end() {
        if let app = pendingApp, app.isActive {
            let id = identity(app)
            usage[id] = min(1_000_000, (usage[id] ?? 0)+1)
            saveJSON(usage, name: "app-usage.json")
        }
        generation += 1; pendingApp = nil; mode = nil; windowPID = nil; entries = []
        refresh?.cancel(); refresh = nil; overlay.hide()
    }

    func canSelect(_ key: String, mode: Mode) -> Bool {
        if mode == .windows {
            // Resolve against a fresh AX snapshot asynchronously. Unknown keys
            // are replayed if no window matches, including a fast first chord.
            return key == "tab" || key.range(of: "^[a-z0-9]$", options: .regularExpression) != nil
        }
        refreshApps()
        return entries.contains { $0.key == key }
    }

    func requestSelection(_ key: String, completion: @escaping (Bool) -> Void) {
        guard mode == .windows, let pid = windowPID else { completion(select(key)); return }
        let version = generation, displays = windowDisplays
        engine.queue.async { [weak self] in
            guard let self else { return }
            let windows = self.stageWindows(pid: pid, displays: displays, version: version)
            let entries = Self.windowEntries(windows)
            let candidates = entries.filter { key == "tab" || $0.key == key }
            let current = self.windowSelectionSession == version ? self.windowSelectionID : self.engine.access.focused(pid: pid)?.identity
            guard let index = AppRules.nextIndex(ids: candidates.map(\.id), current: current),
                  let window = candidates[index].window else {
                DispatchQueue.main.async { completion(false) }; return
            }
            let target = candidates[index]
            let focused = self.engine.access.focus(window, mouse: true)
            self.windowSelectionSession = version; self.windowSelectionID = target.id
            DispatchQueue.main.async {
                if self.generation == version && self.mode == .windows {
                    self.entries = entries; self.selectedID = target.id; self.selectedKey = key; self.draw()
                }
                if !focused { log.error("Ikkunavaihto ei onnistunut") }
                // A known shortcut stays consumed even if its target refuses focus.
                completion(true)
            }
        }
    }

    @discardableResult func select(_ key: String) -> Bool {
        guard mode == .apps else { return false }
        refreshApps()
        let candidates = entries.filter { $0.key == key }
        guard !candidates.isEmpty else { return false }
        let current = selectedID ?? NSWorkspace.shared.frontmostApplication.map { "\($0.processIdentifier)" }
        guard let index = AppRules.nextIndex(ids: candidates.map(\.id), current: current) else { return false }
        let target = candidates[index]
        selectedID = target.id; selectedKey = key
        if let app = target.app {
            pendingApp = app
            app.unhide(); app.activate(options: [.activateIgnoringOtherApps])
            // Activation must happen before any AX request. Most apps need no
            // AX access at all; restore a minimized window only when necessary.
            let pid = app.processIdentifier
            engine.queue.async { [weak self] in
                guard let self else { return }
                if !NativeWindow.snapshot().contains(where: { $0.pid == pid }),
                   let minimized = self.engine.access.windows(pid: pid).first(where: { $0.minimized }) {
                    AX.set(minimized.element, kAXMinimizedAttribute, kCFBooleanFalse)
                }
            }
        }
        draw()
        return true
    }

    private func identity(_ app: NSRunningApplication) -> String {
        (app.bundleIdentifier ?? app.localizedName ?? "\(app.processIdentifier)").lowercased()
    }
    private func refreshApps() {
        let keys = configuration.appKeys, ignored = configuration.ignoredApps
        entries = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            let name = app.localizedName ?? "", bundle = (app.bundleIdentifier ?? "").lowercased()
            guard let key = AppRules.shortcut(name: name, bundleID: bundle, mappings: keys, ignored: ignored) else { return nil }
            return Entry(key: key, name: name, id: "\(app.processIdentifier)", app: app, window: nil, score: usage[identity(app)] ?? 0)
        }.sorted { a, b in
            if a.key != b.key { return a.key < b.key }
            if a.score != b.score { return a.score > b.score }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private func refreshWindows() {
        guard mode == .windows, let pid = windowPID else { return }
        let version = generation, displays = windowDisplays
        engine.queue.async { [weak self] in
            guard let self else { return }
            let windows = self.stageWindows(pid: pid, displays: displays, version: version)
            let focused = self.engine.access.focused(pid: pid)?.identity
            DispatchQueue.main.async {
                guard self.generation == version, self.mode == .windows, self.windowPID == pid else { return }
                self.entries = Self.windowEntries(windows)
                if self.selectedID == nil { self.selectedID = focused }
                self.draw()
            }
        }
    }
    // Pin the display for the chord session so focusing another app cannot
    // change the scope. On-screen CG windows include covered stage windows;
    // resolving their full bounds rejects Stage Manager thumbnails.
    private func stageWindows(pid: pid_t, displays: [Display], version: Int) -> [AccessibleWindow] {
        if stageSession != version {
            stageSession = version
            stageScreen = engine.access.focused(pid: pid).flatMap {
                Geometry.screenIndex(for: $0.frame, screens: displays.map(\.frame))
            }
        }
        guard let screen = stageScreen else { return [] }
        engine.access.invalidate()
        var seen = Set<String>()
        return NativeWindow.snapshot().compactMap { native in
            guard Geometry.screenIndex(for: native.frame, screens: displays.map(\.frame)) == screen,
                  NSRunningApplication(processIdentifier: native.pid)?.activationPolicy == .regular,
                  let window = engine.access.resolve(native), !window.minimized,
                  seen.insert(window.identity).inserted else { return nil }
            return window
        }
    }

    private static func windowEntries(_ windows: [AccessibleWindow]) -> [Entry] {
        windows.enumerated().map { index, window in
            let appName = NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? ""
            let name = window.title.isEmpty ? (appName.lowercased().contains("firefox") ? "\(appName) window \(index+1)" : "Untitled window \(index+1)") : window.title
            return Entry(key: AppRules.initial(name), name: name, id: window.identity, app: nil, window: window)
        }.sorted { a, b in
            let comparison = a.name.localizedStandardCompare(b.name)
            return comparison == .orderedSame ? a.id < b.id : comparison == .orderedAscending
        }
    }

    private func draw() {
        guard let mode else { return }
        let groups = Dictionary(grouping: entries, by: \.key)
        let rows = groups.keys.sorted().map { key -> NSAttributedString in
            let line = NSMutableAttributedString(string: key == "tab" ? "Tab  " : "\(key.uppercased())    ", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: key == selectedKey ? NSColor.systemBlue : NSColor.secondaryLabelColor
            ])
            for (index, entry) in (groups[key] ?? []).enumerated() {
                if index > 0 { line.append(NSAttributedString(string: ", ")) }
                line.append(NSAttributedString(string: entry.name, attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: entry.id == selectedID ? NSColor.systemBlue : NSColor.labelColor
                ]))
            }
            return line
        }
        overlay.show(title: mode == .apps ? "Oikea ⌘ · Sovellukset" : "Oikea ⌘ + oikea ⌥ · Stagen ikkunat",
                     subtitle: mode == .apps ? "Kirjain tai numero vaihtaa · Toista vaihtaaksesi seuraavaan" : "Alkukirjain vaihtaa · Tab selaa kaikki ikkunat",
                     rows: rows)
    }
}
