import WidgetKit
import SwiftUI

/// A watch face complication for LensBeacon — a one-tap "check for camera glasses
/// near me" from the wrist.
///
/// It carries no live data: the watch app scans only while it is open (no background
/// Bluetooth on watchOS for a central-role app), so a complication that showed a
/// count would be stale by design. Instead it is an honest launcher — the mark, and
/// a tap that opens the scanner.
@main
struct LensBeaconComplicationBundle: WidgetBundle {
    var body: some Widget {
        LensBeaconComplication()
    }
}

struct LensBeaconComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LensBeaconComplication", provider: Provider()) { _ in
            ComplicationView()
        }
        .configurationDisplayName("Scan for camera glasses")
        .description("Opens LensBeacon and starts a scan.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

private struct Entry: TimelineEntry { let date: Date }

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Static — nothing to refresh.
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

private struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Camera glasses", systemImage: "dot.radiowaves.left.and.right")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("LensBeacon").font(.headline)
                    Text("Tap to scan").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .accessoryCorner:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .widgetLabel("Scan for camera glasses")
        default: // accessoryCircular
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .widgetAccentable()
            }
        }
    }
}
