import Testing
import Foundation
@testable import UMD_Dining

/// Text-line parsing only; Vision OCR itself needs a real screenshot.
struct OrderScreenshotReaderTests {
    @Test func readsOrderNumberAndAmountsOnSameLine() {
        let reading = OrderScreenshotReader.parse([
            "Order #48213 confirmed",
            "Subtotal $16.28",
            "Total $16.28",
        ])
        #expect(reading.orderNumber == "48213")
        #expect(reading.subtotal == 16.28)
        #expect(reading.total == 16.28)
    }

    @Test func readsAmountFromTheFollowingLine() {
        let reading = OrderScreenshotReader.parse(["Subtotal", "$9.47", "Total", "$9.47"])
        #expect(reading.subtotal == 9.47)
        #expect(reading.total == 9.47)
    }

    @Test func subtotalIsNotMistakenForTotal() {
        let reading = OrderScreenshotReader.parse(["Subtotal $12.00", "Service fee $0.00", "Total $12.50"])
        #expect(reading.subtotal == 12.00)
        #expect(reading.total == 12.50)
    }

    @Test func mismatchOnlyBeyondRoundingTolerance() {
        let close = OrderScreenshotReader.Reading(subtotal: 16.30)
        #expect(close.subtotalMismatch(expected: 16.28) == nil)
        let drifted = OrderScreenshotReader.Reading(subtotal: 17.08)
        #expect(drifted.subtotalMismatch(expected: 16.28) == 17.08)
        #expect(OrderScreenshotReader.Reading().subtotalMismatch(expected: 16.28) == nil)
    }

    @Test func unrelatedTextReadsNothing() {
        let reading = OrderScreenshotReader.parse(["Chick-fil-A", "Stamp Student Union", "Pickup"])
        #expect(reading == OrderScreenshotReader.Reading())
    }
}
