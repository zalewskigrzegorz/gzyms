import AppKit
import EventKit
import GzymsCore

/// Meetings with a video link from the calendars macOS knows (Internet Accounts), via EventKit.
/// Reads the next 12 hours on its own queue: when the calendar changes, every 5 min, and after wake.
final class CalendarSource: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.gzyms.calendar")
    private let store = EKEventStore()
    private let deliver: @MainActor ([Meeting], [CalendarInfo]) -> Void
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var skip: Set<String> = []  // touched only on `queue`

    init(deliver: @escaping @MainActor ([Meeting], [CalendarInfo]) -> Void) { self.deliver = deliver }

    /// Calendars to leave out (`CalendarInfo.key`); reads again when it changes.
    func setSkip(_ s: Set<String>) {
        queue.async { guard s != self.skip else { return }; self.skip = s; self.read() }
    }

    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Asks for access the first time (the system prompt), then reads.
    func start() {
        let status = EKEventStore.authorizationStatus(for: .event)
        log("calendar: access status \(status.rawValue) (0 not asked, 1 restricted, 2 denied, 3 full, 4 write only)")
        if status == .notDetermined {
            store.requestFullAccessToEvents { granted, _ in
                log("calendar: access \(granted ? "granted" : "denied")")
                self.queue.async { self.read() }
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in self?.read() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) {
            [weak self] _ in self?.queue.async { [weak self] in self?.read() }
        })
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 300, leeway: .seconds(10))
        t.setEventHandler { [weak self] in self?.read() }
        t.resume()
        timer = t
        log("calendar: on")
    }

    func stop() {
        timer?.cancel(); timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
    }

    private func read() {
        guard Self.authorized else { return }
        let now = Date()
        let all = store.calendars(for: .event)
        let info = all.map { CalendarInfo(title: $0.title, account: $0.source?.title ?? "") }
        let used = zip(all, info).filter { !skip.contains($1.key) }.map(\.0)
        // From an hour back (a meeting already running still reminds), 12 hours ahead.
        // An empty list would mean "every calendar" to EventKit, so all skipped reads nothing.
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(12 * 3600), calendars: used)
        guard !used.isEmpty else {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.deliver([], info) } }
            return
        }
        let meetings: [Meeting] = store.events(matching: predicate).compactMap { e in
            guard !e.isAllDay, e.status != .canceled,
                  e.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined,
                  let link = videoLink(url: e.url?.absoluteString, location: e.location, notes: e.notes) else { return nil }
            let start = e.startDate.timeIntervalSince1970
            let id = (e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? UUID().uuidString) + "@\(Int(start))"
            return Meeting(id: id, title: e.title ?? "Meeting", start: start, end: e.endDate.timeIntervalSince1970, link: link)
        }
        let found = meetings
        DispatchQueue.main.async { MainActor.assumeIsolated { self.deliver(found, info) } }
    }
}
