import SwiftUI
import UniformTypeIdentifiers

struct ProductCatalogSnapshot: Decodable {
    var schemaVersion: Int
    var fetchedOn: String
    var dataStatus: String
    var source: ProductCatalogSource
    var companies: [CatalogCompany]
    var products: [InsuranceProduct]
}

struct ProductCatalogSource: Decodable {
    var name: String
    var url: URL
    var notes: String
    var rightsStatus: String?
    var rightsEvidenceURL: URL?
    var rightsCheckedOn: String?
}

struct CatalogCompany: Identifiable, Decodable {
    var code: String
    var name: String
    var line: String
    var rosterStatus: String
    var id: String { code }
}

enum CatalogImportError: LocalizedError {
    case tooLarge
    case undecodable
    case rightsNotRecorded
    case indexOnlyViolation
    case unknownCompany(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "檔案超過 50 MB，未匯入。"
        case .undecodable: return "檔案格式不符合商品目錄 schema，未匯入。"
        case .rightsNotRecorded: return "目錄缺少授權記錄（rightsStatus 須為 authorized、public_open_license 或 index_links_only，並附 HTTPS rightsEvidenceURL 與 rightsCheckedOn），未匯入。"
        case .indexOnlyViolation: return "索引模式（index_links_only）的商品不得含給付內容或 verified 標記，且每筆須附 HTTPS 官網連結，未匯入。"
        case .unknownCompany(let code): return "有商品引用未知公司代碼 \(code)，未匯入。"
        }
    }
}

enum ProductCatalogStore {
    private static let fallbackURL = URL(string: "https://insprod.tii.org.tw/Query.aspx")!

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var importedFileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Baobab", isDirectory: true).appendingPathComponent("imported_catalog.json")
    }

    /// 內建公司索引，加上使用者匯入且附授權記錄的商品目錄（若有）。
    static func load() -> ProductCatalogSnapshot {
        let bundled = loadBundled()
        guard let imported = loadImported() else { return bundled }
        var merged = bundled
        let knownCodes = Set(bundled.companies.map(\.code))
        merged.companies += imported.companies.filter { !knownCodes.contains($0.code) }
        var knownIDs = Set(bundled.products.map(\.id))
        for product in imported.products where !knownIDs.contains(product.id) {
            merged.products.append(product)
            knownIDs.insert(product.id)
        }
        if !imported.products.isEmpty {
            merged.dataStatus = "imported_authorized_records"
            merged.source.notes = bundled.source.notes + " 已匯入使用者提供的授權商品目錄「\(imported.source.name)」，擷取日 \(imported.fetchedOn)。"
        }
        return merged
    }

    static func importedProductCount() -> Int {
        loadImported()?.products.count ?? 0
    }

    @discardableResult
    static func importCatalog(from url: URL) throws -> Int {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 50_000_000 else { throw CatalogImportError.tooLarge }
        guard let snapshot = try? decoder.decode(ProductCatalogSnapshot.self, from: data) else { throw CatalogImportError.undecodable }

        let rightsOK = ["authorized", "public_open_license", "index_links_only"].contains(snapshot.source.rightsStatus ?? "")
            && snapshot.source.rightsEvidenceURL?.scheme?.lowercased() == "https"
            && !(snapshot.source.rightsCheckedOn ?? "").isEmpty
        guard rightsOK else { throw CatalogImportError.rightsNotRecorded }
        if snapshot.source.rightsStatus == "index_links_only" {
            for product in snapshot.products {
                guard product.benefits.isEmpty, product.dataQuality != .verified, product.sourceURL?.scheme?.lowercased() == "https" else {
                    throw CatalogImportError.indexOnlyViolation
                }
            }
        }

        let knownCodes = Set(loadBundled().companies.map(\.code)).union(snapshot.companies.map(\.code))
        for product in snapshot.products {
            guard let code = product.companyCode, knownCodes.contains(code) else {
                throw CatalogImportError.unknownCompany(product.companyCode ?? "（空白）")
            }
        }

        let directory = importedFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: importedFileURL, options: .atomic)
        return snapshot.products.count
    }

    static func removeImported() {
        try? FileManager.default.removeItem(at: importedFileURL)
    }

    private static func loadBundled() -> ProductCatalogSnapshot {
        guard let url = Bundle.main.url(forResource: "product_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return ProductCatalogSnapshot(
                schemaVersion: 1,
                fetchedOn: "未知",
                dataStatus: "catalog_file_missing",
                source: ProductCatalogSource(name: "商品資料來源未設定", url: fallbackURL, notes: "找不到 app 內商品目錄檔案。"),
                companies: [],
                products: []
            )
        }
        return (try? decoder.decode(ProductCatalogSnapshot.self, from: data)) ?? ProductCatalogSnapshot(
            schemaVersion: 1,
            fetchedOn: "未知",
            dataStatus: "catalog_file_invalid",
            source: ProductCatalogSource(name: "商品目錄格式錯誤", url: fallbackURL, notes: "商品目錄無法解碼，未顯示任何商品。"),
            companies: [],
            products: []
        )
    }

    /// 匯入檔的商品若宣稱 verified 卻缺少可追溯的條款/來源欄位，載入時降為待人工核對。
    private static func loadImported() -> ProductCatalogSnapshot? {
        guard let data = try? Data(contentsOf: importedFileURL),
              var snapshot = try? decoder.decode(ProductCatalogSnapshot.self, from: data) else { return nil }
        snapshot.products = snapshot.products.map { product in
            var safe = product
            let traceable = product.isEstimateEligible && product.sourceURL?.scheme?.lowercased() == "https" && product.clauseURL?.scheme?.lowercased() == "https"
            if product.dataQuality == .verified && !traceable {
                safe.dataQuality = .needsReview
                safe.benefits = product.benefits.map { benefit in
                    var downgraded = benefit
                    downgraded.verifiedEligible = false
                    return downgraded
                }
            }
            return safe
        }
        return snapshot
    }
}

@MainActor
struct CatalogView: View {
    @State private var snapshot = ProductCatalogStore.load()
    @State private var searchText = ""
    @State private var selectedStatus = "全部"
    @State private var selectedRole = "全部"
    @State private var selectedCompany: CatalogCompany?
    @State private var showImporter = false
    @State private var importMessage: String?

    private let maximumRows = 200

    private var statusFilter: SalesStatus? { SalesStatus(rawValue: selectedStatus) }
    private var roleFilter: ProductRole? { ProductRole(rawValue: selectedRole) }

    private var visibleProducts: [InsuranceProduct] {
        ProductSearch.search(
            products: snapshot.products,
            companies: snapshot.companies,
            query: searchText,
            companyCode: selectedCompany?.code,
            status: statusFilter,
            role: roleFilter
        )
    }

    private var visibleCompanies: [CatalogCompany] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return snapshot.companies }
        return InsurerDirectory.search(searchText, in: snapshot.companies, limit: 60).map(\.company)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("資料來源與涵蓋狀態") {
                    Label("目前商品條款紀錄：\(snapshot.products.count) 筆", systemImage: "books.vertical")
                    Text("公司代碼索引擷取日：\(snapshot.fetchedOn)。下拉名單包含歷史、合併前或持照狀態待確認公司，不等同現行持照名錄。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(snapshot.source.notes)
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("開啟保發中心商品查詢", destination: snapshot.source.url)
                    if let importMessage {
                        Text(importMessage).font(.footnote).foregroundStyle(.orange)
                    }
                }

                if let company = selectedCompany {
                    Section("已選保險公司") {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(company.name).font(.headline)
                                Text("\(company.code) · \(company.line)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("清除") { selectedCompany = nil }
                        }
                    }
                }

                Section(selectedCompany == nil ? "保險公司（輸入簡稱可自動比對，如：南山）" : "其他保險公司") {
                    ForEach(visibleCompanies) { company in
                        Button {
                            selectedCompany = company
                            searchText = ""
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(company.name).foregroundStyle(.primary)
                                Text("\(company.code) · \(company.line) · \(company.rosterStatus)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if visibleCompanies.isEmpty {
                        Text("沒有符合的保險公司。可能使用了索引中沒有的簡稱，請改用公司全名關鍵字。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("商品（含現售與停售）") {
                    let rows = visibleProducts
                    if rows.isEmpty {
                        ContentUnavailableView(
                            snapshot.products.isEmpty ? "尚無已匯入的商品條款" : "沒有符合條件的商品",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(snapshot.products.isEmpty
                                ? "此版本只含官方查詢公司的索引；商品及條款需取得有授權記錄的資料後匯入。在此之前請用下方連結到官方查詢，並在建立保單時手動輸入商品名稱。"
                                : "試試其他商品名稱、公司、主約/附約或銷售狀態。")
                        )
                        if let company = selectedCompany {
                            Link("到保發中心查詢「\(company.name)」的商品", destination: ClauseLinks.tiiQuery)
                        }
                    } else {
                        ForEach(rows.prefix(maximumRows)) { product in
                            NavigationLink {
                                ProductDetailView(product: product)
                            } label: {
                                productRow(product)
                            }
                        }
                        if rows.count > maximumRows {
                            Text("符合 \(rows.count) 筆，只顯示前 \(maximumRows) 筆；請加入公司、狀態或更多關鍵字縮小範圍。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("商品與條款")
            .searchable(text: $searchText, prompt: "搜尋公司簡稱、商品名稱（如：南山、住院）")
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 6) {
                    Picker("商品狀態", selection: $selectedStatus) {
                        Text("全部").tag("全部")
                        Text("現售").tag(SalesStatus.onSale.rawValue)
                        Text("停售").tag(SalesStatus.discontinued.rawValue)
                        Text("未確認").tag(SalesStatus.unknown.rawValue)
                    }
                    .pickerStyle(.segmented)
                    Picker("主約或附約", selection: $selectedRole) {
                        Text("主附約").tag("全部")
                        Text("主約").tag(ProductRole.base.rawValue)
                        Text("附約").tag(ProductRole.rider.rawValue)
                        Text("未確認").tag(ProductRole.unknown.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("匯入授權商品目錄（JSON）", systemImage: "square.and.arrow.down") { showImporter = true }
                        if FileManager.default.fileExists(atPath: ProductCatalogStore.importedFileURL.path) {
                            Button("移除已匯入目錄", systemImage: "trash", role: .destructive) {
                                ProductCatalogStore.removeImported()
                                snapshot = ProductCatalogStore.load()
                                importMessage = "已移除匯入的商品目錄。"
                            }
                        }
                    } label: {
                        Label("目錄", systemImage: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let count = try ProductCatalogStore.importCatalog(from: url)
                        snapshot = ProductCatalogStore.load()
                        importMessage = "已匯入 \(count) 筆商品。未附可追溯條款來源的商品會標為待人工核對。"
                    } catch {
                        importMessage = error.localizedDescription
                    }
                case .failure(let error):
                    importMessage = error.localizedDescription
                }
            }
        }
    }

    private func productRow(_ product: InsuranceProduct) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(product.name).font(.headline)
            Text("\(product.company) · \((product.role ?? .unknown).rawValue) · \(product.salesStatus.rawValue) · \(product.line)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(product.isEstimateEligible ? "條款來源已核驗" : "條款未核驗，不可用於試算")
                .font(.caption).foregroundStyle(product.isEstimateEligible ? .green : .orange)
            if let version = product.clauseVersion {
                Text("條款版本：\(version)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ProductDetailView: View {
    let product: InsuranceProduct

    private var qualityLabel: String {
        switch product.dataQuality {
        case .verified: return "已核驗"
        case .needsReview: return "待人工核對"
        case .demo: return "示範資料"
        case .unavailable: return "資料不可用"
        }
    }

    var body: some View {
        List {
            Section("商品識別") {
                LabeledContent("保險公司", value: product.company)
                if let companyCode = product.companyCode { LabeledContent("公司代碼", value: companyCode) }
                LabeledContent("商品名稱", value: product.name)
                if let productCode = product.productCode { LabeledContent("商品代碼", value: productCode) }
                LabeledContent("險種", value: product.line)
                LabeledContent("主約/附約", value: (product.role ?? .unknown).rawValue)
                LabeledContent("銷售狀態", value: product.salesStatus.rawValue)
                LabeledContent("資料品質", value: qualityLabel)
            }
            Section("銷售期間與來源時間") {
                if let start = product.effectiveFrom {
                    LabeledContent("開始/生效", value: start.formatted(date: .abbreviated, time: .omitted))
                } else {
                    LabeledContent("開始/生效", value: "未提供")
                }
                if let end = product.salesEnd {
                    LabeledContent("停售日", value: end.formatted(date: .abbreviated, time: .omitted))
                } else {
                    LabeledContent("停售日", value: product.salesStatus == .onSale ? "未提供" : "未確認")
                }
                if let retrieved = product.sourceRetrievedAt {
                    LabeledContent("來源擷取日", value: retrieved.formatted(date: .abbreviated, time: .omitted))
                }
            }
            Section("條款版本與連結") {
                LabeledContent("條款版本", value: product.clauseVersion ?? "未提供")
                if let verifiedAt = product.clauseVerifiedAt {
                    LabeledContent("核驗日期", value: verifiedAt.formatted(date: .abbreviated, time: .omitted))
                } else {
                    Text("未提供可追溯核驗日期；此商品不可用於理賠試算。")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if let clauseURL = ClauseLinks.directURL(product.clauseURL) {
                    Link("開啟條款原文", destination: clauseURL)
                } else {
                    Text("此商品沒有已記錄的條款原文連結。以下是間接查詢入口，結果未經本 App 核驗，請確認公司、商品名稱與條款版本都與你的保單相符。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("保發中心商品查詢（需輸入公司與商品名稱）", destination: ClauseLinks.tiiQuery)
                    Link("網頁搜尋條款：\(product.name)", destination: ClauseLinks.webSearch(company: product.company, product: product.name))
                }
                if let sourceURL = product.sourceURL {
                    Link("開啟公司官網商品頁", destination: sourceURL)
                }
                Text("查詢結果或停售狀態不會取代個人保單所載的契約版本；理賠須依保單生效時適用條款核對。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("給付項目") {
                if product.benefits.isEmpty {
                    Text("尚未整理或核驗給付明細；不可從商品名稱推定保障。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(product.benefits) { benefit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(benefit.kind.rawValue) · \(benefit.label)").font(.subheadline.bold())
                            if let amount = benefit.amountNTD {
                                Text("金額：NT$\(amount.formatted())")
                            }
                            if let low = benefit.limitMinNTD, let high = benefit.limitMaxNTD {
                                Text("條款可投保範圍：NT$\(low.formatted()) – NT$\(high.formatted())")
                            }
                            if let maxDays = benefit.maxDays {
                                Text("天數上限：\(maxDays) 日")
                            }
                            if let reference = benefit.clauseReference {
                                Text("條款依據：\(reference)")
                            }
                            Text(benefit.verifiedEligible ? "此項已標記核對" : "此項尚未核對")
                                .font(.caption).foregroundStyle(benefit.verifiedEligible ? .secondary : .orange)
                        }
                        .font(.footnote)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("商品條款明細")
        .navigationBarTitleDisplayMode(.inline)
    }
}
