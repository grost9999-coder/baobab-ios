import SwiftUI

@MainActor
struct PolicyEditorView: View {
    let ocrDraft: String
    let existingPolicy: UserPolicy?
    let onSave: (UserPolicy) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var insurer = ""
    @State private var productName = ""
    @State private var startDate = Date()
    @State private var hasStartDate = false
    @State private var endDate = Date()
    @State private var hasEndDate = false
    @State private var categories: Set<CoverageCategory> = []
    @State private var dailyBenefit = ""
    @State private var hasSurgeryBenefit = false
    @State private var hasOutpatientBenefit = false
    @State private var hasActualExpense = false
    @State private var clauseVersion = ""
    @State private var clauseReference = ""
    @State private var clauseURL = ""
    @State private var verifiedByUser = false

    init(ocrDraft: String = "", existingPolicy: UserPolicy? = nil, onSave: @escaping (UserPolicy) -> Void) {
        self.ocrDraft = ocrDraft
        self.existingPolicy = existingPolicy
        self.onSave = onSave
        _insurer = State(initialValue: existingPolicy?.insurer ?? "")
        _productName = State(initialValue: existingPolicy?.productName ?? "")
        _startDate = State(initialValue: existingPolicy?.startDate ?? Date())
        _hasStartDate = State(initialValue: existingPolicy?.startDate != nil)
        _endDate = State(initialValue: existingPolicy?.endDate ?? Date())
        _hasEndDate = State(initialValue: existingPolicy?.endDate != nil)
        _categories = State(initialValue: Set(existingPolicy?.categories ?? []))
        let dailyAmount = existingPolicy?.benefits.first(where: { $0.kind == .inpatientDaily })?.amountNTD
        _dailyBenefit = State(initialValue: dailyAmount.map { String($0) } ?? "")
        _hasSurgeryBenefit = State(initialValue: existingPolicy?.benefits.contains(where: { $0.kind == .surgerySchedule }) ?? false)
        _hasOutpatientBenefit = State(initialValue: existingPolicy?.benefits.contains(where: { $0.kind == .outpatientSurgery }) ?? false)
        _hasActualExpense = State(initialValue: existingPolicy?.benefits.contains(where: { $0.kind == .actualExpense }) ?? false)
        _clauseVersion = State(initialValue: existingPolicy?.clauseVersion ?? "")
        _clauseReference = State(initialValue: existingPolicy?.clauseReference ?? "")
        _clauseURL = State(initialValue: existingPolicy?.clauseURL?.absoluteString ?? "")
        _verifiedByUser = State(initialValue: existingPolicy?.clauseIsVerified ?? false)
    }

    private var traceable: Bool {
        verifiedByUser && !clauseVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !clauseReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        URL(string: clauseURL)?.scheme?.lowercased() == "https"
    }

    private var ocrSuggestions: PolicyOCRSuggestions {
        let companyNames = ProductCatalogStore.load().companies
            .filter { $0.line == "壽險" || $0.line == "產險" }
            .map(\.name)
        return PolicyOCRDraftParser.parse(ocrDraft, knownCompanies: companyNames)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !ocrDraft.isEmpty {
                    Section("OCR 辨識草稿，僅供人工核對") {
                        Text(ocrDraft)
                            .font(.footnote)
                            .textSelection(.enabled)
                        Text("辨識文字不會寫入保單檔案。請自行核對公司、商品名稱與保單內容。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("欄位候選，需自行核對後採用") {
                        if let candidate = ocrSuggestions.insurer {
                            Button("採用公司候選：\(candidate)") { insurer = candidate }
                        }
                        if let candidate = ocrSuggestions.productName {
                            Button("採用商品名稱候選：\(candidate)") { productName = candidate }
                        }
                        if let candidate = ocrSuggestions.startDate {
                            Button("採用生效日候選：\(candidate.formatted(date: .numeric, time: .omitted))") {
                                startDate = candidate
                                hasStartDate = true
                            }
                        }
                        if let candidate = ocrSuggestions.dailyBenefit {
                            Button("採入住院日額候選：NT$\(candidate.formatted())") { dailyBenefit = String(candidate) }
                        }
                        if !ocrSuggestions.categories.isEmpty {
                            Button("套用保障類別候選（\(ocrSuggestions.categories.map(\.rawValue).joined(separator: "、"))）") {
                                categories.formUnion(ocrSuggestions.categories)
                            }
                        }
                        if !ocrSuggestions.hasSuggestions {
                            Text("未找到帶有明確欄位標籤的候選值；請手動輸入，避免從不確定文字推斷保障。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("候選僅由裝置端 OCR 文字比對而來；套用後仍需核對保單原文，不會自動標記為已核實。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("保單基本資料") {
                    TextField("保險公司", text: $insurer)
                        .textContentType(.organizationName)
                    TextField("商品名稱/附約名稱", text: $productName)
                    Toggle("填寫生效日期", isOn: $hasStartDate)
                    if hasStartDate { DatePicker("生效日期", selection: $startDate, displayedComponents: .date) }
                    Toggle("保單已終止/期滿", isOn: $hasEndDate)
                    if hasEndDate { DatePicker("終止/期滿日期", selection: $endDate, displayedComponents: .date) }
                }
                Section("保單上列出的保障類別") {
                    ForEach(CoverageCategory.allCases) { category in
                        Toggle(isOn: binding(for: category)) {
                            Label(category.rawValue, systemImage: category.symbol)
                        }
                    }
                    Text("此處記錄的是你確認保單上有列出的項目，不代表已確認理賠適用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("你從條款核對到的給付") {
                    TextField("住院每日定額給付（元，選填）", text: $dailyBenefit).keyboardType(.numberPad)
                    Toggle("此保單有手術給付", isOn: $hasSurgeryBenefit)
                    Toggle("此保單有門診手術給付", isOn: $hasOutpatientBenefit)
                    Toggle("此保單有實支實付", isOn: $hasActualExpense)
                    Text("手術表金額會在試算時依每張保單、每個手術項目分別輸入及核對。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("條款來源與版本") {
                    TextField("條款版本/修訂日期", text: $clauseVersion)
                    TextField("條號與頁碼", text: $clauseReference)
                    TextField("條款原始 HTTPS 網址", text: $clauseURL).keyboardType(.URL).textInputAutocapitalization(.never)
                    Toggle("我已核對此版本條款與上述給付", isOn: $verifiedByUser)
                    if !traceable {
                        Text("缺少版本、條號/頁碼、HTTPS 來源或核對確認時，這張保單不會提供理賠金額。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("僅儲存在此 iPhone 的受保護 App 資料夾。不保存身分證、姓名、保單號或原始照片。卸載 App 可能會刪除資料。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existingPolicy == nil ? "確認保單草稿" : "編輯保單資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingPolicy == nil ? "儲存" : "更新") { save() }
                        .disabled(insurer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func binding(for category: CoverageCategory) -> Binding<Bool> {
        Binding(get: { categories.contains(category) }, set: { selected in
            if selected { categories.insert(category) } else { categories.remove(category) }
        })
    }

    private func save() {
        let isVerified = traceable
        var benefits = existingPolicy?.benefits.filter { $0.kind == .surgeryLumpSum || $0.kind == .other } ?? []
        if let daily = Int(dailyBenefit), daily > 0 {
            let prior = existingPolicy?.benefits.first(where: { $0.kind == .inpatientDaily })
            benefits.append(PolicyBenefit(kind: .inpatientDaily, label: prior?.label ?? "住院日額", amountNTD: daily, maxDays: prior?.maxDays, clauseReference: clauseReference, verifiedEligible: isVerified))
        }
        if hasSurgeryBenefit {
            let prior = existingPolicy?.benefits.first(where: { $0.kind == .surgerySchedule })
            benefits.append(PolicyBenefit(kind: .surgerySchedule, label: prior?.label ?? "手術表給付", amountNTD: prior?.amountNTD, maxDays: prior?.maxDays, clauseReference: clauseReference, verifiedEligible: isVerified))
        }
        if hasOutpatientBenefit {
            let prior = existingPolicy?.benefits.first(where: { $0.kind == .outpatientSurgery })
            benefits.append(PolicyBenefit(kind: .outpatientSurgery, label: prior?.label ?? "門診手術", amountNTD: prior?.amountNTD, maxDays: prior?.maxDays, clauseReference: clauseReference, verifiedEligible: isVerified))
        }
        if hasActualExpense {
            let prior = existingPolicy?.benefits.first(where: { $0.kind == .actualExpense })
            benefits.append(PolicyBenefit(kind: .actualExpense, label: prior?.label ?? "實支實付", amountNTD: prior?.amountNTD, maxDays: prior?.maxDays, clauseReference: clauseReference, verifiedEligible: isVerified))
        }
        let policy = UserPolicy(
            id: existingPolicy?.id ?? UUID(),
            insurer: insurer.trimmingCharacters(in: .whitespacesAndNewlines),
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: hasStartDate ? startDate : nil,
            endDate: hasEndDate ? endDate : nil,
            categories: categories.sorted { $0.rawValue < $1.rawValue },
            clauseVersion: clauseVersion.isEmpty ? nil : clauseVersion,
            clauseReference: clauseReference.isEmpty ? nil : clauseReference,
            clauseURL: URL(string: clauseURL),
            clauseVerifiedAt: isVerified ? Date() : nil,
            source: existingPolicy?.source ?? (ocrDraft.isEmpty ? .manuallyEntered : .photoDraft),
            benefits: benefits
        )
        onSave(policy)
        dismiss()
    }
}
