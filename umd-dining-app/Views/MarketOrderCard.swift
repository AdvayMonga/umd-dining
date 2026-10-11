import SwiftUI

/// Live order tracker pinned to the top of the Market tab
struct MarketOrderCard: View {
    let order: MarketOrder
    let store: MarketStore

    @State private var showProblem = false
    @State private var showCancel = false

    private var isClosed: Bool { [.expired, .cancelled].contains(order.status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if order.status == .searching {
                searchingRow
            } else if OrderStatus.track.contains(order.status) {
                progressTrack
            }

            Text(order.status.buyerMessage)
                .font(.inter(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)

            if let problem = order.problem {
                Label(problem.rawValue, systemImage: problem.icon)
                    .font(.inter(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            itemList

            if order.status >= .matched && !isClosed {
                HStack(spacing: 10) {
                    infoTile(label: "Pickup code", value: order.pickupCode)
                    infoTile(label: "Grubhub order #", value: order.orderNumber.map { "#\($0)" } ?? "Waiting…")
                }
            }

            if [.matched, .placed, .ready].contains(order.status) {
                MessageThread(messages: order.messages, replies: QuickReplies.buyer) { store.sendBuyerMessage($0) }
            }

            actions

            if order.status != .searching && !isClosed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.umdRed)
                    Text("Verified UMD seller · ★ \(String(format: "%.1f", order.sellerRating))")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Saving \(order.savings.dollars)")
                        .font(.inter(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .homeCard(tint: order.status == .disputed ? .orange : .umdRed)
        .sensoryFeedback(.success, trigger: order.status)
        .confirmationDialog("What went wrong?", isPresented: $showProblem, titleVisibility: .visible) {
            ForEach(ProblemReason.allCases) { reason in
                Button(reason.rawValue) {
                    withAnimation(.spring(duration: 0.35)) { store.reportProblem(reason) }
                }
            }
        } message: {
            Text("Your payment stays on hold until it's resolved.")
        }
        .confirmationDialog("Cancel this order?", isPresented: $showCancel, titleVisibility: .visible) {
            Button("Cancel order", role: .destructive) {
                withAnimation(.spring(duration: 0.35)) { store.cancelOrder() }
            }
        } message: {
            Text("You won't be charged.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(order.status == .disputed ? "ON HOLD" : "YOUR ORDER")
                    .font(.inter(size: 11, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(order.status == .disputed ? .orange : Color.umdRed)
                Text(order.location.name)
                    .font(.inter(size: 18, weight: .bold))
            }
            Spacer()
            Text(order.buyerPays.dollars)
                .font(.inter(size: 18, weight: .bold))
        }
    }

    private var searchingRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, MarketStore.matchTimeout - context.date.timeIntervalSince(order.placedAt))
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Color.umdRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finding a seller…")
                        .font(.inter(size: 15, weight: .semibold))
                    Text("\(store.onlineSellerRates.count) sellers online · expires in \(Int(left) / 60):\(String(format: "%02d", Int(left) % 60))")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdSurface))
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(order.lines) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text(line.item.emoji)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.quantity > 1 ? "\(line.quantity)× \(line.item.name)" : line.item.name)
                            .font(.inter(size: 13, weight: .semibold))
                        if !line.summary.isEmpty {
                            Text(line.summary)
                                .font(.inter(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch order.status {
        case .ready:
            primaryButton("I picked it up · pay \(order.buyerPays.dollars)", color: .green) {
                withAnimation(.spring(duration: 0.35)) { store.confirmPickup() }
            }
            secondaryLinks
        case .searching, .matched, .placed:
            secondaryLinks
        case .pickedUp:
            ratingRow
        case .expired, .cancelled:
            HStack(spacing: 10) {
                primaryButton("Try again", color: .umdRed) {
                    withAnimation(.spring(duration: 0.35)) { store.retryOrder() }
                }
                Button("Dismiss") { withAnimation { store.dismissOrder() } }
                    .font(.inter(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        case .disputed:
            Button("Dismiss") { withAnimation { store.dismissOrder() } }
                .font(.inter(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var secondaryLinks: some View {
        HStack {
            if order.status.canCancel {
                Button("Cancel order") { showCancel = true }
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if order.status.canReportProblem {
                Button { showProblem = true } label: {
                    Label("Something's wrong", systemImage: "exclamationmark.bubble")
                }
                .foregroundStyle(.orange)
            }
        }
        .font(.inter(size: 13, weight: .semibold))
        .buttonStyle(.plain)
    }

    private var ratingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(order.myRating == nil ? "How was your seller?" : "Thanks for rating!")
                .font(.inter(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.spring(duration: 0.25)) { store.rateSeller(star) }
                    } label: {
                        Image(systemName: star <= (order.myRating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 26))
                            .foregroundStyle(star <= (order.myRating ?? 0) ? Color.umdGold : Color(.systemGray3))
                    }
                    .buttonStyle(.plain)
                    .disabled(order.myRating != nil)
                }
            }
            Text("Ratings are anonymous.")
                .font(.inter(size: 11))
                .foregroundStyle(.secondary)
        }
        .sensoryFeedback(.selection, trigger: order.myRating)
    }

    private func primaryButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.inter(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(color))
        }
        .buttonStyle(PressableButtonStyle())
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private var progressTrack: some View {
        HStack(spacing: 0) {
            ForEach(OrderStatus.track, id: \.self) { step in
                let reached = step <= order.status
                VStack(spacing: 6) {
                    Image(systemName: step.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(reached ? .white : Color(.systemGray3))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(reached ? Color.umdRed : Color.umdSurface))
                        .scaleEffect(step == order.status ? 1.12 : 1)
                    Text(step.title)
                        .font(.inter(size: 10, weight: .semibold))
                        .foregroundStyle(reached ? .primary : .secondary)
                }
                .frame(width: 64)
                if step != OrderStatus.track.last {
                    Capsule()
                        .fill(step < order.status ? Color.umdRed : Color.umdSurface)
                        .frame(height: 3)
                        .padding(.bottom, 18)
                }
            }
        }
    }

    private func infoTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.inter(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.inter(size: 17, weight: .bold))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdSurface))
    }
}

// MARK: - Quick-reply thread (shared by buyer and seller cards)

struct MessageThread: View {
    let messages: [QuickMessage]
    let replies: [String]
    let onSend: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(messages) { msg in
                HStack {
                    if msg.sender == .me { Spacer(minLength: 40) }
                    Text(msg.text)
                        .font(.inter(size: 13, weight: .medium))
                        .foregroundStyle(msg.sender == .me ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(msg.sender == .me ? Color.umdRed : Color.umdSurface)
                        )
                    if msg.sender == .them { Spacer(minLength: 40) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(replies, id: \.self) { reply in
                        Button {
                            withAnimation(.spring(duration: 0.3)) { onSend(reply) }
                        } label: {
                            Text(reply)
                                .font(.inter(size: 12, weight: .semibold))
                                .foregroundStyle(Color.umdRed)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .overlay(Capsule().stroke(Color.umdRed.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: messages.count)
    }
}
