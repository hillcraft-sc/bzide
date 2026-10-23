import NavidromeCore
import SwiftUI

// Ratings in either style (Settings > Ratings > Use Simplified Rating): Meh,
// Like and Love, or Navidrome's 1–5 stars. The style is set once at the root
// (`RootView`) and read here; what's stored is the same either way.

extension EnvironmentValues {
    /// On: Meh, Like and Love. Off: 1–5 stars.
    @Entry var simplifiedRating = true
}

/// The rating shown in lists: a face, or "4★". Display only: it's changed
/// from the item's menu, not by tapping it.
struct RatingMark: View {
    let stars: Int?
    @Environment(\.simplifiedRating) private var simplified

    var body: some View {
        if simplified, let rating = Rating(serverValue: stars) {
            Text(rating.face)
                .font(.caption)
                .accessibilityLabel("Rated \(rating.title)")
        } else if !simplified, let stars = Rating.stars(serverValue: stars) {
            HStack(spacing: 1) {
                Text("\(stars)").monospacedDigit()
                Image(systemName: "star.fill").imageScale(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rated \(Rating.starsTitle(stars))")
        }
    }
}

/// Rate an item: Meh, Like or Love with a checkmark on the current one, or a
/// row of five stars filled up to the current rating. Choosing the current
/// rating again clears it. Reads and writes through the shared `RatingModel`.
struct RateMenu: View {
    let ratings: RatingModel
    let target: StarTarget
    let fromServer: Int?
    @Environment(\.simplifiedRating) private var simplified

    var body: some View {
        let stars = ratings.stars(target, fromServer: fromServer)
        let title = Rating.title(serverValue: stars, simplified: simplified)
        Menu(title.map { "Rated: \($0)" } ?? "Rate", systemImage: stars == nil ? "star" : "star.fill") {
            if simplified {
                simplifiedChoices(current: Rating(serverValue: stars))
            } else {
                starChoices(current: stars)
            }
        }
    }

    @ViewBuilder
    private func simplifiedChoices(current: Rating?) -> some View {
        ForEach(Rating.allCases.reversed(), id: \.self) { rating in
            // A toggle so the menu draws the checkmark; turning the current
            // one off is choosing it again, which clears it.
            Toggle("\(rating.face) \(rating.title)", isOn: Binding(
                get: { rating == current },
                set: { _ in Task { await ratings.choose(rating, for: target, fromServer: fromServer) } }
            ))
        }
    }

    @ViewBuilder
    private func starChoices(current: Int?) -> some View {
        // A palette draws the five side by side across the top of the menu.
        // Palettes stay open after a tap, but an open menu is a snapshot and
        // wouldn't fill the stars in, so a tap closes it like the simplified
        // choices do.
        ControlGroup {
            ForEach(1...5, id: \.self) { count in
                Button(Rating.starsTitle(count), systemImage: count <= (current ?? 0) ? "star.fill" : "star") {
                    Task { await ratings.choose(stars: count, for: target, fromServer: fromServer) }
                }
                .accessibilityAddTraits(count == current ? .isSelected : [])
            }
        }
        .controlGroupStyle(.palette)
        .menuActionDismissBehavior(.enabled)
        if current != nil {
            Button("Clear Rating", systemImage: "star.slash") {
                Task { await ratings.clear(target, fromServer: fromServer) }
            }
        }
    }
}

extension Rating {
    /// Shown beside the title in the Rate menu, and in lists.
    var face: String {
        switch self {
        case .meh: "😩"
        case .like: "👌"
        case .love: "😈"
        }
    }
}
