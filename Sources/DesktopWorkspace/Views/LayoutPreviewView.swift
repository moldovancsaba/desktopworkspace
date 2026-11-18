import SwiftUI

struct LayoutThumbnail: View {
    let preset: LayoutPreset
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.06))

                    ForEach(preset.slots) { slot in
                        let w = max(4, slot.rect.width * geo.size.width - 3)
                        let h = max(4, slot.rect.height * geo.size.height - 3)
                        let x = slot.rect.x * geo.size.width + 1.5
                        let y = slot.rect.y * geo.size.height + 1.5

                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.25), lineWidth: 1)
                            )
                            .frame(width: w, height: h)
                            .offset(x: x, y: y)
                    }
                }
            }
            .frame(width: 72, height: 46)

            Text(preset.name)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
        )
    }
}

struct InteractiveLayoutCanvas: View {
    let preset: LayoutPreset
    let slotApps: [Int: AppAssignment]
    let gap: Double
    let iconProvider: (AppAssignment) -> NSImage
    let onSelectSlot: (LayoutSlot) -> Void
    let onClearSlot: (LayoutSlot) -> Void

    var body: some View {
        GeometryReader { geo in
            let pad = max(2.0, gap * 0.4)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                ForEach(preset.slots) { slot in
                    let x = slot.rect.x * geo.size.width + pad
                    let y = slot.rect.y * geo.size.height + pad
                    let w = max(40, slot.rect.width * geo.size.width - pad * 2)
                    let h = max(40, slot.rect.height * geo.size.height - pad * 2)
                    let assigned = slotApps[slot.id]

                    SlotCardView(
                        slot: slot,
                        assignment: assigned,
                        icon: assigned.map(iconProvider),
                        onTap: { onSelectSlot(slot) },
                        onClear: { onClearSlot(slot) }
                    )
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)
                }
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
    }
}

private struct SlotCardView: View {
    let slot: LayoutSlot
    let assignment: AppAssignment?
    let icon: NSImage?
    let onTap: () -> Void
    let onClear: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(assignment != nil ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                assignment != nil ? Color.accentColor.opacity(isHovering ? 0.9 : 0.45) : Color.primary.opacity(isHovering ? 0.35 : 0.16),
                                style: assignment != nil ? StrokeStyle(lineWidth: 1.5) : StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                            )
                    )

                VStack(spacing: 6) {
                    if let assignment, let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)

                        Text(assignment.name)
                            .font(.headline)
                            .lineLimit(1)

                        Text(slot.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "plus.app")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        Text("Choose App")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(slot.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)

                if assignment != nil {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Remove app from \(slot.label)")
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
