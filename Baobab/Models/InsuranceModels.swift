import Foundation

/// A product record is usable for an estimate only when its exact policy wording has been reviewed.
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
enum BenefitKind: String, Codable, CaseIterable { case inpatientDaily = "住院日額", surgeryLumpSum = "手術定額", surgerySchedule = "手術表定額", outpatientSurgery = "門診手術", actualExpense = "實支實付", other = "其他" }

struct PolicyBenefit: Identifiable, Codable, Hashable {
    var id: String { "\(kind.rawValue)-\(label)" }
    var kind: BenefitKind
    var label: String
    var amountNTD: Int?
    var maxDays: Int?
    var clauseReference: String?
    /// Only explicit, reviewed guaranteed amounts may be used in the conservative floor.
    var verifiedEligible: Bool
}

struct UserPolicy: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var insurer: String
    var productName: String
    var policyNumber: String?
    var insuredName: String?
    var startDate: Date?
    var endDate: Date?
    var annualPremiumNTD: Int?
    var productID: String?
    var benefits: [PolicyBenefit]
    var source: PolicySource
}

enum PolicySource: String, Codable { case manuallyEntered, photoDraft, imported }

struct ClaimInput {
    var hospitalDays: Int
    var surgeryName: String
    var outpatientSurgery: Bool
    var explicitSurgeryBenefitNTD: Int?
}

struct ClaimEstimate {
    var minimumKnownNTD: Int
    var includedItems: [String]
    var excludedItems: [String]
    var canProduceFloor: Bool { !includedItems.isEmpty }
}
