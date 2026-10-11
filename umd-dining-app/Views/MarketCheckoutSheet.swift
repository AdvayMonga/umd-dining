import SwiftUI

struct MarketCheckoutSheet: View {
    let store: MarketStore
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Text("🍗")
                            .font(.system(size: 28))
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.umdRed.opacity(0.1)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.selectedLocation.name)
                                .font(.inter(size: 20, weight: .bold))
                            Text("Pickup at \(store.selectedLocation.building) · ready in ~8 min")
                                .font(.inter(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 24)

                    VStack(spacing: 0) {
                        ForEach(store.cart) { line in
                            lineRow(line)
                            if line.id != store.cart.last?.id {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .homeCard(tint: .gray, thin: true)

                    anonymityNote
                    summary

                    Label("If no seller accepts within 5 minutes, the request expires. You're only charged after you confirm pickup.", systemImage: "lock.shield.fill")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            buyButton
        }
        .background(Color.umdBackground)
        .onChange(of: store.cartCount) { if store.cartCount == 0 { onDone() } }
    }

    private func lineRow(_ line: CartLine) -> some View {
        HStack(spacing: 12) {
            Text(line.item.emoji)
                .font(.system(size: 22))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.item.name)
                    .font(.inter(size: 15, weight: .semibold))
                if !line.summary.isEmpty {
                    Text(line.summary)
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text((line.ddTotal * store.bestRate).dollars)
                    .font(.inter(size: 13, weight: .semibold))
            }
            Spacer()
            HStack(spacing: 14) {
                Button { store.decrement(line) } label: {
                    Image(systemName: line.quantity == 1 ? "trash" : "minus")
                }
                Text("\(line.quantity)")
                    .font(.inter(size: 15, weight: .bold))
                    .contentTransition(.numericText())
                Button { store.increment(line) } label: {
                    Image(systemName: "plus")
                }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.umdRed)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var anonymityNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "theatermasks.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.umdRed)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.umdRed.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text("You stay anonymous")
                    .font(.inter(size: 15, weight: .semibold))
                Text("You'll get a pickup code like \"Terp 48\". Your seller puts it on the order, and you say it at the pickup shelf. No names are shared either way.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeCard(tint: .gray, thin: true)
    }

    private var summary: some View {
        VStack(spacing: 10) {
            summaryRow("Menu price", store.cartDDTotal.dollars, muted: true)
            summaryRow("Market discount (\(store.discountPercent)%)", "−" + (store.cartDDTotal - store.cartPrice).dollars, tint: .green)
            Divider()
            summaryRow("You pay", store.cartPrice.dollars, bold: true)
        }
        .padding(14)
        .homeCard(tint: .gray, thin: true)
    }

    private func summaryRow(_ label: String, _ value: String, muted: Bool = false, bold: Bool = false, tint: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.inter(size: bold ? 16 : 14, weight: bold ? .bold : .medium))
                .foregroundStyle(muted ? .secondary : .primary)
            Spacer()
            Text(value)
                .font(.inter(size: bold ? 18 : 14, weight: bold ? .bold : .semibold))
                .foregroundStyle(muted ? .secondary : tint)
                .strikethrough(muted)
                .contentTransition(.numericText())
        }
    }

    private var buyButton: some View {
        Button {
            withAnimation(.spring(duration: 0.4)) {
                store.placeOrder()
            }
            onDone()
        } label: {
            HStack {
                Image(systemName: "bolt.fill")
                Text("Buy now · \(store.cartPrice.dollars)")
            }
            .font(.inter(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.umdRed))
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.umdBackground)
        .sensoryFeedback(.success, trigger: store.activeOrder != nil)
    }
}
