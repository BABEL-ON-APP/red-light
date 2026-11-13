import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Model

struct Preset: Codable, Equatable {
    var name: String
    var red: Double   // 0...1 ceiling of each colour channel
    var green: Double
    var blue: Double
}

let defaultPresets: [Preset] = [
    Preset(name: "Red", red: 1.0, green: 0.0, blue: 0.0),
    Preset(name: "Dim Red", red: 0.45, green: 0.0, blue: 0.0),
    Preset(name: "Amber", red: 1.0, green: 0.4, blue: 0.0),
]

final class Store {
    private let d = UserDefaults.standard
    var presets: [Preset] {
        get {
            guard let data = d.data(forKey: "presets"),
                  let p = try? JSONDecoder().decode([Preset].self, from: data), !p.isEmpty else { return defaultPresets }
            return p
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "presets") }
    }
    var current: Preset {
        get {
            guard let data = d.data(forKey: "current"),
                  let p = try? JSONDecoder().decode(Preset.self, from: data) else { return defaultPresets[0] }
            return p
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "current") }
    }
}

// MARK: - Display gamma

enum Gamma {
    static func displays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids
    }
    static func apply(_ p: Preset) {
        for id in displays() {
            CGSetDisplayTransferByFormula(id,
                0, CGGammaValue(p.red), 1,
                0, CGGammaValue(p.green), 1,
                0, CGGammaValue(p.blue), 1)
        }
    }
    static func restore() { CGDisplayRestoreColorSyncSettings() }
}

// MARK: - Global hotkey (Control-Option-Command-R)

var hotKeyAction: (() -> Void)?

func registerHotKey() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        DispatchQueue.main.async { hotKeyAction?() }
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x52444C54), id: 1) // 'RDLT'
    RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey | cmdKey), id,
                        GetApplicationEventTarget(), 0, &ref)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = Store()
    var statusItem: NSStatusItem!
    var isOn = false { didSet { refresh() } }
    var timer: Timer?
    var sliders: [NSSlider] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.target = self
            b.action = #selector(clicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.toolTip = "Red Light — click to toggle, right-click for settings (⌃⌥⌘R)"
        }
        hotKeyAction = { [weak self] in self?.toggle() }
        registerHotKey()

        // The system resets gamma on wake and display changes; re-apply.
        let wc = NSWorkspace.shared.notificationCenter
        wc.addObserver(self, selector: #selector(reapply), name: NSWorkspace.didWakeNotification, object: nil)
        wc.addObserver(self, selector: #selector(reapply), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reapply),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refresh()
    }

    func applicationWillTerminate(_ n: Notification) { Gamma.restore() }

    @objc func clicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true || e?.modifierFlags.contains(.option) == true {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggle()
        }
    }

    @objc func toggle() { isOn.toggle() }

    @objc func reapply() {
        guard isOn else { return }
        // Apply now and again shortly after, since wake/reconfig can reset late.
        Gamma.apply(store.current)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if self?.isOn == true { Gamma.apply(self!.store.current) }
        }
    }

    func refresh() {
        timer?.invalidate(); timer = nil
        if isOn {
            Gamma.apply(store.current)
            // Light watchdog: other apps or the system can overwrite the table.
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                guard let self, self.isOn else { return }
                Gamma.apply(self.store.current)
            }
        } else {
            Gamma.restore()
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let name = isOn ? "lightbulb.fill" : "lightbulb"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Red Light")?
            .withSymbolConfiguration(cfg)
        statusItem.button?.contentTintColor = isOn ? .systemRed : nil
    }

    // MARK: Menu

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        let t = NSMenuItem(title: isOn ? "Turn Off" : "Turn On", action: #selector(toggle), keyEquivalent: "r")
        t.keyEquivalentModifierMask = [.control, .option, .command]
        t.target = self
        m.addItem(t)
        m.addItem(.separator())

        m.addItem(NSMenuItem.sectionHeader(title: "Presets"))
        let cur = store.current
        for (i, p) in store.presets.enumerated() {
            let it = NSMenuItem(title: p.name, action: #selector(choosePreset(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            it.target = self
            it.tag = i
            it.state = (p.red == cur.red && p.green == cur.green && p.blue == cur.blue) ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())

        m.addItem(NSMenuItem.sectionHeader(title: "Tune"))
        sliders = []
        for (label, value) in [("Red", cur.red), ("Green", cur.green), ("Blue", cur.blue)] {
            m.addItem(sliderItem(label: label, value: value))
        }
        m.addItem(.separator())

        let save = NSMenuItem(title: "Save Current as Preset…", action: #selector(savePreset), keyEquivalent: "")
        save.target = self
        m.addItem(save)

        let del = NSMenuItem(title: "Delete Preset", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, p) in store.presets.enumerated() {
            let it = NSMenuItem(title: p.name, action: #selector(deletePreset(_:)), keyEquivalent: "")
            it.target = self; it.tag = i
            sub.addItem(it)
        }
        sub.addItem(.separator())
        let reset = NSMenuItem(title: "Restore Default Presets", action: #selector(resetPresets), keyEquivalent: "")
        reset.target = self
        sub.addItem(reset)
        del.submenu = sub
        m.addItem(del)
        m.addItem(.separator())

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)

        let q = NSMenuItem(title: "Quit Red Light", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        m.addItem(q)
        return m
    }

    func sliderItem(label: String, value: Double) -> NSMenuItem {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        let l = NSTextField(labelWithString: label)
        l.frame = NSRect(x: 20, y: 4, width: 50, height: 18)
        l.font = .menuFont(ofSize: 13)
        let s = NSSlider(value: value, minValue: 0, maxValue: 1, target: self, action: #selector(sliderMoved(_:)))
        s.frame = NSRect(x: 72, y: 3, width: 152, height: 20)
        s.isContinuous = true
        v.addSubview(l); v.addSubview(s)
        sliders.append(s)
        let it = NSMenuItem()
        it.view = v
        return it
    }

    @objc func sliderMoved(_ s: NSSlider) {
        guard sliders.count == 3 else { return }
        var c = store.current
        c.red = sliders[0].doubleValue
        c.green = sliders[1].doubleValue
        c.blue = sliders[2].doubleValue
        store.current = c
        if isOn { Gamma.apply(c) } else { isOn = true }
    }

    @objc func choosePreset(_ it: NSMenuItem) {
        store.current = store.presets[it.tag]
        if isOn { refresh() } else { isOn = true }
    }

    @objc func savePreset() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Save Preset"
        a.informativeText = "Name for the current red/green/blue setting:"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        f.placeholderString = "My preset"
        a.accessoryView = f
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = f.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var p = store.current; p.name = name
        var all = store.presets
        if let i = all.firstIndex(where: { $0.name == name }) { all[i] = p } else { all.append(p) }
        store.presets = all
        store.current = p
    }

    @objc func deletePreset(_ it: NSMenuItem) {
        var all = store.presets
        guard all.count > 1 else { return }
        all.remove(at: it.tag)
        store.presets = all
    }

    @objc func resetPresets() { store.presets = defaultPresets }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert(error: error); a.runModal()
        }
    }

    @objc func quit() { Gamma.restore(); NSApp.terminate(nil) }
}

// Restore the screen if the process gets a terminate signal.
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig) { _ in CGDisplayRestoreColorSyncSettings(); exit(0) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
