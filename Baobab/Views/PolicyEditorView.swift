import SwiftUI

@MainActor
struct PolicyEditorView: View {
    let ocrDraft: String
    let existingPolicy: UserPolicy?
    let onSave: (UserPolicy) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: ProductCatalogSnapshot
    @State private var insurer = ""
    @State private var productName = ""
    @State private var productRole: ProductRole = .unknown
    @State private var selectedProduct: InsuranceProduct?
    @State private var startDate = Date()
    @State private var hasStartDate = false
    @State private var endDate = Date()
    @State private var hasEndDate = false
    @State private var categories: Set<CoverageCategory> = []
    @State private var dailyBenefit = ""
    @State private var dailyMaxDays = ""
    @State private var dailyLimitMin = ""
    @State private var dailyLimitMax = ""
    @State private var deathBenefit = ""
    @State private var accidentDeath = ""
    @State private var accidentInpatientDaily = ""
    @State private var fractureBenefit = ""
    @State private var hasSurgeryBenefit = false
    @State private var hasOutpatientBenefit = false
    @State private var hasActualExpense = false
    @State private var clauseVersion = ""
    @State private var clauseReference = ""
    @State private var clauseURL = ""
    @State private var verifiedByUser = false

    private static let managedKinds: Set<BenefitKind> = [
        .inpatientDaily, .surgerySchedule, .outpatientSurgery, .actualExpense,
        .deathBenefit, .accidentDeath, .accidentInpatientDaily, .accidentFracture
    ]

    init(ocrDraft: String = "", existingPolicy: UserPolicy? = nil, onSave: @escaping (UserPolicy) -> Void) {
        self.ocrDraft = ocrDraft
        self.existingPolicy = existingPolicy
        self.onSave = onSave
        _catalog = State(initialValue: ProductCatalogStore.load())
        _insurer = State(initialValue: existingPolicy?.insurer ?? "")
        _productName = State(initialValue: existingPolicy?.productName ?? "")
        _productRole = State(initialValue: existingPolicy?.productRole ?? .unknown)
        _startDate = State(initialValue: existingPolicy?.startDate ?? Date())
        _hasStartDate = State(initialValue: existingPolicy?.startDate != nil)
        _endDate = State(initialValue: existingPolicy?.endDate ?? Date())
        _hasEndDate = State(initialValue: existingPolicy?.endDate != nil)
        _categories = State(initialValue: Set(existingPolicy?.categories ?? []))
        let daily = existingPolicy?.benefits.first(where: { $0.kind == .inpatientDaily })
        _dailyBenefit = State(initialValue: daily?.amountNTD.map { String($0) } ?? "")
        _dailyMaxDays = State(initialValue: daily?.maxDays.map { String($0) } ?? "")
        _dailyLimitMin = State(initialValue: daily?.limitMinNTD.map { String($0) } ?? "")
        _dailyLimitMax = State(initialValue: daily?.limitMaxNTD.map { String($0) } ?? "")
        _deathBenefit = State(initialValue: Self.amountString(existingPolicy, .deathBenefit))
        _accidentDeath = State(initialValue: Self.amountString(existingPolicy, .accidentDeath))
        _accidentInpatientDaily = State(initialValue: Self.amountString(existingPolicy, .accidentInpatientDaily))
        _fractureBenefit = State(initialValue: Self.amountString(existingPolicy, .accidentFracture))
        _hasSurgeryBenefit = State(initialValue: existingPolicy?.benefits.contains(where: { $0.kind == .surgerySchedule }) ?? false)
        _hasOutpatientBenefit = State(initialValue: existingPolicy?.benefits.contains(where: { $0.kind == .outpatientSurgery }) ?? false)
        _hasActualExpense = State(initialValue: existingPolicy?.benefits.contains(where: { $0.kind == .actualExpense }) ?? false)
        _clauseVersion = State(initialValue: existingPolicy?.clauseVersion ?? "")
        _clauseReference = State(initialValue: existingPolicy?.clauseReference ?? "")
        _clauseURL = State(initialValue: existingPolicy?.clauseURL?.absoluteString ?? "")
        _verifiedByUser = State(initialValue: existingPolicy?.clauseIsVerified ?? false)
    }

    private static func amountString(_ policy: UserPolicy?, _ kind: BenefitKind) -> String {
        policy?.benefits.first(where: { $0.kind == kind })?.amountNTD.map { String($0) } ?? ""
    }

    private static func parseAmount(_ text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(cleaned), (1...1_000_000_000).contains(value) else { return nil }
        return value
    }

    private static func parseDays(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(cleaned), (1...3650).contains(value) else { return nil }
        return value
    }

    private var traceable: Bool {
        verifiedByUser && !clauseVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !clauseReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        URL(string: clauseURL)?.scheme?.lowercased() == "https"
    }

    private var ocrSuggestions: PolicyOCRSuggestions {
        let companyNames = catalog.companies
            .filter { $0.line == "壽險" || $0.line == "產險" }
            .map(\.name)
        return PolicyOCRDraftParser.parse(ocrDraft, knownCompanies: companyNames)
    }

    private var trimmedInsurer: String { insurer.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedProduct: String { productName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var resolvedCompany: CatalogCompany? {
        InsurerDirectory.exactCompany(named: trimmedInsurer, in: catalog.companies)
    }

    private var insurerSuggestions: [InsurerMatch] {
        guard !trimmedInsurer.isEmpty, resolvedCompany == nil else { return [] }
        return InsurerDirectory.search(trimmedInsurer, in: catalog.companies, limit: 6, lines: ["壽險", "產險"])
    }

    private var productSuggestions: [InsuranceProduct] {
        guard !trimmedProduct.isEmpty, selectedProduct == nil else { return [] }
        return ProductSearch.search(
            products: catalog.products,
            companies: catalog.companies,
            query: trimmedProduct,
            companyCode: resolvedCompany?.code,
            limit: 8
        )
    }

    private var companyHasNoProducts: Bool {
        guard let company = resolvedCompany else { return catalog.products.isEmpty }
        return !catalog.products.contains { $0.companyCode == company.code }
    }

    private var inputProblems: [String] {
        var problems: [String] = []
        let amountFields: [(String, String)] = [
            ("住院日額", dailyBenefit), ("日額可投保下限", dailyLimitMin), ("日額可投保上限", dailyLimitMax),
            ("一般身故保額", deathBenefit), ("意外身故保額", accidentDeath),
            ("意外住院日額", accidentInpatientDaily), ("骨折未住院金額", fractureBenefit)
        ]
        for (label, text) in amountFields where !text.trimmingCharacters(in: .whitespaces).isEmpty {
            if Self.parseAmount(text) == nil { problems.append("\(label)須為 1 至 1,000,000,000 的整數。") }
        }
        if !dailyMaxDays.trimmingCharacters(in: .whitespaces).isEmpty, Self.parseDays(dailyMaxDays) == nil {
            problems.append("日額給付日數上限須為 1 至 3,650 的整數。")
        }
        if let low = Self.parseAmount(dailyLimitMin), let high = Self.parseAmount(dailyLimitMax), low > high {
            problems.append("日額可投保下限不能大於上限。")
        }
        return problems
    }

    var body: some View {
        NavigationStack {
            Form {
                if !ocrDraft.isEmpty { ocrSections }
                basicSection
                Section("保單上列出的保障類別") {
                    ForEach(CoverageCategory.allCases) { category in
                        Toggle(isOn: binding(for: category)) {
                            Label(category.rawValue, systemImage: category.symbol)
                        }
                    }
                    Text("此處記錄的是你確認保單上有列出的項目，不代表已確認理賠適用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("你從條款核對到的給付（供保單健檢與理賠預估使用）") {
                    TextField("住院每日定額給付（元，選填）", text: $dailyBenefit).keyboardType(.numberPad)
                    TextField("日額給付日數上限（日，選填）", text: $dailyMaxDays).keyboardType(.numberPad)
                    TextField("日額條款可投保下限（元，選填）", text: $dailyLimitMin).keyboardType(.numberPad)
                    TextField("日額條款可投保上限（元，選填）", text: $dailyLimitMax).keyboardType(.numberPad)
                    TextField("一般身故保險金（元，選填）", text: $deathBenefit).keyboardType(.numberPad)
                    TextField("意外身故保險金（元，選填）", text: $accidentDeath).keyboardType(.numberPad)
                    TextField("意外住院每日給付（元，選填）", text: $accidentInpatientDaily).keyboardType(.numberPad)
                    TextField("骨折未住院給付（元，選填）", text: $fractureBenefit).keyboardType(.numberPad)
                    Toggle("此保單有手術給付", isOn: $hasSurgeryBenefit)
                    Toggle("此保單有門診手術給付", isOn: $hasOutpatientBenefit)
                    Toggle("此保單有實支實付", isOn: $hasActualExpense)
                    Text("手術表金額會在試算時依每張保單、每個手術項目分別輸入及核對。骨折給付通常依骨折別表給付，這裡填你核對到的金額。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("條款來源與版本") {
                    TextField("條款版本/修訂日期", text: $clauseVersion)
                    TextField("條號與頁碼", text: $clauseReference)
                    TextField("條款原始 HTTPS 網址", text: $clauseURL).keyboardType(.URL).textInputAutocapitalization(.never)
                    if URL(string: clauseURL)?.scheme?.lowercased() != "https" && !trimmedInsurer.isEmpty && !trimmedProduct.isEmpty {
                        Link("找不到條款？用網頁搜尋「\(trimmedProduct)」條款", destination: ClauseLinks.webSearch(company: trimmedInsurer, product: trimmedProduct))
                            .font(.footnote)
                        Link("保發中心商品查詢", destination: ClauseLinks.tiiQuery)
                            .font(.footnote)
                    }
                    Toggle("我已核對此版本條款與上述給付", isOn: $verifiedByUser)
                    if !traceable {
                        Text("缺少版本、條號/頁碼、HTTPS 來源或核對確認時，這張保單不會提供理賠金額。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !inputProblems.isEmpty {
                    Section("請修正") {
                        ForEach(inputProblems, id: \.self) { Text($0).font(.footnote).foregroundStyle(.red) }
                    }
                }
                Section {
                    Text("僅儲存在此 iPhone 的受保護 App 資料夾。不保存身分證、姓名、保單號或原始照片。卸載 App 可能會刪除資料。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existingPolicy == nil ? "確認保單草稿" : "編輯保單資料")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: productName) { _, newValue in
                if let selected = selectedProduct, selected.name != newValue { selectedProduct = nil }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingPolicy == nil ? "儲存" : "更新") { save() }
                        .disabled(trimmedInsurer.isEmpty || trimmedProduct.isEmpty || !inputProblems.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var ocrSections: some View {
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

    @ViewBuilder
    private var basicSection: some View {
        Section("保險公司") {
            TextField("輸入簡稱，例如：南山、國泰、富邦", text: $insurer)
                .textContentType(.organizationName)
            if let company = resolvedCompany {
                Label("\(company.name)（代碼 \(company.code)）", systemImage: "checkmark.seal")
                    .font(.footnote).foregroundStyle(.green)
            }
            ForEach(insurerSuggestions) { match in
                Button {
                    insurer = match.company.name
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.company.name).foregroundStyle(.primary)
                        Text("\(match.company.code) · \(match.company.line)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !trimmedInsurer.isEmpty && resolvedCompany == nil && insurerSuggestions.isEmpty {
                Text("索引中找不到符合的公司；仍可儲存你輸入的名稱，但無法連結商品目錄。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        Section("商品") {
            TextField("商品名稱/附約名稱，例如輸入「住院」", text: $productName)
            Picker("主約/附約", selection: $productRole) {
                ForEach(ProductRole.allCases) { Text($0.rawValue).tag($0) }
            }
            ForEach(productSuggestions) { product in
                Button {
                    apply(product)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name).foregroundStyle(.primary)
                        Text("\(product.company) · \((product.role ?? .unknown).rawValue) · \(product.salesStatus.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !trimmedProduct.isEmpty && productSuggestions.isEmpty && selectedProduct == nil && companyHasNoProducts {
                Text("商品目錄尚未收錄\(resolvedCompany == nil ? "" : "此公司")的商品；請依保單原文手動輸入商品名稱。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        Section("保單期間") {
            Toggle("填寫生效日期", isOn: $hasStartDate)
            if hasStartDate { DatePicker("生效日期", selection: $startDate, displayedComponents: .date) }
            Toggle("保單已終止/期滿", isOn: $hasEndDate)
            if hasEndDate { DatePicker("終止/期滿日期", selection: $endDate, displayedComponents: .date) }
        }
    }

    private func apply(_ product: InsuranceProduct) {
        selectedProduct = product
        productName = product.name
        productRole = product.role ?? .unknown
        if let company = catalog.companies.first(where: { $0.code == product.companyCode }) {
            insurer = company.name
        } else {
            insurer = product.company
        }
        if clauseVersion.isEmpty, let version = product.clauseVersion { clauseVersion = version }
        if clauseURL.isEmpty, let url = ClauseLinks.directURL(product.clauseURL) { clauseURL = url.absoluteString }
        for benefit in product.benefits {
            switch benefit.kind {
            case .inpatientDaily:
                if dailyBenefit.isEmpty, let amount = benefit.amountNTD { dailyBenefit = String(amount) }
                if dailyMaxDays.isEmpty, let days = benefit.maxDays { dailyMaxDays = String(days) }
                if dailyLimitMin.isEmpty, let low = benefit.limitMinNTD { dailyLimitMin = String(low) }
                if dailyLimitMax.isEmpty, let high = benefit.limitMaxNTD { dailyLimitMax = String(high) }
            case .deathBenefit:
                if deathBenefit.isEmpty, let amount = benefit.amountNTD { deathBenefit = String(amount) }
            case .accidentDeath:
                if accidentDeath.isEmpty, let amount = benefit.amountNTD { accidentDeath = String(amount) }
            case .accidentInpatientDaily:
                if accidentInpatientDaily.isEmpty, let amount = benefit.amountNTD { accidentInpatientDaily = String(amount) }
            case .accidentFracture:
                if fractureBenefit.isEmpty, let amount = benefit.amountNTD { fractureBenefit = String(amount) }
            case .surgerySchedule: hasSurgeryBenefit = true
            case .outpatientSurgery: hasOutpatientBenefit = true
            case .actualExpense: hasActualExpense = true
            case .surgeryLumpSum, .other: break
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
        let reference = clauseReference.trimmingCharacters(in: .whitespacesAndNewlines)
        var benefits = existingPolicy?.benefits.filter { !Self.managedKinds.contains($0.kind) } ?? []

        func prior(_ kind: BenefitKind) -> PolicyBenefit? {
            existingPolicy?.benefits.first(where: { $0.kind == kind })
        }
        func addAmount(_ kind: BenefitKind, _ label: String, _ text: String, maxDays: Int? = nil, low: Int? = nil, high: Int? = nil) {
            guard let amount = Self.parseAmount(text) else { return }
            benefits.append(PolicyBenefit(
                kind: kind, label: prior(kind)?.label ?? label, amountNTD: amount, maxDays: maxDays,
                clauseReference: reference, verifiedEligible: isVerified, limitMinNTD: low, limitMaxNTD: high
            ))
        }
        func addFlag(_ kind: BenefitKind, _ label: String) {
            let old = prior(kind)
            benefits.append(PolicyBenefit(
                kind: kind, label: old?.label ?? label, amountNTD: old?.amountNTD, maxDays: old?.maxDays,
                clauseReference: reference, verifiedEligible: isVerified, limitMinNTD: old?.limitMinNTD, limitMaxNTD: old?.limitMaxNTD
            ))
        }

        addAmount(.inpatientDaily, "住院日額", dailyBenefit, maxDays: Self.parseDays(dailyMaxDays), low: Self.parseAmount(dailyLimitMin), high: Self.parseAmount(dailyLimitMax))
        addAmount(.deathBenefit, "一般身故保險金", deathBenefit)
        addAmount(.accidentDeath, "意外身故保險金", accidentDeath)
        addAmount(.accidentInpatientDaily, "意外住院日額", accidentInpatientDaily)
        addAmount(.accidentFracture, "骨折未住院給付", fractureBenefit)
        if hasSurgeryBenefit { addFlag(.surgerySchedule, "手術表給付") }
        if hasOutpatientBenefit { addFlag(.outpatientSurgery, "門診手術") }
        if hasActualExpense { addFlag(.actualExpense, "實支實付") }

        let policy = UserPolicy(
            id: existingPolicy?.id ?? UUID(),
            insurer: trimmedInsurer,
            productName: trimmedProduct,
            startDate: hasStartDate ? startDate : nil,
            endDate: hasEndDate ? endDate : nil,
            categories: categories.sorted { $0.rawValue < $1.rawValue },
            clauseVersion: clauseVersion.isEmpty ? nil : clauseVersion,
            clauseReference: reference.isEmpty ? nil : reference,
            clauseURL: URL(string: clauseURL),
            clauseVerifiedAt: isVerified ? Date() : nil,
            source: existingPolicy?.source ?? (ocrDraft.isEmpty ? .manuallyEntered : .photoDraft),
            benefits: benefits,
            companyCode: resolvedCompany?.code,
            productRole: productRole == .unknown ? nil : productRole
        )
        onSave(policy)
        dismiss()
    }
}
