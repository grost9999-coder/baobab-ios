import Foundation

struct InsuranceProduct: Identifiable, Codable, Hashable {
    let id: String
    var company: String
    var name: String
    var productCode: String?
    var line: String
    var salesStatus: SalesStatus
    var effectiveFrom: Date?
    var salesEnd: Date?
    var clauseVersion: String?
    var clauseURL: URL?
    var clauseVerifiedAt: Date?
    var sourceURL: URL?
    var sourceRetrievedAt: Date?
    var provenance: String
    var dataQuality: DataQuality
    var benefits: [PolicyBenefit]

    var isEstimateEligible: Bool {
        dataQuality == .verified && clauseURL != nil && clauseVersion != nil && clauseVerifiedAt != nil
    }
}

enum SalesStatus: String, Codable, CaseIterable { case onSale = "現售", discontinued = "停售", unknown = "未確認" }
enum DataQuality: String, Codable { case verified, needsReview, demo, unavailable }
enum PolicySource: String, Codable { case manuallyEntered, photoDraft, imported }
enum BenefitKind: String, Codable, CaseIterable {
    case inpatientDaily = "住院日額"
    case surgeryLumpSum = "手術定額"
    case surgerySchedule = "手術表定額"
    case outpatientSurgery = "門診手術"
    case actualExpense = "實支實付"
    case other = "其他"
}

enum CoverageCategory: String, Codable, CaseIterable, Identifiable {
    case life = "壽險"
    case medical = "住院醫療"
    case surgery = "手術"
    case cancer = "癌症"
    case accident = "意外"
    case disability = "失能"
    case longTermCare = "長照"
    case criticalIllness = "重大傷病"

    var id: String { rawValue }
}

struct PolicyBenefit: Identifiable, Codable, Hashable {
    var id: String { "\(kind.rawValue)-\(label)" }
    var kind: BenefitKind
    var label: String
    var amountNTD: Int?
    var maxDays: Int?
    var clauseReference: String?
    var verifiedEligible: Bool
}

/// Contains no policy number, national ID, name, address, or OCR source text.
struct UserPolicy: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var insurer: String
    var productName: String
    var startDate: Date?
    var endDate: Date?
    var categories: [CoverageCategory]
    var clauseVersion: String?
    var clauseReference: String?
    var clauseURL: URL?
    var clauseVerifiedAt: Date?
    var source: PolicySource
    var benefits: [PolicyBenefit]

    var clauseIsVerified: Bool {
        clauseVerifiedAt != nil && clauseVersion?.isEmpty == false && clauseReference?.isEmpty == false && clauseURL?.scheme?.lowercased() == "https"
    }
}

struct ClaimInput {
    var eventDate: Date
    var hospitalDays: Int
    var surgeryName: String
    var outpatientSurgery: Bool
}

struct ClaimEstimate {
    var minimumKnownNTD: Int
    var includedItems: [String]
    var excludedItems: [String]
    var canProduceFloor: Bool { !includedItems.isEmpty }
}

extension CoverageCategory {
    var symbol: String {
        return switch self {
        case .life: "heart.fill"
        case .medical: "cross.case.fill"
        case .surgery: "scissors"
        case .cancer: "cross.vial.fill"
        case .accident: "figure.fall"
        case .disability: "figure.roll"
        case .longTermCare: "hands.sparkles.fill"
        case .criticalIllness: "heart.text.clipboard"
        }
    }
}
