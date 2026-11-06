import AppKit
import Carbon.HIToolbox
import GzymsCore
import GzymsUI
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = BarModel()
    /// Sparkle updates. Not started here: `applyUpdates` does it once the config says whether it checks by itself.
    /// Never started outside the bundle (`swift run`), where it would fail on a missing SUFeedURL.
    private let updateFound = UpdateFound()
    private lazy var updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: updateFound, userDriverDelegate: nil)
    private var updaterStarted = false
    private var dailyTimer: Timer?
    /// GZYMS_FAKE_BREW=1 on the dev install shows the Homebrew case without a cask.
    private let homebrew = (LoginItem.dev && ProcessInfo.processInfo.environment["GZYMS_FAKE_BREW"] == "1")
        || installedWithHomebrew(exists: { FileManager.default.fileExists(atPath: $0) })
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
    private lazy var banners = BannerSource { [weak self] n in self?.bannerArrived(n) }
    private var bannerGuard = BannerGuard()
    /// Notification Center shows no banners although apps send them (`BannerGuard`).
    private var noBanners = false
    private var ncRestart = NCRestartPolicy()
    private var ncRestartedAt: Date?
    /// The last banner Gzyms showed from another app, and the way it got here (`gzyms debug notifications`). Never its text.
    private var lastShown: (app: String?, at: Date, path: String)?
    private var debugObserver: NSObjectProtocol?
    /// Secure Input held since (system uptime), and whether the anomaly for this stretch is written.
    private var secureSince: TimeInterval?
    private var secureLogged = false
    private var warningsRead: Date?
    /// `nc-` notes opened, dismissed or already shown from their banner, so their database row ~5 s later is skipped.
    private var handled: [String: Date] = [:]
    /// For Settings → Hacks: the delivery log is alive.
    private var lastSignal: Date?
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
    private lazy var mediaServer = MediaServer { [weak self] tabs in if self?.model.tabs != tabs { self?.model.tabs = tabs } }
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
    private var settingsKeyObserver: NSObjectProtocol?
    /// System Settings opened from Settings → Apps: read every second while it runs, and the way back when it quits.
    private var systemSettingsWatch: (timer: Timer, observer: NSObjectProtocol)?
    private lazy var setupPanel = AppSetupPanel(model: model, skip: { [weak self] in self?.nextSetupApp() },
                                                stop: { [weak self] in self?.finishAppSetup() })
    /// The step-by-step setup waits a moment on an app set up right, so the ring is seen going out.
    private var setupAdvance: DispatchWorkItem?
    private let seenAppsFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Gzyms/seen-apps.json")
    private lazy var messages = GzymsMessagePanel(model: model)
    private lazy var palette = PalettePanel(model: model)
    private var messageObserver: NSObjectProtocol?
    private var dupes = DuplicateDetector()
    private var dupeApps: Set<String> = []
    private var dupeFlush: DispatchWorkItem?
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
        startDaily()
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
        model.onMusic = { [weak self] action in
            switch action {
            case .key(let c): MusicSource.nowPlaying(c)
            case .script(let app, let c): MusicSource.script(app, c)
            case .tab(let id, let i, let c): self?.mediaServer.send(id, media: i, c)
            case .jump(let app, let title): MusicSource.jump(to: app, title: title)
            }
        }
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

    private static var notesFile: URL { NotificationsCommand.file }
    private var notesSaved: Data?

    /// After every change, only when something kept on disk moved (hover and ticks leave the bytes alone).
    private func saveNotes() {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        guard let data = try? e.encode(notes.saved(now: ProcessInfo.processInfo.systemUptime, wall: Date())), data != notesSaved else { return }
        do { try data.write(to: Self.notesFile, options: .atomic); notesSaved = data } catch { log("notifications: could not save (\(error))") }
    }

    private var dndObserver: NSObjectProtocol?
    private var notesCLIObserver: NSObjectProtocol?
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
        // `gzyms notifications dismiss <id>` and `clear`. Nothing of the text goes to the log.
        notesCLIObserver = DistributedNotificationCenter.default().addObserver(forName: notificationsName, object: nil, queue: .main) { note in
            let arg = note.object as? String
            MainActor.assumeIsolated { [weak self] in
                guard let self, let arg else { return }
                if arg == "clear" {
                    for app in Array(notes.inboxes.keys) { notes.clearAll(app) }
                } else if arg.hasPrefix("dismiss:") {
                    notes.remove(String(arg.dropFirst("dismiss:".count)), now: ProcessInfo.processInfo.systemUptime)
                } else { return }
                log("notifications: \(arg == "clear" ? "lists cleared" : "one dismissed") from the CLI")
                notesChanged()
            }
        }
        debugObserver = DistributedNotificationCenter.default().addObserver(forName: debugName, object: nil, queue: .main) { note in
            let message = note.object as? String
            MainActor.assumeIsolated { [weak self] in self?.answerDebug(message) }
        }
        model.onOpenNote = { [weak self] in self?.open($0) }
        model.onAltNote = { [weak self] in self?.open($0, alt: true) }
        model.onRemoveNote = { [weak self] id in
            self?.forget(id)
            self?.notes.remove(id, now: ProcessInfo.processInfo.systemUptime)
            self?.notesChanged()
        }
        chords.onMute = { [weak self] in self?.micMute.toggle(self?.model.audio); self?.refreshAudio() }
        chords.onNav = { [weak self] in self?.applyNav($0, $1) }
        chords.onArmageddon = { [weak self] in self?.armageddon.open() }
        chords.onDisabled = { [weak self] why, count in
            self?.anomalies.write(kind: "tap_disabled", detail: ["by": why, "count": String(count)])
        }
        model.onTestSound = { [weak self] in self?.play(.message) }
        chords.start()
        startKeys()
        let source = NotificationCenterSource { [weak self] list in
            guard let self else { return }
            for var n in list where !wasHandled(n.id) {
                n.app = n.app.map(AppIcons.bundleID(matching:))
                lastShown = (n.app, Date(), "database")
                post(n)
            }
        }
        source.start()
        nc = source
        applyNotificationSources()
        // A banner parked off screen goes home when Gzyms quits, so macOS's own is back.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.banners.stopNow() }
        }
        let badges = DockBadges { [weak self] in self?.model.dockBadges = $0 }
        badges.start()
        dock = badges
        island.onOpen = { [weak self] in self?.openBanner(alt: false) }
        island.onRight = { [weak self] in self?.openBanner(alt: true) }
        island.onDismiss = { [weak self] in self?.dismissBanner() }
        island.onStep = { [weak self] in self?.stepBanner($0) }
        island.onHint = { [weak self] in self?.chordAction($0) }
        armageddon.onOpen = { [weak self] id in self?.open(id) }
        armageddon.playSound = { [weak self] in self?.play(.armageddon) }
        armageddon.onVisible = { [weak self] up in self?.chords.armageddon = up }
        armageddon.onDismiss = { [weak self] id in
            guard let self, notes.banner?.id == id else { return }  // already in its inbox otherwise
            dismissBanner()
        }
        island.onHover = { [weak self] on in
            self?.chords.hover(on)
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
        lastSignal = Date()
        countSignal(AppIcons.bundleID(matching: app))
        if let b = notes.banner, !b.compact { return }
        post(.pending(app: AppIcons.bundleID(matching: app), at: Date()))
    }

    /// `[notifications] banner_ax` and `signal`, at start and on every config load.
    private func applyNotificationSources() {
        guard nc != nil else { return }  // the first load comes before startNotifications
        let c = model.config
        // Off still keeps the source: clicks go through its queue and its single owner of the panel's window.
        if c.bannerAX { banners.start() } else { banners.stop() }
        if c.signal, signal == nil {
            let s = DeliverySignal { [weak self] app in self?.pending(app) }
            s.start()
            signal = s
        } else if !c.signal, let s = signal {
            s.stop()
            signal = nil
        }
    }

    /// A banner read through Accessibility. Its database row is skipped, even when the app was not recognised: filed
    /// under no app, the row's copy would not be found and would show a second banner.
    private func bannerArrived(_ n: GzymsNotification) {
        bannerGuard.banner(at: ProcessInfo.processInfo.systemUptime)
        noBanners = false
        ncRestart.bannerShown()
        lastShown = (n.app, Date(), "ax")
        markHandled(n.id)
        post(n)
    }

    /// Counts a delivery with no banner after it (`BannerGuard`). Not under do not disturb or a macOS Focus, not for apps whose
    /// macOS style is None (they never show a banner), not while the observer is off.
    private func countSignal(_ app: String) {
        // The per-app warnings say which apps never show a banner; read once a minute, not only when Settings opens.
        if warningsRead.map({ Date().timeIntervalSince($0) > 60 }) ?? true { warningsRead = Date(); refreshAppWarnings() }
        guard model.config.signal, notes.dnd == nil, banners.attached,
              model.seenApps.first(where: { $0.id == app })?.mac?.desktop != false else { return }
        // A Focus holds banners back on purpose: not a hung Notification Center.
        let assertions = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/DoNotDisturb/DB/Assertions.json")
        if let data = try? Data(contentsOf: assertions), focusIsOn(assertions: data) { return }
        bannerGuard.signal(at: ProcessInfo.processInfo.systemUptime)
        if bannerGuard.warns, !noBanners {
            noBanners = true
            log("banners: apps send notifications but Notification Center shows no banner. A Focus, or NC stuck: killall NotificationCenter")
            let now = ProcessInfo.processInfo.systemUptime
            if ncRestart.stillHung {
                log("banners: still no banner after the Notification Center restart, not restarting again")
                anomalies.write(kind: "nc_restart_failed", detail: ["restarts": String(ncRestart.count)])
            } else if ncRestart.mayAutoRestart(enabled: model.config.ncAutoRestart, at: now) {
                restartNC(reason: "\(bannerGuard.signals) deliveries without a banner over \(Int(now - (bannerGuard.firstSignal ?? now))) s", auto: true)
            }
        }
    }

    /// `killall NotificationCenter`: macOS starts it again and no notification is lost. The guard starts over and the
    /// observer attaches to the new process at once. The automatic caller is limited by `NCRestartPolicy`; the button is not.
    private func restartNC(reason: String, auto: Bool) {
        ncRestart.restarted(at: ProcessInfo.processInfo.systemUptime)
        ncRestartedAt = Date()
        bannerGuard = BannerGuard()
        noBanners = false
        log("banners: restarting Notification Center (\(auto ? "automatic" : "button"): \(reason))")
        anomalies.write(kind: "nc_restart", detail: ["by": auto ? "auto" : "button", "reason": reason, "count": String(ncRestart.count)])
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["NotificationCenter"]
        let banners = banners
        DispatchQueue.global(qos: .userInitiated).async {
            do { try p.run(); p.waitUntilExit() } catch { log("banners: killall failed: \(error)") }
            if p.terminationStatus != 0 { log("banners: killall NotificationCenter exited \(p.terminationStatus)") }
            banners.ncRestarted()
        }
    }

    private func markHandled(_ id: String) {
        guard id.hasPrefix("nc-") else { return }
        let now = Date()
        handled = handled.filter { now.timeIntervalSince($0.value) < 120 }
        handled[id] = now
    }

    /// Dismissed in Gzyms: its database row stays away and a parked alert is closed, not left hidden.
    private func forget(_ id: String) {
        guard let uuid = ncRecordUUID(noteID: id) else { return }
        markHandled(id)
        banners.closeParked(uuid: uuid)
    }

    private func wasHandled(_ id: String) -> Bool { handled[id].map { Date().timeIntervalSince($0) < 120 } ?? false }

    /// From `gzyms notify` or from another app through Notification Center.
    private func post(_ n: GzymsNotification) {
        if let app = n.app, !n.compact { remember(app) }
        // Off in Settings → Apps: no armageddon sound either (the store drops it too).
        guard !notes.appRules.rule(for: n).skip else { return }
        noteDuplicates(n)
        notes.post(n, now: ProcessInfo.processInfo.systemUptime)
        logNote(n, "posted")
        var loud = n
        loud.level = notes.appRules.rule(for: n).raise(n.level)
        if loud.level == .armageddon, !n.compact, !notes.quiet(loud) {
            // Its own sound, every 1.5 s until clicked; a later notification goes under it, not over.
            armageddon.show(loud, theme: model.config.theme, calm: !model.animate)
        }
        notesChanged()
    }

    /// Other apps' notifications only (not plugins, the instant icon or a snooze coming back). The anomaly log gets the bundle
    /// ids and a count, never the text. The notification waits 3 s, so four calendars make one, not three.
    private func noteDuplicates(_ n: GzymsNotification) {
        guard let app = n.app, !n.compact, !n.reminder, !app.hasPrefix("plugin:"), !n.id.hasPrefix("plugin:"),
              let hit = dupes.record(app: app, title: n.title, body: n.body, at: ProcessInfo.processInfo.systemUptime) else { return }
        anomalies.write(kind: "duplicate_apps", detail: ["apps": hit.apps.joined(separator: ","), "count": String(hit.count)])
        log("dupes: \(hit.apps.joined(separator: ",")) x\(hit.count)")
        dupeApps.formUnion(hit.apps)
        guard dupeFlush == nil else { return }
        let w = DispatchWorkItem { [weak self] in self?.flushDuplicates() }
        dupeFlush = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    /// Counts the group for Settings → Debug, and posts one notification when a pair of apps is new.
    private func flushDuplicates() {
        let apps = dupeApps.sorted()
        dupeApps = []
        dupeFlush = nil
        let r = recordDuplicates(apps: apps, at: Date(), seen: messagesSeen())
        saveMessagesSeen(r.seen)
        guard !r.tell.isEmpty else { return }
        let names = r.tell.map { id in model.seenApps.first { $0.id == id }?.name ?? id }
        let text = duplicateNotice(names: names)
        post(GzymsNotification(id: duplicateNoticeID, app: nil, level: .warning, title: text.title, subtitle: nil, body: text.body,
                               link: nil, altLink: nil, sound: nil, at: Date()))
    }

    private func messagesSeen() -> MessagesSeen {
        (try? JSONDecoder().decode(MessagesSeen.self, from: Data(contentsOf: messagesFile))) ?? MessagesSeen()
    }

    private func saveMessagesSeen(_ seen: MessagesSeen) {
        do {
            try FileManager.default.createDirectory(at: messagesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(seen).write(to: messagesFile, options: .atomic)
        } catch { log("messages: could not save: \(error.localizedDescription)") }
    }

    private func setDuplicateWarnings(_ on: Bool) {
        var seen = messagesSeen()
        seen.duplicatesOff = on ? nil : true
        saveMessagesSeen(seen)
    }

    private func forgetDuplicates(_ apps: [String]) {
        saveMessagesSeen(messagesSeen().forgetting(group: apps))
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
                let now = ProcessInfo.processInfo.systemUptime
                if !on { self.secureSince = nil; self.secureLogged = false }
                else if let since = self.secureSince {
                    if !self.secureLogged, now - since >= 60 {
                        self.secureLogged = true
                        self.anomalies.write(kind: "secure_input_long", detail: ["owner": self.secureInputOwner() ?? "unknown", "seconds": String(Int(now - since))])
                    }
                } else { self.secureSince = now }
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

    /// The banner's countdown stands still while the pointer is on it or the leader shows its hints (Greg, #25).
    private func syncPause() { notes.hover(island.hovered || chords.hints != nil, now: ProcessInfo.processInfo.systemUptime) }

    private func applyNav(_ shown: NavSnapshot?, _ actions: [NavAction]) {
        // The banner's letters work with a held modifier leader too, before any bar was picked.
        for case .banner(let a) in actions { chordAction(a) }
        if notes.banner != nil { notesChanged() }  // its hint row follows the mode
        if actions.contains(.palette) { showPalette() }
        guard let p = navPanel else { return }
        for a in actions {
            switch a {
            case .banner, .preview, .palette: break
            case .open(let id): p.popups.open = id
            case .move(let by): p.popups.move(by)
            case .choose: p.popups.choose()
            case .remove: p.popups.remove()
            case .clearAll: p.popups.clearAll()
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
        if alt && !b.hasAlt {
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
        let uuid = ncRecordUUID(noteID: b.id)
        if uuid != nil { markHandled(b.id) }
        if b.meetingStart != nil { finishMeeting(b) }
        if b.id == duplicateNoticeID {
            toggleSettings(.debug)
        } else if let target = alt ? b.altLink : b.link {
            // Any process in the session can post, sandboxed ones too: a file: link would launch whatever it points at.
            let opened = URL(string: target).map { $0.scheme != nil && !$0.isFileURL && NSWorkspace.shared.open($0) } ?? false
            if !opened { logNote(b, "link failed") }
        } else if let owner = pluginNoteOwner(b.id, plugins: model.plugins.map(\.folder)) {
            pluginHost.send(plugin: owner.plugin, alt ? .notifyAlt : .notifyOpen, id: owner.id)  // the plugin knows where it leads
        } else if model.config.openOriginal, let uuid {
            // The original knows the exact chat or thread: its banner while up, else its row in the panel. Without it, the app.
            let app = b.app
            NotificationClick.press(uuid: uuid, app: app, via: banners) { [weak self] pressed in
                self?.banners.closeParked(uuid: uuid)
                guard !pressed else { return }
                if let app { Self.openApp(app) } else { log("nc click: \(uuid.prefix(8)) not opened, its app is unknown") }
            }
        } else if let app = b.app {
            if let uuid { banners.closeParked(uuid: uuid) }
            Self.openApp(app)
        }
        notesChanged()
    }

    private static func openApp(_ app: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func dismissBanner() {
        guard let b = notes.banner else { return }
        // Heard, so a swipe or a key that took one by accident does not go unnoticed (Greg).
        if model.config.notificationSounds { play(.dismiss) }
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
        forget(b.id)
        notesChanged()
    }

    /// Shows what the store holds and arms one timer for the next moment it has work
    /// (banner expiry or a snooze coming back).
    private func notesChanged() {
        // The tap decides on its own thread, from these two values.
        chords.bannerUp = notes.banner != nil
        chords.queued = notes.waiting > 0
        syncPause()  // a banner that comes while the leader is active stands still from the start
        // Heard when it enters the stack, on screen or waiting, whatever let it in. An armageddon plays its own.
        for n in notes.takeSounds() where n.level != .armageddon { play(n) }
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
                        hints: noAltBanner == b.id ? ChordHints(snoozeMinutes: nil, note: "No second action")
                            : chords.hints ?? (island.hovered ? chords.hoverHints : nil),
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
        for r in notes.stacked where !was.contains(r.id) { logNote(r, r.reminder ? "reminder" : "in from the queue") }
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
        let pill = notePlugin(n).flatMap { f in model.pluginPills.contains { $0.plugin == f } ? "plugin:\(f)" : nil }
        let key = n.app.flatMap { onBar.contains($0) ? $0 : nil } ?? pill ?? "bell"
        guard let target = panel.iconRect(key),
              let image = n.app.flatMap(AppIcons.icon(for:)) ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)
        else { return }
        flying += 1
        island.fadeNextHide = true
        FlyToIcon.run(image: image, from: island.avatarRect, to: target, pace: island.pace) { [weak self] in
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

    /// The config is the user's choice, so it wins over what Sparkle kept in the defaults. Set before the first start,
    /// or a Homebrew install would check once before it got the chance to say no.
    private func applyUpdates(_ c: GzymsConfig) {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let on = automaticUpdates(chosen: c.updatesAutomatic, homebrew: homebrew)
        if updater.updater.automaticallyChecksForUpdates != on { updater.updater.automaticallyChecksForUpdates = on }
        if !updaterStarted { updaterStarted = true; updater.startUpdater() }
    }

    /// Once a day, and a minute after start: rotate the log, and let a Homebrew install hear about a new version.
    private func startDaily() {
        updateFound.found = { [weak self] v in self?.newVersionFound(v) }
        let t = Timer(fire: Date(timeIntervalSinceNow: 60), interval: 86_400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.daily() }
        }
        RunLoop.main.add(t, forMode: .common)
        dailyTimer = t
    }

    private func daily() {
        LogFile.rotateIfBig()
        // Sparkle checks by itself when it is on; this only reads the appcast and installs nothing.
        guard homebrew, updaterStarted, !updater.updater.automaticallyChecksForUpdates else { return }
        updater.updater.checkForUpdateInformation()
    }

    private func newVersionFound(_ version: String) {
        guard homebrew, !updater.updater.automaticallyChecksForUpdates, isNewer(version, than: gzymsVersion) else { return }
        model.newVersion = version
        let key = "toldUpdate"
        guard shouldTellUpdate(found: version, current: gzymsVersion, told: UserDefaults.standard.string(forKey: key)) else { return }
        UserDefaults.standard.set(version, forKey: key)
        log("update: \(version) is out, told once")
        post(GzymsNotification(id: "update-\(version)", app: nil, level: .info, title: "Gzyms \(version) is out", subtitle: nil,
                               body: "Update with brew upgrade gzyms.", link: releaseURL(version: version), altLink: nil, sound: nil, at: Date()))
    }

    private func loadConfig() {
        let load = GzymsCore.loadConfig(toml: try? String(contentsOf: ThemeCommand.configFile, encoding: .utf8))
        if !load.broken { LoginItem.sync(wanted: load.config.startAtLogin) }  // before the config lands, so General draws the new state
        model.config = load.config
        applyUpdates(load.config)
        chords.micShortcut = load.config.micShortcut
        chords.configureNav(leader: load.config.leader, idleTimeout: load.config.idleTimeout, hintChars: load.config.hintChars,
                            verbs: load.config.verbs)
        meetingClock.points = load.config.meetingPoints
        calendar?.setSkip(load.config.calendarSkip)
        if load.config.hiddenWidgets.contains(.music) { music.stop() } else { music.start() }
        if load.config.browserMedia && !load.config.hiddenWidgets.contains(.music) { mediaServer.start() } else { mediaServer.stop() }
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
        notes.priority = load.config.priority
        applyNotificationSources()
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
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.animate = c.animates(reduceMotion: reduce)
        island.entry = c.entry(reduceMotion: reduce)
        island.pace = c.animationSpeed.factor
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
        if now.first(where: { $0.grant == .accessibility })?.granted == true { chords.start(); if model.config.bannerAX { banners.start() } }
        // Taken away while running: stop parking. Without the grant the parked window cannot be moved back either.
        else if banners.attached { banners.stop() }
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
        if r.seen != seen { saveMessagesSeen(r.seen) }
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
        model.onLogo = { [weak self] in self?.toggleSettings(nil) }
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

    /// Marks each app whose macOS notification settings keep opening the original from working (Settings → Apps).
    /// The file opens only with Full Disk Access, so it is read off the main thread.
    private func refreshAppWarnings() {
        let ids = model.seenApps.map(\.id), on = model.config.openOriginal || model.config.bannerAX
        DispatchQueue.global(qos: .utility).async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let prefs = try? Data(contentsOf: home.appending(path: "Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist"))
            let hotkeys = try? Data(contentsOf: home.appending(path: "Library/Preferences/com.apple.symbolichotkeys.plist"))
            let settings = on ? prefs.flatMap { ncAppSettings(prefs: $0, apps: ids, hotkeys: hotkeys) } ?? [:] : [:]
            DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                let apps = self.model.seenApps.map { a in var a = a; a.mac = settings[a.id]; return a }
                if apps != self.model.seenApps {
                    self.model.seenApps = apps
                    log("nc settings: \(settings.values.filter { $0.warning != nil }.count) apps set up wrong")
                }
                self.checkAppSetup()
            } }
        }
    }

    /// The mirror in Settings → Apps follows each click in System Settings. When System Settings quits, HyprMac
    /// moves to another app's workspace, so Settings comes back to the front (Greg, 2026-11-04).
    private func watchSystemSettings() {
        guard systemSettingsWatch == nil else { return }
        let started = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                // shortcut: a System Settings left open stops being watched after 15 min; reopening the page starts it again.
                if Date().timeIntervalSince(started) > 900 { self?.stopWatchingSystemSettings() } else { self?.refreshAppWarnings() }
            }
        }
        let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
            guard (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.apple.systempreferences" else { return }
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.systemSettingsWatch != nil else { return }
                self.stopWatchingSystemSettings()
                if self.model.appSetup != nil { self.finishAppSetup(); return }
                self.refreshAppWarnings()
                guard self.settings.isVisible else { return }
                log("settings: back from System Settings")
                NSApp.activate()
                self.settings.makeKeyAndOrderFront(nil)
            }
        }
        systemSettingsWatch = (timer, observer)
        busy.start("system settings watch, every 1 s")
    }

    private func stopWatchingSystemSettings() {
        guard let w = systemSettingsWatch else { return }
        busy.stop("system settings watch, every 1 s")
        w.timer.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(w.observer)
        systemSettingsWatch = nil
    }

    /// One app's own page in System Settings → Notifications, watched while open.
    private func openAppPage(_ id: String) {
        settings.stepBack()
        // Mail's page does not open by its id (Greg, 2026-11-01): the list opens, Mail is one click from there.
        let page = id == "com.apple.mail" ? "" : "?id=\(id)"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension\(page)") { NSWorkspace.shared.open(url) }
        watchSystemSettings()
    }

    /// Settings → Apps, step by step: each app's page in turn, the helper beside it, the next one once macOS says so.
    private func startAppSetup(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        model.appSetup = (ids, 0)
        log("app setup: \(ids.count) apps")
        setupPanel.show(on: focusedScreen())
        openAppPage(ids[0])
    }

    private func checkAppSetup() {
        guard let s = model.appSetup, setupAdvance == nil,
              model.seenApps.first(where: { $0.id == s.queue[s.at] })?.mac?.pageDone == true else { return }
        let work = DispatchWorkItem { MainActor.assumeIsolated { [weak self] in
            guard let self, self.model.appSetup?.at == s.at else { return }
            self.nextSetupApp()
        } }
        setupAdvance = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Done or skipped: the next app's page, or the end.
    private func nextSetupApp() {
        setupAdvance?.cancel()
        setupAdvance = nil
        guard var s = model.appSetup else { return }
        s.at += 1
        guard s.at < s.queue.count else { finishAppSetup(); return }
        model.appSetup = s
        log("app setup: step \(s.at + 1) of \(s.queue.count)")
        openAppPage(s.queue[s.at])
        checkAppSetup()  // set up already, while an earlier one was open
    }

    /// The end, Stop, or System Settings quit: back to Settings → Apps.
    private func finishAppSetup() {
        setupAdvance?.cancel()
        setupAdvance = nil
        guard model.appSetup != nil else { return }
        model.appSetup = nil
        setupPanel.orderOut(nil)
        log("app setup: finished")
        refreshAppWarnings()
        guard settings.isVisible else { return }
        NSApp.activate()
        settings.makeKeyAndOrderFront(nil)
    }

    /// A tab opens on that tab (and stays open); no tab toggles.
    private func toggleSettings(_ tab: SettingsTab?) {
        if let tab { model.settingsTab = tab }
        refreshAppWarnings()
        if settingsKeyObserver == nil {  // back from System Settings: the warnings follow what was changed there
            settingsKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: settings, queue: .main) { _ in
                MainActor.assumeIsolated { [weak self] in self?.refreshAppWarnings() }
            }
        }
        log("settings: toggle (visible \(settings.isVisible), in front \(settings.isInFront))")
        if settings.isVisible {
            if tab == nil, settings.isInFront { settings.hide() } else { settings.makeKeyAndOrderFront(nil) }
            return
        }
        guard let screen = focusedScreen() else { return }
        settings.show(on: screen)
        if model.settingsTab == .permissions { checkGrants() }  // opened straight on it: the tab-change hook never fires
        log("settings: open \(model.settingsTab.rawValue)")
    }

    /// Leader, then space: the Settings tabs, the actions people look for, every theme and the notifications still on
    /// the lists, in one search.
    private func showPalette() {
        let a = settingsActions()
        var items = SettingsTab.allCases.map { t in
            PaletteItem(id: "tab:\(t.rawValue)", title: t.title, kind: "Settings", words: t.keywords) { [weak self] in self?.toggleSettings(t) }
        }
        func action(_ title: String, _ words: String, _ run: @escaping () -> Void) {
            items.append(PaletteItem(id: title, title: title, kind: "Action", words: words, run: run))
        }
        action("Do Not Disturb on", "dnd quiet silence") { [weak self] in self?.setDND(.distantFuture) }
        action("Do Not Disturb off", "dnd") { [weak self] in self?.setDND(nil) }
        action("Test banner", "notification try demo") { [weak self] in
            self?.post(GzymsNotification(id: "palette-test-\(Int(Date().timeIntervalSince1970))", app: nil, level: .info, title: "Gzyms test",
                                         subtitle: nil, body: "This is how a banner looks.", link: nil, altLink: nil, sound: nil, at: Date()))
        }
        action("Usage HUD", "cpu memory stats", a.showHUD)
        action("Report a problem", "bug zip issue") { _ = a.report() }
        if a.canCheckForUpdates { action("Check for updates", "update upgrade version", a.checkForUpdates) }
        action("What's new", "changes release notes") { [weak self] in
            if let n = newestWhatsNew() { self?.showMessage(.whatsNew(version: n.version, lines: n.lines)) }
        }
        action("Open config.toml", "config file edit", a.revealConfig)
        action("Open the event log", "log debug", a.openLog)
        action("Restart Gzyms", "reload relaunch", a.restart)
        action("Quit Gzyms", "exit close", a.quit)
        items += Theme.all.map { t in
            PaletteItem(id: "theme:\(t.name)", title: "Theme \(t.name)", kind: "Theme", words: "colors colours look") { [weak self] in
                self?.writeSetting("theme", .string(t.name), .table([]))
            }
        }
        // A notification is found by its app, title and text; Enter opens it like a click, ⌘Enter takes its second action.
        let names = Dictionary(model.seenApps.map { ($0.id, $0.name) }) { a, _ in a }
        for n in notes.inboxes.values.joined().sorted(by: { $0.at > $1.at }) {
            let app = n.app.map { names[$0] ?? seenApp($0)?.name ?? $0 } ?? "Notification"
            let alt: (() -> Void)? = n.altLink == nil ? nil : { [weak self] in self?.open(n.id, alt: true) }
            items.append(PaletteItem(id: "note:\(n.id)", title: n.title, kind: app, words: [app, n.subtitle, n.body].compactMap { $0 }.joined(separator: " "),
                                     alt: alt) { [weak self] in self?.open(n.id) })
        }
        palette.show(items: items, extra: { [weak self] q in
            guard let m = paletteDNDMinutes(q) else { return [] }
            let span = m % 60 == 0 ? "\(m / 60) h" : m > 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
            return [PaletteItem(id: "dnd:\(m)", title: "Do Not Disturb for \(span)", kind: "Action") { self?.setDND(Date() + Double(m) * 60) }]
        }, on: focusedScreen())
        log("palette: open")
    }

    private func settingsActions() -> SettingsActions {
        var a = SettingsActions { [weak self] key, value, table in self?.writeSetting(key, value, table) }
        a.recording = { [weak self] on in self?.chords.paused = on; self?.settings.recording = on }
        a.hacks = { [weak self] in self?.hacksState() ?? HacksState() }
        a.restartNotificationCenter = { [weak self] in self?.restartNC(reason: "Settings button", auto: false) }
        a.quitApp = { id in NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() } }
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
            do { try installCatalogPlugin(in: pluginHost.dir, c); log("plugin \(name): added") }
            catch { log("plugin \(name): could not add: \((error as? NotifyArgsError)?.message ?? error.localizedDescription)") }
        }
        a.installPlugin = { [weak self] url in self?.installPluginFolder(url) }
        a.updatePlugin = { [weak self] folder in self?.pluginHost.replaceFromCatalog(folder) }
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
        a.restart = {
            let p = Process()
            switch restartRoute(agentProgram: DevAgent.program, me: DevAgent.me) {
            case .kickstart:  // launchd starts it again; a plain quit would stay quit now that KeepAlive only covers crashes
                p.executableURL = URL(filePath: "/bin/launchctl")
                p.arguments = ["kickstart", "-k", "gui/\(getuid())/dev.gzyms"]
                do { try p.run() } catch { log("restart: \(error)") }
            case .relaunch:  // the shell has its own process group, so it outlives this process
                p.executableURL = URL(filePath: "/bin/sh")
                p.arguments = relaunchArguments(pid: getpid(), bundle: Bundle.main.bundlePath)
                do { try p.run(); log("restart: relaunching"); NSApp.terminate(nil) } catch { log("restart: \(error)") }
            }
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
            if let zip {
                self?.settings.hide()  // Finder and the page are what you look at now
                NSWorkspace.shared.activateFileViewerSelecting([zip])
                // 404 until Discussions are on in the repo.
                if let url = URL(string: "https://github.com/zalewskigrzegorz/gzyms/discussions/new?category=problems") { NSWorkspace.shared.open(url) }
            }
            return zip
        }
        a.loginItem = { LoginItem.dev ? nil : LoginItem.status }
        a.openLoginItems = { [weak self] in
            self?.settings.stepBack()
            LoginItem.openSettings()
        }
        a.version = gzymsVersion
        a.canCheckForUpdates = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        a.homebrew = homebrew
        a.newVersion = { [weak self] in self?.model.newVersion }
        a.checkForUpdates = { [weak self] in
            self?.settings.stepBack()  // Sparkle's window must come over the floating panel
            self?.updater.checkForUpdates(nil)
        }
        a.quit = { NSApp.terminate(nil) }
        a.openURL = { [weak self] s in
            self?.settings.hide()  // the page is what you look at now; a panel left behind kept the CPU busy (Greg)
            if let url = URL(string: s) { NSWorkspace.shared.open(url) }
        }
        a.requestFeature = { [weak self] in
            self?.settings.hide()
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
        a.openAppNotifications = { [weak self] id in self?.openAppPage(id) }
        a.duplicates = { [weak self] in
            guard let self else { return DuplicatesState() }
            let seen = messagesSeen()
            return DuplicatesState(groups: seen.duplicateGroups ?? [], warningsOn: seen.duplicatesOff != true)
        }
        a.setDuplicateWarnings = { [weak self] on in self?.setDuplicateWarnings(on) }
        a.forgetDuplicates = { [weak self] apps in self?.forgetDuplicates(apps) }
        a.setUpApps = { [weak self] ids in self?.startAppSetup(ids) }
        a.forgetApp = { [weak self] id in self?.forget(app: id) }
        a.openNotificationSettings = { [weak self] in
            self?.settings.stepBack()
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
            self?.watchSystemSettings()
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
        pluginHost.onItems = { [weak self] pills in
            guard let self, model.pluginPills != pills else { return }
            model.pluginPills = pills
            let gone = goneRowNotes(notes.inboxes, pills: pills)
            guard !gone.isEmpty else { return }
            for id in gone { notes.remove(id, now: ProcessInfo.processInfo.systemUptime) }
            log("plugins: \(gone.count) notifications left with their rows")
            notesChanged()
        }
        pluginHost.onStatus = { [weak self] s in if self?.model.plugins != s { self?.model.plugins = s } }
        pluginHost.onNotify = { [weak self] n in self?.post(n) }
        model.onPluginEvent = { [weak self] plugin, e, id in self?.pluginHost.send(plugin: plugin, e, id: id) }
        pluginHost.start(disabled: disabled, options: options)
        // Plugins get EOF and a SIGTERM when Gzyms quits, so none outlives it.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pluginHost.stopAll() }
        }
    }

    // MARK: - `gzyms debug`

    /// The CLI asks, the bar answers into a file named by the request's id: this process holds the grants.
    private func answerDebug(_ message: String?) {
        guard let message, let (id, topics) = debugRequestParts(message) else { return }
        let dir = DebugCommand.dir, fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix("debug-") && f.hasSuffix(".json") {
            let url = dir.appendingPathComponent(f)
            if let m = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, Date().timeIntervalSince(m) > 60 { try? fm.removeItem(at: url) }
        }
        let file = DebugCommand.replyFile(id)
        guard topics.contains("cpu") else { answerDebug(topics, into: file); return }
        cpuDebug { [weak self] cpu in
            let rest = topics.filter { $0 != "cpu" }
            if rest.isEmpty { try? cpu.wire().write(to: file, options: .atomic) } else { self?.answerDebug(rest, into: file, after: cpu) }
        }
    }

    /// `gzyms debug cpu`: the process's CPU, main run loop wakeups and panel rebuilds over `debugCPUWindow`, then
    /// who is signed into `busy` and which windows are hidden, covered or on screen.
    private func cpuDebug(done: @escaping @MainActor (DebugReport) -> Void) {
        func cpuSeconds() -> Double {
            var u = rusage()
            getrusage(RUSAGE_SELF, &u)
            return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
        }
        final class Count: @unchecked Sendable { var n = 0 }  // touched on main only
        let wakeups = Count()
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, 0) { _, _ in wakeups.n += 1 }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        let cpu0 = cpuSeconds(), t0 = ProcessInfo.processInfo.systemUptime, rebuilds0 = rebuilds
        DispatchQueue.main.asyncAfter(deadline: .now() + debugCPUWindow) {
            MainActor.assumeIsolated { [weak self] in
                CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
                guard let self else { return }
                let windows = NSApp.windows.compactMap { w -> (name: String, state: String)? in
                    let name = String(describing: type(of: w))
                    guard !name.hasPrefix("NS"), !name.hasPrefix("_") else { return nil }  // AppKit's own: menus, status items
                    return (name, !w.isVisible ? "hidden" : w.occlusionState.contains(.visible) ? "on screen" : "covered")
                }
                done(debugCPUReport(cpuSeconds: cpuSeconds() - cpu0, wall: ProcessInfo.processInfo.systemUptime - t0, wakeups: wakeups.n,
                                    rebuilds: rebuilds - rebuilds0, rebuildsTotal: rebuilds, busy: busy.names, windows: windows))
            }
        }
    }

    private func answerDebug(_ topics: [String], into file: URL, after first: DebugReport = DebugReport()) {
        let wantKeys = topics.contains("keys")
        guard topics.contains("notifications") else {
            var r = first
            r.add(keysDebug())
            try? r.wire().write(to: file, options: .atomic)
            return
        }
        let ids = model.seenApps.map(\.id)
        banners.debug { [weak self] b in
            // Read fresh, whatever Settings last showed: this is the answer to "what does Gzyms read from macOS".
            DispatchQueue.global(qos: .utility).async {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let prefs = try? Data(contentsOf: home.appending(path: "Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist"))
                let hotkeys = try? Data(contentsOf: home.appending(path: "Library/Preferences/com.apple.symbolichotkeys.plist"))
                let macOS = prefs.flatMap { ncAppSettings(prefs: $0, apps: ids, hotkeys: hotkeys) }
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    guard let self else { return }
                    var r = first
                    r.add(self.notificationsDebug(b, macOS: macOS))
                    if wantKeys { r.add(self.keysDebug()) }
                    try? r.wire().write(to: file, options: .atomic)
                } }
            }
        }
    }

    private func notificationsDebug(_ b: BannerSource.Debug, macOS: [String: NCAppSettings]?) -> DebugReport {
        var r = DebugReport()
        let c = model.config
        r.add("config.banner_ax", c.bannerAX)
        r.add("config.open_original", c.openOriginal)
        r.add("config.signal", c.signal)
        r.add("config.nc_auto_restart", c.ncAutoRestart)
        r.add("grant.accessibility", AXIsProcessTrusted())
        r.add("grant.full_disk_access", NotificationCenterSource.hasAccess())
        r.add("observer.running", b.running)
        r.add("observer.attached", banners.attached)
        r.add("observer.attach_tries", String(b.attachTries))
        let ncNow = NSRunningApplication.runningApplications(withBundleIdentifier: NCAX.bundleID).first?.processIdentifier
        r.add("notification_center.pid", ncNow.map(String.init) ?? "not running")
        r.add("notification_center.pid_observed", b.ncPid.map(String.init) ?? "none")
        r.add("notification_center.panel_open", b.panelOpen.map { $0 ? "yes" : "no" } ?? "unknown")
        r.add("host_window.parked", b.hostParked.map { $0 ? "yes" : "no" } ?? "no host window found")
        r.add("host_window.held_by_gzyms", b.heldByGzyms)
        r.add("banners.parked_now", String(b.live))
        r.add("click.in_progress", b.pressing)
        if let l = lastShown { r.add("last_banner", "\(l.app ?? "unknown app"), \(debugAgo(l.at)), via \(l.path)") } else { r.add("last_banner", "none since start") }
        r.add("last_ax_read", debugAgo(banners.lastBanner))
        r.add("last_delivery_signal", debugAgo(lastSignal))
        let now = ProcessInfo.processInfo.systemUptime
        r.add("guard.signals_without_banner", String(bannerGuard.signals))
        r.add("guard.first_signal", bannerGuard.firstSignal.map { "\(Int(now - $0)) s ago" } ?? "none")
        r.add("guard.warns", bannerGuard.warns)
        r.add("guard.no_banners_flag", noBanners)
        r.add("nc_restart.count", String(ncRestart.count))
        r.add("nc_restart.last", debugAgo(ncRestartedAt))
        r.add("nc_restart.awaiting_banner", ncRestart.stillHung)
        r.add("nc_restart.gave_up", ncRestart.stillHung && noBanners)
        r.add("dnd", notes.dnd != nil)
        r.add("notificationnanny.running", !NSRunningApplication.runningApplications(withBundleIdentifier: "com.notificationnanny.app").isEmpty)
        r.add("macos.globe_n_shortcut", macOS?.values.contains { $0.shortcutOff } == true ? "off" : "on")
        guard let macOS else { r.add("apps", "macOS notification settings could not be read"); return r }
        for a in model.seenApps { r.add("app.\(a.id)", macOS[a.id]?.debugLine ?? "not in macOS's list") }
        return r
    }

    private func keysDebug() -> DebugReport {
        var r = DebugReport()
        let t = chords.debug
        let now = ProcessInfo.processInfo.systemUptime
        r.add("grant.accessibility", AXIsProcessTrusted())
        r.add("tap.created", t.made)
        r.add("tap.enabled", t.enabled.map { $0 ? "yes" : "no" } ?? "no tap")
        r.add("tap.disabled_by_macos", t.disabledCount == 0 ? "never since start"
              : "\(t.disabledCount) since start, last by \(t.lastDisabled ?? "?") \(t.lastDisabledUptime.map { "\(Int(now - $0)) s ago" } ?? "")")
        let secure = IsSecureEventInputEnabled()
        r.add("secure_input", secure)
        if secure {
            r.add("secure_input.owner", secureInputOwner() ?? "unknown")
            r.add("secure_input.held_for", secureSince.map { "\(Int(now - $0)) s" } ?? "unknown")
        }
        r.add("leader", t.leader ?? "none")
        r.add("leader.held", t.leaderHeld)
        r.add("mode.on", t.modeOn)
        r.add("mode.popup", t.popup ?? "none")
        r.add("mode.paused_by_recorder", t.paused)
        r.add("banner.up", t.bannerUp)
        r.add("banner.hovered", t.hovered)
        r.add("armageddon.up", t.armageddon)
        r.add("frontmost_app", NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")
        r.add("gzyms_key_window", NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none")
        return r
    }

    /// Who holds Secure Keyboard Entry: the session's `kCGSSessionSecureInputPID`, as a process name.
    private func secureInputOwner() -> String? {
        guard IsSecureEventInputEnabled(), let d = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = d["kCGSSessionSecureInputPID"] as? Int else { return nil }
        var buf = [CChar](repeating: 0, count: 256)
        let name = NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName ?? (proc_name(pid_t(pid), &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "?")
        return "\(name) (pid \(pid))"
    }

    private func hacksState() -> HacksState {
        var h = HacksState()
        let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        for browser in geckoBrowsers {
            let dir = support.appending(path: "\(browser)/Profiles")
            for p in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
                guard let js = try? String(contentsOf: dir.appending(path: "\(p)/prefs.js"), encoding: .utf8) else { continue }
                h.profiles.append(.init(browser: browser, name: String(p.split(separator: ".").last ?? ""), keysOff: mediaKeysOff(prefsJS: js)))
            }
        }
        h.musicAppRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        h.serverListening = mediaServer.listening
        h.tabs = model.tabs.count
        h.reader = music.reader
        h.lastSignal = lastSignal
        h.bannerAXOn = banners.attached
        h.lastBanner = banners.lastBanner
        h.nannyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.notificationnanny.app").isEmpty
        h.noBanners = noBanners
        h.ncRestarts = ncRestart.count
        h.ncLastRestart = ncRestartedAt
        h.ncStillHung = ncRestart.stillHung && noBanners
        return h
    }

    private func musicChanged(_ line: NowPlayingLine) {
        switch line {
        case .nothing: if model.nowPlaying != nil { model.nowPlaying = nil }
        case .item(let np): if model.nowPlaying != np { model.nowPlaying = np }
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

    /// Off the Apps list until it sends something again.
    private func forget(app id: String) {
        model.seenApps.removeAll { $0.id == id }
        saveSeenApps()
        for key in ["banner", "sound", "count", "level", "phone", "skip"] { writeSetting(key, nil, .table(["notifications", "apps", id])) }
        log("settings: \(id) removed from the list")
    }

    private func saveSeenApps() {
        try? FileManager.default.createDirectory(at: seenAppsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(model.seenApps.map(\.id)).write(to: seenAppsFile, options: .atomic)
    }

    /// The Notifications tab lists every app that ever sent something. Kept outside the config folder (not a setting).
    private func remember(_ app: String) {
        guard !model.seenApps.contains(where: { $0.id == app }), let s = seenApp(app) else { return }
        model.seenApps.append(s)
        saveSeenApps()
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

/// What Sparkle's informational check found (`checkForUpdateInformation`). Sparkle holds its delegate weakly.
@MainActor
final class UpdateFound: NSObject, @preconcurrency SPUUpdaterDelegate {
    var found: (String) -> Void = { _ in }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { found(item.displayVersionString) }
}
