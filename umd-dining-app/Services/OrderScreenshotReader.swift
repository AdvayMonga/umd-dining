import UIKit
import Vision

/// Reads a Grubhub order confirmation screenshot on-device: order number and
/// subtotal. The subtotal is compared against our menu price so drift on
/// Grubhub gets noticed from real orders instead of manual checking.
enum OrderScreenshotReader {
    struct Reading: Equatable {
        var orderNumber: String?
        var subtotal: Double?
        var total: Double?
    }

    static func read(_ image: UIImage) async -> Reading {
        guard let cgImage = image.cgImage else { return Reading() }
        let lines = await recognizeLines(cgImage)
        return parse(lines)
    }

    /// Pure parsing, separate from Vision so it can be tested with plain strings
    static func parse(_ lines: [String]) -> Reading {
        var reading = Reading()
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            if reading.orderNumber == nil, let number = firstMatch(#"(?:order|#)\D{0,6}(\d{3,})"#, in: line) {
                reading.orderNumber = number
            }
            // Amount is usually on the same line, sometimes the next one
            let amount = dollarAmount(in: line) ?? (i + 1 < lines.count ? dollarAmount(in: lines[i + 1]) : nil)
            if lower.contains("subtotal") {
                reading.subtotal = reading.subtotal ?? amount
            } else if lower.contains("total") {
                reading.total = reading.total ?? amount
            }
        }
        return reading
    }

    private static func dollarAmount(in text: String) -> Double? {
        firstMatch(#"\$\s?(\d{1,3}(?:,\d{3})*\.\d{2})"#, in: text)
            .flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func recognizeLines(_ image: CGImage) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: image).perform([request])
            // Vision's origin is bottom-left; sort top to bottom
            return (request.results ?? [])
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

/// A real order whose Grubhub subtotal didn't match our menu
struct MenuPriceFlag: Identifiable {
    let id = UUID()
    let requestId: UUID
    let locationId: String
    /// capturedOn of the menu the order was priced with
    let menuVersion: String
    let expected: Double
    let grubhub: Double
    let items: [String]
    let reportedAt = Date()
}

extension OrderScreenshotReader.Reading {
    /// Small tolerance for rounding; anything larger means the menu drifted
    func subtotalMismatch(expected: Double) -> Double? {
        guard let subtotal, abs(subtotal - expected) > 0.05 else { return nil }
        return subtotal
    }
}
