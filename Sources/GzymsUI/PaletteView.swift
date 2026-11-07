import GzymsCore
import SwiftUI

/// One row of the command palette: a Settings tab, an action, a theme or a notification still on a list.
public struct PaletteItem: Identifiable {
    public let id: String
    public let title: String
    /// The grey word on the right: Settings, Action, Theme, or a notification's app.
    public let kind: String
    /// Searched along with the title.
    public let words: String
    public let run: () -> Void
    /// ⌘Enter: a notification's second action, as on its banner.
    public let alt: (() -> Void)?
    public init(id: String, title: String, kind: String, words: String = "", alt: (() -> Void)? = nil, run: @escaping () -> Void) {
        self.id = id; self.title = title; self.kind = kind; self.words = words; self.alt = alt; self.run = run
    }
}

extension SettingsTab {
    /// What the tab holds, so "leader" finds Shortcuts and "battery" finds General.
    public var keywords: String {
        switch self {
        case .general: "workspaces caffeine display awake battery config notch tiling aerospace spaces mission control"
        case .appearance: "look cpu chart device icons"
        case .animations: "motion animations reduce banner entry icon first drop notch unroll pop fade speed slow fast"
        case .themes: "theme colors colours"
        case .notifications: "banners levels armageddon sound dnd disturb phone pushover push"
        case .apps: "app rules banner count skip mute"
        case .modules: "order layout bar pills drag sides modules"
        case .plugins: "plugin add catalog make own"
        case .calendar: "meetings reminders calendars join"
        case .agents: "tuios claude coding agents"
        case .sounds: "sound audio chime"
        case .shortcuts: "keyboard leader keys verbs letters mic mute microphone menu hotkey"
        case .permissions: "grants accessibility full disk access privacy"
        case .hacks: "media keys music browser tabs instant notification center"
        case .debug: "anomaly hud usage log report problem bug"
        case .about: "version update tutorial website logo license changes"
        }
    }
}

/// What the palette shows: the typed query, the rows that fit it and the highlighted one.
@Observable @MainActor
public final class PaletteState {
    public var query = "" { didSet { selected = 0 } }
    public var selected = 0
    public var items: [PaletteItem] = []
    /// Rows made from the query itself ("dnd 1h").
    @ObservationIgnored public var extra: (String) -> [PaletteItem] = { _ in [] }
    public static let limit = 8

    public init() {}

    public var shown: [PaletteItem] { Array((extra(query) + paletteRank(query, items) { $0.title + " " + $0.words }).prefix(Self.limit)) }
    public var current: PaletteItem? { let s = shown; return s.indices.contains(selected) ? s[selected] : nil }
    public func move(_ by: Int) { selected = min(max(selected + by, 0), max(shown.count - 1, 0)) }
}

/// The command palette (leader, then space): a field and the rows that fit. The panel takes the arrows, Enter and Esc.
public struct PaletteView: View {
    @Bindable var state: PaletteState
    let run: (PaletteItem) -> Void
    /// The window follows the content's size as the list grows and shrinks.
    let resize: (CGSize) -> Void
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    public init(state: PaletteState, run: @escaping (PaletteItem) -> Void, resize: @escaping (CGSize) -> Void = { _ in }) {
        self.state = state; self.run = run; self.resize = resize
    }

    public var body: some View {
        let shown = state.shown
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search settings, actions and notifications", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .padding(.horizontal, 16).padding(.vertical, 13)
                .focused($focused)
            if !shown.isEmpty || !state.query.isEmpty {
                Rectangle().fill(theme[\.surface]).frame(height: 1)
                VStack(spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                        HStack {
                            Text(item.title).font(.system(size: 13, weight: i == state.selected ? .semibold : .regular))
                            Spacer()
                            if i == state.selected, item.alt != nil {
                                Text("⌘↩ second action").font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                            }
                            Text(item.kind).font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(i == state.selected ? theme[\.mauve].opacity(0.3) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { run(item) }
                    }
                    if shown.isEmpty {
                        Text("Nothing found").font(.system(size: 13)).foregroundStyle(theme[\.overlay])
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 560)
        .foregroundStyle(theme[\.text])
        .background(theme[\.base])
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme[\.mauve], lineWidth: 1))
        .onGeometryChange(for: CGSize.self, of: \.size, action: resize)
        .onAppear { focused = true }
    }
}
