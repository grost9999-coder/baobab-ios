import SwiftUI

private struct HealthItem: Identifiable {
    let kind: BenefitKind
    let title: String
    let perDay: Bool
    var id: String { kind.rawValue }
}

private let healthItems: [HealthItem] = [
    HealthItem(kind: .inpatientDaily, title: "住院日額", perDay: true),
    HealthItem(kind: .deathBenefit, title: "一般身故", perDay: false),
    HealthItem(kind: .accidentDeath, title: "意外身故", perDay: false),
    HealthItem(kind: .accidentInpatientDaily, title: "意外住院日額", perDay: true),
    HealthItem(kind: .accidentFracture, title: "骨折未住院", perDay: false),
    HealthItem(kind: .surgerySchedule, title: "住院手術（依手術表）", perDay: false),
    HealthItem(kind: .outpatientSurgery, title: "門診手術", perDay: false),
    HealthItem(kind: .actualExpense, title: "實支實付", perDay: false)
]

private func ntd(_ amount: Int) -> String { "NT$\(amount.formatted())" }

@MainActor
struct PolicyHealthCheckView: View {
    @ObservedObject var store: PolicyStore
    let onEdit: (UserPolicy) -> Void

    private let totalKinds: [(BenefitKind, String)] = [
        (.inpatientDaily, "住院日額合計（每日）"),
        (.accidentInpatientDaily, "意外住院日額合計（每日）"),
        (.deathBenefit, "一般身故合計"),
        (.accidentDeath, "意外身故合計"),
        (.accidentFracture, "骨折未住院金額合計")
    ]

    var body: some View {
        NavigationStack {
            List {
                if let message = store.storageMessage {
                    Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }

                Section("逐張保單健檢") {
                    if store.policies.isEmpty {
                        ContentUnavailableView("尚未建立保單", systemImage: "stethoscope", description: Text("在「總覽」或「拍照建檔」建立保單後，這裡會整理每張保單的給付項目與上下限。"))
                    }
                    ForEach(store.policies) { policy in
                        NavigationLink {
                            PolicyHealthDetailView(policy: policy) { onEdit(policy) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(policy.productName).font(.headline)
                                Text("\(policy.insurer) · \((policy.productRole ?? .unknown).rawValue)").font(.subheadline)
                                Text(summary(of: policy)).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !store.policies.isEmpty {
                    Section("全部保單合計（依你記錄的金額）") {
                        ForEach(totalKinds, id: \.0) { kind, title in
                            totalRow(kind: kind, title: title)
                        }
                        Text("「已核對」是該保單的條款版本、條號/頁碼與 HTTPS 來源都已記錄並確認。合計僅是把你輸入的數字相加，不是理賠承諾，也不判斷保額是否足夠。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("保障項目紀錄") {
                    ForEach(CoverageCategory.allCases) { category in
                        let matches = store.policies.filter { $0.categories.contains(category) }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: category.symbol).frame(width: 24).foregroundStyle(matches.isEmpty ? .orange : .green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.rawValue).font(.headline)
                                if matches.isEmpty {
                                    Text("目前未找到保單紀錄，需確認是否為保障缺口。")
                                        .font(.footnote).foregroundStyle(.secondary)
                                } else {
                                    ForEach(matches) { policy in
                                        Text("\(policy.insurer)／\(policy.productName) · \(policy.clauseIsVerified ? "條款已核對" : "條款待核對")")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }

                Section("保單資料待補") {
                    let incomplete = store.policies.filter { !$0.missingFields.isEmpty }
                    if store.policies.isEmpty {
                        Text("建立保單後，這裡會提醒尚未記錄的生效日、保障類別或條款來源。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if incomplete.isEmpty {
                        Text("目前已填寫基本欄位；仍請以保單原件核對條款與保障內容。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(incomplete) { policy in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(policy.insurer)／\(policy.productName)").font(.subheadline.bold())
                                Text("尚未記錄：\(policy.missingFields.joined(separator: "、"))")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Button("編輯並補充") { onEdit(policy) }
                                    .font(.footnote)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    Text("這些是資料完整度提示，不是保障缺口判定。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("如何解讀") {
                    Text("健檢只整理你自行建檔、且標示來源的保障內容，不會判斷適不適合、保額是否足夠，也不會把「未記錄」當成確定缺口。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("若商品名稱、附約或條款版本不確定，先回到保單及保險公司原始條款核對。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("保單健檢")
        }
    }

    private func summary(of policy: UserPolicy) -> String {
        let recorded = healthItems.filter { !policy.recordedBenefits($0.kind).isEmpty }
        if recorded.isEmpty { return "尚未記錄任何給付項目" }
        return "已記錄 \(recorded.count)／\(healthItems.count) 項：" + recorded.map(\.title).joined(separator: "、")
    }

    private func totalRow(kind: BenefitKind, title: String) -> some View {
        var verified = 0
        var unverified = 0
        for policy in store.policies {
            for benefit in policy.recordedBenefits(kind) {
                guard let amount = benefit.amountNTD, amount > 0 else { continue }
                if benefit.verifiedEligible { verified += amount } else { unverified += amount }
            }
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline)
            if verified == 0 && unverified == 0 {
                Text("未記錄").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("已核對：\(ntd(verified))").font(.footnote)
                if unverified > 0 {
                    Text("未核對（僅供參考）：\(ntd(unverified))").font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }
}

@MainActor
struct PolicyHealthDetailView: View {
    let policy: UserPolicy
    let onEdit: () -> Void

    var body: some View {
        List {
            Section("保單") {
                LabeledContent("保險公司", value: policy.insurer)
                LabeledContent("商品", value: policy.productName)
                LabeledContent("主約/附約", value: (policy.productRole ?? .unknown).rawValue)
                if let start = policy.startDate {
                    LabeledContent("生效日", value: start.formatted(date: .abbreviated, time: .omitted))
                } else {
                    LabeledContent("生效日", value: "未記錄")
                }
                LabeledContent("條款狀態", value: policy.clauseIsVerified ? "版本與來源已核對" : "待核對")
                if let version = policy.clauseVersion { LabeledContent("條款版本", value: version) }
            }

            ForEach(healthItems) { item in
                Section(item.title) {
                    let found = policy.recordedBenefits(item.kind)
                    if found.isEmpty {
                        Text("未記錄。這不代表沒有此保障，請對照保單條款後補充。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(found) { benefit in
                            benefitRows(item, benefit)
                        }
                    }
                }
            }

            Section("條款連結") {
                if let url = ClauseLinks.directURL(policy.clauseURL) {
                    Link("開啟你記錄的條款原文", destination: url)
                } else {
                    Text("尚未記錄條款網址。以下是間接查詢入口，結果未經本 App 核驗，請確認版本與你的保單相符。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("保發中心商品查詢", destination: ClauseLinks.tiiQuery)
                    Link("網頁搜尋條款：\(policy.productName)", destination: ClauseLinks.webSearch(company: policy.insurer, product: policy.productName))
                }
            }

            Section {
                Text("理賠須依保單生效時適用的條款版本、診斷、手術表、除外責任與完整文件由保險公司審核。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("保單健檢")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("編輯", action: onEdit) }
        }
    }

    @ViewBuilder
    private func benefitRows(_ item: HealthItem, _ benefit: PolicyBenefit) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let amount = benefit.amountNTD {
                Text("\(ntd(amount))\(item.perDay ? "／日" : "")").font(.headline)
            } else {
                Text("有此給付項目，金額未記錄").font(.subheadline)
            }
            if let days = benefit.maxDays {
                Text("給付日數上限：\(days) 日")
                if item.perDay, let amount = benefit.amountNTD {
                    let (total, overflow) = amount.multipliedReportingOverflow(by: days)
                    if !overflow { Text("單次最高累計：\(ntd(total))（日額 × 日數上限）") }
                }
            } else if item.perDay {
                Text("給付日數上限：未記錄")
            }
            if let low = benefit.limitMinNTD, let high = benefit.limitMaxNTD {
                Text("條款可投保範圍：\(ntd(low)) – \(ntd(high))")
                if let amount = benefit.amountNTD {
                    if amount < low || amount > high {
                        Text("你記錄的金額不在這個範圍內，請重新核對保單與條款。").foregroundStyle(.red)
                    } else if amount == high {
                        Text("已在記錄範圍的上限。")
                    } else if amount == low {
                        Text("已在記錄範圍的下限。")
                    }
                }
            } else if item.perDay {
                Text("條款可投保上下限：未記錄")
            }
            if let reference = benefit.clauseReference, !reference.isEmpty {
                Text("條款依據：\(reference)")
            }
            Text(benefit.verifiedEligible ? "已核對" : "未核對，不納入理賠預估")
                .foregroundStyle(benefit.verifiedEligible ? .green : .orange)
        }
        .font(.footnote)
        .padding(.vertical, 2)
    }
}
