import AppKit
import Carbon.HIToolbox
import GzymsCore
import GzymsUI
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = BarModel()
    /// Sparkle updates. Off outside the bundle (`swift run`), where it would fail on a missing SUFeedURL.
    private let updater = SPUStandardUpdaterController(startingUpdater: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
                                                       updaterDelegate: nil, userDriverDelegate: nil)
    private var panels: [UInt32: BarPanel] = [:]
    private var screens: ScreenManager?
    private var state: StateWatcher?
    private let anomalies = AnomalyLog(dir: Paths.logsDir(home: FileManager.default.homeDirectoryForCurrentUser))
    private lazy var watchdog = MainThreadWatchdog(anomalies: anomalies)
    private var storm = RebuildStorm(limit: 3, window: 10)
    private var lifecycle = PanelLifecycle(grace: 10)
    private var appExit: NSObjectProtocol?
    private var rebuilds = 0
    private var stateEvents = RateCounter(window: 5)
    private var vitals: VitalsWriter?
    private var reload: DispatchSourceSignal?
    private var cpuTimer: Timer?
    private var cpuTicks: CPUTicks?
    private var cpuHeld = HeldSeries()
    private var netSampler = NetSampler()
    private var netDown = HeldSeries(), netUp = HeldSeries()
    private var batteryWatch = BatteryWatch()
    private let micMute = MicMute()
    private let micMeter = MicMeter()
    private var ticks = 0
    private var topTimer: Timer?
    private var topOpen = 0  // popups open across screens
    private var topLast: (cpu: [Int32: Double], at: TimeInterval)?
    private var notes = NotificationStore()
    private var notesTimer: Timer?
    private var sounds: [String: NSSound] = [:]
    private var notifyObserver: NSObjectProtocol?
    private let island = IslandPanel()
    private let armageddon = ArmageddonController()
    private let chords = ChordTap()
    private var keysObserver: NSObjectProtocol?
    private var nc: NotificationCenterSource?
    private var signal: DeliverySignal?
    private var dock: DockBadges?
    private var flying = 0  // the counts wait for the icon to land, then bump
    private var configWatcher: ConfigWatcher?
    private var motionObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var tilerTimer: Timer?
    private var grantTimer: Timer?
    private var calendar: CalendarSource?
    private var meetings: [Meeting] = []
    private var meetingClock = MeetingClock()
    private lazy var music = MusicSource { [weak self] line in self?.musicChanged(line) }
    private let pluginHost = PluginHost(dir: Paths.configDir(env: ProcessInfo.processInfo.environment).appendingPathComponent("plugins"))
    private var pluginsStarted = false
    private let caffeine = CaffeineController()
    private let dropZone = ShelfDropZone()
    private var meetingTimer: Timer?
    private var meetingShown: String?  // the meeting id whose reminder is posted
    private var calendarMeetings: [Meeting] = []
    private var testMeetings: [Meeting] = []  // from `gzyms meeting-test`
    private var meetingTestObserver: NSObjectProtocol?
    private let meetingPreview = MeetingPreview()
    /// The banner asked for a second action it does not have; its hint row says so for a moment.
    private var noAltBanner: String?
    private lazy var wizard = PermissionsWizard(model: model) { [weak self] g in self?.openGrant(g) }
    private var appsObservers: [NSObjectProtocol] = []
    private lazy var settings = SettingsPanel(model: model, actions: settingsActions())
    private let seenAppsFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Gzyms/seen-apps.json")
    private lazy var messages = GzymsMessagePanel(model: model)
    private var messageObserver: NSObjectProtocol?
    private let messagesFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Gzyms/messages.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        watchdog.start()
        // After sleep macOS thaws Gzyms, fires every due timer and often moves the screens: a short stall is expected.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [watchdog] _ in
            watchdog.settling("wake")
        }
        let ws = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.screensDidSleepNotification, true),
                               (NSWorkspace.didWakeNotification, false), (NSWorkspace.screensDidWakeNotification, false)] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [watchdog] _ in watchdog.asleep(asleep) }
        }
        loadConfig()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let watcher = StateWatcher(url: home.appendingPathComponent("Library/Application Support/HyprMac/state.json")) { [weak self] read in
            self?.stateEvents.hit(at: ProcessInfo.processInfo.systemUptime)
            self?.model.apply(read)
            self?.tilerCheck()
            self?.pushTargets()  // focus may have moved to another screen
        }
        let writer = VitalsWriter { [unowned self] in
            Vitals(pid: ProcessInfo.processInfo.processIdentifier, at: Date(), lagMs: watchdog.lagMs, panels: panels.count,
                   rebuilds: rebuilds, eventsPerSec: stateEvents.perSecond(at: ProcessInfo.processInfo.systemUptime))
        }
        vitals = writer
        writer.start()
        state = watcher
        watcher.start()
        appExit = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? ""
            MainActor.assumeIsolated { self?.appTerminated(bundleID) }
        }
        let manager = ScreenManager { [weak self] plan, screensByID in self?.apply(plan, screensByID) }
        screens = manager
        manager.start()
        tilerCheck()  // no state.json at all: the watcher may never call
        startCPU()
        startNotifications()

        // `gzyms theme` writes the config and sends SIGHUP: reload it in place.
        Darwin.signal(SIGHUP, SIG_IGN)
        let hup = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
        hup.setEventHandler { MainActor.assumeIsolated { [weak self] in self?.loadConfig(); log("config reloaded (SIGHUP)") } }
        hup.resume()
        reload = hup
        let cw = ConfigWatcher(file: ThemeCommand.configFile) { [weak self] in self?.loadConfig() }
        cw.start()
        configWatcher = cw
        startSettings()
        if model.config.calendarEnabled { startCalendar() }
        model.onGrantWarning = { [weak self] in self?.wizard.show(on: self?.focusedScreen()); self?.checkGrants() }
        model.onSettingsTab = { [weak self] in if self?.model.settingsTab == .permissions { self?.checkGrants() } }
        checkGrants()
        if model.grants.contains(where: { $0.grant.required && !$0.granted }) { wizard.show(on: focusedScreen()) }
        startMessages()
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { [weak self] in self?.applyMotion() } }
    }

    /// Top processes cost a read of every process, so they are sampled only while a CPU popup is open.
    private func cpuPopup(_ open: Bool) {
        topOpen = max(0, topOpen + (open ? 1 : -1))
        if topOpen > 0, topTimer == nil {
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sampleTop() } }
            RunLoop.main.add(t, forMode: .common)
            topTimer = t
            sampleTop()
        } else if topOpen == 0 {
            topTimer?.invalidate(); topTimer = nil
            topLast = nil
            model.topProcesses = []
        }
    }

    /// `ps` takes tens of ms, so it runs off the main thread (the watchdog would see it as lag).
    private func sampleTop() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snap = TopProcesses.snapshot()
            let now = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyTop(snap, at: now) } }
        }
    }

    private func applyTop(_ snap: [Int32: (cpu: Double, name: String)], at now: TimeInterval) {
        guard topTimer != nil else { return }  // the popup closed while ps ran
        let cpu = snap.mapValues(\.cpu)
        if let last = topLast {
            model.topProcesses = TopProcesses.top(prev: last.cpu, now: cpu, wall: now - last.at, count: 5).map { p in
                let name = NSRunningApplication(processIdentifier: p.pid)?.localizedName ?? snap[p.pid]?.name ?? "pid \(p.pid)"
                return ProcessCPU(pid: p.pid, name: name, percent: p.percent)
            }
        }
        topLast = (cpu, now)
    }

    /// shortcut: polled with the 2 s tick, so volume keys show up to 2 s late; switch to CoreAudio listeners if that bothers.
    /// Read on `Audio.queue`: a device still switching (an iPhone mic) answers slowly, and after a pick it runs behind that write.
    private func refreshAudio() {
        Audio.queue.async {
            let read = Audio.read()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var a = read
                let icons = model.config.deviceIcons, banned = model.config.bannedDevices
                for i in a.outputs.indices {
                    a.outputs[i].kindOverride = icons[a.outputs[i].name]; a.outputs[i].banned = banned.contains(a.outputs[i].name)
                }
                for i in a.inputs.indices {
                    a.inputs[i].kindOverride = icons[a.inputs[i].name]; a.inputs[i].banned = banned.contains(a.inputs[i].name)
                }
                if a != model.audio { model.audio = a }
            }
        }
    }

    private static var shelfFile: URL { VitalsWriter.url.deletingLastPathComponent().appendingPathComponent("shelf.json") }

    private func changeShelf(_ change: ShelfChange) {
        var s = Shelf(paths: model.shelf.map(\.path))
        let why: String
        switch change {
        case .add(let urls): s.add(urls.map(\.path)); why = "\(urls.count) dropped"
        case .remove(let urls): s.remove(urls.map(\.path)); why = "\(urls.count) taken off"
        }
        let before = s.paths.count
        s.prune { FileManager.default.fileExists(atPath: $0) }
        guard s.paths != model.shelf.map(\.path) else { return }
        model.shelf = s.paths.map { URL(fileURLWithPath: $0) }
        try? JSONEncoder().encode(s.paths).write(to: Self.shelfFile, options: .atomic)
        log("shelf: \(s.paths.count) file(s), \(why)\(before > s.paths.count ? ", \(before - s.paths.count) gone from disk" : "")")
    }

    private func startCPU() {
        model.onCPUPopup = { [weak self] open in self?.cpuPopup(open) }
        model.onAudioChange = { [weak self] in self?.refreshAudio() }
        model.onMicMute = { [weak self] in self?.micMute.toggle(self?.model.audio) }
        model.onMusic = { MusicSource.send($0) }
        model.onCaffeine = { [weak self] command in
            guard let self else { return }
            if let minutes = command { caffeine.start(minutes: minutes, display: model.config.caffeineDisplay) } else { caffeine.stop() }
        }
        caffeine.onChange = { [weak self] s in self?.model.caffeine = s }
        caffeine.onEnded = { [weak self] why in
            self?.post(GzymsNotification(id: "caffeine", app: nil, level: .info, title: "Caffeine is off", subtitle: nil, body: why,
                                         link: nil, altLink: nil, sound: nil, at: Date()))
        }
        caffeine.restore()  // a caffeinate from before this restart keeps going, and the pill shows it again
        model.onShelf = { [weak self] in self?.changeShelf($0) }
        // What was on the shelf before this restart, minus files gone since.
        let saved = (try? Data(contentsOf: Self.shelfFile)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        model.shelf = saved.map { URL(fileURLWithPath: $0) }
        changeShelf(.remove([]))
        dropZone.enabled = { [weak self] in self?.model.config.hiddenWidgets.contains(.shelf) == false }
        dropZone.theme = { [weak self] in self?.model.config.theme ?? .mochaNeon }
        dropZone.animate = { [weak self] in self?.model.animate ?? false }
        dropZone.onDrop = { [weak self] in self?.changeShelf(.add($0)) }
        dropZone.start()
        micMeter.onLevel = { [weak self] in self?.model.micLevel = $0 }
        model.onMicPopup = { [weak self] open in open ? self?.micMeter.start() : self?.micMeter.stop() }
        sampleCPU()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sampleCPU() } }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)  // keeps ticking while a menu is open
        cpuTimer = t
    }

    /// A widget turned off is not sampled either (spec: a plugin that is off costs nothing).
    private func sampleCPU() {
        let hidden = model.config.hiddenWidgets
        if !hidden.contains(.memory), let m = MemorySample.read(), m != model.memory { model.memory = m }
        let uptime = ProcessInfo.processInfo.systemUptime
        if !hidden.contains(.network) {
            let n = netSampler.sample(now: uptime)
            netDown.add(n.down, at: uptime); netUp.add(n.up, at: uptime)
            model.net = n; model.netDown = netDown.values; model.netUp = netUp.values
        }
        // The mic shortcut needs the audio state even with both pills off, so audio is read anyway (one cheap call).
        refreshAudio()
        // The battery changes slowly: every 5th tick (10 s). The charger warning goes with the widget.
        if ticks % 5 == 0, !hidden.contains(.battery), let b = BatterySample.read() {
            if b != model.battery { model.battery = b }
            let floor = model.config.caffeineBatteryBelow
            if caffeine.state != nil, CaffeineState.batteryTooLow(percent: b.percent, charging: b.plugged, threshold: floor) {
                caffeine.stop(reason: "On battery under \(floor)%, the Mac may sleep again.")
            }
            let w = batteryWatch.update(b, now: uptime)
            if w != model.batteryWarning { model.batteryWarning = w; log("battery: \(w.map { "\($0)" } ?? "ok")") }
        }
        ticks += 1
        guard !hidden.contains(.cpu), let now = SystemCPU.ticks() else { cpuTicks = nil; return }
        if let prev = cpuTicks {
            let pct = SystemCPU.percent(prev: prev, now: now)
            cpuHeld.add(pct, at: ProcessInfo.processInfo.systemUptime)
            model.cpu = pct
            model.cpuSeries = cpuHeld.values
        }
        cpuTicks = now
    }

    private static var notesFile: URL { VitalsWriter.url.deletingLastPathComponent().appendingPathComponent("notifications.json") }
    private var notesSaved: Data?

    /// After every change, only when something kept on disk moved (hover and ticks leave the bytes alone).
    private func saveNotes() {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        guard let data = try? e.encode(notes.saved(now: ProcessInfo.processInfo.systemUptime, wall: Date())), data != notesSaved else { return }
        do { try data.write(to: Self.notesFile, options: .atomic); notesSaved = data } catch { log("notifications: could not save (\(error))") }
    }

    private var dndObserver: NSObjectProtocol?
    private var dndTimer: Timer?

    /// From the moon pill or `gzyms dnd`; nil turns it off.
    private func setDND(_ until: Date?) {
        notes.setDND(until, now: ProcessInfo.processInfo.systemUptime)
        log(until.map { $0 == .distantFuture ? "dnd: on until turned off" : "dnd: on until \(ISO8601DateFormatter().string(from: $0))" } ?? "dnd: off")
        armDNDTimer()
        notesChanged()
    }

    private func armDNDTimer() {
        dndTimer?.invalidate(); dndTimer = nil
        guard let until = notes.dnd, until != .distantFuture else { return }
        let t = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.setDND(nil) } }
        RunLoop.main.add(t, forMode: .common)
        dndTimer = t
    }

    private func startNotifications() {
        if let s = NotificationStore.load(Self.notesFile, log: { log($0) }) {
            notes.restore(s, now: ProcessInfo.processInfo.systemUptime, wall: Date())
            log("notifications: \(s.inbox.count) in the lists, \(s.snoozed.count) snoozed, back from before the restart"
                + (notes.dnd != nil ? ", do not disturb still on" : ""))
        }
        armDNDTimer()
        notesChanged()
        model.onDND = { [weak self] in self?.setDND($0) }
        dndObserver = DistributedNotificationCenter.default().addObserver(forName: dndName, object: nil, queue: .main) { note in
            let arg = note.object as? String
            MainActor.assumeIsolated { [weak self] in
                guard let arg, let until = dndUntil(arg, now: Date()) else { return }
                self?.setDND(until)
            }
        }
        model.onOpenNote = { [weak self] in self?.open($0) }
        model.onAltNote = { [weak self] in self?.open($0, alt: true) }
        model.onRemoveNote = { [weak self] id in
            self?.notes.remove(id, now: ProcessInfo.processInfo.systemUptime)
            self?.notesChanged()
        }
        chords.onMute = { [weak self] in self?.micMute.toggle(self?.model.audio); self?.refreshAudio() }
        chords.onNav = { [weak self] in self?.applyNav($0, $1) }
        chords.onArmageddon = { [weak self] in self?.armageddon.open() }
        model.onTestSound = { [weak self] in self?.play(.message) }
        chords.start()
        startKeys()
        let source = NotificationCenterSource { [weak self] list in
            for var n in list {
                n.app = n.app.map(AppIcons.bundleID(matching:))
                self?.post(n)
            }
        }
        source.start()
        nc = source
        let sig = DeliverySignal { [weak self] app in self?.pending(app) }
        sig.start()
        signal = sig
        let badges = DockBadges { [weak self] in self?.model.dockBadges = $0 }
        badges.start()
        dock = badges
        island.onOpen = { [weak self] in self?.openBanner(alt: false) }
        island.onRight = { [weak self] in self?.openBanner(alt: true) }
        island.onDismiss = { [weak self] in self?.dismissBanner() }
        island.onStep = { [weak self] in self?.stepBanner($0) }
        armageddon.onOpen = { [weak self] id in self?.open(id) }
        armageddon.playSound = { [weak self] in self?.play(.armageddon) }
        armageddon.onVisible = { [weak self] up in self?.chords.armageddon = up }
        armageddon.onDismiss = { [weak self] id in
            guard let self, notes.banner?.id == id else { return }  // already in its inbox otherwise
            dismissBanner()
        }
        island.onHover = { [weak self] on in
            self?.notes.hover(on, now: ProcessInfo.processInfo.systemUptime)
            self?.notesChanged()
        }
        notifyObserver = DistributedNotificationCenter.default().addObserver(forName: notifyName, object: nil, queue: .main) { note in
            let json = note.object as? String
            MainActor.assumeIsolated { [weak self] in self?.received(json) }
        }
    }

    private func received(_ json: String?) {
        guard let n = json.flatMap({ GzymsNotification(json: $0) }) else { log("notify: dropped a message that is not a notification"); return }
        // A click on a plugin's note goes back to that plugin: nobody else may post in its name.
        guard !n.id.hasPrefix("plugin:") else { log("notify: dropped \(n.id), plugin ids come from plugins only"); return }
        post(n)
    }

    /// The log says an app just sent something: its icon shows at once, the text follows from the db.
    /// A full banner on screen is left alone; the row replaces it in a few seconds anyway.
    private func pending(_ app: String) {
        if let b = notes.banner, !b.compact { return }
        post(.pending(app: AppIcons.bundleID(matching: app), at: Date()))
    }

    /// From `gzyms notify` or from another app through Notification Center.
    private func post(_ n: GzymsNotification) {
        if let app = n.app, !n.compact { remember(app) }
        let before = notes.banner?.id, wasIn = notes.contains(n.id)
        notes.post(n, now: ProcessInfo.processInfo.systemUptime)
        logNote(n, "posted")
        var loud = n
        loud.level = notes.appRules.rule(for: n).raise(n.level)
        if loud.level == .armageddon, !n.compact, !notes.quiet(loud) {
            // Its own sound, every 1.5 s until clicked; a later notification goes under it, not over.
            armageddon.show(loud, theme: model.config.theme, calm: !model.animate)
        } else if !wasIn, notes.contains(n.id), before != n.app.map({ "pending-\($0)" }) {
            // Heard when it enters the stack, on screen or waiting. An update (same id) stays quiet: progress updates would beep every time.
            // So does the text replacing its own app's icon: the icon already played the sound.
            play(n)
        }
        notesChanged()
    }

    // MARK: - Keyboard mode (leader, hints, popups by keys)

    /// The bar the mode runs on and its targets in hint order, frozen while the mode is on.
    private var navPanel: BarPanel?
    private var navOrder: [HintTarget] = []

    private func startKeys() {
        keysObserver = DistributedNotificationCenter.default().addObserver(forName: keysName, object: nil, queue: .main) { note in
            let on = note.object as? String == "on"
            MainActor.assumeIsolated { [weak self] in self?.pushTargets(); self?.chords.nav(on: on) }
        }
        // Whatever takes the user elsewhere ends the mode: it must never sit there eating keys.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { [weak self] in self?.chords.nav(on: false) } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.chords.nav(on: false) }
        }
        // Secure Input keeps every key from the tap: say so on the bar instead of a leader that silently does nothing.
        let t = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                let on = IsSecureEventInputEnabled()
                if on != self.model.secureInput { self.model.secureInput = on; log("keys: secure input \(on ? "on" : "off")") }
            }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
    }

    /// The bar with an open popup, else the focused screen's (HyprMac's focus, else the screen under the pointer),
    /// and what is on it.
    private func pushTargets() {
        guard model.nav == nil else { return }
        let mouse = NSEvent.mouseLocation
        let screen = model.state == nil ? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } : focusedScreen()
        let visible = panels.values.filter(\.isVisible)
        let p = visible.first { $0.popups.open != nil } ?? visible.first { $0.screenFrame == screen?.frame } ?? visible.first
        navPanel = p
        let t = p?.hintTargets() ?? []
        if t != navOrder { navOrder = t; chords.navTargets = t }
    }

    /// A popup opened by the mouse: the mode's keys must land on its bar (`pushTargets` picks it).
    private func popupChanged(_ id: String?) {
        pushTargets()
        chords.popup(id)
    }

    private func applyNav(_ shown: NavSnapshot?, _ actions: [NavAction]) {
        // The banner's letters work with a held modifier leader too, before any bar was picked.
        for case .banner(let a) in actions { chordAction(a) }
        if notes.banner != nil { notesChanged() }  // its hint row follows the mode
        guard let p = navPanel else { return }
        for a in actions {
            switch a {
            case .banner, .preview: break
            case .open(let id): p.popups.open = id
            case .move(let by): p.popups.move(by)
            case .choose: p.popups.choose()
            case .remove: p.popups.remove()
            case .alt: if p.popups.alt() { chords.nav(on: false) }
            case .side(let by):
                let ids = navOrder.filter(\.popup).map(\.id)
                if let cur = p.popups.open, let i = ids.firstIndex(of: cur) { p.popups.open = ids[min(max(i + by, 0), ids.count - 1)] }
            case .back: p.popups.open = nil
            case .activate(let id): p.spots[id]?.action?()
            case .exit: p.popups.open = nil
            }
        }
        model.nav = shown.map { s in
            NavShown(panel: ObjectIdentifier(p), labels: s.hints.compactMap { id, text in p.spots[id].map { HintLabel(text: text, frame: $0.frame) } },
                     typed: s.typed)
        }
        if shown == nil { pushTargets() }
    }

    private func chordAction(_ a: ChordAction) {
        switch a {
        case .open: openBanner(alt: false)
        case .alt: openBanner(alt: true)
        case .dismiss: dismissBanner()
        case .next: stepBanner(1)
        case .previous: stepBanner(-1)
        case .snooze(let minutes):
            guard let b = notes.banner else { return }
            if b.meetingStart != nil, let m = meetings.first(where: { "meeting-\($0.id)" == b.id }) {
                meetingClock.snooze(m, now: Date().timeIntervalSince1970)
                saveMeetings()
                notes.remove(b.id, now: ProcessInfo.processInfo.systemUptime)
                meetingShown = nil
                logNote(b, "snoozed to the next point")
                notesChanged()
                meetingsChanged()
                return
            }
            notes.snooze(minutes: minutes, now: ProcessInfo.processInfo.systemUptime)
            logNote(b, "snoozed \(minutes) min")
            notesChanged()
        }
    }

    /// Scroll or the next/previous letter: another banner of the stack comes up, the one on screen keeps its time.
    private func stepBanner(_ by: Int) {
        let before = notes.banner?.id
        if by > 0 { notes.next(now: ProcessInfo.processInfo.systemUptime) } else { notes.previous(now: ProcessInfo.processInfo.systemUptime) }
        if let b = notes.banner, b.id != before { logNote(b, by > 0 ? "next" : "previous") }
        notesChanged()
    }

    /// Right click without a second action dismisses, like the wheel.
    private func openBanner(alt: Bool) {
        guard let b = notes.banner else { return }
        if alt && b.altLink == nil {
            // Right click and the alt letter never remove anything: without a second action the banner just says so.
            noAltBanner = b.id
            notesChanged()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, noAltBanner == b.id else { return }
                noAltBanner = nil
                notesChanged()
            }
            return
        }
        open(b.id, alt: alt)
    }

    /// From the banner or from a list: takes it out of the store and opens its link, or its app.
    /// `joining` skips the check before a meeting (it is the check's own Join).
    private func open(_ id: String, alt: Bool = false, joining: Bool = false) {
        if !joining, model.config.meetingPreview, let m = meetings.first(where: { "meeting-\($0.id)" == id }) {
            showMeetingPreview(m)
            return
        }
        guard let b = notes.open(id, now: ProcessInfo.processInfo.systemUptime) else { return }
        logNote(b, alt ? "alt" : "opened")
        if b.meetingStart != nil { finishMeeting(b) }
        if let target = alt ? b.altLink : b.link {
            // Any process in the session can post, sandboxed ones too: a file: link would launch whatever it points at.
            let opened = URL(string: target).map { $0.scheme != nil && !$0.isFileURL && NSWorkspace.shared.open($0) } ?? false
            if !opened { logNote(b, "link failed") }
        } else if let owner = pluginNoteOwner(b.id, plugins: model.plugins.map(\.folder)) {
            pluginHost.send(plugin: owner.plugin, .notifyOpen, id: owner.id)  // the plugin knows where it leads
        } else if let app = b.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        notesChanged()
    }

    private func dismissBanner() {
        guard let b = notes.banner else { return }
        if b.meetingStart != nil {
            // Only hides it for this meeting (Greg): nothing is sent, nothing is filed.
            notes.remove(b.id, now: ProcessInfo.processInfo.systemUptime)
            logNote(b, "dismissed")
            finishMeeting(b)
            notesChanged()
            return
        }
        notes.dismiss(now: ProcessInfo.processInfo.systemUptime)  // gone for good: nothing flies to the icon
        logNote(b, "dismissed")
        notesChanged()
    }

    /// Shows what the store holds and arms one timer for the next moment it has work
    /// (banner expiry or a snooze coming back).
    private func notesChanged() {
        // The tap decides on its own thread, from these two values.
        chords.bannerUp = notes.banner != nil
        chords.queued = notes.waiting > 0
        syncInboxes()
        saveNotes()
        if model.dnd != notes.dnd { model.dnd = notes.dnd }
        // Opened or dismissed some other way (a chord, a list): the red screen goes too.
        if let a = armageddon.shown, notes.banner?.id != a.id, !notes.inbox(a.app).contains(where: { $0.id == a.id }) { armageddon.hide() }
        if let b = notes.banner, let screen = bannerScreen(b) {
            // A meeting counts down to its start from the first point; after the start the line stays full.
            let toStart = b.meetingStart.map { $0 - Date().timeIntervalSince1970 }
            let total = b.meetingStart != nil ? Double(model.config.meetingPoints.max() ?? 3) * 60 : notes.levelSeconds[b.level] ?? b.level.seconds
            let remaining = toStart.map { $0 > 0 ? $0 : nil } ?? notes.remaining(now: ProcessInfo.processInfo.systemUptime)
            island.show(b, icon: b.app.flatMap(AppIcons.icon(for:)), theme: model.config.theme, on: screen,
                        total: total, remaining: remaining, running: b.meetingStart != nil ? (toStart ?? 0) > 0 : !notes.isPaused,
                        hints: noAltBanner == b.id ? ChordHints(snoozeMinutes: nil, note: "No second action") : chords.hints,
                        queue: notes.queue)
        } else {
            island.hide()
        }
        notesTimer?.invalidate(); notesTimer = nil
        guard let at = notes.nextDeadline else { return }
        let t = Timer(fire: Date(timeIntervalSinceNow: max(0, at - ProcessInfo.processInfo.systemUptime)), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickNotes() }
        }
        RunLoop.main.add(t, forMode: .common)
        notesTimer = t
    }

    private func tickNotes() {
        let before = notes.banner, was = Set(notes.stacked.map(\.id))
        let due = notes.tick(now: ProcessInfo.processInfo.systemUptime)
        due.forEach { sendToPhone($0) }
        // After a tick the banner can only have expired (left the stack), or a snooze came back into it.
        if let b = before, !notes.contains(b.id) { flyToIcon(b); logNote(b, "expired") }
        for r in notes.stacked where !was.contains(r.id) { logNote(r, "reminder"); play(r) }
        notesChanged()
    }

    private func syncInboxes() {
        if flying == 0, model.inboxes != notes.inboxes { model.inboxes = notes.inboxes }
    }

    /// From the banner's icon to the app's icon on the bar of the same screen (the 🔔 for apps not on the bar).
    /// No target on that screen (bell never shown yet) → no flight, the count just updates.
    private func flyToIcon(_ n: GzymsNotification) {
        guard model.animate, !n.compact, island.shown != nil, let id = island.screen?.displayID, let panel = panels[id] else { return }
        let onBar = Set(model.workspaces.flatMap(\.appBundleIDs))
        let key = n.app.flatMap { onBar.contains($0) ? $0 : nil } ?? "bell"
        guard let target = panel.iconRect(key),
              let image = n.app.flatMap(AppIcons.icon(for:)) ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)
        else { return }
        flying += 1
        island.fadeNextHide = true
        FlyToIcon.run(image: image, from: island.avatarRect, to: target) { [weak self] in
            self?.flying -= 1
            self?.syncInboxes()
        }
    }

    /// The screen HyprMac has focus on, so the banner shows where Greg is looking.
    private func bannerScreen(_ n: GzymsNotification) -> NSScreen? {
        if let want = n.screen, let s = NSScreen.screens.first(where: { $0.localizedName.localizedCaseInsensitiveContains(want) }) { return s }
        return focusedScreen()
    }

    private func focusedScreen() -> NSScreen? {
        guard let s = model.state, let focused = s.monitors.firstIndex(where: \.focused) else { return NSScreen.main }
        let screens = NSScreen.screens
        let slots = screens.map { ScreenSlot(displayID: $0.displayID ?? 0, localizedName: $0.localizedName, originX: Double($0.frame.minX)) }
        return zip(screens, slots).first { monitorIndex(for: $1, all: slots, stateMonitors: s.monitors) == focused }?.0 ?? NSScreen.main
    }

    private func play(_ n: GzymsNotification) {
        guard model.config.notificationSounds, model.config.appRules.rule(for: n).sound,
              let source = soundSource(for: n, choices: model.config.sounds) else { return }
        guard !play(source) else { return }
        // A moved or deleted file must not silence it: the event's own default plays instead.
        logNote(n, "sound \(source) would not play, the default plays")
        let e = n.sound.flatMap(SoundEvent.init(rawValue:)) ?? ([.error, .critical].contains(n.level) ? .fail : .message)
        play(SoundSource(e.defaultChoice, event: e))
    }

    /// Left alone long enough: it goes to `[notifications.phone] url`. `done` gets one line for Settings.
    private func sendToPhone(_ n: GzymsNotification, done: (@MainActor (String) -> Void)? = nil) {
        let name = n.app.flatMap { id in model.seenApps.first { $0.id == id }?.name }
        guard let request = model.config.phone.request(n, appName: name) else { done?(model.config.phone.format == .pushover ? "Fill in both keys first" : "Set an https:// address first"); return }
        Task { @MainActor [weak self] in
            let status: String
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                status = (200..<300).contains(code) ? "sent" : "failed with HTTP \(code)"
            } catch {
                status = "failed: \(error.localizedDescription)"
            }
            self?.logNote(n, "phone \(status)")
            done?(status == "sent" ? "Sent. Check the phone." : "Not sent. It \(status).")
        }
    }

    /// One NSSound per source, kept: a tone is synthesised once, a file read once (until the config changes).
    @discardableResult private func play(_ source: SoundSource) -> Bool {
        let key = "\(source)"
        let sound = sounds[key] ?? {
            let s: NSSound? = switch source {
            case .system(let name): NSSound(named: name)
            case .tone(let e): NSSound(data: toneWAV(e.tone))
            case .cat(let e): Bundle.main.url(forResource: "cat-\(e.rawValue)", withExtension: "mp3", subdirectory: "sounds")
                .flatMap { NSSound(contentsOf: $0, byReference: true) }
            case .file(let path): NSSound(contentsOf: URL(filePath: path), byReference: true)
            }
            sounds[key] = s
            return s
        }()
        guard let sound else { return false }
        // play() refuses while it still plays (a burst), so start it over.
        if !sound.play() { sound.stop(); return sound.play() }
        return true
    }

    private func play(_ e: SoundEvent) {
        let source = SoundSource(model.config.sounds[e] ?? e.defaultChoice, event: e)
        guard !play(source) else { return }
        log("sound: \(e.rawValue) (\(source)) would not play, the default plays")
        play(SoundSource(e.defaultChoice, event: e))
    }

    /// Never the title or body: they can carry private text.
    private func logNote(_ n: GzymsNotification, _ action: String) {
        log("notify: \(n.level.rawValue) \(n.app ?? "bell") \(n.id) \(action)")
    }

    private func appTerminated(_ bundleID: String) {
        guard let s = model.state, !model.stale, let read = stateAfterAppExit(bundleID: bundleID, current: .fresh(s)) else { return }
        model.apply(read)
        log("hyprmac quit: workspaces marked stale")
        tilerCheck()
    }

    private func loadConfig() {
        let load = GzymsCore.loadConfig(toml: try? String(contentsOf: ThemeCommand.configFile, encoding: .utf8))
        model.config = load.config
        chords.micShortcut = load.config.micShortcut
        chords.configureNav(leader: load.config.leader, idleTimeout: load.config.idleTimeout, hintChars: load.config.hintChars,
                            verbs: load.config.verbs)
        meetingClock.points = load.config.meetingPoints
        calendar?.setSkip(load.config.calendarSkip)
        if load.config.hiddenWidgets.contains(.music) { music.stop() } else { music.start() }
        if pluginsStarted {
            pluginHost.setOptions(load.config.pluginOptions)
            pluginHost.setDisabled(load.config.disabledPlugins)
        } else { startPlugins(disabled: load.config.disabledPlugins, options: load.config.pluginOptions) }
        model.customLogo = load.config.logo.flatMap { path in
            let image = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath)
            if image == nil { log("bar: logo \(path) could not be read, the cat stays") }
            return image
        }
        if load.config.calendarEnabled, calendar == nil, configLoadedOnce { startCalendar() }
        if !load.config.calendarEnabled, let c = calendar { c.stop(); calendar = nil; meetings = []; meetingsChanged() }
        configLoadedOnce = true
        anomalies.enabled = load.config.anomalies
        notes.levelSeconds = load.config.levelSeconds
        notes.appRules = load.config.appRules
        notes.phone = load.config.phone
        notes.breaksThrough = load.config.dndBreaks
        sounds = [:]  // a file may have changed under the same path
        applyMotion()
        if notes.banner != nil { notesChanged() }  // a banner on screen takes the new theme too
        refreshAudio()
        model.configProblems = load.problems
        model.configBroken = load.broken
        settings.animate = model.animate
        load.problems.forEach { log("config: \($0)") }
        log("config: loaded (\(load.problems.count) problems)")
    }

    private func applyMotion() {
        let c = model.config
        let on = c.animations && !(c.followReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        model.animate = on
        island.animate = on
    }

    // MARK: - No tiling manager

    /// A fresh state ends the single-desktop mode at once; a stale or missing one starts it after 10 s,
    /// so a HyprMac restart does not make the bar jump.
    private func tilerCheck() {
        let gone = model.state == nil || model.stale
        if !gone {
            tilerTimer?.invalidate(); tilerTimer = nil
            if model.noWindowManager { setNoWindowManager(false) }
            return
        }
        guard !model.noWindowManager, tilerTimer == nil else { return }
        let t = Timer(timeInterval: 10, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tilerTimer = nil
                if self.model.state == nil || self.model.stale { self.setNoWindowManager(true) }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        tilerTimer = t
    }

    private func setNoWindowManager(_ on: Bool) {
        model.noWindowManager = on
        log("tiler: \(on ? "none, one desktop" : "back")")
        appsObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        appsObservers = []
        guard on else { return }
        refreshRunningApps()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            appsObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { [weak self] in self?.refreshRunningApps() }
            })
        }
    }

    private func refreshRunningApps() {
        model.runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap(\.bundleIdentifier)
    }

    // MARK: - Meetings

    private var configLoadedOnce = false

    private func startCalendar() {
        if let data = try? Data(contentsOf: Self.meetingsFile), let s = try? JSONDecoder().decode(MeetingClock.Saved.self, from: data) {
            meetingClock.restore(s)  // unreadable: start empty, the worst case is one reminder again
        }
        let c = CalendarSource { [weak self] found, calendars in
            guard let self else { return }
            if model.calendars != calendars { model.calendars = calendars }
            if found.map(\.id) != calendarMeetings.map(\.id) { log("calendar: \(found.count) meetings with a video link in the next 12 h") }
            calendarMeetings = found
            meetings = calendarMeetings + testMeetings
            meetingsChanged()
        }
        c.setSkip(model.config.calendarSkip)  // queued before the first read
        c.start()
        calendar = c
        meetingTestObserver = DistributedNotificationCenter.default().addObserver(forName: meetingTestName, object: nil, queue: .main) { note in
            let minutes = (note.object as? String).flatMap(Double.init) ?? 4
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                let start = Date().timeIntervalSince1970 + minutes * 60
                testMeetings = [Meeting(id: "test@\(Int(start))", title: "Gzyms test meeting", start: start, end: start + 900,
                                        link: "https://meet.google.com/abc-defg-hij")]
                meetings = calendarMeetings + testMeetings
                log("calendar: pretend meeting in \(minutes) min")
                meetingsChanged()
            }
        }
        model.onMeetingPill = { [weak self] in
            guard let id = self?.meetingShown else { return }
            self?.open("meeting-\(id)")
        }
    }

    /// Posts (or refreshes) the reminder the clock says is due, keeps the 📅 pill, and wakes up at the next point
    /// or the next minute while one is up (the subtitle counts minutes).
    private func meetingsChanged() {
        let now = Date().timeIntervalSince1970
        let due = meetingClock.due(meetings, now: now)
        if let old = meetingShown, old != due?.meeting.id {
            notes.remove("meeting-\(old)", now: ProcessInfo.processInfo.systemUptime)  // moved, cancelled, or another one starts first
            meetingShown = nil
            notesChanged()
        }
        if let d = due {
            let m = d.meeting
            var n = GzymsNotification(id: "meeting-\(m.id)", app: "com.apple.iCal", level: .info, title: m.title,
                                      subtitle: Self.meetingSubtitle(m, now: now), body: nil, link: m.link, altLink: nil,
                                      sound: meetingShown == m.id ? nil : "waiting", at: Date())
            n.meetingStart = m.start
            n.meetingEnd = m.end
            if !notes.contains(n.id) { notes.remove(n.id, now: ProcessInfo.processInfo.systemUptime) }  // out of an inbox, so it shows again
            if meetingShown != m.id { log("calendar: \(m.id) at \(d.point) min") }
            meetingShown = m.id
            post(n)
        }
        model.meetingPill = due.flatMap { d in now < d.meeting.start + 600 ? "\(d.meeting.title) \(Self.meetingShort(d.meeting, now: now))" : nil }
        meetingTimer?.invalidate(); meetingTimer = nil
        // The subtitle changes on whole minutes counted from the start.
        let nextMinute = due.map { d in now + 60 - ((now - d.meeting.start).truncatingRemainder(dividingBy: 60) + 60).truncatingRemainder(dividingBy: 60) }
        guard let at = [meetingClock.nextCheck(meetings, now: now), nextMinute].compactMap({ $0 }).min() else { return }
        let t = Timer(fire: Date(timeIntervalSince1970: at + 0.5), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.meetingsChanged() }
        }
        RunLoop.main.add(t, forMode: .common)
        meetingTimer = t
    }

    private func showMeetingPreview(_ m: Meeting) {
        meetingPreview.onJoin = { [weak self] m in
            self?.meetingPreview.close()
            self?.open("meeting-\(m.id)", joining: true)
        }
        meetingPreview.onClose = { [weak self] in self?.micMeter.stop() }
        micMeter.start()
        meetingPreview.show(m, model: model, on: focusedScreen())
        log("calendar: \(m.id) check before joining")
    }

    private static var meetingsFile: URL { notesFile.deletingLastPathComponent().appendingPathComponent("meetings.json") }

    /// Joined, dismissed and snoozed meetings, so a restart (install, update, crash) does not bring a reminder back.
    private func saveMeetings() {
        guard let data = try? JSONEncoder().encode(meetingClock.saved(now: Date().timeIntervalSince1970)) else { return }
        do { try data.write(to: Self.meetingsFile, options: .atomic) } catch { log("calendar: could not save meetings.json (\(error))") }
    }

    private func finishMeeting(_ n: GzymsNotification) {
        let id = String(n.id.dropFirst("meeting-".count))
        meetingClock.finish(id)
        saveMeetings()
        if meetingShown == id { meetingShown = nil }
        meetingsChanged()
    }

    /// Whole minutes: before the start rounded up ("in 3 min" until 2:00 left), after it rounded down.
    private static func meetingMinutes(_ m: Meeting, now: Double) -> Int {
        let d = m.start - now
        return d > 0 ? Int((d / 60).rounded(.up)) : -Int((-d / 60).rounded(.down))
    }

    static func meetingSubtitle(_ m: Meeting, now: Double) -> String {
        let minutes = meetingMinutes(m, now: now)
        return minutes > 0 ? "in \(minutes) min" : minutes == 0 ? "starting now" : "\(-minutes) min late"
    }

    static func meetingShort(_ m: Meeting, now: Double) -> String {
        let minutes = meetingMinutes(m, now: now)
        return minutes > 0 ? "\(minutes)m" : minutes == 0 ? "now" : "−\(-minutes)m"
    }

    // MARK: - Permissions

    /// Every 2 s while the wizard or the Permissions tab is on screen, every 30 s otherwise.
    private func checkGrants() {
        let now = [GrantState(grant: .accessibility, granted: AXIsProcessTrusted()),
                   GrantState(grant: .fullDiskAccess, granted: NotificationCenterSource.hasAccess()),
                   GrantState(grant: .calendars, granted: CalendarSource.authorized)]
        let before = model.grants
        if now != before {
            model.grants = now
            log("permissions: " + now.map { "\($0.grant.rawValue) \($0.granted ? "on" : "off")" }.joined(separator: ", "))
        }
        if !revokedGrants(before: before, after: now).isEmpty { model.grantWarning = true }
        if now.filter(\.grant.required).allSatisfy(\.granted) {
            model.grantWarning = false
            // Only when the last missing one just came on: a wizard opened from the menu with all green stays.
            if wizard.isVisible, before.filter(\.grant.required).contains(where: { !$0.granted }) { wizard.orderOut(nil) }
        }
        // Accessibility given after launch: the keyboard tap starts now instead of after a restart.
        if now.first(where: { $0.grant == .accessibility })?.granted == true { chords.start() }
        let watching = wizard.isVisible || (settings.isVisible && model.settingsTab == .permissions)
        grantTimer?.invalidate()
        let t = Timer(timeInterval: watching ? 2 : 30, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.checkGrants() } }
        t.tolerance = watching ? 0.3 : 5
        RunLoop.main.add(t, forMode: .common)
        grantTimer = t
    }

    private func openGrant(_ g: Grant) {
        settings.stepBack()
        wizard.stepBack()
        if let url = URL(string: g.settingsURL) { NSWorkspace.shared.open(url) }
        checkGrants()  // switch to the 2 s pace now
    }

    // MARK: - Messages from Gzyms

    /// What is new after an update and an untested macOS, once each. `gzyms message` shows one without touching the file.
    private func startMessages() {
        let seen = try? JSONDecoder().decode(MessagesSeen.self, from: Data(contentsOf: messagesFile))
        let r = launchMessages(seen: seen, version: gzymsVersion, macOS: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        if r.seen != seen {
            do {
                try FileManager.default.createDirectory(at: messagesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(r.seen).write(to: messagesFile, options: .atomic)
            } catch { log("messages: could not save: \(error.localizedDescription)") }
        }
        r.show.forEach(showMessage)
        messageObserver = DistributedNotificationCenter.default().addObserver(forName: messageName, object: nil, queue: .main) { note in
            let kind = note.object as? String
            MainActor.assumeIsolated { [weak self] in
                if kind == "whats-new", let n = newestWhatsNew() { self?.showMessage(.whatsNew(version: n.version, lines: n.lines)) }
                if kind == "untested-macos" { self?.showMessage(.untestedMacOS(major: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)) }
            }
        }
    }

    private func showMessage(_ m: GzymsMessage) {
        let close: () -> Void = { [weak self] in self?.messages.next() }
        let view = switch m {
        case let .whatsNew(version, lines):
            GzymsMessageView(title: "What's new in Gzyms \(version)", lines: lines,
                             actions: [.init("Learn the keys") { NSWorkspace.shared.open(tutorialURL) }], close: close)
        case let .untestedMacOS(major):
            GzymsMessageView(title: "Gzyms was not tested on macOS \(major)",
                             lines: ["Some parts may not work right.", "If something breaks, a report helps fix it."],
                             actions: [.init("Turn on debug mode") { [weak self] in self?.debugModeOn() },
                                       .init("Report a problem") { [weak self] in self?.reportIssue() }],
                             close: close)
        }
        log("messages: showing \(m)")
        messages.show(view, on: focusedScreen())
    }

    /// Debug mode: the anomaly detector logs stalls and stale data, the usage HUD shows Gzyms' own CPU and lag.
    private func debugModeOn() {
        messages.next()
        writeSetting("anomalies", nil, .table(["debug"]))
        settingsActions().showHUD()
    }

    private func reportIssue() {
        messages.next()
        if let zip = Report.make(grants: model.grants) { NSWorkspace.shared.activateFileViewerSelecting([zip]) }
        if let url = URL(string: "https://github.com/zalewskigrzegorz/gzyms/issues/new") { NSWorkspace.shared.open(url) }
    }

    // MARK: - Settings

    private func startSettings() {
        model.seenApps = ((try? JSONDecoder().decode([String].self, from: Data(contentsOf: seenAppsFile))) ?? []).compactMap(seenApp)
        model.onMenu = { [weak self] in self?.showMenu() }
        settingsObserver = DistributedNotificationCenter.default().addObserver(forName: settingsName, object: nil, queue: .main) { note in
            let tab = (note.object as? String).flatMap(SettingsTab.init(rawValue:))
            MainActor.assumeIsolated { [weak self] in self?.toggleSettings(tab) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                watchdog.settling("screens")  // the panels are rebuilt now
                settings.hide()
                armageddon.screensChanged(theme: model.config.theme, calm: !model.animate)
            }
        }
    }

    private func showMenu() {
        log("bar: logo clicked, menu shown")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        let grants = NSMenuItem(title: "Permissions…", action: #selector(menuPermissions), keyEquivalent: "")
        grants.target = self
        menu.addItem(grants)
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        update.target = updater
        menu.addItem(update)
        let learn = NSMenuItem(title: "Learn Gzyms…", action: #selector(menuLearn), keyEquivalent: "")
        learn.target = self
        menu.addItem(learn)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Gzyms", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func menuSettings() { toggleSettings(nil) }
    @objc private func menuPermissions() { wizard.show(on: focusedScreen()); checkGrants() }
    @objc private func menuLearn() { NSWorkspace.shared.open(tutorialURL) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    /// A tab opens on that tab (and stays open); no tab toggles.
    private func toggleSettings(_ tab: SettingsTab?) {
        if let tab { model.settingsTab = tab }
        log("settings: toggle (visible \(settings.isVisible), in front \(settings.isInFront))")
        if settings.isVisible {
            if tab == nil, settings.isInFront { settings.hide() } else { settings.makeKeyAndOrderFront(nil) }
            return
        }
        guard let screen = focusedScreen() else { return }
        settings.show(on: screen)
        log("settings: open \(model.settingsTab.rawValue)")
    }

    private func settingsActions() -> SettingsActions {
        var a = SettingsActions { [weak self] key, value, table in self?.writeSetting(key, value, table) }
        a.recording = { [weak self] on in self?.chords.paused = on; self?.settings.recording = on }
        a.chooseApp = { [weak self] in self?.chooseApp() }
        a.chooseLogo = { [weak self] in self?.chooseLogo() }
        a.revealPlugin = { [weak self] folder in
            guard let dir = self?.pluginHost.dir.appendingPathComponent(folder) else { return }
            self?.settings.stepBack()
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        }
        a.addPlugin = { [weak self] name in
            guard let self, let c = pluginCatalog.first(where: { $0.name == name }) else { return }
            // The plugins folder is watched: the new one starts and gets its section by itself.
            do { try installPlugin(in: pluginHost.dir, folder: name, manifest: c.manifest, script: c.script); log("plugin \(name): added") }
            catch { log("plugin \(name): could not add: \((error as? NotifyArgsError)?.message ?? error.localizedDescription)") }
        }
        a.installPlugin = { [weak self] url in self?.installPluginFolder(url) }
        a.choosePlugin = { [weak self] in
            guard let self else { return }
            settings.stepBack()
            watchdog.settling("file picker", for: 3)  // macOS builds the open panel on the main thread, slowly the first time
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            NSApp.activate()
            panel.begin { [weak self] r in
                guard r == .OK, let url = panel.url else { return }
                MainActor.assumeIsolated { _ = self?.installPluginFolder(url) }
            }
        }
        a.removePlugin = { [weak self] folder in
            guard let dir = self?.pluginHost.dir.appendingPathComponent(folder) else { return }
            // The Trash, not a delete: a plugin is the user's code, and this is one click.
            do { try FileManager.default.trashItem(at: dir, resultingItemURL: nil); log("plugin \(folder): moved to the Trash") }
            catch { log("plugin \(folder): could not move to the Trash: \(error.localizedDescription)") }
        }
        a.dropApp = { [weak self] url in self?.addApp(url) }
        // Out of SwiftUI's layout pass: resizing the window inside it would lay out again.
        a.close = { [weak self] in self?.settings.hide() }
        a.openGrant = { [weak self] g in self?.openGrant(g) }
        // launchd starts it again; a plain quit would stay quit now that KeepAlive only covers crashes.
        a.restart = {
            let p = Process()
            p.executableURL = URL(filePath: "/bin/launchctl")
            p.arguments = ["kickstart", "-k", "gui/\(getuid())/dev.gzyms"]
            do { try p.run() } catch { log("restart: \(error)") }
        }
        a.showHUD = {
            let p = Process()
            p.executableURL = Bundle.main.executableURL
            p.arguments = ["hud"]
            try? p.run()
        }
        a.openLog = { NSWorkspace.shared.activateFileViewerSelecting([Paths.logsDir(home: FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent("gzyms.log")]) }
        a.report = { [weak self] in
            let zip = Report.make(grants: self?.model.grants)
            if let zip { NSWorkspace.shared.activateFileViewerSelecting([zip]) }
            return zip
        }
        a.version = gzymsVersion
        a.openURL = { [weak self] s in
            self?.settings.stepBack()
            if let url = URL(string: s) { NSWorkspace.shared.open(url) }
        }
        a.requestFeature = { [weak self] in
            self?.settings.stepBack()
            if let url = URL(string: "https://github.com/zalewskigrzegorz/gzyms/discussions/new?category=ideas") { NSWorkspace.shared.open(url) }
        }
        a.height = { h in DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.settings.fit(height: h) } } }
        a.revealConfig = { NSWorkspace.shared.activateFileViewerSelecting([ThemeCommand.configFile.resolvingSymlinksInPath()]) }
        a.playSound = { [weak self] e in self?.play(e) }
        a.chooseSound = { [weak self] e in self?.chooseSound(e) }
        a.testPhone = { [weak self] done in
            self?.settings.makeFirstResponder(nil)  // saves the field still being typed in
            let n = GzymsNotification(id: "phone-test", app: nil, level: .critical, title: "Gzyms test", subtitle: nil,
                                      body: "Phone push works.", link: nil, altLink: nil, sound: nil, at: Date())
            self?.sendToPhone(n, done: done)
        }
        a.openAppNotifications = { [weak self] id in
            self?.settings.stepBack()
            // Mail's page does not open by its id (Greg, 2026-11-01): the list opens, Mail is one click from there.
            let page = id == "com.apple.mail" ? "" : "?id=\(id)"
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension\(page)") { NSWorkspace.shared.open(url) }
        }
        a.openNotificationSettings = { [weak self] in
            self?.settings.stepBack()
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        }
        return a
    }

    /// One line of `config.toml`, written at the symlink's target so a dotfiles link stays a link.
    private func writeSetting(_ key: String, _ value: TOMLValue?, _ table: ConfigTable) {
        guard !model.configBroken else { log("settings: config.toml does not parse, nothing written"); return }
        let target = ThemeCommand.configFile.resolvingSymlinksInPath()
        let current = try? String(contentsOf: target, encoding: .utf8)
        let next = setting(key, to: value, in: table, toml: current)
        guard next != current else { return }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try next.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            log("settings: could not write \(target.path): \(error)")
            return
        }
        log("settings: \(key) written")
        loadConfig()  // the watcher would too, 200 ms later; this keeps the switch from flicking back meanwhile
    }

    /// Copies a plugin folder in; the watched plugins folder starts it. A copy, so the original stays where it was.
    private func installPluginFolder(_ url: URL) -> String? {
        let name = url.lastPathComponent
        let problem: String? = if !FileManager.default.fileExists(atPath: url.appendingPathComponent("plugin.toml").path) {
            "\(name) has no plugin.toml, so it is not a plugin"
        } else if name.contains(":") {
            "A plugin folder name cannot have a colon"
        } else if FileManager.default.fileExists(atPath: pluginHost.dir.appendingPathComponent(name).path) {
            "There is a plugin called \(name) already. Remove it first."
        } else {
            (try? FileManager.default.copyItem(at: url, to: pluginHost.dir.appendingPathComponent(name))) == nil ? "Could not copy \(name)" : nil
        }
        log("plugin \(name): " + (problem.map { "not installed, \($0)" } ?? "installed from a folder"))
        return problem
    }

    private func chooseSound(_ e: SoundEvent) {
        settings.stepBack()
        watchdog.settling("file picker", for: 3)  // macOS builds the open panel on the main thread, slowly the first time
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.directoryURL = URL(filePath: NSHomeDirectory()).appending(path: "Music")
        NSApp.activate()
        panel.begin { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                // A copy next to the config, so moving or deleting the original does not silence the event.
                let dir = ThemeCommand.configFile.resolvingSymlinksInPath().deletingLastPathComponent().appending(path: "sounds")
                let copy = dir.appending(path: url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    if copy.path != url.path { try? FileManager.default.removeItem(at: copy); try FileManager.default.copyItem(at: url, to: copy) }
                } catch { log("sound: could not copy \(url.lastPathComponent): \(error.localizedDescription)"); return }
                self?.writeSetting(e.rawValue, .string(copy.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")), .table(["sounds"]))
                self?.play(e)
            }
        }
    }

    private func chooseApp() {
        settings.stepBack()
        watchdog.settling("file picker", for: 3)  // macOS builds the open panel on the main thread, slowly the first time
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        panel.begin { [weak self] r in
            guard r == .OK else { return }
            MainActor.assumeIsolated { panel.urls.forEach { self?.addApp($0) } }
        }
    }

    private func startPlugins(disabled: Set<String>, options: [String: [String: TOMLValue]]) {
        pluginsStarted = true
        pluginHost.onItems = { [weak self] pills in if self?.model.pluginPills != pills { self?.model.pluginPills = pills } }
        pluginHost.onStatus = { [weak self] s in if self?.model.plugins != s { self?.model.plugins = s } }
        pluginHost.onNotify = { [weak self] n in self?.post(n) }
        model.onPluginEvent = { [weak self] plugin, e, id in self?.pluginHost.send(plugin: plugin, e, id: id) }
        pluginHost.start(disabled: disabled, options: options)
        // Plugins get EOF and a SIGTERM when Gzyms quits, so none outlives it.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pluginHost.stopAll() }
        }
    }

    /// The artwork comes once per track; later lines of the same track keep it.
    private func musicChanged(_ line: NowPlayingLine) {
        switch line {
        case .nothing:
            if model.nowPlaying != nil { model.nowPlaying = nil; model.artwork = nil }
        case .item(let np, let art):
            if let art { model.artwork = NSImage(data: art) }
            else if np.artworkID != model.nowPlaying?.artworkID { model.artwork = nil }
            if model.nowPlaying != np { model.nowPlaying = np }
        }
    }

    private func chooseLogo() {
        settings.stepBack()
        watchdog.settling("file picker", for: 3)  // macOS builds the open panel on the main thread, slowly the first time
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf, .svg, .tiff, .heic]
        NSApp.activate()
        panel.begin { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.writeSetting("logo", .string(url.path), .table(["bar"])) }
        }
    }

    private func addApp(_ url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier else { log("settings: \(url.lastPathComponent) has no bundle id"); return }
        remember(id)
    }

    /// The Notifications tab lists every app that ever sent something. Kept outside the config folder (not a setting).
    private func remember(_ app: String) {
        guard !model.seenApps.contains(where: { $0.id == app }), let s = seenApp(app) else { return }
        model.seenApps.append(s)
        let ids = model.seenApps.map(\.id)
        try? FileManager.default.createDirectory(at: seenAppsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(ids).write(to: seenAppsFile, options: .atomic)
    }

    private func seenApp(_ id: String) -> SeenApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return SeenApp(id: id, name: id, icon: nil) }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return SeenApp(id: id, name: name, icon: AppIcons.icon(for: id))
    }

    private func apply(_ plan: DisplayPlan, _ screensByID: [UInt32: NSScreen]) {
        let now = ProcessInfo.processInfo.systemUptime
        let actions = lifecycle.apply(plan, at: now)
        // A display that left is hidden, not destroyed: a slow monitor after wake gets its own panel back.
        for id in actions.hide { panels[id]?.orderOut(nil) }
        for id in actions.reshow { if let screen = screensByID[id] { panels[id]?.fit(to: screen); panels[id]?.orderFrontRegardless() } }
        for id in actions.create {
            guard let screen = screensByID[id] else { continue }
            let p = BarPanel(screen: screen, model: model)
            p.onSpots = { [weak self] in self?.pushTargets() }
            p.popups.onChange = { [weak self] id in self?.popupChanged(id) }
            panels[id] = p
        }
        for id in plan.keep { if let screen = screensByID[id] { panels[id]?.fit(to: screen) } }
        if !actions.hide.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + lifecycle.grace + 0.1) { [weak self] in
                MainActor.assumeIsolated { self?.expireHidden() }
            }
        }
        guard !actions.create.isEmpty || !actions.hide.isEmpty else { return }
        let detail = ["keep": "\(plan.keep.sorted())", "create": "\(actions.create.sorted())",
                      "reshow": "\(actions.reshow.sorted())", "hide": "\(actions.hide.sorted())"]
        log("panels: \(detail)")
        rebuilds += 1
        anomalies.write(kind: "panel_rebuild", detail: detail)
        if storm.record(at: now) { anomalies.write(kind: "rebuild_storm", detail: ["limit": "3 in 10 s"]) }
    }

    private func expireHidden() {
        for id in lifecycle.expire(at: ProcessInfo.processInfo.systemUptime) {
            panels.removeValue(forKey: id)?.close()
            log("panel \(id) destroyed: display gone for \(Int(lifecycle.grace)) s")
        }
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("\(Date().ISO8601Format()) \(message)\n".utf8))
}
