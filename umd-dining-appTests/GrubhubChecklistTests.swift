import Testing
import Foundation
@testable import UMD_Dining

/// The seller checklist must follow Grubhub's screen order, not the buyer's tap order.
@MainActor
struct GrubhubChecklistTests {
    private func nuggets12(sauces: [String], quantity: Int = 1) -> CartLine {
        CartLine(item: MarketMenu.placeholderItem("cfa-nuggets-12")!, selections: ["sauce": sauces], quantity: quantity)
    }

    @Test func choicesFollowMenuOrderNotPickOrder() {
        // Buyer tapped BBQ before Chick-fil-A Sauce; the menu lists Chick-fil-A Sauce first
        let steps = GrubhubChecklist.steps(for: nuggets12(sauces: ["bbq", "cfa"]), index: 0)
        let sauce = steps.first { $0.label == "Sauces" }
        #expect(sauce?.detail == "Chick-fil-A Sauce, Barbeque")
    }

    @Test func stepsOpenThenOptionsThenQuantityThenAdd() {
        let steps = GrubhubChecklist.steps(for: nuggets12(sauces: ["poly"], quantity: 2), index: 0)
        #expect(steps.map(\.label) == ["Entrées → 12ct Nuggets", "Sauces", "Quantity", "Add to bag"])
    }

    @Test func unpickedOptionalGroupsAreSkipped() {
        let steps = GrubhubChecklist.steps(for: nuggets12(sauces: []), index: 0)
        #expect(!steps.contains { $0.label == "Sauces" })
        #expect(GrubhubChecklist.stepCount([nuggets12(sauces: []), nuggets12(sauces: ["poly"])]) == 2 + 3)
    }
}
