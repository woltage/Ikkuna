import AppKit
import ApplicationServices
import ServiceManagement

@main
final class IkkunaApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = Overlay()
    private var configuration = Configuration()
    private var engine: WindowEngine!
    private var switcher: AppSwitcher!
    private var hotkeys: Hotkeys!
    private var stagePicker: StagePicker!
    private var healthTimer: Timer?
    private var tapFailed = false
    private var lastHammerspoon = false
    private var menuStatus: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var overrideItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    static func main() {
        let app = NSApplication.shared
        let delegate = IkkunaApp()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid duplicate event taps if the executable is launched directly twice.
        let ownBundle = Bundle.main.bundleIdentifier ?? "fi.iiro.Ikkuna"
        if NSRunningApplication.runningApplications(withBundleIdentifier: ownBundle).contains(where: {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }) { NSApp.terminate(nil); return }
        do { configuration = try Configuration.load() }
        catch { showError("Asetusten lukeminen epäonnistui", error.localizedDescription) }
        engine = WindowEngine(configuration: configuration)
        switcher = AppSwitcher(engine: engine, overlay: overlay, configuration: configuration)
        hotkeys = Hotkeys(engine: engine, switcher: switcher, overlay: overlay, configuration: configuration)
        stagePicker = StagePicker(engine: engine, overlay: overlay)
        hotkeys.onStagePicker = { [weak self] in
            self?.hotkeys.cancelTransientActions()
            self?.stagePicker.show()
        }
        hotkeys.stagePickerOpen = { [weak self] in self?.stagePicker.isOpen ?? false }
        hotkeys.closeStagePicker = { [weak self] in self?.stagePicker.close() }
        engine.notice = { [weak self] in self?.overlay.message($0) }
        hotkeys.onReload = { [weak self] in self?.reloadConfiguration() }
        hotkeys.onStateChange = { [weak self] in self?.updateMenu() }
        buildMenu()
        checkHealth()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkHealth() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        if !AXIsProcessTrusted() { requestPermission() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        stagePicker?.stop()
        healthTimer?.invalidate(); hotkeys?.stop()
        // Restore any temporary Enhanced UI changes before exiting.
        engine?.queue.sync {}
    }
    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Ikkuna")
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector?) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; menu.addItem(item); return item
        }
        menuStatus = add("Ikkuna", nil)
        menu.addItem(.separator())
        pauseItem = add("Keskeytä pikanäppäimet", #selector(togglePause))
        overrideItem = add("Pakota paikalliset pikanäppäimet", #selector(toggleOverride))
        menu.addItem(.separator())
        _ = add("Avaa asetukset…", #selector(openConfiguration))
        _ = add("Lataa asetukset uudelleen", #selector(reloadConfiguration))
        loginItem = add("Käynnistä kirjautuessa", #selector(toggleLogin))
        _ = add("Myönnä käyttöapuoikeus…", #selector(requestPermission))
        _ = add("Avaa näppäimistön tarkkailuoikeudet…", #selector(openInputMonitoring))
        _ = add("Pikanäppäimet ja ohjeet", #selector(showHelp))
        _ = add("Diagnostiikkaloki…", #selector(showDiagnostics))
        menu.addItem(.separator())
        _ = add("Lopeta Ikkuna", #selector(quit))
        statusItem.menu = menu
        updateMenu()
    }
    private var hammerspoonRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "org.hammerspoon.Hammerspoon").isEmpty
    }
    private func checkHealth() {
        guard hotkeys != nil else { return }
        let other = hammerspoonRunning
        if other {
            if hotkeys.running { hotkeys.stop() }
            if !lastHammerspoon { overlay.message("Sulje Hammerspoon. Ikkuna käynnistää pikanäppäimet sen jälkeen.") }
        } else if AXIsProcessTrusted() && !hotkeys.running {
            tapFailed = !hotkeys.start()
        } else if !AXIsProcessTrusted() && hotkeys.running { hotkeys.stop() }
        lastHammerspoon = other
        updateMenu()
    }
    private func updateMenu() {
        guard menuStatus != nil, hotkeys != nil else { return }
        if hammerspoonRunning { menuStatus.title = "Odottaa Hammerspoonin sulkemista" }
        else if !AXIsProcessTrusted() { menuStatus.title = "Käyttöapuoikeus puuttuu" }
        else if tapFailed { menuStatus.title = "Näppäinkuuntelu ei käynnistynyt — tarkista oikeudet" }
        else { menuStatus.title = hotkeys.paused ? "Pikanäppäimet keskeytetty" : "Ikkuna käytössä" }
        pauseItem.state = hotkeys.paused ? .on : .off
        overrideItem.state = hotkeys.forceLocal ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        statusItem.button?.appearsDisabled = !hotkeys.running || hotkeys.paused
    }
    @objc private func togglePause() { hotkeys.setPaused(!hotkeys.paused) }
    @objc private func toggleOverride() { hotkeys.toggleOverride() }
    @objc private func openConfiguration() { NSWorkspace.shared.open(Configuration.url) }
    @objc private func reloadConfiguration() {
        do {
            let updated = try Configuration.load()
            configuration = updated
            engine.configure(updated); switcher.configure(updated); hotkeys.configure(updated)
            overlay.message("Asetukset ladattu")
        } catch { showError("Asetuksia ei otettu käyttöön", error.localizedDescription) }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { showError("Kirjautumiskäynnistystä ei voitu muuttaa", error.localizedDescription) }
        updateMenu()
    }
    @objc private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    @objc private func openInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }
    @objc private func willSleep() { hotkeys.cancelTransientActions() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showDiagnostics() { Diagnostics.shared.show() }
    @objc private func showHelp() {
        let text = """
        ⌃⌥ + ← / →: puolikkaat · U/I/J/K: neljännekset
        ⌃⌥ + C: keskitys 75 % · Return: suurenna · Delete: palauta
        ⌃⌥ + 0: älykäs jako · +/−: suurenna/pienennä (pidä pohjassa)
        ⇧⌃⌘ + +/−: kasvata/pienennä ikkunan korkeutta
        ⇧⌃⌥ + +/−: sama korkeuden säätö
        ⌃⌥⇧ + ←/→ tai U/I/J/K: täytä naapuriin asti
        ⌥ + H/J/K/L: vaihda ikkunaa suunnan mukaan
        ⌃⌥⌘ + ←/→: siirrä toiselle näytölle
        Hyper + Tab: seuraava näyttö · M: hiiri ikkunaan
        Hyper + J: hae ja lisää ikkuna nykyiseen Stage Manager -ryhmään
        Hyper + S: paikallisten näppäinten pakotus · R: lataa asetukset

        Oikea ⌘ + kirjain/numero: vaihda sovellusta
        Oikea ⌘ + oikea ⌥ + kirjain: vaihda saman sovelluksen ikkunaa
        Oikea ⌘ + oikea ⌥ + Tab: selaa saman sovelluksen ikkunat

        Hyper = ⌃⌥⇧⌘. Asetukset: ~/Library/Application Support/Ikkuna/config.json
        """
        showError("Ikkuna · pikanäppäimet", text, warning: false)
    }
    private func showError(_ title: String, _ message: String, warning: Bool = true) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.alertStyle = warning ? .warning : .informational
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
}
