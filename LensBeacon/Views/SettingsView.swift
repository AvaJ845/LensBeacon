import SwiftUI

/// Settings is short on purpose. Scan behaviour, the Unlock features, the data
/// controls, and the plain statements of what LensBeacon does and doesn't do.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UnlockStore.self) private var unlock
    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(SightingsStore.self) private var store
    @Environment(MineRegistry.self) private var mine

    private let notifier = FlagNotifier()

    @AppStorage(SharedContainer.Key.backgroundScanning, store: SharedContainer.defaults)
    private var backgroundScanning = false
    @AppStorage(SharedContainer.Key.alertsEnabled, store: SharedContainer.defaults)
    private var alertsEnabled = false
    @AppStorage(SharedContainer.Key.quietHoursEnabled, store: SharedContainer.defaults)
    private var quietHoursEnabled = false
    @AppStorage(SharedContainer.Key.quietHoursStartMinutes, store: SharedContainer.defaults)
    private var quietHoursStartMinutes = QuietHours.disabled.startMinutes
    @AppStorage(SharedContainer.Key.quietHoursEndMinutes, store: SharedContainer.defaults)
    private var quietHoursEndMinutes = QuietHours.disabled.endMinutes
    @AppStorage(SharedContainer.Key.appearance, store: SharedContainer.defaults)
    private var appearanceRaw = AppAppearance.system.rawValue

    @State private var showUnlock = false
    @State private var pendingWipe: WipeKind?
    @State private var iconOption: AppIconOption = .classic

    private enum WipeKind: Identifiable {
        case history, mine, everything
        var id: Int { hashValue }
    }

    var body: some View {
        NavigationStack {
            List {
                unlockSection
                appearanceSection
                scanningSection
                dataSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .lensChrome()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { iconOption = .current }
            .sheet(isPresented: $showUnlock) { UnlockView() }
            .confirmationDialog(wipeTitle, isPresented: wipeBinding, titleVisibility: .visible, presenting: pendingWipe) { kind in
                Button(wipeButton(kind), role: .destructive) { perform(kind) }
                Button("Cancel", role: .cancel) {}
            } message: { kind in
                Text(wipeMessage(kind))
            }
        }
    }

    // MARK: - Unlock

    @ViewBuilder
    private var unlockSection: some View {
        Section {
            if unlock.isUnlocked {
                Label("LensBeacon Unlock is active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Palette.accent)
            } else {
                Button {
                    showUnlock = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Get LensBeacon Unlock — \(unlock.displayPrice) once")
                            .font(.body.weight(.medium))
                        Text("Background scanning, widget, watch complication, unlimited history, CSV export. No subscription.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu)

            Picker(selection: $iconOption) {
                ForEach(AppIconOption.allCases) { option in
                    Label {
                        Text(option.title)
                    } icon: {
                        Circle().fill(option.swatch).frame(width: 14, height: 14)
                    }
                    .tag(option)
                }
            } label: {
                Text("App icon")
            }
            .pickerStyle(.menu)
            .onChange(of: iconOption) { _, new in IconSwitcher.apply(new) }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Appearance overrides the system light/dark setting for LensBeacon only. Changing the app icon takes a moment to appear on the Home Screen.")
        }
    }

    // MARK: - Scanning

    @ViewBuilder
    private var scanningSection: some View {
        Section {
            Toggle("Listen for camera glasses", isOn: Binding(
                get: { !coordinator.isPaused },
                set: { coordinator.setPaused(!$0) }
            ))
            Toggle("Keep scanning in the background", isOn: $backgroundScanning)
                .disabled(!unlock.isUnlocked)
                .onChange(of: backgroundScanning) { _, on in
                    coordinator.applyScenePhase(active: true)
                    if on { Task { _ = await notifier.requestAuthorizationIfNeeded() } }
                }
            Toggle("Alert me about new likely/strong flags", isOn: $alertsEnabled)
                .disabled(!unlock.isUnlocked || !backgroundScanning)
                .onChange(of: alertsEnabled) { _, on in
                    if on { Task { _ = await notifier.requestAuthorizationIfNeeded() } }
                }
            Toggle("Quiet hours", isOn: $quietHoursEnabled)
                .disabled(!unlock.isUnlocked || !alertsEnabled)
            if quietHoursEnabled {
                DatePicker("From", selection: dateBinding(for: $quietHoursStartMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!unlock.isUnlocked || !alertsEnabled)
                DatePicker("To", selection: dateBinding(for: $quietHoursEndMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!unlock.isUnlocked || !alertsEnabled)
            }
        } header: {
            Text("Scanning")
        } footer: {
            Text("Turn listening off and LensBeacon detects and logs nothing until you turn it back on — the setting sticks across relaunches. " + (unlock.isUnlocked
                 ? "Background scanning uses a filtered Bluetooth scan and shows a Live Activity so it’s always visible. LensBeacon still never connects to anything. Quiet hours mutes alerts on a schedule — by time only, never by place."
                 : "Background scanning is part of LensBeacon Unlock."))
        }
    }

    /// Minutes-since-midnight ↔ `Date` for the quiet-hours pickers. Only the time
    /// of day is ever stored; the date's day component is thrown away on read.
    private func dateBinding(for minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = minutes.wrappedValue / 60
                comps.minute = minutes.wrappedValue % 60
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                minutes.wrappedValue = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }

    // MARK: - Data

    @ViewBuilder
    private var dataSection: some View {
        Section {
            LabeledContent("Sightings stored") {
                Text("\(store.sightings.count) · \(formattedSize)")
                    .foregroundStyle(.secondary)
            }
            Button("Clear sightings history", systemImage: "trash") {
                pendingWipe = .history
            }
            .disabled(store.sightings.isEmpty)

            LabeledContent("Devices marked as mine") {
                Text("\(mine.keys.count)").foregroundStyle(.secondary)
            }
            Button("Reset devices marked as mine", systemImage: "arrow.counterclockwise") {
                pendingWipe = .mine
            }
            .disabled(mine.keys.isEmpty)

            Button("Erase all LensBeacon data", systemImage: "exclamationmark.triangle", role: .destructive) {
                pendingWipe = .everything
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Everything LensBeacon stores lives only on this iPhone. These controls remove it immediately — there is no cloud copy to also delete.")
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(store.approximateByteCount), countStyle: .file)
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            statement("Scans Bluetooth for camera-glasses signatures", yes: true)
            statement("Shows the evidence behind every flag", yes: true)
            statement("Stores your history only on this iPhone", yes: true)
            statement("Matches against a transparent, versioned rule table", yes: true)
            statement("Connects to, pairs with, or transmits to any device", yes: false)
            statement("Uses GPS or any location service", yes: false)
            statement("Sends analytics or makes any network request", yes: false)
            statement("Uses AI or a black-box model to decide what's nearby", yes: false)
            NavigationLink("Privacy details") { PrivacyDetailView() }
            #if DEBUG
            NavigationLink("BLE capture (dev only)") { CaptureView() }
            NavigationLink("Detection harness (dev only)") { HarnessView() }
            #endif
            LabeledContent("Version") {
                Text(Self.versionString).foregroundStyle(.secondary)
            }
        } header: {
            Text("What LensBeacon does and doesn’t do")
        } footer: {
            Text(Legal.nonAffiliation)
        }
    }

    /// e.g. "1.0.0 (1)" — marketing version + build number from the bundle.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private func statement(_ text: String, yes: Bool) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: yes ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(yes ? Palette.accent : Color.secondary)
        }
        .font(.subheadline)
    }

    // MARK: - Wipe plumbing

    private var wipeBinding: Binding<Bool> {
        Binding(get: { pendingWipe != nil }, set: { if !$0 { pendingWipe = nil } })
    }

    private var wipeTitle: String {
        switch pendingWipe {
        case .history:    return "Clear sightings history?"
        case .mine:       return "Reset devices marked as mine?"
        case .everything: return "Erase all LensBeacon data?"
        case nil:         return ""
        }
    }

    private func wipeButton(_ kind: WipeKind) -> String {
        switch kind {
        case .history:    return "Clear history"
        case .mine:       return "Reset"
        case .everything: return "Erase everything"
        }
    }

    private func wipeMessage(_ kind: WipeKind) -> String {
        switch kind {
        case .history:
            return "Removes every recorded sighting from this iPhone. It cannot be undone."
        case .mine:
            return "LensBeacon will flag those devices again the next time it sees them."
        case .everything:
            return "Removes all history, the devices you marked as yours, the widget’s last reading, and resets scanning preferences. Your LensBeacon Unlock purchase is kept. This cannot be undone."
        }
    }

    private func perform(_ kind: WipeKind) {
        switch kind {
        case .history:
            store.wipe()
            DashboardSnapshot.clear()
        case .mine:
            mine.wipeAll()
        case .everything:
            store.wipe()
            mine.wipeAll()
            DashboardSnapshot.clear()
            backgroundScanning = false
            alertsEnabled = false
            quietHoursEnabled = false
            SharedContainer.defaults.removeObject(forKey: SharedContainer.Key.scanningPaused)
            coordinator.setPaused(false)
        }
        pendingWipe = nil
    }
}

/// A full-screen restatement of the privacy posture, so a curious or skeptical user
/// (or an App Review reader) can find it without leaving the app.
struct PrivacyDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink {
                    AirplaneProofView()
                } label: {
                    HStack {
                        Label("Prove it — the Airplane Mode test", systemImage: "airplane")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
                }
                .buttonStyle(.plain)

                Group {
                    para("LensBeacon works entirely on your device.", "There is no LensBeacon account and no LensBeacon server. The app makes no network connections of any kind — you can verify this by putting the phone in Airplane Mode; every feature still works.")
                    para("It listens; it never speaks.", "LensBeacon uses Bluetooth in central role only. It scans for the advertisements that nearby devices broadcast. It never connects, never pairs, never reads or writes a device’s data, and never advertises itself.")
                    para("Nearby devices are read, briefly.", "While something is in range, LensBeacon holds its advertised name and manufacturer data in memory only — the same fields the Nearby tab already shows for it. That's dropped the moment it leaves range; none of it is written to disk unless it's a recognised pair of glasses.")
                    para("No location, ever.", "Proximity is estimated only from Bluetooth signal strength, in three coarse bands. LensBeacon requests no location permission and links no location framework.")
                    para("No AI, no black box.", "Every match comes from a small, versioned rule table you can read yourself — a manufacturer ID, a service UUID, a name pattern. Nothing here is a model's guess; every flag traces back to a specific rule.")
                    para("Your history stays here.", "The Sightings log is a single file on this device, encrypted at rest and excluded from iCloud/device backups. Bluetooth identifiers rotate on their own; LensBeacon stores the rotating identifier as an opaque key and makes no attempt to track a device or person across that rotation. Settings ▸ Data erases it all at any time.")
                    para("Exports are yours alone.", "CSV export and \"Suggest what this is\" both work the same way: when you export or share, you choose where it goes. Nothing is sent unless you send it.")
                }
                Text(Legal.nonAffiliation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .lensChrome()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func para(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// The one-minute proof: cut the phone off from the world and watch LensBeacon keep
/// working, because there was never anything to cut off.
struct AirplaneProofView: View {
    @State private var step = 0
    private let steps = [
        ("1", "Turn on Airplane Mode", "Swipe down from the top-right for Control Centre and tap the ✈ button. Wi-Fi and cellular go dark."),
        ("2", "Come back to LensBeacon", "Scan, open a flag, read its evidence, export the log, change the appearance — everything you can do now, you can do offline."),
        ("3", "That's the whole proof", "Nothing broke, because LensBeacon links no networking framework and makes no request. There is no server to reach and nothing to send."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("An app can *say* it works on-device. This is how you check.")
                    .font(.subheadline).foregroundStyle(.secondary)

                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 14) {
                        Text(s.0)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Palette.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.1).font(.headline)
                            Text(s.2).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .opacity(i <= step ? 1 : 0.4)
                }

                Button(step < steps.count - 1 ? "Next" : "Done") {
                    withAnimation { step = min(step + 1, steps.count - 1) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("You can also read the source: LensBeacon is open. Search it for any networking API and you will find only the comments noting there are none.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .lensChrome()
        .navigationTitle("The Airplane Mode test")
        .navigationBarTitleDisplayMode(.inline)
    }
}
