import Foundation
import Vision
import UIKit

/// OCR creates an untrusted draft only; extracted text never becomes coverage or claim evidence by itself.
enum PolicyPhotoOCR {
    static func recognize(_ image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw NSError(domain: "PolicyPhotoOCR", code: 1) }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = OCRContinuationGate()
            let request = VNRecognizeTextRequest { request, error in
                if let error { gate.resume(continuation, with: .failure(error)); return }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                gate.resume(continuation, with: .success(lines.joined(separator: "\n")))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                } catch {
                    gate.resume(continuation, with: .failure(error))
                }
            }
        }
    }
}

private final class OCRContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<String, Error>, with result: Result<String, Error>) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        if shouldResume { continuation.resume(with: result) }
    }
}

struct PolicyOCRSuggestions {
    var insurer: String?
    var productName: String?
    var startDate: Date?
    var dailyBenefit: Int?
    var categories: [CoverageCategory]

    var hasSuggestions: Bool {
        insurer != nil || productName != nil || startDate != nil || dailyBenefit != nil || !categories.isEmpty
    }
}

/// Extracts cautious, explicitly labelled candidates from on-device OCR text. Nothing is auto-confirmed.
enum PolicyOCRDraftParser {
    static func parse(_ text: String, knownCompanies: [String]) -> PolicyOCRSuggestions {
        let insurerMatches = knownCompanies
            .filter { company in
                companyFragments(company).contains { fragment in
                    fragment.count >= 3 && text.localizedCaseInsensitiveContains(fragment)
                }
            }
            .sorted { $0.count > $1.count }
        let insurer = insurerMatches.count == 1 ? insurerMatches.first : nil

        let productPattern = #"(?:商品名稱|保險商品名稱|險種名稱)\s*[：:]\s*([^\n，,。；;]{2,60})"#
        let product = firstCapture(pattern: productPattern, in: text)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let startDate = parseStartDate(text)
        let dailyBenefit = parseDailyBenefit(text)
        let categoryRules: [(CoverageCategory, String)] = [
            (.life, "壽險|身故保障|死亡給付"),
            (.medical, "住院醫療|醫療保險|住院日額"),
            (.surgery, "手術給付|手術保險|手術費用"),
            (.cancer, "癌症保障|癌症保險|癌症給付"),
            (.accident, "意外傷害|意外事故|意外保險"),
            (.disability, "失能給付|失能保險|失能保障"),
            (.longTermCare, "長期照顧|長照給付|長照保險"),
            (.criticalIllness, "重大傷病|重大疾病|特定傷病")
        ]
        let categories = categoryRules.compactMap { item in
            text.range(of: item.1, options: .regularExpression) == nil ? nil : item.0
        }
        return PolicyOCRSuggestions(
            insurer: insurer,
            productName: product,
            startDate: startDate,
            dailyBenefit: dailyBenefit,
            categories: categories
        )
    }

    private static func companyFragments(_ name: String) -> [String] {
        let base = name.replacingOccurrences(of: #"\s*[（(].*?[）)]"#, with: "", options: .regularExpression)
        let withoutLegalSuffix = base
            .replacingOccurrences(of: "股份有限公司", with: "")
            .replacingOccurrences(of: "有限公司", with: "")
        let commonAbbreviation = withoutLegalSuffix.replacingOccurrences(of: "保險", with: "")
        return Array(Set([name, base, withoutLegalSuffix, commonAbbreviation].filter { !$0.isEmpty }))
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func parseStartDate(_ text: String) -> Date? {
        let pattern = #"(?:契約\s*)?(?:生效日|生效日期|保險期間起日|保險期間自)\s*[：:]?\s*(?:民國\s*)?(\d{2,4})\s*[年/-]\s*(\d{1,2})\s*[月/-]\s*(\d{1,2})\s*日?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 4 else { return nil }
        func integer(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }
        guard var year = integer(1), let month = integer(2), let day = integer(3) else { return nil }
        if year < 1000 { year += 1911 }
        guard (1912...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        guard let date = components.date else { return nil }
        let check = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    private static func parseDailyBenefit(_ text: String) -> Int? {
        let pattern = #"(?:住院日額|住院每日給付|住院每日保險金)\s*[：:]?\s*(?:NT\$|新臺幣|新台幣)?\s*([0-9,]{2,12})\s*(?:元|/日|每日)"#
        guard let value = firstCapture(pattern: pattern, in: text),
              let amount = Int(value.replacingOccurrences(of: ",", with: "")),
              (1...1_000_000_000).contains(amount) else { return nil }
        return amount
    }
}
