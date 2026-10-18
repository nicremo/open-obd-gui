import SwiftUI

/// Section of the timing sheet: a strong hairline on top, heading, optional description, status slot
/// on the right, thin progress bar on the rule while loading. No box around the content.
struct Panel<Accessory: View, Content: View>: View {
    let title: String
    var subtitle: String?
    var info: String?
    var isLoading = false
    var padding: CGFloat = Spacing.l
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.obdTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .help(title)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle).font(.obdCaption).foregroundStyle(Palette.textSecondary)
                    }
                }
                if let info {
                    Image(systemName: "info.circle")
                        .font(.obdCaption)
                        .foregroundStyle(Palette.textTertiary)
                        .help(info)
                        .accessibilityLabel("Beschreibung: \(info)")
                }
                Spacer(minLength: Spacing.s)
                accessory
            }
            content
        }
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairlineStrong).frame(height: 1) }
        .overlay(alignment: .top) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .tint(Palette.live)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension Panel where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, info: String? = nil, isLoading: Bool = false, padding: CGFloat = Spacing.l,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.isLoading = isLoading
        self.padding = padding
        accessory = EmptyView()
        self.content = content()
    }
}

/// Label on the left, value on the right. Technical values use monospace and can be selected.
struct KeyValueRow: Identifiable {
    let label: String
    let value: String
    var mono = false
    var note: String?

    var id: String { label }
}

struct KeyValueGrid: View {
    let rows: [KeyValueRow]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.s) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.label)
                        .font(.obdLabel)
                        .foregroundStyle(Palette.textSecondary)
                        .gridColumnAlignment(.leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.value)
                            .font(row.mono ? .obdMono : .obdBody)
                            .foregroundStyle(Palette.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = row.note {
                            Text(note).font(.obdCaption).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

/// Single choice filter with counts, drawn as the native segmented control.
struct FilterChipBar<Option: Hashable>: View {
    let options: [(option: Option, title: String, count: Int?)]
    @Binding var selection: Option

    var body: some View {
        Picker("Filter", selection: $selection) {
            ForEach(options, id: \.option) { item in
                Text(item.count.map { "\(item.title) \($0)" } ?? item.title).tag(item.option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
