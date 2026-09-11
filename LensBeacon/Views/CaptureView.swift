#if DEBUG
import SwiftUI

/// Developer-only. Reachable from Settings ▸ About in Debug builds. A full BLE
/// advertisement logger for confirming the signature table against real Meta / Snap
/// / Even Realities hardware. Not in the Release / TestFlight binary.
struct CaptureView: View {
    @State private var model = CaptureLog()
    @State private var exportText = ""

    var body: some View {
        List {
            Section {
                Toggle("Scanning", isOn: Binding(get: { model.isRunning },
                                                 set: { $0 ? model.start() : model.stop() }))
                if !model.devices.isEmpty {
                    Button("Prepare export…") { exportText = model.exportText() }
                    if !exportText.isEmpty {
                        ShareLink("Share capture text", item: exportText)
                    }
                    Button("Clear", role: .destructive) { model.clear(); exportText = "" }
                }
                Text("Put the device in pairing mode / out of its case, hold the phone ~20 cm away. Tag the ones you can identify, then prepare + share the text. Central-role scan only — nothing is stored or transmitted.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(headerState)
            }

            if model.devices.isEmpty {
                Text(model.isRunning ? "Listening…" : "Scanning is off.")
                    .foregroundStyle(.secondary)
            }

            ForEach(model.devices) { d in
                NavigationLink {
                    DeviceDetail(id: d.id, model: model)
                } label: {
                    DeviceRow(device: d)
                }
            }
        }
        .navigationTitle("BLE capture (dev)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var headerState: String {
        switch model.state {
        case .scanning: return "Scanning · \(model.devices.count) devices"
        case .poweredOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission needed"
        case .unsupported: return "No Bluetooth LE radio"
        case .idle: return "Idle"
        }
    }
}

private struct DeviceRow: View {
    let device: CapturedDevice
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.isCandidate ? "eyeglasses" : "dot.radiowaves.right")
                .foregroundStyle(device.isCandidate ? Color.accentColor : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.userTag ?? device.latest?.localName ?? device.latest?.peripheralName ?? "(unnamed)")
                    .font(.subheadline.weight(device.userTag != nil ? .semibold : .regular))
                Text(device.latest?.companyID.map { "company \($0)" }
                     ?? (device.latest?.serviceUUIDs.first.map { "svc \($0)" } ?? "no mfg / svc"))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(device.strongestRSSI) dBm").font(.caption2)
                Text("\(device.packetCount)×").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DeviceDetail: View {
    let id: String
    let model: CaptureLog

    var body: some View {
        if let device = model.device(id) {
            List {
                Section("Identify") {
                    Picker("This device is", selection: Binding(
                        get: { device.userTag ?? "" },
                        set: { model.tag(id, $0.isEmpty ? nil : $0) }
                    )) {
                        Text("(untagged)").tag("")
                        ForEach(CaptureLog.tags, id: \.self) { Text($0).tag($0) }
                    }
                    LabeledContent("Engine says", value: device.engineVerdict)
                    LabeledContent("Packets", value: "\(device.packetCount)")
                    ShareLink("Share this device", item: model.exportText(only: id))
                }

                ForEach(Array(device.variants.enumerated()), id: \.offset) { i, v in
                    Section("Advertisement \(i + 1)") {
                        field("Local name", v.localName ?? "—")
                        field("peripheral.name", v.peripheralName ?? "—")
                        field("Company ID", v.companyID ?? "none")
                        field("Manufacturer data", v.manufacturerHex ?? "—",
                              ascii: RawAdvertisement.asciiHint(v.manufacturerHex))
                        field("Service UUIDs", v.serviceUUIDs.isEmpty ? "—" : v.serviceUUIDs.joined(separator: "\n"))
                        if !v.serviceData.isEmpty {
                            field("Service data", v.serviceData.sorted { $0.key < $1.key }
                                .map { "\($0.key) = \($0.value)" }.joined(separator: "\n"))
                        }
                        if !v.overflowServiceUUIDs.isEmpty {
                            field("Overflow UUIDs", v.overflowServiceUUIDs.joined(separator: "\n"))
                        }
                        field("Tx power", v.txPower.map(String.init) ?? "—")
                        field("Connectable", v.isConnectable ? "yes" : "no")
                    }
                }
            }
            .navigationTitle(device.userTag ?? device.latest?.localName ?? "Device")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Device left range", systemImage: "dot.radiowaves.right")
        }
    }

    private func field(_ k: String, _ value: String, ascii: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.monospaced()).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let ascii {
                Text("ascii: “\(ascii)”  (likely a serial / model — not a signal)")
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
    }
}
#endif
