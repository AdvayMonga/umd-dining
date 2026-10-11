import PhotosUI
import SwiftUI

struct MarketSellView: View {
    @Bindable var store: MarketStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            paceCard
            rateCard

            if !store.jobs.isEmpty {
                SectionHeader(title: "Your Jobs")
                ForEach(store.jobs) { job in
                    SellerJobCard(job: job, store: store)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }
            }

            SectionHeader(title: "Requests", trailing: store.isSelling ? "\(store.requests.count) near Stamp" : nil)
            if !store.isSelling {
                emptyState(icon: "moon.zzz.fill", text: "You're offline. Go online to see requests.")
            } else if store.requests.isEmpty {
                emptyState(icon: "tray", text: "No open requests right now. We'll ping you.")
            } else {
                ForEach(store.requests) { request in
                    RequestCard(request: request, rate: store.sellerRate) {
                        withAnimation(.spring(duration: 0.35)) { store.accept(request) }
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
        }
    }

    // MARK: - Pace

    private var paceCard: some View {
        let pace = store.pace
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dining Dollars")
                        .font(.inter(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(pace.balance.dollarsShort)
                        .font(.inter(size: 34, weight: .bold))
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Earned")
                        .font(.inter(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(store.earnedThisSemester.dollars)
                        .font(.inter(size: 20, weight: .bold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                    Text("★ \(String(format: "%.1f", store.sellerRating)) · \(store.completedJobs) orders")
                        .font(.inter(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.umdGold.opacity(0.35))
                    Capsule()
                        .fill(Color.umdRed)
                        .frame(width: geo.size.width * pace.usageFraction)
                }
            }
            .frame(height: 12)

            HStack(spacing: 14) {
                legendDot(Color.umdRed, "You'll spend \(pace.projectedSpend.dollarsShort)")
                legendDot(Color.umdGold, "Left over \(pace.projectedSurplus.dollarsShort)")
            }

            if pace.projectedSurplus > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("At your pace, **\(pace.projectedSurplus.dollarsShort)** expires on \(pace.expiresOn.formatted(.dateTime.month(.abbreviated).day())). Sell it for about **\(MarketPricing.sellerTake(buyerPays: pace.projectedSurplus * store.sellerRate).dollarsShort)** instead.")
                        .font(.inter(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }
        }
        .padding(16)
        .homeCard()
        .animation(.spring(duration: 0.4), value: pace.balance)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.inter(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rate & availability

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $store.isSelling.animation(.spring(duration: 0.3))) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.isSelling ? Color.green : Color(.systemGray3))
                        .frame(width: 10, height: 10)
                    Text(store.isSelling ? "Online — taking requests" : "Offline")
                        .font(.inter(size: 15, weight: .semibold))
                }
            }
            .tint(.green)

            Divider()

            Text("Your rate")
                .font(.inter(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(MarketPricing.sellerRates, id: \.self) { rate in
                    let selected = store.sellerRate == rate
                    Button {
                        withAnimation(.spring(duration: 0.25)) { store.sellerRate = rate }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(Int((rate * 100).rounded()))¢")
                                .font(.inter(size: 18, weight: .bold))
                            Text("\(Int(((1 - rate) * 100).rounded()))% off")
                                .font(.inter(size: 11, weight: .medium))
                                .opacity(0.8)
                        }
                        .foregroundStyle(selected ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.umdRed : Color.umdSurface))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .sensoryFeedback(.selection, trigger: store.sellerRate)

            Text("Buyers pay \(Int((store.sellerRate * 100).rounded()))¢ per Dining Dollar; you keep \(Int((MarketPricing.sellerTake(buyerPays: store.sellerRate) * 100).rounded()))¢. Lower rates get matched first.")
                .font(.inter(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .homeCard(tint: .gray, thin: true)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color(.systemGray3))
            Text(text)
                .font(.inter(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Request card

private struct RequestCard: View {
    let request: MarketRequest
    let rate: Double
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(request.lines.first?.item.emoji ?? "🍗")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.umdRed.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(itemCountText)
                        .font(.inter(size: 15, weight: .semibold))
                    Text("\(request.location.name) · \(request.postedMinutesAgo) min ago · ★ \(String(format: "%.1f", request.buyerRating))")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("+\(request.sellerEarns(at: rate).dollars)")
                        .font(.inter(size: 18, weight: .bold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                    Text("for \(request.ddTotal.dollars) DD")
                        .font(.inter(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            OrderLinesList(lines: request.lines)

            Button(action: onAccept) {
                Text("Accept")
                    .font(.inter(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdRed))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(14)
        .homeCard(tint: .gray, thin: true)
    }

    private var itemCountText: String {
        let count = request.lines.reduce(0) { $0 + $1.quantity }
        return count == 1 ? "1 item" : "\(count) items"
    }
}

/// Items with their chosen options, so the seller can copy them into Grubhub exactly
private struct OrderLinesList: View {
    let lines: [CartLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines) { line in
                HStack(alignment: .top, spacing: 10) {
                    Text(line.item.emoji)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.quantity > 1 ? "\(line.quantity)× \(line.item.name)" : line.item.name)
                            .font(.inter(size: 13, weight: .semibold))
                        if !line.summary.isEmpty {
                            Text(line.summary)
                                .font(.inter(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdSurface))
    }
}

// MARK: - Grubhub checklist

/// The buyer's order as taps in Grubhub's own screen order: open the item,
/// pick each option group top to bottom, set quantity, add to bag.
struct GrubhubChecklist: View {
    let lines: [CartLine]
    @Binding var ticked: Set<String>

    struct Step: Identifiable {
        let id: String
        let label: String
        let detail: String?
    }

    static func steps(for line: CartLine, index: Int) -> [Step] {
        var steps = [Step(id: "\(index)-open", label: "\(line.item.category) → \(line.item.name)", detail: nil)]
        for group in line.item.options {
            let picked = line.selections[group.id] ?? []
            // Grubhub lists choices in its own order, so follow that rather than pick order
            let names = group.choices.filter { picked.contains($0.id) }.map(\.name)
            guard !names.isEmpty else { continue }
            steps.append(Step(id: "\(index)-\(group.id)", label: group.title, detail: names.joined(separator: ", ")))
        }
        if line.quantity > 1 {
            steps.append(Step(id: "\(index)-qty", label: "Quantity", detail: "\(line.quantity)"))
        }
        steps.append(Step(id: "\(index)-add", label: "Add to bag", detail: nil))
        return steps
    }

    static func stepCount(_ lines: [CartLine]) -> Int {
        lines.enumerated().reduce(0) { $0 + steps(for: $1.element, index: $1.offset).count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.steps(for: line, index: index)) { step in
                        let isOn = ticked.contains(step.id)
                        Button {
                            withAnimation(.snappy) {
                                if isOn { ticked.remove(step.id) } else { ticked.insert(step.id) }
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 17))
                                    .foregroundStyle(isOn ? .green : Color(.systemGray3))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(step.label)
                                        .font(.inter(size: 13, weight: step.id.hasSuffix("-open") ? .bold : .semibold))
                                    if let detail = step.detail {
                                        Text(detail)
                                            .font(.inter(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .strikethrough(isOn)
                                .opacity(isOn ? 0.6 : 1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .padding(.leading, step.id.hasSuffix("-open") ? 0 : 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdSurface))
            }
        }
        .sensoryFeedback(.selection, trigger: ticked)
    }
}

// MARK: - Seller job

private struct SellerJobCard: View {
    let job: SellerJob
    let store: MarketStore

    @Environment(\.openURL) private var openURL
    @State private var copied = false
    @State private var orderNumber = ""
    @State private var screenshot: PhotosPickerItem?
    @State private var reading: OrderScreenshotReader.Reading?
    @State private var isReading = false
    @State private var ticked: Set<String> = []
    @State private var bagCheck: BagCheck?
    @State private var grubhubBagText = ""

    enum BagCheck { case matches, different }

    private var earns: String { job.request.sellerEarns(at: job.rate).dollars }
    private var orderNumberValid: Bool { orderNumber.filter(\.isNumber).count >= 3 }
    private var placed: Bool { job.step.rawValue > SellerJobStep.placeOrder.rawValue }
    private var checklistDone: Bool { ticked.count >= GrubhubChecklist.stepCount(job.request.lines) }
    private var canSubmitProof: Bool { orderNumberValid && bagCheck != nil }

    /// Bag total vs ours, checked before the seller pays so a stale menu never costs them
    @ViewBuilder
    private var bagTotalCheck: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Grubhub bag subtotal should be")
                    .font(.inter(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(job.request.ddTotal.dollars)
                    .font(.inter(size: 17, weight: .bold))
            }
            HStack(spacing: 8) {
                choiceButton("Matches", icon: "checkmark", selected: bagCheck == .matches) { bagCheck = .matches }
                choiceButton("It's different", icon: "exclamationmark.triangle", selected: bagCheck == .different) { bagCheck = .different }
            }
            if bagCheck == .different {
                HStack {
                    Text("$").foregroundStyle(.secondary)
                    TextField("What Grubhub shows", text: $grubhubBagText)
                        .keyboardType(.decimalPad)
                        .font(.inter(size: 15, weight: .medium))
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdSurface))
                Text("Double-check every option against the checklist first. If it's still different, you can release the job without paying, or go ahead: you're paid \(earns) either way, and we'll fix the menu.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Release this job") {
                    withAnimation(.spring(duration: 0.35)) { store.releaseJob(job, grubhubBag: Double(grubhubBagText)) }
                }
                .font(.inter(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            }
        }
    }

    private func choiceButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Label(title, systemImage: icon)
                .font(.inter(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.umdRed : Color.umdSurface))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Order for \(job.request.pickupCode)")
                    .font(.inter(size: 16, weight: .bold))
                Spacer()
                Text("+\(earns)")
                    .font(.inter(size: 16, weight: .bold))
                    .foregroundStyle(.green)
            }

            stepRow(1, "Build the bag in Grubhub", done: placed || checklistDone) {
                VStack(alignment: .leading, spacing: 10) {
                    smallButton("Open Grubhub", icon: "arrow.up.forward.app") {
                        openURL(URL(string: "https://www.grubhub.com")!)
                    }
                    GrubhubChecklist(lines: job.request.lines, ticked: $ticked)
                }
            }

            stepRow(2, "Check the bag total before paying", done: placed || bagCheck != nil) {
                bagTotalCheck
            }

            stepRow(3, "Check out with order name \"\(job.request.pickupCode)\"", done: placed || copied) {
                Button {
                    UIPasteboard.general.string = job.request.pickupCode
                    copied = true
                } label: {
                    Label("Copy \"\(job.request.pickupCode)\"", systemImage: "doc.on.doc")
                        .font(.inter(size: 12, weight: .semibold))
                        .foregroundStyle(Color.umdRed)
                }
                .buttonStyle(.plain)
            }

            stepRow(4, "Add proof of order", done: placed) {
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $screenshot, matching: .screenshots) {
                        Label(screenshot == nil ? "Attach confirmation screenshot" : "Screenshot attached",
                              systemImage: screenshot == nil ? "photo.badge.plus" : "checkmark.circle.fill")
                            .font(.inter(size: 13, weight: .semibold))
                            .foregroundStyle(screenshot == nil ? Color.umdRed : .green)
                    }
                    readingStatus

                    HStack {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                        TextField("Grubhub order #", text: $orderNumber)
                            .keyboardType(.numberPad)
                            .font(.inter(size: 15, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdSurface))
                }
                .task(id: screenshot) { await readScreenshot() }
            }

            stepRow(5, "Mark ready when Grubhub says it is", done: job.step.rawValue > SellerJobStep.markReady.rawValue) { EmptyView() }

            if job.step != .rate && job.step != .done {
                MessageThread(messages: job.messages, replies: QuickReplies.seller) { store.sendSellerMessage(job, $0) }
            }

            footer
        }
        .padding(14)
        .homeCard()
        .sensoryFeedback(.success, trigger: job.step)
    }

    /// What the screenshot told us: order # found, subtotal matches or not
    @ViewBuilder
    private var readingStatus: some View {
        if isReading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading screenshot…")
            }
            .font(.inter(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        } else if let reading {
            VStack(alignment: .leading, spacing: 4) {
                if let number = reading.orderNumber {
                    Label("Found order #\(number)", systemImage: "checkmark")
                        .foregroundStyle(.green)
                }
                if let grubhub = reading.subtotalMismatch(expected: job.request.ddTotal) {
                    Label("Grubhub subtotal \(grubhub.dollars) vs our \(job.request.ddTotal.dollars). We'll recheck the menu; you still get \(earns).",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if let subtotal = reading.subtotal {
                    Label("Subtotal \(subtotal.dollars) matches", systemImage: "checkmark")
                        .foregroundStyle(.green)
                } else if reading.orderNumber == nil {
                    Label("Couldn't read this one. Enter the order # below.", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.inter(size: 12, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readScreenshot() async {
        guard let screenshot else { reading = nil; return }
        isReading = true
        defer { isReading = false }
        guard let data = try? await screenshot.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { reading = nil; return }
        let result = await OrderScreenshotReader.read(image)
        reading = result
        if orderNumber.isEmpty, let number = result.orderNumber { orderNumber = number }
    }

    @ViewBuilder
    private var footer: some View {
        switch job.step {
        case .placeOrder:
            mainButton("Submit proof", icon: "checkmark.seal", enabled: canSubmitProof) {
                if bagCheck == .different, let grubhub = Double(grubhubBagText) {
                    store.flagMenu(job.request, grubhub: grubhub)
                }
                store.submitProof(job, orderNumber: orderNumber.filter(\.isNumber), reading: reading)
            }
        case .markReady:
            mainButton("Mark ready for pickup", icon: "bell.badge", enabled: true) {
                store.markReady(job)
            }
        case .waitingPickup:
            HStack(spacing: 10) {
                ProgressView()
                Text("Waiting for \(job.request.pickupCode) to pick up…")
                    .font(.inter(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .rate:
            VStack(alignment: .leading, spacing: 8) {
                Text("Picked up! \(earns) is on its way. How was the buyer?")
                    .font(.inter(size: 14, weight: .semibold))
                HStack(spacing: 10) {
                    rateButton(up: true)
                    rateButton(up: false)
                }
            }
        case .done:
            Label("Paid \(earns)", systemImage: "checkmark.circle.fill")
                .font(.inter(size: 15, weight: .bold))
                .foregroundStyle(.green)
        }
    }

    private func rateButton(up: Bool) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { store.rateBuyer(job, thumbsUp: up) }
        } label: {
            Image(systemName: up ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                .font(.system(size: 18))
                .foregroundStyle(up ? .green : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdSurface))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func mainButton(_ title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.35)) { action() }
        } label: {
            Label(title, systemImage: icon)
                .font(.inter(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdRed.opacity(enabled ? 1 : 0.4)))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
    }

    private func smallButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.inter(size: 13, weight: .semibold))
                .foregroundStyle(Color.umdRed)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .overlay(Capsule().stroke(Color.umdRed.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func stepRow<Content: View>(_ n: Int, _ title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.green : Color.umdSurface)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(n)").font(.inter(size: 12, weight: .bold))
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.inter(size: 14, weight: .semibold))
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
                if !done { content() }
            }
        }
    }
}
