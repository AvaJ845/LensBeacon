import SwiftUI
import CoreBluetooth

/// Three screens, no account, no email field, no "allow notifications" hard sell.
/// It explains what LensBeacon detects, what it can't, and that everything stays on
/// the device — then asks for Bluetooth once, in context.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @State private var probe: PermissionProbe?

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                Panel(
                    symbol: "dot.radiowaves.left.and.right",
                    title: "Awareness, not accusation",
                    text: "Camera glasses announce themselves over Bluetooth. LensBeacon listens for a known pair nearby — never for a person."
                ).tag(0)

                Panel(
                    symbol: "checkmark.seal",
                    title: "Every flag shows its evidence",
                    text: "See the exact signal behind each flag and disagree with it. A detection is not proof anyone is recording, and quiet is not proof no one is."
                ).tag(1)

                Panel(
                    symbol: "iphone",
                    title: "Nothing leaves your iPhone",
                    text: "No account, no server, no analytics — zero network connections. Your log is on this device only, and Settings ▸ Data erases it any time."
                ).tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if page < 2 {
                    Button("Continue") { withAnimation { page += 1 } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Turn on Bluetooth & start") { requestAndFinish() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("Not now") { onFinish() }
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Palette.canvas)
        .tint(Palette.accent)
    }

    private func requestAndFinish() {
        // Instantiating a CBCentralManager is what triggers the system Bluetooth
        // prompt. The probe is discarded immediately; the real manager lives in the
        // ScanCoordinator.
        probe = PermissionProbe { onFinish() }
    }
}

private struct Panel: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Palette.accent)
            Text(title)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Tiny one-shot `CBCentralManager` used only to raise the permission dialog during
/// onboarding, then torn down.
@MainActor
private final class PermissionProbe: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private let done: () -> Void

    init(done: @escaping () -> Void) {
        self.done = done
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state          // Sendable enum; the manager itself is not
        Task { @MainActor in
            // Any resolved state (authorized, denied, powered off) means the user has
            // answered the prompt or it isn't going to appear — move on either way.
            if state != .unknown && state != .resetting {
                done()
                manager = nil
            }
        }
    }
}
