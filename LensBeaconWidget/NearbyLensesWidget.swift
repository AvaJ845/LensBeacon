import WidgetKit
import SwiftUI

/// A quiet at-a-glance count of what LensBeacon last saw nearby.
///
/// The widget cannot scan — extensions get no `bluetooth-central` time — so it
/// renders the `DashboardSnapshot` the app writes to the App Group, and it always
/// shows the snapshot's age so a stale reading can't be mistaken for a live one.
/// Without LensBeacon Unlock it shows a calm locked state instead of data.
struct NearbyLensesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedContainer.widgetKind, provider: SnapshotProvider()) { entry in
            NearbyLensesView(entry: entry)
                .containerBackground(Palette.widgetBackground, for: .widget)
        }
        .configurationDisplayName("Nearby camera glasses")
        .description("The most recent count of camera glasses LensBeacon detected around you.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot
    let unlocked: Bool
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .empty, unlocked: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // Re-read every 15 minutes. The app also nudges WidgetKit whenever the
        // snapshot changes materially, so this is just a backstop for staleness.
        let entry = current()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current() -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .load(), unlocked: SharedContainer.isUnlocked)
    }
}

struct NearbyLensesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snapshot: DashboardSnapshot { entry.snapshot }
    private var count: Int { snapshot.flagged.count }

    var body: some View {
        if !entry.unlocked {
            lockedState
        } else {
            switch family {
            case .accessoryInline:      Text(inlineText)
            case .accessoryCircular:    circular
            case .accessoryRectangular: rectangular
            case .systemMedium:         medium
            default:                    small
            }
        }
    }

    // MARK: - Families

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BeaconMark(tint: count > 0 ? Palette.tier(.serviceUUID) : Palette.accent)
                    .frame(width: 26, height: 26)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 4)
            Text(count == 0 ? "Nothing flagged" : "camera glasses nearby")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ageLine
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("nearby")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ageLine
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if snapshot.flagged.isEmpty {
                    Text("Nothing flagged in the last scan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.flagged.prefix(3)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.tier.symbolName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(item.productName).font(.caption).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(item.proximity.title).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "eyeglasses").font(.caption)
                Text("\(count)").font(.headline)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(count == 0 ? "Nothing flagged" : "\(count) camera glasses nearby")
                .font(.headline)
                .lineLimit(1)
            if let band = snapshot.nearestBand {
                Text("Nearest: \(band.title)").font(.caption).foregroundStyle(.secondary)
            }
            ageLine
        }
    }

    private var inlineText: String {
        count == 0 ? "LensBeacon: clear" : "LensBeacon: \(count) nearby"
    }

    // MARK: - Bits

    @ViewBuilder
    private var ageLine: some View {
        if snapshot.updatedAt == .distantPast {
            Text("Open LensBeacon to scan").font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("as of \(snapshot.updatedAt, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var lockedState: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock").font(.headline).foregroundStyle(.secondary)
            Text("LensBeacon Unlock")
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("adds the widget")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
    }
}

extension Palette {
    /// Widgets can't resolve a `UIColor` trait closure at render time the way the app
    /// can, so give the widget a flat token that still adapts via the asset system's
    /// light/dark resolution of `Palette.canvas`.
    static var widgetBackground: Color { canvas }
}
