import GzymsCore
import SwiftUI

/// A message from Gzyms itself, not from an app: the cat and "From Gzyms" on top, so it never reads as a banner.
/// Used for what is new after an update and for a macOS Gzyms was not tested on.
public struct GzymsMessageView: View {
    public struct Action {
        let title: String
        let run: () -> Void
        public init(_ title: String, _ run: @escaping () -> Void) { self.title = title; self.run = run }
    }

    let title: String
    let lines: [String]
    let actions: [Action]
    let close: () -> Void
    @Environment(\.theme) private var theme

    public init(title: String, lines: [String], actions: [Action] = [], close: @escaping () -> Void) {
        self.title = title; self.lines = lines; self.actions = actions; self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                GzymsLogo().frame(width: 34, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("From Gzyms").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme[\.mauve])
                    Text(title).font(.system(size: 15, weight: .semibold))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(theme[\.sky])
                        Text((try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                            ?? AttributedString(line)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                ForEach(actions, id: \.title) { a in Button(a.title, action: a.run).buttonStyle(MessageButton(primary: false)) }
                Button("Got it", action: close).keyboardShortcut(.defaultAction).buttonStyle(MessageButton(primary: true))
            }
        }
        .padding(18)
        .frame(width: 460)
        .foregroundStyle(theme[\.text])
        .background(theme[\.base])
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme[\.mauve], lineWidth: 1))
    }
}

/// Buttons in the theme's colours, not macOS grey and blue: the main one in mauve.
private struct MessageButton: ButtonStyle {
    let primary: Bool
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? theme[\.base] : theme[\.text])
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(primary ? theme[\.mauve] : theme[\.surface]))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
