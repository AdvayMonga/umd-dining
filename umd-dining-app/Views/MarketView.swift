import SwiftUI

struct MarketView: View {
    @Binding var tabResetID: UUID
    @State private var store = MarketStore.shared
    @State private var mode: Mode = .buy
    @State private var showCheckout = false
    @State private var sheetItem: MarketItem?
    @Namespace private var modeNamespace

    enum Mode: String, CaseIterable {
        case buy = "Buy"
        case sell = "Sell"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 14) {
                        if let order = store.activeOrder {
                            MarketOrderCard(order: order, store: store)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        switch mode {
                        case .buy: buyContent
                        case .sell: MarketSellView(store: store)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, store.cartCount > 0 && mode == .buy ? 96 : 32)
                    .animation(.spring(duration: 0.35), value: store.activeOrder?.status)
                }
                .scrollIndicators(.hidden)
            }
            .background(Color.umdBackground)
            .overlay(alignment: .bottom) {
                if mode == .buy && store.cartCount > 0 {
                    cartBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: store.cartCount > 0)
        }
        .id(tabResetID)
        // Expire a request nobody picked up
        .task(id: store.activeOrder?.status) {
            while store.activeOrder?.status == .searching {
                store.expireIfStale()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(item: $sheetItem) { item in
            MarketItemSheet(item: item, rate: store.bestRate) { selections, quantity in
                store.add(item, selections: selections, quantity: quantity)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCheckout) {
            MarketCheckoutSheet(store: store) {
                showCheckout = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Market")
                .font(.inter(size: 22, weight: .bold))
                .foregroundStyle(Color.umdRed)
            Spacer()
            modePicker
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.spring(duration: 0.3)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.inter(size: 14, weight: .semibold))
                        .foregroundStyle(mode == m ? .white : .secondary)
                        .frame(width: 58, height: 30)
                        .background {
                            if mode == m {
                                Capsule()
                                    .fill(Color.umdRed)
                                    .matchedGeometryEffect(id: "mode", in: modeNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.umdSurface))
        .sensoryFeedback(.selection, trigger: mode)
    }

    // MARK: - Buy

    private var buyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.isTakingOrders {
                dealBanner
            } else {
                closedBanner
            }
            locationChips
            hoursLine
            ForEach(categories, id: \.self) { category in
                VStack(alignment: .leading, spacing: 10) {
                    Text(category)
                        .font(.inter(size: 17, weight: .semibold))
                        .padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(store.items.filter { $0.category == category }) { item in
                            MarketItemCard(
                                item: item,
                                rate: store.bestRate,
                                quantity: store.quantity(of: item),
                                isEnabled: store.isTakingOrders,
                                onAdd: {
                                    if item.options.isEmpty { store.add(item) } else { sheetItem = item }
                                },
                                onRemove: { store.removeOne(of: item) }
                            )
                            .onTapGesture { if store.isTakingOrders { sheetItem = item } }
                        }
                    }
                }
            }
        }
    }

    private var hoursLine: some View {
        let status = store.selectedLocation.status()
        let text: String
        if status.isOpen, let close = status.dayCloseTime {
            text = "Open until \(close) · last call \(store.selectedLocation.lastCallMinutes) min before"
        } else if let next = status.nextOpenTime {
            text = "Closed · opens at \(next)"
        } else {
            text = "Closed for today"
        }
        let captured = MarketMenu.capturedOn[store.selectedLocationId]
        return VStack(alignment: .leading, spacing: 4) {
            Label(text, systemImage: "clock")
            Label(captured.map { "Menu from Grubhub · updated \($0)" } ?? "Sample menu · prices not confirmed yet",
                  systemImage: captured == nil ? "exclamationmark.circle" : "checkmark.circle")
            #if DEBUG
            if !store.menuFlags.isEmpty {
                Label("\(store.menuFlags.count) real order(s) didn't match menu prices. Refresh the menu.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            #endif
        }
        .font(.inter(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var closedBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.umdRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.selectedLocation.name) isn't taking orders")
                        .font(.inter(size: 16, weight: .bold))
                    Text("You can browse the menu. Ordering opens with the restaurant.")
                        .font(.inter(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            #if DEBUG
            Button("Demo: order anyway") {
                withAnimation(.spring(duration: 0.3)) { store.ignoreHours = true }
            }
            .font(.inter(size: 13, weight: .semibold))
            .foregroundStyle(Color.umdRed)
            #endif
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeCard(tint: .gray, thin: true)
    }

    private var categories: [String] {
        var seen: [String] = []
        for item in store.items where !seen.contains(item.category) { seen.append(item.category) }
        return seen
    }

    private var dealBanner: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(store.discountPercent)% off")
                    .font(.inter(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text("everything, paid with a student's Dining Dollars")
                    .font(.inter(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Label("\(store.onlineSellerRates.count) online", systemImage: "circle.fill")
                    .labelStyle(OnlineDotLabelStyle())
                Label("~8 min", systemImage: "bolt.fill")
                    .font(.inter(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.umdRed, Color.umdRedActive],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            Text("🍗")
                .font(.system(size: 64))
                .opacity(0.18)
                .rotationEffect(.degrees(-12))
                .offset(x: -70, y: 6)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.umdRed.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    private var locationChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(store.locations) { loc in
                    let selected = loc.id == store.selectedLocationId
                    Button {
                        guard loc.isLive else { return }
                        withAnimation(.spring(duration: 0.3)) { store.selectedLocationId = loc.id }
                    } label: {
                        HStack(spacing: 6) {
                            Text(loc.name)
                                .font(.inter(size: 14, weight: .semibold))
                            if !loc.isLive {
                                Text("SOON")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }
                        }
                        .foregroundStyle(selected ? .white : loc.isLive ? .primary : .secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(selected ? Color.umdRed : Color(.systemBackground)))
                        .overlay(Capsule().stroke(selected ? .clear : Color.umdBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!loc.isLive)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Cart bar

    private var cartBar: some View {
        Button { showCheckout = true } label: {
            HStack(spacing: 12) {
                Text("\(store.cartCount)")
                    .font(.inter(size: 15, weight: .bold))
                    .foregroundStyle(Color.umdRed)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white))
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 1) {
                    Text("View order")
                        .font(.inter(size: 16, weight: .bold))
                    Text("You save \((store.cartDDTotal - store.cartPrice).dollars)")
                        .font(.inter(size: 12, weight: .medium))
                        .opacity(0.85)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text(store.cartPrice.dollars)
                    .font(.inter(size: 17, weight: .bold))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.umdRed))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            .animation(.snappy, value: store.cartCount)
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct OnlineDotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(.green)
            configuration.title
                .font(.inter(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - Item card

struct MarketItemCard: View {
    let item: MarketItem
    let rate: Double
    let quantity: Int
    var isEnabled = true
    let onAdd: () -> Void
    let onRemove: () -> Void

    private var price: Double { item.ddPrice * rate }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.umdRed.opacity(0.08))
                Text(item.emoji)
                    .font(.system(size: 44))
            }
            .frame(height: 84)
            .overlay(alignment: .topTrailing) {
                if quantity > 0 {
                    Text("\(quantity)")
                        .font(.inter(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Circle().fill(Color.umdRed))
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.inter(size: 14, weight: .semibold))
                    .lineLimit(2, reservesSpace: true)
                // Fixed one-line slot keeps card heights even
                Text(item.calories.map { "\($0) cal" } ?? (item.options.isEmpty ? " " : "Customizable"))
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.ddPrice.dollars)
                        .font(.inter(size: 11, weight: .medium))
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Text(price.dollars)
                        .font(.inter(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                if isEnabled { stepper }
            }
        }
        .padding(10)
        .opacity(isEnabled ? 1 : 0.6)
        .contentShape(Rectangle())
        .homeCard(tint: quantity > 0 ? .umdRed : .gray, thin: quantity == 0)
        .animation(.spring(duration: 0.3), value: quantity)
        .sensoryFeedback(.increase, trigger: quantity)
    }

    @ViewBuilder
    private var stepper: some View {
        if quantity == 0 {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.umdRed))
            }
            .buttonStyle(PressableButtonStyle())
        } else {
            HStack(spacing: 0) {
                Button(action: onRemove) {
                    Image(systemName: quantity == 1 ? "trash" : "minus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 32)
                }
                Text("\(quantity)")
                    .font(.inter(size: 14, weight: .bold))
                    .frame(minWidth: 14)
                    .contentTransition(.numericText())
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 32)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.umdRed)
            .background(Capsule().fill(Color.umdRed.opacity(0.12)))
        }
    }
}

#Preview {
    MarketView(tabResetID: .constant(UUID()))
}
