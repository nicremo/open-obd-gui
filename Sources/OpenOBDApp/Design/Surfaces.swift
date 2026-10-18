import SwiftUI

/// Title and optional subtitle above a group.
struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.obdTitle).foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.obdBody).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Scrollable page with consistent margins and a header.
struct ScreenScaffold<Accessory: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 1200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Decided by the measured width, not by ViewThatFits: measuring a horizontal scroll view
                // flipped the choice on every pass at the boundary and the split view never settled.
                if width >= 760 {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                        heading
                        Spacer(minLength: Spacing.l)
                        accessory
                    }
                } else {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        heading
                        accessory
                    }
                }
                content
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(.obdHero).foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.obdBody).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension ScreenScaffold where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

/// Calm empty state with a symbol and one sentence.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = Palette.textSecondary

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(tint)
            Text(title).font(.obdTitle).foregroundStyle(Palette.textPrimary)
            Text(message)
                .font(.obdBody)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}
