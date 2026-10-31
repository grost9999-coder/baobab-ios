import Foundation

/// Conservative, deterministic lower-bound calculation. No policy wording inference is performed.
enum ClaimEstimator {
    static func estimate(input: ClaimInput, benefits: [PolicyBenefit], clauseVerified: Bool) -> ClaimEstimate {
        guard clauseVerified else {
            return ClaimEstimate(minimumKnownNTD: 0, includedItems: [], excludedItems: ["條款版本尚未核對；不產生金額估算"])
        }
        var total = 0
        var included: [String] = []
        var excluded: [String] = []
        for benefit in benefits where benefit.verifiedEligible {
            switch benefit.kind {
            case .inpatientDaily:
                guard !input.outpatientSurgery, input.hospitalDays > 0, let daily = benefit.amountNTD else { continue }
                let days = min(input.hospitalDays, benefit.maxDays ?? input.hospitalDays)
                let amount = days * daily
                total += amount
                included.append("\(benefit.label)：\(days) 日 × \(daily) 元 = \(amount) 元")
            case .surgeryLumpSum, .surgerySchedule, .outpatientSurgery:
                guard let amount = input.explicitSurgeryBenefitNTD, amount > 0 else {
                    excluded.append("\(benefit.label)：需依條款手術表/代碼核對，未自行推定")
                    continue
                }
                if benefit.kind == .outpatientSurgery && !input.outpatientSurgery { continue }
                total += amount
                included.append("\(benefit.label)：依已核對的輸入金額 \(amount) 元")
            case .actualExpense:
                excluded.append("\(benefit.label)：實支實付須核對收據、限額、除外責任及已領給付，未納入最低額")
            case .other:
                excluded.append("\(benefit.label)：給付條件尚未結構化，未納入")
            }
        }
        if included.isEmpty { excluded.append("沒有符合「條款已核對且給付條件明確」的項目") }
        return ClaimEstimate(minimumKnownNTD: total, includedItems: included, excludedItems: excluded)
    }
}
