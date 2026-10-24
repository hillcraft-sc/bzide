import NavidromeCore
import SwiftUI

extension View {
    /// Offers a queue saved on the server from another device or app (Gitea
    /// #37), just above the mini player. Stays until Continue or Not Now.
    func queueOffer(_ sync: QueueSync?) -> some View {
        safeAreaInset(edge: .bottom) {
            if let sync, let offer = sync.offer {
                QueueOfferBanner(offer: offer, continueOffer: sync.continueOffer, decline: sync.declineOffer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: sync?.offer)
    }
}

private struct QueueOfferBanner: View {
    let offer: ServerPlayQueue
    let continueOffer: () -> Void
    let decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.offerTitle).font(.headline)
                Text(offer.offerDetail()).font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 12) {
                Button("Continue", systemImage: "play.fill", action: continueOffer)
                    .buttonStyle(.borderedProminent)
                Button("Not Now", action: decline)
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .readableWidth()
        .onAppear { AccessibilityNotification.Announcement(offer.offerTitle).post() }
    }
}
