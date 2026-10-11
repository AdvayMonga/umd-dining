import SwiftUI

/// Shown in place of the menu when a hall has nothing for the selected day or meal.
struct MenuEmptyStateView: View {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let state: HomeMenuState
    let hallName: String
    let date: Date
    /// Seam for live hours: a specific reason ("Closed for fall break") replaces the generic explanation
    var closedReason: String? = nil
    var action: Action? = nil

    private static let hoursURL = URL(string: "https://dining.umd.edu/hours/open-now")!

    private var icon: String {
        switch state {
        case .hallNotServing(false), .noMenusPosted(false): return "moon.zzz"
        case .hallNotServing(true), .noMenusPosted(true): return "line.3.horizontal.decrease.circle"
        default: return "clock"
        }
    }

    var body: some View {
        let copy = state.copy(hallName: hallName, date: date, closedReason: closedReason)
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.umdRed)
                .frame(width: 56, height: 56)
                .background(Color.umdRed.opacity(0.1))
                .clipShape(Circle())

            VStack(spacing: 6) {
                Text(copy.title)
                    .font(.inter(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Text(copy.message)
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                if let action {
                    Button(action: action.perform) {
                        Text(action.title)
                            .font(.inter(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.umdRed)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                Link(destination: Self.hoursURL) {
                    Label("Check dining hours", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.inter(size: 14, weight: .medium))
                        .foregroundStyle(Color.umdRed)
                        .padding(.vertical, 4)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .homeCard(tint: .gray, thin: true)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        MenuEmptyStateView(
            state: .hallNotServing(filtered: false),
            hallName: "Yahentamitsi",
            date: .now,
            action: .init(title: "See 251 North", perform: {})
        )
        MenuEmptyStateView(
            state: .mealNotServed(meal: "Lunch", nextMeal: "Dinner", nextOpens: "4 PM"),
            hallName: "Yahentamitsi",
            date: .now,
            action: .init(title: "Show Dinner", perform: {})
        )
    }
    .padding(16)
    .background(Color.umdBackground)
}
