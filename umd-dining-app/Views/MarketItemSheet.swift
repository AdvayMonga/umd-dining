import SwiftUI

/// Grubhub-style item screen: pick required options, add-ons, quantity
struct MarketItemSheet: View {
    let item: MarketItem
    let rate: Double
    let onAdd: (_ selections: [String: [String]], _ quantity: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [String: [String]] = [:]
    @State private var quantity = 1

    private var line: CartLine { CartLine(item: item, selections: selections, quantity: quantity) }

    private var missingGroups: [OptionGroup] {
        item.options.filter { ($0.minSelect) > (selections[$0.id]?.count ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        ForEach(item.options) { group in
                            groupSection(group).id(group.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    addBar {
                        if let first = missingGroups.first {
                            withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                        }
                    }
                }
            }
        }
        .background(Color.umdBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.umdRed.opacity(0.08))
                Text(item.emoji).font(.system(size: 72))
            }
            .frame(height: 150)
            .padding(.top, 28)

            Text(item.name)
                .font(.inter(size: 22, weight: .bold))
            HStack(spacing: 8) {
                Text((item.ddPrice * rate).dollars)
                    .font(.inter(size: 17, weight: .bold))
                Text(item.ddPrice.dollars)
                    .font(.inter(size: 14, weight: .medium))
                    .strikethrough()
                    .foregroundStyle(.secondary)
                if let calories = item.calories {
                    Text("· \(calories) cal")
                        .font(.inter(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func groupSection(_ group: OptionGroup) -> some View {
        let picked = selections[group.id] ?? []
        let satisfied = picked.count >= group.minSelect
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.title)
                    .font(.inter(size: 17, weight: .bold))
                Spacer()
                Text(group.isRequired && satisfied ? "Done" : group.rule)
                    .font(.inter(size: 11, weight: .bold))
                    .foregroundStyle(group.isRequired && !satisfied ? Color.umdRed : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(group.isRequired && !satisfied ? Color.umdRed.opacity(0.12) : Color.umdSurface))
            }
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(group.choices) { choice in
                    let isOn = picked.contains(choice.id)
                    let isFull = !group.isSingle && picked.count >= group.maxSelect && !isOn
                    Button { toggle(choice, in: group) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: group.isSingle
                                  ? (isOn ? "largecircle.fill.circle" : "circle")
                                  : (isOn ? "checkmark.square.fill" : "square"))
                                .font(.system(size: 20))
                                .foregroundStyle(isOn ? Color.umdRed : Color(.systemGray3))
                            Text(choice.name)
                                .font(.inter(size: 15, weight: isOn ? .semibold : .regular))
                                .foregroundStyle(isFull ? .secondary : .primary)
                            Spacer()
                            if choice.priceDelta > 0 {
                                Text("+\((choice.priceDelta * rate).dollars)")
                                    .font(.inter(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isFull)
                    if choice.id != group.choices.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .homeCard(tint: .gray, thin: true)
        }
        .sensoryFeedback(.selection, trigger: picked)
    }

    private func toggle(_ choice: OptionChoice, in group: OptionGroup) {
        var picked = selections[group.id] ?? []
        if group.isSingle {
            picked = [choice.id]
        } else if let i = picked.firstIndex(of: choice.id) {
            picked.remove(at: i)
        } else if picked.count < group.maxSelect {
            picked.append(choice.id)
        }
        withAnimation(.snappy) { selections[group.id] = picked }
    }

    private func addBar(onBlocked: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button { if quantity > 1 { quantity -= 1 } } label: {
                    Image(systemName: "minus").frame(width: 40, height: 50)
                }
                .disabled(quantity == 1)
                Text("\(quantity)")
                    .font(.inter(size: 16, weight: .bold))
                    .frame(minWidth: 20)
                    .contentTransition(.numericText())
                Button { quantity += 1 } label: {
                    Image(systemName: "plus").frame(width: 40, height: 50)
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.umdRed)
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.umdRed.opacity(0.1)))

            Button {
                if missingGroups.isEmpty {
                    onAdd(selections, quantity)
                    dismiss()
                } else {
                    onBlocked()
                }
            } label: {
                Text(missingGroups.isEmpty
                     ? "Add · \((line.ddTotal * rate).dollars)"
                     : "Choose \(missingGroups.first!.title.lowercased().replacingOccurrences(of: "choose ", with: ""))")
                    .font(.inter(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(missingGroups.isEmpty ? Color.umdRed : Color.umdRed.opacity(0.5)))
                    .contentTransition(.numericText())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.umdBackground)
    }
}
