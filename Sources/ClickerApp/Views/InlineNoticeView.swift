import SwiftUI

/// One line of news under the remote: a connection problem, a failed action,
/// a pending update. `MenuBarView` collects whichever apply and stacks them.
struct InlineNotice: Identifiable {
    enum Kind {
        /// Something went wrong (connection, a command the TV refused).
        case warning
        /// Neutral news.
        case info
        /// A new version of Clicker is ready to install.
        case update

        fileprivate var symbol: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle"
            case .update: return "arrow.down.circle.fill"
            }
        }

        fileprivate var tint: AnyShapeStyle {
            switch self {
            case .warning: return AnyShapeStyle(.orange)
            case .info: return AnyShapeStyle(.secondary)
            case .update: return AnyShapeStyle(.tint)
            }
        }
    }

    struct Action {
        /// Beside the message, the usual place, or under it at full width
        /// for a message that needs the room.
        enum Placement {
            case trailing
            case below
        }

        let title: String
        var placement: Placement = .trailing
        let perform: () -> Void
    }

    /// Stable per source, so a notice keeps its identity while others come and go.
    let id: String
    let kind: Kind
    let message: String
    var action: Action? = nil
}

struct InlineNoticeView: View {
    let notice: InlineNotice

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: notice.kind.symbol)
                    .foregroundStyle(notice.kind.tint)
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    // Wrap rather than truncate when the panel's height is pinned.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let action = notice.action, action.placement == .trailing {
                    Button(action.title, action: action.perform)
                        .controlSize(.small)
                }
            }
            if let action = notice.action, action.placement == .below {
                Button(action: action.perform) {
                    Text(action.title)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous))
    }
}
