import AppKit
import CoreGraphics

/// A nonactivating panel: showing the switcher must never steal keyboard focus.
final class Overlay {
    private var panel: NSPanel?
    private var toast: NSPanel?
    private var toastGeneration = 0
    func hide() { panel?.orderOut(nil) }
    func show(title: String, subtitle: String, rows: [NSAttributedString]) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        let maximumRows = max(1, Int((screen.visibleFrame.height-134)/25))
        let columns = max(1, Int(ceil(Double(max(1, rows.count))/Double(maximumRows))))
        let rowCount = max(1, Int(ceil(Double(rows.count)/Double(columns))))
        let width = min(CGFloat(columns)*340+40, screen.visibleFrame.width-48)
        let height = CGFloat(rowCount)*25+86
        panel.setFrame(CGRect(x: screen.visibleFrame.midX-width/2, y: screen.visibleFrame.midY-height/2, width: width, height: height), display: false)
        let background = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        background.material = .hudWindow; background.blendingMode = .behindWindow
        background.state = .active; background.wantsLayer = true; background.layer?.cornerRadius = 14
        let tint = NSView(frame: background.bounds)
        tint.wantsLayer = true; tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
        tint.layer?.cornerRadius = 14
        background.addSubview(tint)
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        heading.frame = CGRect(x: 20, y: height-36, width: width-40, height: 22)
        let hint = NSTextField(labelWithString: subtitle)
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.frame = CGRect(x: 20, y: height-57, width: width-40, height: 18)
        background.addSubview(heading); background.addSubview(hint)
        let displayed = rows.isEmpty ? [NSAttributedString(string: "Ei valittavia kohteita", attributes: [.foregroundColor: NSColor.secondaryLabelColor])] : rows
        let columnWidth = (width-40)/CGFloat(columns)
        for (index, row) in displayed.enumerated() {
            let field = NSTextField(labelWithAttributedString: row)
            field.lineBreakMode = .byTruncatingTail
            let column = index/rowCount, position = index % rowCount
            field.frame = CGRect(x: 20+CGFloat(column)*columnWidth, y: height-84-CGFloat(position)*25,
                                 width: columnWidth-14, height: 22)
            background.addSubview(field)
        }
        panel.contentView = background; panel.orderFrontRegardless()
    }
    func message(_ message: String) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        if toast == nil { toast = makePanel() }
        guard let toast else { return }
        let width = min(620, screen.visibleFrame.width-40)
        let label = NSTextField(wrappingLabelWithString: message)
        label.alignment = .center; label.font = .systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.preferredMaxLayoutWidth = width-32
        let background = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: width, height: 68))
        background.material = .hudWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 12
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: width-32)
        ])
        toast.contentView = background
        toast.setFrame(CGRect(x: screen.visibleFrame.midX-width/2, y: screen.visibleFrame.minY+70, width: width, height: 68), display: true)
        toast.orderFrontRegardless(); toastGeneration += 1
        let version = toastGeneration
        DispatchQueue.main.asyncAfter(deadline: .now()+2.5) { if self.toastGeneration == version { self.toast?.orderOut(nil) } }
    }
    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        return panel
    }
}
