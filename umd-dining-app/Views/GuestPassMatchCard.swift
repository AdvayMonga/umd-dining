import SwiftUI

/// Buyer's live guest pass, pinned to the top of the tab
struct GuestPassMatchCard: View {
    let match: GuestPassMatch
    let store: GuestPassStore

    @State private var showCancel = false
    @State private var showProblem = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? { reduceMotion ? nil : .spring(duration: 0.35) }

    private var otherName: String { match.holderName ?? "Your holder" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch match.status {
            case .searching:
                searchingRow
            case .matched, .atDoor, .completed:
                progressTrack
            default:
                EmptyView()
            }

            Text(message)
                .font(.inter(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if match.status == .matched || match.status == .atDoor {
                GuestPassMeetupPanel(
                    hall: match.hall,
                    otherName: otherName,
                    themHere: match.themHere,
                    theirNote: match.theirNote,
                    meHere: match.meHere,
                    myNote: match.myNote
                ) { note in
                    withAnimation(spring) { store.setBuyerHere(note: note) }
                }
                GuestPassMessageThread(messages: match.messages, replies: GuestPassReplies.buyer) {
                    store.sendBuyerMessage($0)
                }
            }

            actions
        }
        .padding(16)
        .homeCard(tint: match.status == .disputed || match.status == .noShow ? .orange : .umdRed)
        .sensoryFeedback(.success, trigger: match.status)
        .confirmationDialog("Cancel this guest pass?", isPresented: $showCancel, titleVisibility: .visible) {
            Button("Cancel", role: .destructive) { withAnimation(spring) { store.cancel() } }
        } message: {
            Text("You won't be charged.")
        }
        .confirmationDialog("What went wrong?", isPresented: $showProblem, titleVisibility: .visible) {
            Button("They didn't swipe me in") { withAnimation(spring) { store.reportProblem() } }
            Button("The swipe didn't work") { withAnimation(spring) { store.reportProblem() } }
            Button("Something else") { withAnimation(spring) { store.reportProblem() } }
        } message: {
            Text("You won't be charged while we sort it out.")
        }
    }

    private var message: String {
        switch match.status {
        case .searching:
            match.timing == .now
                ? "Looking for a student with a guest pass near \(match.hall.name). You're not charged unless you get in."
                : "Looking for someone free at \(match.timing.label). We'll notify you when it's set."
        case .matched:
            match.timing == .now
                ? "\(otherName) is heading to \(match.hall.name). Meet at the card swipe."
                : "\(otherName) will meet you at \(match.timing.label). We'll remind you 15 minutes before."
        case .atDoor:
            GuestPassRules.holderMustEnter
                ? "You're both here. Walk in together and tap \"I'm in\" once you're through."
                : "You're both here. Once \(otherName) swipes you in, tap \"I'm in\"."
        case .completed: "Enjoy your meal! Payment released."
        case .expired: "Nobody was free in time. You weren't charged."
        case .cancelled: "Cancelled. You weren't charged."
        case .noShow: "Sorry about that. You weren't charged, and we've noted the no-show."
        case .disputed: "Payment is on hold while we sort this out. We'll follow up within 24 hours."
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(match.meal.uppercased()) · \(match.timing.label.uppercased())")
                    .font(.inter(size: 11, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Color.umdRed)
                Text(match.hall.name)
                    .font(.inter(size: 18, weight: .bold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(GuestPassPricing.format(match.price))
                    .font(.inter(size: 18, weight: .bold))
                Text("saving \(GuestPassPricing.format(match.savings))")
                    .font(.inter(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    private var searchingRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, GuestPassRules.matchTimeout - context.date.timeIntervalSince(match.requestedAt))
            HStack(spacing: 12) {
                ProgressView().tint(Color.umdRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finding a guest pass…")
                        .font(.inter(size: 15, weight: .semibold))
                    Text(match.timing == .now
                         ? "\(store.holdersFreeNow(at: match.hall)) free now · expires in \(Int(left) / 60):\(String(format: "%02d", Int(left) % 60))"
                         : "\(store.scheduledHolders[match.hall.id] ?? 0) students free later today")
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

    private var progressTrack: some View {
        HStack(spacing: 0) {
            ForEach(GuestPassStatus.track, id: \.self) { step in
                let reached = step <= match.status
                VStack(spacing: 6) {
                    Image(systemName: step.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(reached ? Color.white : Color.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(reached ? Color.umdRed : Color.umdSurface))
                        .overlay(Circle().stroke(reached ? Color.clear : Color.umdBorder, lineWidth: 1))
                        .scaleEffect(step == match.status ? 1.12 : 1)
                    Text(step.title)
                        .font(.inter(size: 10, weight: .semibold))
                        .foregroundStyle(reached ? .primary : .secondary)
                }
                .frame(width: 76)
                if step != GuestPassStatus.track.last {
                    Capsule()
                        .fill(step < match.status ? Color.umdRed : Color.umdSurface)
                        .frame(height: 3)
                        .padding(.bottom, 18)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch match.status {
        case .searching, .matched:
            HStack {
                textButton("Cancel", color: .secondary) { showCancel = true }
                Spacer()
                // Waiting at the door with nobody showing up
                if match.meHere && !match.themHere {
                    textButton("They didn't show", color: .orange) { withAnimation(spring) { store.reportNoShow() } }
                }
            }
        case .atDoor:
            primaryButton("I'm in · pay \(GuestPassPricing.format(match.price))", color: .green) {
                withAnimation(spring) { store.confirmIn() }
            }
            textButton("Something's wrong", icon: "exclamationmark.bubble", color: .orange) { showProblem = true }
        case .completed:
            ratingRow
        case .expired, .cancelled:
            HStack(spacing: 10) {
                primaryButton("Try again", color: .umdRed) {
                    withAnimation(spring) {
                        store.dismissMatch()
                        store.request()
                    }
                }
                textButton("Dismiss", color: .secondary) { withAnimation(spring) { store.dismissMatch() } }
                    .padding(.horizontal, 8)
            }
        case .noShow, .disputed:
            textButton("Dismiss", color: .secondary) { withAnimation(spring) { store.dismissMatch() } }
        }
    }

    /// Secondary actions: text-only, but still a full 44pt tap target
    private func textButton(_ title: String, icon: String? = nil, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon { Label(title, systemImage: icon) } else { Text(title) }
            }
            .font(.inter(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var ratingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(match.myRating == nil ? "How was \(otherName)?" : "Thanks for rating!")
                .font(.inter(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(spring) { store.rateHolder(star) }
                    } label: {
                        Image(systemName: star <= (match.myRating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 26))
                            .foregroundStyle(star <= (match.myRating ?? 0) ? Color.umdGold : Color(.systemGray3))
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(match.myRating != nil)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }
            Text("Ratings are anonymous.")
                .font(.inter(size: 11))
                .foregroundStyle(.secondary)
        }
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
    }
}

// MARK: - Meetup panel (shared by buyer and holder)

/// Where to meet, whether the other person is there, and an "I'm here" button
/// with a quick "what I'm wearing" note so two strangers can spot each other.
struct GuestPassMeetupPanel: View {
    let hall: GuestPassHall
    let otherName: String
    let themHere: Bool
    let theirNote: String?
    let meHere: Bool
    let myNote: String?
    let onHere: (String?) -> Void

    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.umdRed)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Meet at \(hall.name)")
                        .font(.inter(size: 14, weight: .semibold))
                    Text(hall.meetSpot)
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                presence(name: otherName, here: themHere, note: theirNote)
                presence(name: "You", here: meHere, note: myNote)
            }

            if !meHere {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("What you're wearing (optional)", text: $note)
                        .font(.inter(size: 15))
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.umdBorder, lineWidth: 1))
                    Button {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onHere(trimmed.isEmpty ? nil : String(trimmed.prefix(40)))
                    } label: {
                        Label("I'm here", systemImage: "location.fill")
                            .font(.inter(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.umdRed))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.umdRed.opacity(0.05)))
    }

    private func presence(name: String, here: Bool, note: String?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(here ? Color.green : Color(.systemGray3))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.inter(size: 13, weight: .semibold))
                Text(here ? (note.map { "Here · \($0)" } ?? "Here") : "On the way")
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundStyle(here ? .green : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
    }
}

// MARK: - Quick-reply thread

struct GuestPassMessageThread: View {
    let messages: [GuestPassMessage]
    let replies: [String]
    let onSend: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? { reduceMotion ? nil : .spring(duration: 0.3) }

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
                        .background(RoundedRectangle(cornerRadius: 14).fill(msg.sender == .me ? Color.umdRed : Color.umdSurface))
                    if msg.sender == .them { Spacer(minLength: 40) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(replies, id: \.self) { reply in
                        Button {
                            withAnimation(spring) { onSend(reply) }
                        } label: {
                            Text(reply)
                                .font(.inter(size: 12, weight: .semibold))
                                .foregroundStyle(Color.umdRed)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .overlay(Capsule().stroke(Color.umdRed.opacity(0.4), lineWidth: 1))
                                .padding(.vertical, 5)       // 44pt tap area
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Sends this message")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: messages.count)
    }
}
