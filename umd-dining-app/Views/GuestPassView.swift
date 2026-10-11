import SwiftUI

struct GuestPassView: View {
    @Binding var tabResetID: UUID
    @State private var store = GuestPassStore.shared
    @State private var mode: Mode = .buy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? { reduceMotion ? nil : .spring(duration: 0.35) }

    enum Mode: String, CaseIterable {
        case buy = "Buy a pass"
        case sell = "Sell my passes"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 14) {
                        if let period = DiningSpecialHours.period() {
                            specialHoursBanner(period)
                        }
                        if let match = store.activeMatch {
                            GuestPassMatchCard(match: match, store: store)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        switch mode {
                        case .buy: buyContent
                        case .sell: GuestPassHolderView(store: store)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    // Clear the floating tab bar, plus the request bar when it shows
                    .padding(.bottom, CustomTabBar.clearance + (showRequestBar ? 96 : 24))
                    .animation(spring, value: store.activeMatch?.status)
                }
                .scrollIndicators(.hidden)
            }
            .background(Color.umdBackground)
            .overlay(alignment: .bottom) {
                if showRequestBar {
                    requestBar.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(spring, value: showRequestBar)
        }
        .id(tabResetID)
        .task(id: store.activeMatch?.status) {
            while store.activeMatch?.status == .searching {
                store.expireIfStale()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var showRequestBar: Bool { mode == .buy && store.activeMatch == nil }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guest Passes")
                .font(.inter(size: 22, weight: .bold))
                .foregroundStyle(Color.umdRed)
                .frame(height: 36)
            Picker("Mode", selection: $mode.animation(spring)) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: mode)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func specialHoursBanner(_ period: DiningSpecialHours.Period) -> some View {
        Link(destination: URL(string: "https://dining.umd.edu/hours-locations")!) {
            HStack(spacing: 10) {
                Image(systemName: period.closed ? "moon.zzz.fill" : "calendar.badge.clock")
                    .foregroundStyle(.orange)
                Text(period.note)
                    .font(.inter(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
        }
        .accessibilityHint("Opens UMD Dining hours")
    }

    // MARK: - Buy

    private var buyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.activeMatch == nil {
                priceCard
            }
            Text("Pick a dining hall")
                .font(.inter(size: 17, weight: .semibold))
            VStack(spacing: 10) {
                ForEach(GuestPassHall.all) { hall in
                    GuestPassHallCard(
                        hall: hall,
                        freeNow: store.holdersFreeNow(at: hall),
                        scheduled: store.scheduledHolders[hall.id] ?? 0,
                        isSelected: hall.id == store.selectedHallId
                    ) {
                        withAnimation(spring) {
                            store.selectedHallId = hall.id
                            if !hall.status.isOpen, store.timing == .now {
                                store.timing = GuestPassTiming.slots(for: hall).first.map { .at($0) } ?? .now
                            }
                        }
                    }
                }
            }
            timePicker
            howItWorks
        }
    }

    /// Same price at every hall; it only changes by meal
    private var priceCard: some View {
        let current = store.selectedMeal
        return VStack(alignment: .leading, spacing: 12) {
            Text("Eat at any dining hall for less than the door price. A student swipes you in with a guest pass.")
                .font(.inter(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(["Breakfast", "Lunch", "Dinner"], id: \.self) { meal in
                    let isCurrent = meal == current || (meal == "Lunch" && current == "Brunch")
                    VStack(spacing: 2) {
                        Text(meal)
                            .font(.inter(size: 12, weight: .semibold))
                        Text(GuestPassPricing.format(GuestPassPricing.buyerPrice(meal)))
                            .font(.inter(size: 22, weight: .bold))
                        Text("\(GuestPassPricing.format(GuestPassPricing.door(meal))) at door")
                            .font(.inter(size: 10, weight: .medium))
                            .strikethrough()
                            .opacity(0.75)
                    }
                    .foregroundStyle(isCurrent ? Color.umdRed : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(isCurrent ? Color.white : Color.white.opacity(0.14)))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [Color.umdRed, Color.umdRedActive], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.umdRed.opacity(0.25), radius: 8, x: 0, y: 4)
        .animation(spring, value: current)
    }

    private var timePicker: some View {
        let hall = store.selectedHall
        let slots = GuestPassTiming.slots(for: hall)
        return VStack(alignment: .leading, spacing: 10) {
            Text("When")
                .font(.inter(size: 17, weight: .semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    timeChip(.now, enabled: hall.status.isOpen)
                    ForEach(slots, id: \.self) { slot in
                        timeChip(.at(slot), enabled: true)
                    }
                }
            }
            .scrollIndicators(.hidden)
            if slots.isEmpty && !hall.status.isOpen {
                Text("\(hall.name) is closed for the next few hours.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeChip(_ timing: GuestPassTiming, enabled: Bool) -> some View {
        let selected = store.timing == timing
        let meal = GuestPassPricing.meal(at: store.selectedHall, timing.date)
        return Button {
            withAnimation(spring) { store.timing = timing }
        } label: {
            VStack(spacing: 1) {
                Text(timing.label)
                    .font(.inter(size: 14, weight: .semibold))
                Text(enabled ? "\(meal) · \(GuestPassPricing.format(GuestPassPricing.buyerPrice(meal)))" : "Closed")
                    .font(.inter(size: 11, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(selected ? .white : enabled ? .primary : .secondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.umdRed : Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? .clear : Color.umdBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: store.timing)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works")
                .font(.inter(size: 15, weight: .semibold))
            howStep("mappin.and.ellipse", "Meet at the card swipe", "Each hall has a set spot. You'll see each other's first name.")
            howStep("person.badge.key.fill",
                    GuestPassRules.holderMustEnter ? "Walk in together" : "They swipe you in",
                    GuestPassRules.holderMustEnter ? "Your guest pass holder walks in with you." : "Takes a few seconds; they can head off after.")
            howStep("lock.shield.fill", "Pay once you're in", "You're only charged after you tap \"I'm in\".")
        }
        .padding(16)
        .homeCard(tint: .gray, thin: true)
    }

    private func howStep(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.umdRed)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.umdRed.opacity(0.1)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.inter(size: 14, weight: .semibold))
                Text(text)
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var requestBar: some View {
        let hall = store.selectedHall
        let meal = store.selectedMeal
        let canRequest = store.timing != .now || hall.status.isOpen
        return Button {
            withAnimation(spring) { store.request() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Get a guest pass")
                        .font(.inter(size: 16, weight: .bold))
                    Text("\(hall.name) · \(meal) · \(store.timing.label)")
                        .font(.inter(size: 12, weight: .medium))
                        .opacity(0.85)
                }
                Spacer()
                Text(GuestPassPricing.format(GuestPassPricing.buyerPrice(meal)))
                    .font(.inter(size: 18, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.umdRed.opacity(canRequest ? 1 : 0.5)))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!canRequest)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        // Sit above the floating tab bar instead of under it
        .padding(.bottom, CustomTabBar.clearance + 10)
        .background(alignment: .bottom) {
            // Solid strip so scrolled content doesn't show between the button and the tab bar
            LinearGradient(colors: [Color.umdBackground.opacity(0), Color.umdBackground], startPoint: .top, endPoint: .center)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .sensoryFeedback(.success, trigger: store.activeMatch != nil)
    }
}

// MARK: - Hall card

struct GuestPassHallCard: View {
    let hall: GuestPassHall
    let freeNow: Int
    let scheduled: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Color(.systemGray4)
                    .overlay {
                        Image("hall_\(hall.id)")
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusText)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.88))
                        Text(hall.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Label(availability, systemImage: "person.2.fill")
                        .font(.inter(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.35)))
                }
                .padding(12)
            }
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.umdRed : .clear, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, Color.umdRed)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hall.name), \(statusText), \(availability)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var availability: String {
        hall.status.isOpen && freeNow > 0 ? "\(freeNow) free now" : "\(scheduled) free later"
    }

    private var statusText: String {
        let status = hall.status
        if status.isOpen, let close = status.dayCloseTime, let meal = status.currentMeal {
            return "Open until \(close) · \(meal)"
        } else if let next = status.nextOpenTime {
            return "Opens at \(next)"
        }
        return "Closed now"
    }
}

#Preview {
    GuestPassView(tabResetID: .constant(UUID()))
}
