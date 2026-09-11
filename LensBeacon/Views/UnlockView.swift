import SwiftUI
import StoreKit

/// The purchase screen for the single non-consumable "LensBeacon Unlock".
///
/// The whole pitch is one line: **one payment, no subscription, everything included.**
/// The competing apps train users to expect either a yearly renewal or a
/// pay-to-start wall; this screen exists to make the difference impossible to miss.
struct UnlockView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(UnlockStore.self) private var unlock

    @State private var message: String?
    @State private var working = false
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    VStack(spacing: 0) {
                        feature("Background scanning", "Keep detecting while LensBeacon is closed, with a Live Activity so it’s always visible.")
                        Divider()
                        feature("Home Screen widget", "A quiet at-a-glance count of what’s nearby.")
                        Divider()
                        feature("New-flag alerts", "An optional local notification when a likely or strong flag appears.")
                        Divider()
                        feature("Unlimited history", "Keep every sighting instead of the last 7 days.")
                        Divider()
                        feature("CSV export", "Take your log with you, with every column labelled.")
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline))

                    comparisonNote

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    buttons

                    legalFooter
                }
                .padding(20)
            }
            .lensChrome()
            .navigationTitle("LensBeacon Unlock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $showPrivacy) {
                NavigationStack { PrivacyDetailView() }
            }
        }
        .task { if unlock.product == nil { await unlock.load() } }
    }

    private var legalFooter: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Button("Terms of Use (EULA)") { openURL(Legal.termsURL) }
                Text("·").foregroundStyle(.secondary)
                Button("Privacy") { showPrivacy = true }
            }
            .font(.caption)
            Text("One payment unlocks LensBeacon Unlock permanently for your Apple ID. No subscription, no auto-renew.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: unlock.isUnlocked ? "checkmark.seal.fill" : "lock.open")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.accent)
            Text(unlock.isUnlocked ? "Unlock is active" : "One payment. Everything included.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(unlock.isUnlocked
                 ? "Thank you. Every feature below is on."
                 : "\(unlock.displayPrice) once — no subscription, no renewal, no trial countdown.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func feature(_ title: String, _ body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }

    private var comparisonNote: some View {
        Text("Most glasses-detector apps either charge every year or lock scanning behind a paywall. LensBeacon’s scanning, Dashboard and evidence view are free forever. Unlock is a one-time thank-you that adds the background features.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var buttons: some View {
        if !unlock.isUnlocked {
            Button {
                Task { await buy() }
            } label: {
                Text(working ? "…" : "Unlock for \(unlock.displayPrice)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working || unlock.product == nil)
        }

        Button("Restore Purchase") {
            Task { await restore() }
        }
        .font(.subheadline)
        .disabled(working)

        Text("Restore brings back a previous LensBeacon Unlock bought with your Apple ID, on any device.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private func buy() async {
        working = true; defer { working = false }
        switch await unlock.purchase() {
        case .success:   message = "Unlocked. Enjoy."; try? await Task.sleep(for: .seconds(1)); dismiss()
        case .pending:   message = "Your purchase needs approval. It will unlock automatically once approved."
        case .cancelled: message = nil
        case .failed(let reason): message = reason
        }
    }

    private func restore() async {
        working = true; defer { working = false }
        switch await unlock.restore() {
        case .success: message = "Restored. Every feature is on."
        case .failed(let reason): message = reason
        default: break
        }
    }
}
