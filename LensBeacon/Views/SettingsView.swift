import SwiftUI

/// Settings is short on purpose. Scan behaviour, the Unlock features, and the plain
/// statements of what LensBeacon does and doesn't do.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UnlockStore.self) private var unlock
    @Environment(ScanCoordinator.self) private var coordinator

    private let notifier = FlagNotifier()

    @AppStorage(SharedContainer.Key.backgroundScanning, store: SharedContainer.defaults)
    private var backgroundScanning = false
    @AppStorage(SharedContainer.Key.alertsEnabled, store: SharedContainer.defaults)
    private var alertsEnabled = false

    @State private var showUnlock = false

    var body: some View {
        NavigationStack {
            List {
                unlockSection
                scanningSection
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
            .sheet(isPresented: $showUnlock) { UnlockView() }
        }
    }

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
                        Text("Background scanning, widget, Live Activity, unlimited history, CSV export. No subscription.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scanningSection: some View {
        Section {
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
        } header: {
            Text("Scanning")
        } footer: {
            Text(unlock.isUnlocked
                 ? "Background scanning uses a filtered Bluetooth scan and shows a Live Activity so it’s always visible. LensBeacon still never connects to anything."
                 : "Background scanning is part of LensBeacon Unlock. While the app is open, scanning always runs.")
        }
    }

    private var aboutSection: some View {
        Section("What LensBeacon does and doesn’t do") {
            statement("Scans Bluetooth for camera-glasses signatures", yes: true)
            statement("Shows the evidence behind every flag", yes: true)
            statement("Stores your history only on this iPhone", yes: true)
            statement("Connects to, pairs with, or transmits to any device", yes: false)
            statement("Uses GPS or any location service", yes: false)
            statement("Sends analytics or makes any network request", yes: false)
            NavigationLink("Privacy details") { PrivacyDetailView() }
        }
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
}

/// A full-screen restatement of the privacy posture, so a curious or skeptical user
/// (or an App Review reader) can find it without leaving the app.
struct PrivacyDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    para("LensBeacon works entirely on your device.", "There is no LensBeacon account and no LensBeacon server. The app makes no network connections of any kind — you can verify this by putting the phone in Airplane Mode; every feature still works.")
                    para("It listens; it never speaks.", "LensBeacon uses Bluetooth in central role only. It scans for the advertisements that nearby devices broadcast. It never connects, never pairs, never reads or writes a device’s data, and never advertises itself.")
                    para("No location, ever.", "Proximity is estimated only from Bluetooth signal strength, in three coarse bands. LensBeacon requests no location permission and links no location framework.")
                    para("Your history stays here.", "The Sightings log is a single file on this device, encrypted at rest and excluded from iCloud/device backups. Bluetooth identifiers rotate on their own; LensBeacon stores the rotating identifier as an opaque key and makes no attempt to track a device or person across that rotation.")
                    para("CSV export is yours alone.", "When you export, you choose where the file goes. The header names every column so you can see exactly what’s in it.")
                }
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
