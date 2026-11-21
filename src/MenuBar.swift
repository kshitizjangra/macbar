import Cocoa
import ServiceManagement
import IOKit.pwr_mgt

// MARK: helpers

@discardableResult
func sh(_ cmd: String, _ env: [String: String] = [:]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", cmd]
    var e = ProcessInfo.processInfo.environment
    e["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.hermes/node/bin"
    for (k, v) in env { e[k] = v }
    p.environment = e
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return "" }
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: d, as: UTF8.self)
}

final class Act: NSObject {
    let f: () -> Void
    init(_ f: @escaping () -> Void) { self.f = f }
    @objc func go() { f() }
}

struct Mem { var used = 0.0, total = 0.0, swapUsed = 0.0, swapTotal = 0.0, diskFree = 0.0 }
struct Grp { let name: String; var mb: Double; var pids: [Int32] }

func readMem() -> Mem {
    var m = Mem()
    let gib = 1073741824.0
    m.total = Double(ProcessInfo.processInfo.physicalMemory) / gib

    let vm = sh("vm_stat")
    var page = 16384.0
    if let r = vm.range(of: "page size of "), let n = Double(String(vm[r.upperBound...].prefix { $0.isNumber })) { page = n }
    func pages(_ key: String) -> Double {
        for l in vm.split(separator: "\n") where l.hasPrefix(key) {
            return Double(String((l.split(separator: ":").last ?? "").filter { $0.isNumber })) ?? 0
        }
        return 0
    }
    m.used = (pages("Pages active") + pages("Pages wired down") + pages("Pages occupied by compressor")) * page / gib

    let toks = sh("sysctl -n vm.swapusage").split(whereSeparator: { " =".contains($0) })
    func sw(_ k: String) -> Double {
        guard let i = toks.firstIndex(of: Substring(k)), i + 1 < toks.count else { return 0 }
        return (Double(toks[i + 1].dropLast()) ?? 0) / 1024
    }
    m.swapTotal = sw("total")
    m.swapUsed = sw("used")

    let df = sh("df -k /System/Volumes/Data | tail -1").split(separator: " ", omittingEmptySubsequences: true)
    if df.count > 3 { m.diskFree = (Double(df[3]) ?? 0) / 1048576 }
    return m
}

func topGroups() -> [Grp] {
    let skip: Set<String> = ["WindowServer", "loginwindow", "Finder", "Dock", "SystemUIServer", "launchd", "kernel_task", "MacBar", "ps", "bash"]
    var g: [String: Grp] = [:]
    for line in sh("ps -U $(id -un) -o pid=,rss=,command=").split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, let pid = Int32(parts[0]), let rss = Double(parts[1]) else { continue }
        let cmd = String(parts[2])
        var name: String
        if let r = cmd.range(of: ".app/") {
            name = String(cmd[..<r.lowerBound]).components(separatedBy: "/").last ?? cmd
        } else {
            name = (cmd.split(separator: " ").first.map(String.init) ?? cmd).components(separatedBy: "/").last ?? cmd
        }
        if skip.contains(name) { continue }
        var e = g[name] ?? Grp(name: name, mb: 0, pids: [])
        e.mb += rss / 1024
        e.pids.append(pid)
        g[name] = e
    }
    return g.values.sorted { $0.mb > $1.mb }
}

func fmt(_ x: Double) -> String { String(format: "%.1f", x) }
func fmtMB(_ mb: Double) -> String { mb >= 1024 ? fmt(mb / 1024) + " GB" : String(Int(mb)) + " MB" }

// MARK: app

final class App: NSObject, NSApplicationDelegate {
    let bar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let script = Bundle.main.path(forResource: "mcpclean", ofType: nil) ?? NSHomeDirectory() + "/.local/bin/mcpclean"
    let choices: [(String, Double)] = [("All running sessions", 0), ("Older than 1 hour", 1), ("Older than 3 hours", 3),
                                       ("Older than 6 hours", 6), ("Older than 12 hours", 12), ("Older than 24 hours", 24)]
    var hours: Double = {
        let d = UserDefaults.standard
        return d.object(forKey: "hours") == nil ? 12 : d.double(forKey: "hours")
    }()
    var filterName: String { choices.first { $0.1 == hours }?.0 ?? "Older than \(Int(hours)) hours" }

    var mem = Mem()
    var groups: [Grp] = []
    var rows: [String] = []
    var summary = ""
    var cacheMB = 0.0
    var tickN = 0
    var acts: [Act] = []

    // keep awake
    var sysID: IOPMAssertionID = 0
    var dispID: IOPMAssertionID = 0
    var awakeOn = false
    var awakeUntil: Date? = nil
    var awakeTimer: Timer?
    var lidOn = false
    var keepScreen: Bool = {
        let d = UserDefaults.standard
        return d.object(forKey: "keepScreen") == nil ? true : d.bool(forKey: "keepScreen")
    }()
    let durations: [(String, Double?)] = [("Indefinitely", nil), ("15 minutes", 900), ("30 minutes", 1800), ("1 hour", 3600),
                                          ("2 hours", 7200), ("4 hours", 14400), ("8 hours", 28800)]

    var loginOn: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    func setLogin(_ on: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                _ = confirm("Could not change launch at login", error.localizedDescription, "OK")
            }
        }
        render()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        // First run: turn launch-at-login on once. Menu toggle turns it off.
        let d = UserDefaults.standard
        if !d.bool(forKey: "loginInit") {
            d.set(true, forKey: "loginInit")
            if #available(macOS 13.0, *) { try? SMAppService.mainApp.register() }
        }
        bar.button?.title = "🧹"
        tick()
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
    }

    // MARK: refresh

    func tick(forceSessions: Bool = false) {
        let h = hours
        let doSessions = forceSessions || tickN % 4 == 0
        tickN += 1
        DispatchQueue.global().async {
            let m = readMem()
            let g = topGroups()
            let lid = sh("pmset -g | grep -i SleepDisabled").contains("1")
            var newRows: [String]? = nil
            var sum = ""
            var cache: Double? = nil
            if doSessions {
                let out = sh("bash '\(self.script)'", ["MAX_AGE_H": String(h)])
                newRows = out.split(separator: "\n").map(String.init).filter { $0.first?.isNumber ?? false }
                sum = out.split(separator: "\n").first { $0.hasPrefix("-- ") }.map(String.init) ?? ""
                let kb = sh("du -sk ~/Library/Developer/Xcode/DerivedData ~/.npm/_cacache \"$(brew --cache 2>/dev/null)\" 2>/dev/null | awk '{s+=$1} END{print s+0}'")
                cache = (Double(kb.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) / 1024
            }
            DispatchQueue.main.async {
                self.mem = m
                self.groups = g
                self.lidOn = lid
                if self.awakeOn, let u = self.awakeUntil, Date() >= u { self.stopAwake(revertLid: false) }
                if let r = newRows { self.rows = r; self.summary = sum }
                if let c = cache { self.cacheMB = c }
                self.render()
            }
        }
    }

    // MARK: menu

    func item(_ title: String, _ f: @escaping () -> Void) -> NSMenuItem {
        let a = Act(f)
        acts.append(a)
        let i = NSMenuItem(title: title, action: #selector(Act.go), keyEquivalent: "")
        i.target = a
        return i
    }

    func label(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    func header(_ title: String) -> NSMenuItem {
        let i = NSMenuItem()
        i.attributedString(title)
        return i
    }

    func render() {
        acts.removeAll()
        let pct = mem.total > 0 ? Int(mem.used / mem.total * 100) : 0
        var t = "🧹 \(pct)%"
        if !rows.isEmpty { t += " · \(rows.count)" }
        if awakeOn || lidOn { t += lidOn ? " ☕⚠" : " ☕" }
        bar.button?.title = t

        let m = NSMenu()

        // Memory
        m.addItem(header("MEMORY"))
        m.addItem(label("RAM   \(fmt(mem.used)) / \(fmt(mem.total)) GB  (\(pct)%)"))
        let swapBad = mem.swapTotal > 0 && mem.swapUsed / mem.swapTotal > 0.6
        m.addItem(label("Swap  \(fmt(mem.swapUsed)) / \(fmt(mem.swapTotal)) GB" + (swapBad ? "   ⚠ high" : "")))
        m.addItem(label("Disk free  \(fmt(mem.diskFree)) GB" + (mem.diskFree < 30 ? "   ⚠ low" : "")))
        m.addItem(.separator())
        m.addItem(label("Top memory (click to quit)"))
        for g in groups.prefix(6) {
            let sub = NSMenu()
            sub.addItem(item("Quit \(g.name) (\(g.pids.count) proc)") { [weak self] in self?.quitGroup(g, force: false) })
            sub.addItem(item("Force quit") { [weak self] in self?.quitGroup(g, force: true) })
            let i = NSMenuItem(title: "\(g.name) — \(fmtMB(g.mb))", action: nil, keyEquivalent: "")
            i.submenu = sub
            m.addItem(i)
        }
        m.addItem(.separator())
        m.addItem(item("Purge inactive memory (asks password)") { [weak self] in self?.purge() })

        // Keep awake
        m.addItem(.separator())
        m.addItem(header("KEEP AWAKE"))
        m.addItem(label(awakeStatus()))
        let lo = NSMenu()
        for (name, secs) in durations {
            lo.addItem(item(name) { [weak self] in self?.startAwake(name, secs, lid: false) })
        }
        let loi = NSMenuItem(title: "Keep awake (lid open)", action: nil, keyEquivalent: "")
        loi.submenu = lo
        m.addItem(loi)
        let lc = NSMenu()
        for (name, secs) in durations {
            lc.addItem(item(name) { [weak self] in self?.startAwake(name, secs, lid: true) })
        }
        let lci = NSMenuItem(title: "Keep awake, lid closed (asks password)", action: nil, keyEquivalent: "")
        lci.submenu = lc
        m.addItem(lci)
        let ks = item("Keep screen on") { [weak self] in self?.setKeepScreen(!(self?.keepScreen ?? true)) }
        ks.state = keepScreen ? .on : .off
        m.addItem(ks)
        if awakeOn || lidOn { m.addItem(item("Turn off keep awake") { [weak self] in self?.stopAwake() }) }

        // Sessions
        m.addItem(.separator())
        m.addItem(header("CLAUDE SESSIONS & MCP"))
        if rows.isEmpty {
            m.addItem(label("Nothing matches (\(filterName.lowercased()))"))
        } else {
            m.addItem(label(summary.replacingOccurrences(of: "-- ", with: "Stale: ")))
            for r in rows.prefix(12) {
                let cols = r.split(separator: " ", omittingEmptySubsequences: true)
                let line = cols.prefix(4).joined(separator: "  ") + "  " + String(cols.dropFirst(4).joined(separator: " ").prefix(46))
                m.addItem(label("   " + line))
            }
            if rows.count > 12 { m.addItem(label("   …and \(rows.count - 12) more")) }
        }
        let fm = NSMenu()
        for (name, h) in choices {
            let i = item(name) { [weak self] in
                self?.hours = h
                UserDefaults.standard.set(h, forKey: "hours")
                self?.tick(forceSessions: true)
            }
            i.state = (h == hours) ? .on : .off
            fm.addItem(i)
        }
        let fi = NSMenuItem(title: "Session filter: \(filterName)", action: nil, keyEquivalent: "")
        fi.submenu = fm
        m.addItem(fi)
        m.addItem(item("Clean now") { [weak self] in self?.cleanSessions(dev: false) })
        m.addItem(item("Clean now + dev servers") { [weak self] in self?.cleanSessions(dev: true) })

        // Disk
        if cacheMB > 50 {
            m.addItem(.separator())
            m.addItem(header("DISK"))
            m.addItem(item("Clean dev caches (\(fmtMB(cacheMB)))…") { [weak self] in self?.cleanCaches() })
        }

        m.addItem(.separator())
        let li = item("Launch at login") { [weak self] in self?.setLogin(!(self?.loginOn ?? false)) }
        li.state = loginOn ? .on : .off
        m.addItem(li)
        m.addItem(item("Refresh") { [weak self] in self?.tick(forceSessions: true) })
        m.addItem(item("Quit MacBar") { [weak self] in self?.quitApp() })
        bar.menu = m
    }

    // MARK: keep awake

    func awakeStatus() -> String {
        guard awakeOn || lidOn else { return "Keep awake: off" }
        var s = "Keep awake: on"
        if let u = awakeUntil {
            let r = max(0, Int(u.timeIntervalSinceNow))
            s += " · \(r / 3600)h \(r % 3600 / 60)m left"
        } else if awakeOn {
            s += " · until turned off"
        }
        if lidOn { s += " · lid closed OK" }
        return s
    }

    @discardableResult
    func admin(_ cmd: String) -> Bool {
        let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(esc)\" with administrator privileges")?.executeAndReturnError(&err)
        return err == nil
    }

    func createAssertions() {
        IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "MacBar keep awake" as CFString, &sysID)
        if keepScreen {
            IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "MacBar keep screen on" as CFString, &dispID)
        }
    }

    func releaseAssertions() {
        if sysID != 0 { IOPMAssertionRelease(sysID); sysID = 0 }
        if dispID != 0 { IOPMAssertionRelease(dispID); dispID = 0 }
    }

    func setKeepScreen(_ on: Bool) {
        keepScreen = on
        UserDefaults.standard.set(on, forKey: "keepScreen")
        if awakeOn { releaseAssertions(); createAssertions() }
        render()
    }

    func startAwake(_ name: String, _ secs: Double?, lid: Bool) {
        if lid {
            let warn = secs == nil
                ? "It stays on until you turn it off."
                : "It switches itself off after \(name.lowercased())."
            guard confirm("Keep awake with the lid closed?",
                          warn + " Do not put the Mac in a bag while it is on: it can overheat and drain the battery.\n\nNeeds your admin password.",
                          "Enable") else { return }
            let token = UUID().uuidString
            var cmd = "pmset -a disablesleep 1; echo \(token) > /private/tmp/macbar-lid"
            if let s = secs {
                cmd += "; nohup sh -c 'sleep \(Int(s)); if [ \"$(cat /private/tmp/macbar-lid 2>/dev/null)\" = \"\(token)\" ]; then pmset -a disablesleep 0; rm -f /private/tmp/macbar-lid; fi' >/dev/null 2>&1 &"
            }
            guard admin(cmd) else { return }
        }
        releaseAssertions()
        createAssertions()
        awakeOn = true
        awakeUntil = secs.map { Date().addingTimeInterval($0) }
        awakeTimer?.invalidate()
        if let s = secs {
            awakeTimer = Timer.scheduledTimer(withTimeInterval: s, repeats: false) { [weak self] _ in self?.stopAwake(revertLid: false) }
        }
        tick()
    }

    func stopAwake(revertLid: Bool = true) {
        awakeTimer?.invalidate()
        awakeTimer = nil
        releaseAssertions()
        awakeOn = false
        awakeUntil = nil
        if revertLid && lidOn { admin("pmset -a disablesleep 0; rm -f /private/tmp/macbar-lid") }
        tick()
    }

    func quitApp() {
        guard lidOn else { NSApp.terminate(nil); return }
        let a = NSAlert()
        a.messageText = "Lid-closed mode is still on"
        a.informativeText = "Turn it off before quitting? (needs your admin password)"
        a.addButton(withTitle: "Turn off & quit")
        a.addButton(withTitle: "Quit, leave on")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn:
            if admin("pmset -a disablesleep 0; rm -f /private/tmp/macbar-lid") { NSApp.terminate(nil) }
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
    }

    // MARK: actions

    func confirm(_ title: String, _ info: String, _ ok: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    func quitGroup(_ g: Grp, force: Bool) {
        guard confirm("\(force ? "Force quit" : "Quit") \(g.name)?",
                      "\(g.pids.count) process(es), \(fmtMB(g.mb)). Unsaved work in it will be lost.", "Quit") else { return }
        for pid in g.pids {
            if !force, let a = NSRunningApplication(processIdentifier: pid), a.activationPolicy == .regular {
                a.terminate()
            } else {
                kill(pid, force ? SIGKILL : SIGTERM)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.tick(forceSessions: true) }
    }

    func purge() {
        bar.button?.title = "🧹 …"
        DispatchQueue.global().async {
            sh("osascript -e 'do shell script \"purge\" with administrator privileges'")
            DispatchQueue.main.async { self.tick() }
        }
    }

    func cleanSessions(dev: Bool) {
        if hours == 0 && !confirm("Stop ALL running Claude sessions?",
                                  "Includes any session you are using right now, plus their MCP servers.", "Stop all") { return }
        bar.button?.title = "🧹 …"
        let h = hours
        DispatchQueue.global().async {
            sh("bash '\(self.script)' --kill" + (dev ? " --dev" : ""), ["MAX_AGE_H": String(h)])
            DispatchQueue.main.async { self.tick(forceSessions: true) }
        }
    }

    func cleanCaches() {
        guard confirm("Clean dev caches?",
                      "Removes Xcode DerivedData, the npm cache and old Homebrew downloads (~\(fmtMB(cacheMB))). They rebuild on demand.", "Clean") else { return }
        bar.button?.title = "🧹 …"
        DispatchQueue.global().async {
            sh("rm -rf ~/Library/Developer/Xcode/DerivedData/* 2>/dev/null; npm cache clean --force 2>/dev/null; brew cleanup -s --prune=all 2>/dev/null")
            DispatchQueue.main.async { self.tick(forceSessions: true) }
        }
    }
}

extension NSMenuItem {
    func attributedString(_ s: String) {
        attributedTitle = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        isEnabled = false
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
