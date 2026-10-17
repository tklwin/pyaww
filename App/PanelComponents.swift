import SwiftUI

/// Building blocks for the menu bar popover (owner decision 2026-10-18: the
/// popover replaces both the plain NSMenu and the Settings window; card /
/// row pattern learned from vorssaint's menu panel).

/// A titled group of rows on a soft rounded card.
struct PanelCard<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String?
    let content: Content
    let accessory: Accessory

    init(title: String, systemImage: String? = nil,
         @ViewBuilder content: () -> Content,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
                accessory
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 9) {
                content
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }
}

extension PanelCard where Accessory == EmptyView {
    init(title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, content: content) { EmptyView() }
    }
}

/// One row: label (and optional caption) on the left, control on the right.
struct PanelRow<Control: View>: View {
    let title: String
    let caption: String?
    let control: Control

    init(_ title: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

extension PanelRow where Control == EmptyView {
    init(_ title: String, caption: String? = nil) {
        self.init(title, caption: caption) { EmptyView() }
    }
}

/// A read-only row: label left, value right — with a small spinner for a
/// still-loading value and an orange value when the reading needs
/// attention (the Model card's states).
struct PanelValueRow: View {
    let title: String
    let value: String
    var attention = false
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(value)
                    .font(.system(size: 12.5))
                    .foregroundStyle(attention ? Color.orange : Color.secondary)
            }
        }
    }
}

/// Permission state dot: green when granted, orange when it needs attention.
struct StatusDot: View {
    let ok: Bool

    var body: some View {
        Circle()
            .fill(ok ? Color.green : Color.orange)
            .frame(width: 7, height: 7)
    }
}
