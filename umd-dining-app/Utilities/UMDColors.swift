import SwiftUI
import UIKit

// MARK: - Brand Colors

extension Color {
    static let umdRed        = Color(red: 226/255, green: 24/255,  blue: 51/255)   // #E21833
    static let umdRedActive  = Color(red: 185/255, green: 28/255,  blue: 28/255)   // #B91C1C
    static let umdGold       = Color(red: 255/255, green: 210/255, blue: 0/255)    // #FFD200

    // Adaptive: #F9FAFB in light, system dark grouped background in dark
    static let umdBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.systemGroupedBackground
            : UIColor(red: 249/255, green: 250/255, blue: 251/255, alpha: 1)
    })

    // Adaptive: #F3F4F6 in light, secondary system background in dark
    static let umdSurface = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.secondarySystemBackground
            : UIColor(red: 243/255, green: 244/255, blue: 246/255, alpha: 1)
    })

    // Adaptive border
    static let umdBorder = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.systemGray4
            : UIColor(red: 229/255, green: 231/255, blue: 235/255, alpha: 1)
    })
}

// MARK: - Home Card Style (matches FoodItemRow)

struct HomeCardStyle: ViewModifier {
    var tint: Color
    // Secondary cards (gray) wear a lighter outline than the red ones
    var thin: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                tint.opacity(colorScheme == .dark ? 0.7 : 0.35),
                lineWidth: thin
                    ? (colorScheme == .dark ? 1.5 : 1)
                    : (colorScheme == .dark ? 2 : 1.5)
            ))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Press Feedback

// Cards and buttons dip slightly while held, like a physical button
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// Same dip for views driven by tap gestures rather than a Button
struct PressEffect: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func pressEffect() -> some View {
        modifier(PressEffect())
    }
}

extension View {
    func homeCard(tint: Color = .umdRed, thin: Bool = false) -> some View {
        modifier(HomeCardStyle(tint: tint, thin: thin))
    }
}

// MARK: - Section Header (matches StationHeaderRow)

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(title.uppercased())
                    .font(.inter(size: 17, weight: .bold))
                    .foregroundStyle(Color.umdRed)
                    .kerning(1.5)
                    .lineLimit(1)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.umdRed.opacity(0.7))
                }
            }
            .frame(height: 36)

            Rectangle()
                .fill(Color.umdRed.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.top, 4)
    }
}

// MARK: - CalendarCardButton (used in StationPageView and TrackerView)

struct CalendarCardButton: View {
    @Binding var selection: Date

    private var displayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selection)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.subheadline)
                .foregroundStyle(Color.umdRed)
            Text(displayText)
                .font(.custom("Inter18pt-SemiBold", size: 15))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(color: .gray.opacity(0.12), radius: 3, x: 0, y: 1)
        .overlay {
            DatePicker("", selection: $selection, displayedComponents: .date)
                .labelsHidden()
                .tint(Color.umdRed)
                .colorMultiply(.clear)
        }
    }
}
