import AppKit
import ApplicationServices

private final class StagePickerPanel: NSPanel {
    var command: ((UInt16) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if command?(event.keyCode) != true { super.keyDown(with: event) }
    }
}

/// A key panel that leaves the user's application and Stage Manager group active.
final class StagePicker: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private struct Entry {
        let window: AccessibleWindow
        let app: String
        var label: String { "\(app) — \(window.title.isEmpty ? "Nimetön ikkuna" : window.title)" }
    }
    private let engine: WindowEngine
    private let overlay: Overlay
    private var timer: Timer?
    private var sampling = false
    private var history: [String] = [] // Only accessed on engine.queue.
    private var entries: [Entry] = []
    private var filtered: [Entry] = []
    private var origin: AccessibleWindow?
    private var uniqueTitles = Set<String>()
    private var panel: NSPanel?
    private let search = NSSearchField()
    private let table = NSTableView()
    private var generation = 0
    private(set) var isOpen = false

    init(engine: WindowEngine, overlay: Overlay) {
        self.engine = engine; self.overlay = overlay
        super.init()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.sample() }
    }
    func stop() { timer?.invalidate(); timer = nil; close() }
    private func sample() {
        guard !isOpen, !sampling, let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular else { return }
        sampling = true
        let pid = app.processIdentifier
        engine.queue.async {
            if let window = self.engine.access.focused(pid: pid) {
                self.history.removeAll { $0 == window.identity }
                self.history.insert(window.identity, at: 0)
                self.history = Array(self.history.prefix(100))
            }
            DispatchQueue.main.async { self.sampling = false }
        }
    }
    func show() {
        guard !isOpen, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        isOpen = true; generation += 1
        let version = generation
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        engine.queue.async {
            guard CFPreferencesCopyAppValue("GloballyEnabled" as CFString, "com.apple.WindowManager" as CFString) as? Bool == true else {
                DispatchQueue.main.async {
                    guard self.generation == version else { return }
                    self.close(); self.showFailure("Ota Stage Manager käyttöön ennen ikkunoiden liittämistä.")
                }
                return
            }
            let origin = self.engine.access.focused(pid: pid)
            let visible = NativeWindow.snapshot()
            let allEntries = apps.flatMap { app in
                self.engine.access.windows(pid: app.processIdentifier, fresh: true).map {
                    Entry(window: $0, app: app.localizedName ?? "Sovellus")
                }
            }
            let uniqueTitles = Set(Dictionary(grouping: allEntries, by: { $0.window.title })
                .filter { !$0.key.isEmpty && $0.value.count == 1 }.keys)
            let entries = allEntries.compactMap { entry -> Entry? in
                    let window = entry.window
                    guard !window.minimized, AX.value(window.element, "AXFullScreen") as? Bool != true,
                          window.identity != origin?.identity,
                          self.engine.access.native(for: window, in: visible) == nil else { return nil }
                    return entry
            }.sorted {
                let a = self.history.firstIndex(of: $0.window.identity) ?? Int.max
                let b = self.history.firstIndex(of: $1.window.identity) ?? Int.max
                return a == b ? $0.label.localizedStandardCompare($1.label) == .orderedAscending : a < b
            }
            DispatchQueue.main.async {
                guard self.generation == version, self.isOpen else { return }
                self.origin = origin; self.entries = entries; self.uniqueTitles = uniqueTitles; self.present()
            }
        }
    }
    func close() {
        generation += 1; isOpen = false; panel?.orderOut(nil)
        entries = []; filtered = []; origin = nil
    }
    private func present() {
        if panel == nil {
            let panel = StagePickerPanel(contentRect: CGRect(x: 0, y: 0, width: 640, height: 390),
                                         styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Lisää ikkuna tähän ryhmään"
            panel.command = { [weak self] code in
                guard let self else { return false }
                switch code {
                case 53: self.close()
                case 36, 76: self.confirm()
                case 125: self.move(1)
                case 126: self.move(-1)
                default: return false
                }
                return true
            }
            panel.level = .statusBar; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 640, height: 390))
            search.frame = CGRect(x: 16, y: 338, width: 608, height: 30)
            search.placeholderString = "Hae sovellusta tai ikkunaa…"; search.delegate = self
            content.addSubview(search)
            let scroll = NSScrollView(frame: CGRect(x: 16, y: 44, width: 608, height: 280))
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window")); column.width = 600
            table.addTableColumn(column); table.headerView = nil; table.rowHeight = 30
            table.dataSource = self; table.delegate = self
            table.target = self; table.doubleAction = #selector(confirm)
            scroll.documentView = table; scroll.hasVerticalScroller = true; content.addSubview(scroll)
            let hint = NSTextField(labelWithString: "↑↓ Valitse    ↵ Lisää    Esc Sulje")
            hint.frame = CGRect(x: 20, y: 12, width: 600, height: 22); hint.textColor = .secondaryLabelColor
            content.addSubview(hint); panel.contentView = content
            self.panel = panel
        }
        search.stringValue = ""; filter()
        panel?.center(); panel?.makeKeyAndOrderFront(nil); panel?.makeFirstResponder(search)
    }
    func controlTextDidChange(_ obj: Notification) { filter() }
    private func filter() {
        let words = search.stringValue.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        filtered = entries.filter { entry in words.allSatisfy { entry.label.localizedStandardContains($0) } }
        table.reloadData()
        search.placeholderString = entries.isEmpty ? "Ei lisättäviä ikkunoita" : "Hae sovellusta tai ikkunaa…"
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = NSTextField(labelWithString: filtered[row].label)
        field.lineBreakMode = .byTruncatingTail; return field
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)): close(); return true
        case #selector(NSResponder.insertNewline(_:)): confirm(); return true
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        default: return false
        }
    }
    private func move(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let row = min(filtered.count-1, max(0, table.selectedRow+delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
    }
    @objc private func confirm() {
        guard filtered.indices.contains(table.selectedRow), let origin else { return }
        let target = filtered[table.selectedRow].window
        guard uniqueTitles.contains(target.title) else {
            showFailure("Ikkunan otsikko ei ole yksilöllinen. Liitä ikkuna vetämällä Stage Managerin sivupalkista.")
            return
        }
        close()
        // Wait for physical modifiers to be released before asking WindowManager to join.
        joinAfterRelease(target, origin: origin, attempts: 30)
    }
    private func joinAfterRelease(_ target: AccessibleWindow, origin: AccessibleWindow, attempts: Int) {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty {
            guard attempts > 0 else { showFailure("Liittäminen peruttiin: vapauta muokkausnäppäimet."); return }
            DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { self.joinAfterRelease(target, origin: origin, attempts: attempts-1) }
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == origin.pid else {
            showFailure("Liittäminen peruttiin: aktiivinen sovellus vaihtui."); return
        }
        engine.queue.async {
            let result = self.addToStage(target)
            DispatchQueue.main.async {
                if let error = result {
                    self.showFailure(error)
                } else {
                    self.verifyJoin(target, origin: origin, attempts: 8)
                }
            }
        }
    }
    private func showFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Ikkunan liittäminen ei onnistunut"
        if message.count > 700 {
            alert.informativeText = "Tarkemmat tiedot ovat alla. Kopioi virhe -painikkeella saat koko tekstin talteen."
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false; text.isSelectable = true; text.string = message
            text.font = .systemFont(ofSize: 12)
            text.textContainer?.widthTracksTextView = true
            text.isVerticallyResizable = true
            scroll.documentView = text; scroll.hasVerticalScroller = true
            alert.accessoryView = scroll
        } else {
            alert.informativeText = message
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Kopioi virhe")
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message, forType: .string)
        }
    }
    // Stage Manager exposes a nonstandard AXAddToStage action in WindowManager.
    // Match either a unique title or a uniquely identified app-owned thumbnail.
    private func addToStage(_ target: AccessibleWindow) -> String? {
        let managers = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager")
        guard let manager = managers.first else {
            return "Stage Managerin WindowManager-prosessia ei löytynyt. Tarkista, että Stage Manager on käytössä."
        }
        var pending = [AX.application(manager.processIdentifier)]
        var matches: [AXUIElement] = []
        var buttons: [(AXUIElement, CGRect)] = []
        var diagnostics: [String] = []
        var count = 0
        var actionCount = 0
        let started = ProcessInfo.processInfo.systemUptime
        while !pending.isEmpty && count < 1000 && ProcessInfo.processInfo.systemUptime-started < 3 {
            let element = pending.removeLast(); count += 1
            AXUIElementSetMessagingTimeout(element, 0.05)
            var names: CFArray?
            let status = AXUIElementCopyActionNames(element, &names)
            let actions = status == .success ? (names as? [String] ?? []) : []
            if actions.contains("AXAddToStage") {
                actionCount += 1
                let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].map { AX.string(element, $0) }
                let frame = AX.frame(element)
                if let frame, !buttons.contains(where: { CFEqual($0.0, element) }) {
                    buttons.append((element, frame))
                }
                if diagnostics.count < 16 {
                    let label = labels.filter { !$0.isEmpty }.joined(separator: " | ")
                    diagnostics.append("\(label.prefix(160)) · \(frame.map { NSStringFromRect($0) } ?? "ei sijaintia")")
                }
                if labels.contains(target.title), !matches.contains(where: { CFEqual($0, element) }) {
                    matches.append(element)
                }
            }
            pending.append(contentsOf: AX.elements(element, kAXChildrenAttribute))
        }
        let titleMatches = matches.count
        let native = NativeWindow.snapshot().filter { $0.pid == target.pid }
        let titled = native.filter { $0.title == target.title }
        let appWindows = engine.access.windows(pid: target.pid, fresh: true)
            .filter { !$0.minimized }
        // A process with several windows cannot be identified from its PID alone.
        let thumbnail: NativeWindow?
        if titled.count == 1 {
            thumbnail = titled[0]
        } else if appWindows.count == 1, appWindows[0].identity == target.identity, native.count == 1 {
            thumbnail = native[0]
        } else {
            thumbnail = nil
        }
        if matches.isEmpty, let thumbnail {
            matches = buttons.compactMap { element, frame in
                let overlap = frame.intersection(thumbnail.frame)
                guard !overlap.isNull else { return nil }
                let area = min(frame.width*frame.height, thumbnail.frame.width*thumbnail.frame.height)
                guard area > 0, overlap.width*overlap.height/area > 0.5,
                      frame.contains(CGPoint(x: thumbnail.frame.midX, y: thumbnail.frame.midY)) else { return nil }
                return element
            }
        }
        guard matches.count == 1 else {
            let complete = pending.isEmpty ? "valmis" : "aika- tai solmuraja saavutettu"
            return "Ikkunalle ‘\(target.title)’ ei löytynyt yksiselitteistä Lisää ryhmään -toimintoa.\n\nWindowManager: \(count) kohdetta, \(actionCount) AXAddToStage-toimintoa, \(titleMatches) otsikkovastaavuutta, \(matches.count) lopullista vastaavuutta; haku \(complete).\nSovellus: \(appWindows.count) AX-ikkunaa, \(native.count) näkyvää CG-kohdetta, \(titled.count) CG-otsikkovastaavuutta.\nPienoiskuva: \(thumbnail.map { NSStringFromRect($0.frame) } ?? "ei yksilöitävissä").\n\nLiittämiskohteet:\n\(diagnostics.joined(separator: "\n"))\n\nKopioi tämä virhe, jos ongelma jatkuu."
        }
        guard pending.isEmpty else {
            return "Stage Managerin käyttöapuhaku jäi kesken. Yksiselitteistä kohdetta ei voitu varmistaa (\(count) kohdetta)."
        }
        let result = AXUIElementPerformAction(matches[0], "AXAddToStage" as CFString)
        return result == .success ? nil : "Stage Manager hylkäsi AXAddToStage-toiminnon: AX-virhe \(result.rawValue)."
    }
    private func verifyJoin(_ target: AccessibleWindow, origin: AccessibleWindow, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
            self.engine.queue.async {
                let all = NativeWindow.snapshot()
                let joined = [target, origin].allSatisfy { window in
                    guard let frame = AX.frame(window.element) else { return false }
                    let refreshed = AccessibleWindow(element: window.element, pid: window.pid, title: window.title, frame: frame)
                    return self.engine.access.native(for: refreshed, in: all) != nil
                }
                DispatchQueue.main.async {
                    if joined {
                        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
                        if !self.isOpen && (pid == origin.pid || pid == target.pid) {
                            self.engine.queue.async { _ = self.engine.access.focus(origin) }
                        }
                    } else if attempts > 0 {
                        self.verifyJoin(target, origin: origin, attempts: attempts-1)
                    } else {
                        self.showFailure("Ryhmään liittämistä ei voitu varmistaa. Voit vetää ikkunan Stage Managerin sivupalkista ryhmään.")
                    }
                }
            }
        }
    }
}
