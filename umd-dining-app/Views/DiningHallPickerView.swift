import SwiftUI

struct DiningHallPickerView: View {
    let selectedHallId: String?
    let onSelect: (_ hallId: String, _ tab: Int) -> Void

    private let halls: [(id: String, name: String, imageAlignment: Alignment)] = [
        ("19", "Yahentamitsi",      .center),
        ("51", "251 North",         .top),
        ("16", "South Campus Diner", .center)
    ]

    // First preferred hall (in hall order), else Yahentamitsi
    private var defaultHall: String {
        let prefs = UserPreferences.shared.preferredDiningHalls
        return halls.map(\.id).first(where: prefs.contains) ?? "19"
    }

    // Home stays selected; Tracker/Profile open the app on that tab
    private var tabBinding: Binding<Int> {
        Binding(
            get: { 0 },
            set: { tab in if tab != 0 { onSelect(defaultHall, tab) } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — same metrics as HomeView so nothing shifts on entry
            Text("UMD Dining")
                .font(.inter(size: 22, weight: .bold))
                .foregroundStyle(Color.umdRed)
                .frame(height: 36)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Prompt + View Hours link
            HStack {
                Text("Hungry? Pick a dining hall.")
                    .font(.inter(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Link("View Hours", destination: URL(string: "https://dining.umd.edu/hours-locations/dining-halls")!)
                    .font(.inter(size: 14, weight: .medium))
                    .foregroundStyle(Color.umdRed)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)

            // Cards — fill remaining space, no scroll needed
            VStack(spacing: 8) {
                ForEach(halls, id: \.id) { hall in
                    DiningHallCard(
                        hallId: hall.id,
                        hallName: hall.name,
                        imageAlignment: hall.imageAlignment,
                        onTap: { onSelect(hall.id, 0) }
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxHeight: .infinity)
        }
        // Stretch to full screen; background fills behind safe areas
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.umdBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selectedTab: tabBinding)
        }
    }
}

struct DiningHallCard: View {
    let hallId: String
    let hallName: String
    let imageAlignment: Alignment
    let onTap: () -> Void

    private var status: DiningHallSchedule.Status {
        DiningHallSchedule.all[hallId]?.currentStatus() ?? .closed
    }

    private var statusText: String {
        if status.isOpen, let close = status.dayCloseTime, let meal = status.currentMeal {
            return "Open until \(close) · \(meal)"
        } else if let nextTime = status.nextOpenTime {
            return "Opens at \(nextTime)"
        } else {
            return "Closed today"
        }
    }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                ZStack {
                    Color(.systemGray4)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(alignment: imageAlignment) {
                            Image("hall_\(hallId)")
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width)
                        }
                        .clipped()

                    // Gradient scrim at bottom for text legibility
                    VStack(spacing: 0) {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: min(geo.size.height * 0.55, 90))
                    }

                    // Top-right: OPEN / CLOSING SOON / CLOSED badge
                    VStack {
                        HStack {
                            Spacer()
                            Text(status.isClosingSoon ? "CLOSING SOON" : status.isOpen ? "OPEN" : "CLOSED")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(status.isClosingSoon ? Color.orange : status.isOpen ? Color.green : Color.umdRed)
                                .clipShape(Capsule())
                        }
                        .padding(10)
                        Spacer()
                    }

                    // Bottom-left: status hours ABOVE hall name
                    VStack {
                        Spacer()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(statusText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white.opacity(0.88))
                                Text(hallName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DiningHallPickerView(
        selectedHallId: nil,
        onSelect: { _, _ in }
    )
}
