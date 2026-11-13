import Foundation

enum ClaimEstimator {
    private static let maximumSingleBenefitNTD = 1_000_000_000

    static func estimate(
        input: ClaimInput,
        policies: [UserPolicy],
        surgeryAmounts: [UUID: Int],
        confirmedSurgeryPolicies: Set<UUID>
    ) -> ClaimEstimate {
        guard (0...365).contains(input.hospitalDays) else {
            return ClaimEstimate(minimumKnownNTD: 0, includedItems: [], excludedItems: ["住院天數輸入超出可試算範圍（0–365 天），未提供金額。"])
        }
        var total = 0
        var included: [String] = []
        var excluded: [String] = []
        let claimDay = Calendar.current.startOfDay(for: input.eventDate)

        /// 將一筆金額加入總額；溢位時改列為未納入。
        func addToTotal(_ amount: Int, label: String, policyName: String) {
            let (newTotal, overflow) = total.addingReportingOverflow(amount)
            if overflow {
                excluded.append("\(policyName)：累計金額超出安全範圍，\(label)未納入")
            } else {
                total = newTotal
            }
        }

        /// 住院日額類（疾病住院日額、意外住院日額）：日額 × min(住院天數, 給付日數上限)。
        func addDailyBenefits(of kind: BenefitKind, for policy: UserPolicy, policyName: String) {
            for benefit in policy.benefits where benefit.kind == kind && benefit.verifiedEligible {
                guard let dailyAmount = benefit.amountNTD,
                      dailyAmount > 0,
                      dailyAmount <= maximumSingleBenefitNTD else { continue }
                let allowedDays = max(benefit.maxDays ?? input.hospitalDays, 0)
                let days = min(input.hospitalDays, allowedDays)
                guard days > 0 else { continue }
                let (amount, multiplicationOverflow) = days.multipliedReportingOverflow(by: dailyAmount)
                guard !multiplicationOverflow else {
                    excluded.append("\(policyName)：\(benefit.label)乘算超出安全範圍，未納入")
                    continue
                }
                let before = total
                addToTotal(amount, label: benefit.label, policyName: policyName)
                if total != before {
                    included.append("\(policyName)－\(benefit.label)：\(days) 日 × NT$\(dailyAmount.formatted()) = NT$\(amount.formatted())")
                }
            }
        }

        for policy in policies {
            let policyName = "\(policy.insurer)／\(policy.productName)"
            guard policy.clauseIsVerified else {
                excluded.append("\(policyName)：條款版本/來源未核對，未納入")
                continue
            }
            guard let startDate = policy.startDate,
                  Calendar.current.startOfDay(for: startDate) <= claimDay,
                  policy.endDate.map({ Calendar.current.startOfDay(for: $0) >= claimDay }) ?? true else {
                excluded.append("\(policyName)：保單生效日未確認，或就醫日不在已記錄的有效期間，未納入")
                continue
            }

            if !input.outpatientSurgery, input.hospitalDays > 0 {
                if input.isAccident {
                    // 意外事故同時可能符合疾病住院日額與意外住院日額，是否可併給須依條款，這裡分別列出。
                    addDailyBenefits(of: .accidentInpatientDaily, for: policy, policyName: policyName)
                }
                addDailyBenefits(of: .inpatientDaily, for: policy, policyName: policyName)
            }

            if input.isAccident, input.hasFracture, input.hospitalDays == 0 {
                for benefit in policy.benefits where benefit.kind == .accidentFracture && benefit.verifiedEligible {
                    guard let amount = benefit.amountNTD, amount > 0, amount <= maximumSingleBenefitNTD else { continue }
                    let before = total
                    addToTotal(amount, label: benefit.label, policyName: policyName)
                    if total != before {
                        included.append("\(policyName)－\(benefit.label)：依你記錄的金額 NT$\(amount.formatted())（實際依條款骨折別表與診斷核定）")
                    }
                }
            } else if input.isAccident, input.hasFracture, policy.benefits.contains(where: { $0.kind == .accidentFracture }) {
                excluded.append("\(policyName)：骨折未住院給付僅適用於未住院；本次有住院，未納入")
            }

            let requiredBenefit: BenefitKind = input.outpatientSurgery ? .outpatientSurgery : .surgerySchedule
            let hasApplicableVerifiedBenefit = policy.benefits.contains {
                $0.kind == requiredBenefit && $0.verifiedEligible
            }
            if let amount = surgeryAmounts[policy.id], amount != 0 {
                if amount < 0 {
                    excluded.append("\(policyName)：手術金額不能為負數，未納入")
                } else if input.surgeryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    excluded.append("\(policyName)：尚未輸入本次手術項目，未納入手術給付")
                } else if amount > maximumSingleBenefitNTD {
                    excluded.append("\(policyName)：輸入金額超出試算上限，未納入")
                } else if !hasApplicableVerifiedBenefit {
                    excluded.append("\(policyName)：未記錄符合本次類型的已核對手術給付項目，未納入")
                } else if confirmedSurgeryPolicies.contains(policy.id) {
                    let before = total
                    addToTotal(amount, label: "手術項目", policyName: policyName)
                    if total != before {
                        let event = input.outpatientSurgery ? "門診手術" : "手術"
                        included.append("\(policyName)－\(event)（\(input.surgeryName)）：依你核對的該保單條款金額 NT$\(amount.formatted())")
                    }
                } else {
                    excluded.append("\(policyName)：手術金額已輸入，但尚未確認對應條款/手術表項目")
                }
            }

            if policy.benefits.contains(where: { $0.kind == .actualExpense }) {
                excluded.append("\(policyName)：實支實付須依收據、限額、除外責任及已領給付審核，未列入最低估算")
            }
        }

        if included.isEmpty { excluded.append("目前沒有符合條款版本已核對、保單有效期間確認且給付金額明確的項目；不以缺少資料推算保障") }
        return ClaimEstimate(minimumKnownNTD: total, includedItems: included, excludedItems: excluded)
    }
}
