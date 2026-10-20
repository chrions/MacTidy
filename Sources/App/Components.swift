import SwiftUI

/// Small outlined label, e.g. "Unused" or "Intel only".
struct Tag: View {
    let text: String
    var filled = false

    init(_ text: String, filled: Bool = false) {
        self.text = text
        self.filled = filled
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(filled ? Color(nsColor: .windowBackgroundColor) : .secondary)
            .background {
                if filled {
                    Capsule().fill(.primary)
                } else {
                    Capsule().strokeBorder(.tertiary, lineWidth: 1)
                }
            }
            .fixedSize()
    }
}

/// A labelled number in a row of facts.
struct Fact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium)).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

/// Wraps its children onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (view, point) in zip(subviews, result.points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points = [CGPoint]()
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: maxX, height: y + lineHeight), points)
    }
}

/// Grey levels for eras, oldest lightest; the current Mac is solid.
func eraShade(_ index: Int, count: Int) -> Double {
    guard count > 1 else { return 0.85 }
    return 0.15 + 0.7 * Double(index) / Double(count - 1)
}

enum Fmt {
    static func day(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    static func month(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.year().month(.defaultDigits))
    }

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return bytes == 0 ? "0" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func path(_ path: String) -> String { abbreviate(path, home: CatalogStore.home) }
}
