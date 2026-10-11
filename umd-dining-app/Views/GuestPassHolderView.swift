import SwiftUI

/// "Give" side: your remaining passes, availability, requests and active meetups
struct GuestPassHolderView: View {
    @Bindable var store: GuestPassStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? { reduceMotion ? nil : .spring(duration: 0.35) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            passesCard
            availabilityCard

            if !store.jobs.isEmpty {
                SectionHeader(title: "Meetups")
                ForEach(store.jobs) { job in
                    GuestPassJobCard(job: job, store: store)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }
            }

            SectionHeader(title: "Requests", trailing: store.isAvailable ? "\(store.visibleRequests.count) open" : nil)
            if store.passesLeft == 0 {
                emptyState(icon: "ticket", text: "You've used all your guest passes this semester.")
            } else if !store.isAvailable {
                emptyState(icon: "moon.zzz.fill", text: "You're hidden. Turn on \"Open to requests\" to see them.")
            } else if store.visibleRequests.isEmpty {
                emptyState(icon: "tray", text: "No requests at your halls right now. We'll notify you.")
            } else {
                ForEach(store.visibleRequests) { request in
                    GuestPassRequestCard(request: request) {
                        withAnimation(spring) { store.accept(request) }
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
        }
    }

    // MARK: - Passes

    private var passesCard: some View {
        let total = GuestPassRules.passesByPlan.first { $0.plan == store.planName }?.passes ?? max(store.passesLeft, 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guest passes left")
                        .font(.inter(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(store.passesLeft)")
                            .font(.inter(size: 36, weight: .bold))
                            .contentTransition(.numericText())
                        Text("of \(total)")
                            .font(.inter(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                planMenu
            }
            .accessibilityElement(children: .combine)

            // One ticket per pass so the "use them or lose them" count is visible at a glance
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { i in
                    Image(systemName: i < store.passesLeft ? "ticket.fill" : "ticket")
                        .font(.system(size: 18))
                        .foregroundStyle(i < store.passesLeft ? Color.umdRed : Color(.systemGray3))
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
                Text("They expire \(store.passesExpire.formatted(.dateTime.month(.abbreviated).day())). Selling the rest could earn you up to **\(GuestPassPricing.format(store.passesValue))**.")
                    .font(.inter(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))

            HStack {
                stat(GuestPassPricing.format(store.earnedThisSemester), "earned", tint: .green)
                Divider().frame(height: 28)
                stat("\(store.passesSold)", "sold", tint: .primary)
                Divider().frame(height: 28)
                stat("★ \(String(format: "%.1f", store.holderRating))", "rating", tint: .primary)
            }
        }
        .padding(16)
        .homeCard()
        .animation(spring, value: store.passesLeft)
    }

    private var planMenu: some View {
        Menu {
            ForEach(GuestPassRules.passesByPlan, id: \.plan) { option in
                Button("\(option.plan) · \(option.passes) passes") {
                    withAnimation(spring) { store.setPlan(option.plan, passes: option.passes) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.planName ?? "Your plan")
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(.inter(size: 13, weight: .semibold))
            .foregroundStyle(Color.umdRed)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Meal plan: \(store.planName ?? "not set")")
    }

    private func stat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.inter(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.inter(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Availability

    private var availabilityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $store.isAvailable.animation(spring)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isAvailable ? "Open to requests" : "Hidden")
                        .font(.inter(size: 15, weight: .semibold))
                    Text(store.isAvailable ? "Students at your halls can match with you" : "Nobody can send you requests")
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.green)

            if store.isAvailable {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Halls you'll swipe at")
                        .font(.inter(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(GuestPassHall.all) { hall in
                            hallChip(hall)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .homeCard(tint: .gray, thin: true)
    }

    private func hallChip(_ hall: GuestPassHall) -> some View {
        let on = store.availableHallIds.contains(hall.id)
        return Button {
            withAnimation(spring) {
                if on { store.availableHallIds.remove(hall.id) } else { store.availableHallIds.insert(hall.id) }
            }
        } label: {
            Text(hall.shortName)
                .font(.inter(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(on ? .white : .primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.umdRed : Color.umdSurface))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(hall.name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: on)
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
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Request card

private struct GuestPassRequestCard: View {
    let request: GuestPassRequest
    let onAccept: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image("hall_\(request.hall.id)")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(request.hall.name)
                    .font(.inter(size: 15, weight: .semibold))
                Label("\(request.meal) · \(request.timing.label)", systemImage: request.timing == .now ? "bolt.fill" : "clock")
                    .font(.inter(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(request.timing == .now ? Color.umdRed : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(request.timing == .now ? Color.umdRed.opacity(0.12) : Color.umdSurface))
                Text("★ \(String(format: "%.1f", request.buyerRating)) · \(request.postedMinutesAgo)m ago")
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button(action: onAccept) {
                VStack(spacing: 0) {
                    Text("+\(GuestPassPricing.format(request.holderEarns))")
                        .font(.inter(size: 16, weight: .bold))
                    Text("Accept")
                        .font(.inter(size: 11, weight: .semibold))
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .frame(width: 76, height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.umdRed))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Accept, earn \(GuestPassPricing.format(request.holderEarns))")
        }
        .padding(12)
        .homeCard(tint: .gray, thin: true)
    }
}

// MARK: - Job card

private struct GuestPassJobCard: View {
    let job: GuestPassJob
    let store: GuestPassStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? { reduceMotion ? nil : .spring(duration: 0.35) }
    private var earns: String { GuestPassPricing.format(job.request.holderEarns) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MEET \(job.request.buyerName.uppercased()) · \(job.request.timing.label.uppercased())")
                        .font(.inter(size: 11, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(Color.umdRed)
                    Text(job.request.hall.name)
                        .font(.inter(size: 18, weight: .bold))
                }
                Spacer()
                Text("+\(earns)")
                    .font(.inter(size: 18, weight: .bold))
                    .foregroundStyle(.green)
            }

            if job.step == .heading || job.step == .atDoor {
                GuestPassMeetupPanel(
                    hall: job.request.hall,
                    otherName: job.request.buyerName,
                    themHere: job.themHere,
                    theirNote: job.theirNote,
                    meHere: job.meHere,
                    myNote: job.myNote
                ) { note in
                    withAnimation(spring) { store.setHolderHere(job, note: note) }
                }
                GuestPassMessageThread(messages: job.messages, replies: GuestPassReplies.holder) {
                    store.sendHolderMessage(job, $0)
                }
            }

            footer
        }
        .padding(16)
        .homeCard()
        .sensoryFeedback(.success, trigger: job.step)
    }

    @ViewBuilder
    private var footer: some View {
        switch job.step {
        case .heading:
            if job.meHere {
                HStack {
                    Text("Waiting for \(job.request.buyerName)…")
                        .font(.inter(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("They didn't show") { withAnimation(spring) { store.holderReportNoShow(job) } }
                        .font(.inter(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(minHeight: 44)
                }
            }
        case .atDoor:
            Button {
                withAnimation(spring) { store.swipedIn(job) }
            } label: {
                Label(GuestPassRules.holderMustEnter ? "We're both in" : "I swiped them in", systemImage: "person.badge.key.fill")
                    .font(.inter(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.umdRed))
            }
            .buttonStyle(PressableButtonStyle())
        case .waitingConfirm:
            HStack(spacing: 10) {
                ProgressView()
                Text("Waiting for \(job.request.buyerName) to confirm they're in…")
                    .font(.inter(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .rate:
            VStack(alignment: .leading, spacing: 8) {
                Text("\(earns) is on its way. How was \(job.request.buyerName)?")
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
            withAnimation(spring) { store.rateBuyer(job, thumbsUp: up) }
        } label: {
            Image(systemName: up ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                .font(.system(size: 18))
                .foregroundStyle(up ? .green : .secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdSurface))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(up ? "Good experience" : "Bad experience")
    }
}
