import SwiftUI
import LoreAgentKit

/// Compact colour-facet control for the gallery filter bar. The popover holds
/// the full taxonomy: hue family (multi-membership) and tonal character.
struct ColorFilterControl: View {
    @Environment(LibraryStore.self) private var store
    @State private var presented = false
    @State private var triggerHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                presented.toggle()
            } label: {
                label
            }
            .buttonStyle(PointerPlainButtonStyle())
            .help(T("Filter by color family and tone"))

            if store.hasColorFilter {
                Button {
                    store.clearColorFilters()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PointerPlainButtonStyle())
                .help(T("Clear color filter"))
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, store.hasColorFilter ? 5 : 11)
        .frame(height: 32)
        .background(
            Capsule().fill(
                store.hasColorFilter
                    ? (triggerHovering ? Color(hex: 0x2B2622) : Theme.ink)
                    : (triggerHovering ? Theme.parchmentDeep : Theme.parchment)
            )
        )
        .overlay(
            Capsule().strokeBorder(store.hasColorFilter ? Color.clear : Theme.hairline, lineWidth: 1)
        )
        .contentShape(Capsule())
        .onHover { triggerHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: triggerHovering)
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            ColorFilterPopover()
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if let family = store.colorFamilyFilter {
                ColorFamilySwatch(family: family, size: 10)
            } else if store.hasColorFilter {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 9, weight: .semibold))
            } else {
                ColorFamilySwatch(family: .multicolor, size: 10)
            }

            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 7.5, weight: .bold))
                .opacity(0.55)
        }
        .foregroundStyle(store.hasColorFilter ? Color.white : Theme.inkSecondary)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var title: String {
        switch (store.colorFamilyFilter, store.toneFilter) {
        case let (family?, tone?):
            return "\(family.localizedTitle) · \(tone.localizedTitle)"
        case let (family?, nil):
            return family.localizedTitle
        case let (nil, tone?):
            return "\(T("Tone")) · \(tone.localizedTitle)"
        case (nil, nil):
            return T("Color")
        }
    }
}

private struct ColorFilterPopover: View {
    @Environment(LibraryStore.self) private var store

    private let familyColumns = [
        GridItem(.flexible(), spacing: 4, alignment: .leading),
        GridItem(.flexible(), spacing: 4, alignment: .leading),
        GridItem(.flexible(), spacing: 4, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: T("Color family"))

            LazyVGrid(columns: familyColumns, spacing: 3) {
                ForEach(LoreColorFamily.allCases, id: \.self) { family in
                    familyButton(family)
                }
            }

            Hairline()

            SectionLabel(text: T("Tone"))
            FlowLayout(spacing: 6, lineSpacing: 6) {
                toneChip(nil)
                ForEach(LoreColorTone.allCases, id: \.self) { tone in
                    toneChip(tone)
                }
            }

            if store.hasColorFilter {
                Hairline()
                Button {
                    store.clearColorFilters()
                } label: {
                    Text(T("Clear color filter"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PointerPlainButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(Theme.paper)
        .preferredColorScheme(.light)
    }

    private func familyButton(_ family: LoreColorFamily) -> some View {
        let selected = store.colorFamilyFilter == family
        let count = store.colorFamilyCount(family)
        return Button {
            store.setColorFamilyFilter(selected ? nil : family)
        } label: {
            HStack(spacing: 7) {
                ColorFamilySwatch(family: family, size: 10)
                Text(family.localizedTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 1)
                Text("\(count)")
                    .font(Theme.mono(9, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 7)
            .frame(height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Theme.hairline : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .menuRowHover(isSelected: selected)
        }
        .buttonStyle(PointerPlainButtonStyle())
        .disabled(count == 0)
        .opacity(count == 0 ? 0.42 : 1)
    }

    private func toneChip(_ tone: LoreColorTone?) -> some View {
        let selected = store.toneFilter == tone
        let count = tone.map { store.toneCount($0) } ?? store.scopeCounts.all
        let title = tone?.localizedTitle ?? T("Any tone")
        return ToneFilterChip(
            title: title,
            count: count,
            isSelected: selected,
            isEnabled: count > 0 || tone == nil
        ) {
            store.setToneFilter(tone)
        }
    }
}


private struct ToneFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(Theme.mono(9, weight: .medium))
                    .opacity(isSelected ? 0.6 : 0.5)
            }
            .foregroundStyle(isSelected ? Color.white : Theme.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(
                Capsule().fill(
                    isSelected
                        ? (hovering ? Color(hex: 0x2B2622) : Theme.ink)
                        : (hovering ? Theme.parchmentDeep : Theme.parchment)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.clear : (hovering ? Theme.ink.opacity(0.12) : Theme.hairline),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
