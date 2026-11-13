import Foundation

struct InsuranceProduct: Identifiable, Codable, Hashable {
    let id: String
    var company: String
    var companyCode: String?
    var name: String
    var productCode: String?
    var line: String
    /// 主約/附約。目錄未提供時為 nil，顯示為「未確認」，不依商品名稱推測。
    var role: ProductRole?
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
enum ProductRole: String, Codable, CaseIterable, Identifiable {
    case base = "主約"
    case rider = "附約"
    case unknown = "未確認"

    var id: String { rawValue }
}
enum DataQuality: String, Codable { case verified, needsReview, demo, unavailable }
enum PolicySource: String, Codable { case manuallyEntered, photoDraft, imported }
enum BenefitKind: String, Codable, CaseIterable {
    case inpatientDaily = "住院日額"
    case surgeryLumpSum = "手術定額"
    case surgerySchedule = "手術表定額"
    case outpatientSurgery = "門診手術"
    case actualExpense = "實支實付"
    case deathBenefit = "一般身故"
    case accidentDeath = "意外身故"
    case accidentInpatientDaily = "意外住院日額"
    case accidentFracture = "骨折未住院"
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
    /// 條款記載的可投保下限／上限（例如住院日額計畫範圍）。不是使用者實際投保額。
    var limitMinNTD: Int? = nil
    var limitMaxNTD: Int? = nil
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
    var companyCode: String? = nil
    var productRole: ProductRole? = nil

    var clauseIsVerified: Bool {
        clauseVerifiedAt != nil && clauseVersion?.isEmpty == false && clauseReference?.isEmpty == false && clauseURL?.scheme?.lowercased() == "https"
    }

    func recordedBenefits(_ kind: BenefitKind) -> [PolicyBenefit] {
        benefits.filter { $0.kind == kind }
    }

    /// 資料完整度提示，不是保障缺口判定。
    var missingFields: [String] {
        var missing: [String] = []
        if startDate == nil { missing.append("生效日") }
        if categories.isEmpty { missing.append("保障類別") }
        if clauseVersion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { missing.append("條款版本") }
        if clauseReference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { missing.append("條號/頁碼") }
        if clauseURL?.scheme?.lowercased() != "https" { missing.append("官方條款來源") }
        if benefits.isEmpty { missing.append("給付項目") }
        return missing
    }
}

struct ClaimInput {
    var eventDate: Date
    var hospitalDays: Int
    var surgeryName: String
    var outpatientSurgery: Bool
    var isAccident: Bool = false
    var hasFracture: Bool = false
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
