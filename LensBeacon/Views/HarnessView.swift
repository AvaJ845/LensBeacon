#if DEBUG
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Phase 0 detection validation harness. Reachable only from Settings ▸ "About"
/// in a DEBUG build (see `SettingsView.aboutSection`) — never in Release. See
/// `HARNESS.md` for what this exists to measure, the field protocol, and the
/// pre-registered kill criterion. Deliberately plain: this is a measurement
/// instrument, not a polished screen, and every ounce of design effort spent
/// here is effort not spent asking the actual question.
struct HarnessView: View {
    // `@Query` needs the model container already set by an ancestor's
    // `.modelContainer(_:)` by the time its own view's body runs — applying
    // that modifier further down, inside the same view that declares the
    // `@Query`, is too late for that view itself (only its descendants would
    // see it). So this outer wrapper carries no `@Query` of its own and exists
    // solely to install the container above `HarnessRootContent`, which does.
    var body: some View {
        HarnessRootContent()
            .modelContainer(HarnessStore.container)
    }
}

private struct HarnessRootContent: View {
    @State private var coordinator = HarnessCoordinator()
    @State private var showSessionForm = false
    @Query(sort: \HarnessSession.startedAt, order: .reverse) private var sessions: [HarnessSession]

    var body: some View {
        NavigationStack {
            List {
                Section("Scanner") {
                    LabeledContent("State", value: stateLabel)
                    LabeledContent("Packets this session", value: "\(coordinator.packetCount)")
                    LabeledContent("Unique peripherals", value: "\(coordinator.uniquePeripheralCount)")
                }
                Section("Session") {
                    if let session = coordinator.activeSession {
                        LabeledContent("Environment", value: session.environment.title)
                        ForEach(session.deviceStates, id: \.id) { state in
                            Text("• \(state.label) — \(state.asRecord.category.title)")
                                .font(.caption)
                        }
                        if !session.notes.isEmpty {
                            Text(session.notes).font(.caption).foregroundStyle(.secondary)
                        }
                        Button("End session", role: .destructive) { coordinator.endSession() }
                    } else {
                        Button("Start tagged session…") { showSessionForm = true }
                        Text("Nothing is captured before a session starts — an untagged packet has no ground truth.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink("All sessions (\(sessions.count))") { SessionListView(sessions: sessions) }
                    NavigationLink("Aggregate analysis") { AggregateAnalysisView(sessions: sessions) }
                }
                Section {
                    Text("Promiscuous scan — no service filter, allowDuplicates. Background collection is throttled by iOS once this app is backgrounded for more than a brief window; there is no workaround for an unfiltered scan. See HARNESS.md.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Detection Harness")
            .navigationBarTitleDisplayMode(.inline)
            .task { coordinator.start() }
            .onDisappear { coordinator.stop() }
            .sheet(isPresented: $showSessionForm) {
                SessionFormView { environment, notes, deviceStates in
                    coordinator.startSession(environment: environment, notes: notes, deviceStates: deviceStates)
                }
            }
        }
    }

    private var stateLabel: String {
        switch coordinator.state {
        case .idle:         return "Idle"
        case .unauthorized: return "Bluetooth permission denied"
        case .poweredOff:   return "Bluetooth is off"
        case .unsupported:  return "Unsupported"
        case .scanning:     return "Scanning"
        }
    }
}

// MARK: - Session form (ground-truth entry)

private struct SessionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var environment: HarnessEnvironment = .isolated
    @State private var notes = ""
    @State private var devices: [Draft] = [Draft()]

    let onStart: (HarnessEnvironment, String, [DeviceState]) -> Void

    struct Draft: Identifiable {
        let id = UUID()
        var label = ""
        var present = true
        var paired = false
        var worn = false
        var activelyRecording = false
        var inBagOrCase = false
        var poweredOff = false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Environment") {
                    Picker("Environment", selection: $environment) {
                        ForEach(HarnessEnvironment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Known devices present") {
                    Text("One tagged device per session gives the cleanest read on the crux question — see HARNESS.md's field protocol.")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach($devices) { $device in deviceRow($device) }
                        .onDelete { devices.remove(atOffsets: $0) }
                    Button("Add device", systemImage: "plus") { devices.append(Draft()) }
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 80)
                }
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let states = devices.filter { !$0.label.isEmpty }.map { d -> DeviceState in
                            let s = DeviceState(label: d.label)
                            s.present = d.present; s.paired = d.paired; s.worn = d.worn
                            s.activelyRecording = d.activelyRecording
                            s.inBagOrCase = d.inBagOrCase; s.poweredOff = d.poweredOff
                            return s
                        }
                        onStart(environment, notes, states)
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: Binding<Draft>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Device label, e.g. \"Ray-Ban Meta — mine\"", text: device.label)
            Toggle("Present", isOn: device.present)
            Toggle("Paired to a phone", isOn: device.paired)
            Toggle("Actively worn", isOn: device.worn)
            Toggle("Actively recording", isOn: device.activelyRecording)
            Toggle("In a bag/case", isOn: device.inBagOrCase)
            Toggle("Powered off", isOn: device.poweredOff)
        }
        .toggleStyle(.switch)
        .font(.subheadline)
    }
}

// MARK: - Session list

private struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    let sessions: [HarnessSession]

    var body: some View {
        List {
            ForEach(sessions, id: \.id) { session in
                NavigationLink {
                    AnalysisView(session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        Text("\(session.environment.title) · \(session.packetCount) packets\(session.isActive ? " · active" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { modelContext.delete(sessions[i]) }
            }
        }
        .navigationTitle("Sessions")
    }
}

// MARK: - Per-session analysis

private struct AnalysisView: View {
    let session: HarnessSession
    @State private var exportDoc: CSVDocument?

    // Computed once, in `.task` below, not as plain computed properties.
    // `session.packets` is a SwiftData relationship — reading it faults
    // (fully materializes) every `RawPacket` in the session, and
    // `SessionAnalyzer.summarize` then walks that whole array. As plain
    // `var`s, both re-ran on *every* re-render of this view, including the
    // one triggered by just tapping an Export button below — for a session
    // with thousands of packets that was a visible freeze on every tap.
    @State private var records: [PacketRecord] = []
    @State private var summaries: [SessionAnalyzer.DeviceSummary] = []
    @State private var ratio: Double?
    @State private var loaded = false

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Environment", value: session.environment.title)
                LabeledContent("Started", value: session.startedAt.formatted())
                if let ended = session.endedAt {
                    LabeledContent("Duration", value: durationString(ended.timeIntervalSince(session.startedAt)))
                }
                LabeledContent("Total packets", value: "\(session.packetCount)")
                if !session.notes.isEmpty { Text(session.notes).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Ground truth") {
                if session.deviceStates.isEmpty {
                    Text("No devices tagged for this session.").foregroundStyle(.secondary)
                }
                ForEach(session.deviceStates, id: \.id) { state in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.label)
                        Text(state.asRecord.category.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let ratio {
                Section("Payload-confirmation ratio (0x058E / 0x01AB packets only)") {
                    Text("\(Int((ratio * 100).rounded()))% carried the confirming payload")
                }
            }
            if loaded {
                Section("Per-device summary (\(summaries.count))") {
                    ForEach(summaries) { s in deviceSummaryRow(s) }
                }
                Section {
                    Button("Export raw packets (CSV)") {
                        exportDoc = CSVDocument(text: HarnessCSVExporter.rawPackets(records, sessionID: session.id.uuidString))
                    }
                    Button("Export device summary (CSV)") {
                        exportDoc = CSVDocument(text: HarnessCSVExporter.deviceSummaries(summaries, sessionID: session.id.uuidString))
                    }
                }
            } else {
                Section { ProgressView("Loading \(session.packetCount) packets…") }
            }
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Computed exactly once per time this screen is opened — see the
            // doc comment on the `@State` properties above for why this must
            // never be a plain re-evaluated computed property here.
            records = session.packets.map(\.asRecord)
            summaries = SessionAnalyzer.summarize(records)
            ratio = SessionAnalyzer.payloadConfirmedRatio(records)
            loaded = true
        }
        .fileExporter(
            isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
            document: exportDoc, contentType: .commaSeparatedText, defaultFilename: "harness-export"
        ) { _ in exportDoc = nil }
    }

    @ViewBuilder
    private func deviceSummaryRow(_ s: SessionAnalyzer.DeviceSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(s.peripheralID).font(.caption.monospaced())
            Text("\(s.packetCount) packets · confirmed \(s.confirmedCount) · company-ID-only \(s.companyIDOnlyCount)")
                .font(.caption2)
            if let mean = s.meanIntervalSeconds, let max = s.maxIntervalSeconds {
                Text("Interval: mean \(String(format: "%.1f", mean))s · max \(String(format: "%.1f", max))s")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let rssi = s.meanRSSI {
                Text("Mean RSSI: \(String(format: "%.0f", rssi)) dBm").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }
}

// MARK: - Aggregate analysis (across every session)

private struct AggregateAnalysisView: View {
    let sessions: [HarnessSession]

    // Same reasoning as `AnalysisView`, worse in degree: this walks every
    // packet in *every* session, not just one. As plain computed properties
    // this re-ran on every re-render of this screen — exactly the screen the
    // field protocol says to check repeatedly through the day.
    @State private var rates: [SessionAnalyzer.TruePositiveRate] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded {
                Section("True-positive rate by ground-truth category") {
                    ForEach(rates, id: \.category) { r in
                        HStack {
                            Text(r.category.title)
                            Spacer()
                            if let rate = r.rate {
                                Text("\(Int((rate * 100).rounded()))% (\(r.detectedSessions)/\(r.totalSessions))")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("no sessions yet").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("A category with 0 sessions is not a 0% detection rate — it's no data. Run the field protocol in HARNESS.md before drawing any conclusion from this table, and check the pre-registered kill criterion against the \"Worn + paired\" row specifically.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Section { ProgressView("Loading \(sessions.count) session(s)…") }
            }
        }
        .navigationTitle("Aggregate")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let outcomes = sessions.flatMap { session in
                SessionAnalyzer.outcomes(
                    startedAt: session.startedAt,
                    deviceStates: session.deviceStates.map(\.asRecord),
                    packets: session.packets.map(\.asRecord)
                )
            }
            rates = SessionAnalyzer.truePositiveRates(outcomes)
            loaded = true
        }
    }
}
#endif
