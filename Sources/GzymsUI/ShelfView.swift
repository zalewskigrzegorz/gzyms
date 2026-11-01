import AppKit
import GzymsCore
import SwiftUI

public enum ShelfChange: Sendable { case add([URL]), remove([URL]) }

/// The file shelf: files dropped anywhere on the bar wait here. It shows only with files on it, or while a drag is
/// over the bar. Dragging the pill takes all of them out, the popup lists them one by one.
public struct ShelfView: View {
    let files: [URL]
    let small: Bool
    let dropping: Bool
    let onChange: (ShelfChange) -> Void
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(files: [URL], small: Bool, dropping: Bool, onChange: @escaping (ShelfChange) -> Void) {
        self.files = files; self.small = small; self.dropping = dropping; self.onChange = onChange
    }

    public var body: some View {
        HStack(spacing: small ? 3 : 4) {
            Image(systemName: files.isEmpty ? "tray.and.arrow.down" : "tray.full")
            if !files.isEmpty { Text("\(files.count)").monospacedDigit() }
        }
        .font(.system(size: small ? 10 : 11))
        .foregroundStyle(dropping ? theme[\.base] : theme[\.sky])
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(dropping ? theme[\.sky] : theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            FileDrag(urls: files, tip: files.isEmpty ? "Drop files here" : "Click to see them. Drag to take them all out.") {
                popups.binding("widget:shelf").wrappedValue.toggle()
            } onDropped: { onChange(.remove(files)) }
        }
        // Files moved or deleted outside the shelf leave it now, not when someone tries to drag them.
        .onChange(of: popups.open == "widget:shelf") { _, on in
            if on { onChange(.remove(files.filter { !FileManager.default.fileExists(atPath: $0.path) })) }
        }
        .popover(isPresented: popups.binding("widget:shelf"), arrowEdge: .bottom) {
            ShelfPopup(files: files, onChange: onChange).environment(\.theme, theme).environment(\.popups, popups)
        }
    }
}

public struct ShelfPopup: View {
    let files: [URL]
    let onChange: (ShelfChange) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.fileIcon) private var fileIcon
    public init(files: [URL], onChange: @escaping (ShelfChange) -> Void) { self.files = files; self.onChange = onChange }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(files.enumerated()), id: \.element) { i, url in
                HStack(spacing: 8) {
                    Image(nsImage: fileIcon(url.path)).resizable().frame(width: 20, height: 20)
                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "xmark").foregroundStyle(theme[\.overlay])
                        .contentShape(Rectangle())
                        .onTapGesture { onChange(.remove([url])) }
                        .help("Take it off the shelf. The file stays where it is.")
                }
                .overlay(alignment: .leading) {
                    // The row minus the ×: a click shows the file in Finder, a drag takes it out.
                    FileDrag(urls: [url], tip: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } onDropped: { onChange(.remove([url])) }
                        .padding(.trailing, 24)
                }
                .navRow(i, choose: { NSWorkspace.shared.activateFileViewerSelecting([url]) }, remove: { onChange(.remove([url])) })
            }
            Divider()
            Text("Drop a file in Finder to move it. Hold ⌥ to copy it.").font(.caption).foregroundStyle(theme[\.overlay])
            Button("Clear the shelf") { onChange(.remove(files)) }
        }
        .popupStyle(theme, width: 300)
    }
}

/// The place a dragged file goes: it hangs under the notch (or the bar) while any file is being dragged.
public struct ShelfDropZoneView: View {
    let topInset: CGFloat
    let onDrop: ([URL]) -> Void
    @State private var over = false
    @Environment(\.theme) private var theme
    public init(topInset: CGFloat, over: Bool = false, onDrop: @escaping ([URL]) -> Void) {
        self.topInset = topInset; self.onDrop = onDrop; _over = State(initialValue: over)
    }

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: over ? "tray.and.arrow.down.fill" : "tray.and.arrow.down").font(.system(size: 22))
            Text(over ? "Let go to keep it on the shelf" : "Drop here to keep it on the shelf").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(theme[\.sky])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme[\.sky].opacity(over ? 0.25 : 0), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme[\.sky], style: StrokeStyle(lineWidth: 1.5, dash: over ? [] : [5, 4])))
        .padding(10)
        .padding(.top, topInset)
        .background(topInset > 0 ? theme[\.island] : theme[\.base])
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            onDrop(files)
            return true
        } isTargeted: { over = $0 }
    }
}

/// Files dragged out with AppKit: SwiftUI's own drag never says whether, or how, the drop happened.
struct FileDrag: NSViewRepresentable {
    let urls: [URL]
    let tip: String
    let onClick: () -> Void
    let onDropped: () -> Void

    func makeNSView(context: Context) -> Source { Source() }
    func updateNSView(_ v: Source, context: Context) {
        v.urls = urls; v.onClick = onClick; v.onDropped = onDropped; v.toolTip = tip
    }

    final class Source: NSView, NSDraggingSource {
        var urls: [URL] = []
        var onClick = {}
        var onDropped = {}
        private var down: NSPoint?

        // The bar never becomes the active app: the first click has to count.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { down = event.locationInWindow }
        override func mouseUp(with event: NSEvent) {
            if down != nil { down = nil; onClick() }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = down, !urls.isEmpty, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 else { return }
            down = nil
            let at = convert(event.locationInWindow, from: nil)
            let items = urls.enumerated().map { i, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let offset = CGFloat(min(i, 4) * 4)
                item.setDraggingFrame(NSRect(x: at.x - 16 + offset, y: at.y - 16 - offset, width: 32, height: 32),
                                      contents: NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        // Finder moves on the same disk and copies to another one, ⌥ copies. Back onto the bar is no drop at all.
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .move, .generic] : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
            if !operation.isEmpty { onDropped() }
        }
    }
}
