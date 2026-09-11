import WidgetKit
import SwiftUI

/// A watch face complication for LensBeacon.
///
/// LensBeacon Unlock relays the same `DashboardSnapshot` the Home Screen widget
/// reads (`LensBeacon/Support/WatchRelay.swift`) over WatchConnectivity — the
/// complication never scans on its own; the watch app scans only while it's open,
/// same as always. Without Unlock (or before the first relay arrives), it's the
/// same honest launcher it always was: the mark, and a tap that opens the scanner.
@main
struct LensBeaconComplicationBundle: WidgetBundle {
    var body: some Widget {
        LensBeaconComplication()
    }
}

struct LensBeaconComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LensBeaconComplication", provider: Provider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Scan for camera glasses")
        .description("Shows the last count LensBeacon Unlock relayed from your iPhone, or opens the scanner.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot
    let unlocked: Bool
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: .empty, unlocked: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // No timer of our own — real refreshes come from WatchRelayReceiver calling
        // reloadTimelines when a new relay arrives. This is just a staleness
        // backstop, same pattern as the iPhone widget.
        let entry = current()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current() -> Entry {
        Entry(date: .now, snapshot: .load(), unlocked: SharedContainer.isUnlocked)
    }
}

private struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var count: Int { entry.snapshot.flagged.count }
    private var hasRelay: Bool { entry.unlocked && entry.snapshot.updatedAt != .distantPast }

    var body: some View {
        switch family {
        case .accessoryInline:
            if hasRelay {
                Text(count == 0 ? "LensBeacon: clear" : "LensBeacon: \(count) nearby")
            } else {
                Label("Camera glasses", systemImage: "dot.radiowaves.left.and.right")
            }
        case .accessoryRectangular:
            rectangular
        case .accessoryCorner:
            corner
        default: // accessoryCircular
            circular
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if hasRelay {
            VStack(alignment: .leading, spacing: 1) {
                Text(count == 0 ? "Nothing flagged" : "\(count) flagged").font(.headline)
                Text("as of \(entry.snapshot.updatedAt, style: .relative) ago")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("LensBeacon").font(.headline)
                    Text("Tap to scan").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var corner: some View {
        if hasRelay {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .widgetLabel("\(count) flagged")
        } else {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .widgetLabel("Scan for camera glasses")
        }
    }

    @ViewBuilder
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if hasRelay {
                VStack(spacing: 0) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.caption2)
                    Text("\(count)").font(.headline)
                }
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .widgetAccentable()
            }
        }
    }
}
