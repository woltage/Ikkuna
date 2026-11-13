import AppKit

/// Bounded, process-local diagnostics. No files or network writes.
final class Diagnostics: NSObject {
    static let shared = Diagnostics()
    private let lock = NSLock()
    private var lines: [String] = []
    private let limit = 300
    private var window: NSWindow?
    private var textView: NSTextView?
    private var timer: Timer?

    func record(_ message: String) {
        let line = String(format: "%.3f %@", ProcessInfo.processInfo.systemUptime, message)
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
        if lines.count > limit { lines.removeFirst(lines.count-limit) }
    }
    private func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return "Ikkuna diagnostics — \(ProcessInfo.processInfo.operatingSystemVersionString)\nTimes: seconds since boot. Last \(limit) entries, memory only.\n\n" + lines.joined(separator: "\n")
    }
    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 540),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Ikkuna · Diagnostiikkaloki"
            window.isReleasedWhenClosed = false
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 540))
            let scroll = NSScrollView(frame: NSRect(x: 12, y: 52, width: 876, height: 476))
            scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false; text.isSelectable = true
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.autoresizingMask = [.width]; text.isVerticallyResizable = true
            text.textContainer?.widthTracksTextView = true
            scroll.documentView = text; content.addSubview(scroll)
            for (index, item) in [("Kopioi loki", #selector(copyLog)), ("Tyhjennä", #selector(clearLog))].enumerated() {
                let button = NSButton(title: item.0, target: self, action: item.1)
                button.frame = NSRect(x: CGFloat(12+index*140), y: 12, width: 130, height: 28)
                content.addSubview(button)
            }
            window.contentView = content; window.center()
            self.window = window; textView = text
        }
        refresh(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.window?.isVisible == true else { timer.invalidate(); return }
            self.refresh()
        }
    }
    private func refresh() {
        let value = snapshot()
        if textView?.string != value { textView?.string = value }
    }
    @objc private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot(), forType: .string)
    }
    @objc private func clearLog() {
        lock.lock(); lines.removeAll(); lock.unlock(); refresh()
    }
}
