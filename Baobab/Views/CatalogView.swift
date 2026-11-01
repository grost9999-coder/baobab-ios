import SwiftUI

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
}

struct CatalogCompany: Identifiable, Decodable {
    var code: String
    var name: String
    var line: String
    var rosterStatus: String
    var id: String { code }
}

enum ProductCatalogStore {
    static func load() -> ProductCatalogSnapshot {
        guard let url = Bundle.main.url(forResource: "product_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return ProductCatalogSnapshot(
                schemaVersion: 1,
                fetchedOn: "未知",
                dataStatus: "catalog_file_missing",
                source: ProductCatalogSource(name: "商品資料來源未設定", url: URL(string: "https://insprod.tii.org.tw/Query.aspx")!, notes: "找不到 app 內商品目錄檔案。"),
                companies: [],
                products: []
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ProductCatalogSnapshot.self, from: data)) ?? ProductCatalogSnapshot(
            schemaVersion: 1,
            fetchedOn: "未知",
            dataStatus: "catalog_file_invalid",
            source: ProductCatalogSource(name: "商品目錄格式錯誤", url: URL(string: "https://insprod.tii.org.tw/Query.aspx")!, notes: "商品目錄無法解碼，未顯示任何商品。"),
            companies: [],
            products: []
        )
    }
}

struct CatalogView: View {
    @State private var snapshot = ProductCatalogStore.load()
    @State private var searchText = ""
    @State private var selectedStatus = "全部"

    private var visibleProducts: [InsuranceProduct] {
        snapshot.products.filter { product in
            let matchesStatus = selectedStatus == "全部" || product.salesStatus.rawValue == selectedStatus
            let matchesText = searchText.isEmpty || product.name.localizedCaseInsensitiveContains(searchText) ||
                product.company.localizedCaseInsensitiveContains(searchText) ||
                (product.productCode?.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesStatus && matchesText
        }
    }

    private var visibleCompanies: [CatalogCompany] {
        guard !searchText.isEmpty else { return snapshot.companies }
        return snapshot.companies.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.code.localizedCaseInsensitiveContains(searchText)
        }
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
                }

                Section("商品資料") {
                    if visibleProducts.isEmpty {
                        ContentUnavailableView(
                            snapshot.products.isEmpty ? "尚無已匯入的商品條款" : "沒有符合條件的商品",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(snapshot.products.isEmpty
                                ? "此版本只含官方查詢公司的索引，商品及條款尚未取得可批次匯入的授權資料；不可用此空目錄進行保障或理賠判斷。"
                                : "試試其他商品名稱、公司或銷售狀態。")
                        )
                    } else {
                        ForEach(visibleProducts) { product in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(product.name).font(.headline)
                                Text("\(product.company) · \(product.salesStatus.rawValue) · \(product.line)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(product.isEstimateEligible ? "條款來源已核驗" : "條款未核驗，不可用於試算")
                                    .font(.caption).foregroundStyle(product.isEstimateEligible ? .green : .orange)
                                if let url = product.clauseURL {
                                    Link("查看條款原文", destination: url).font(.caption)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section("官方查詢公司索引（原始名稱）") {
                    ForEach(visibleCompanies) { company in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(company.code) · \(company.name)")
                            Text("\(company.line) · \(company.rosterStatus)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("商品與條款")
            .searchable(text: $searchText, prompt: "搜尋公司、商品名稱或代碼")
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("商品狀態", selection: $selectedStatus) {
                    Text("全部").tag("全部")
                    Text("現售").tag(SalesStatus.onSale.rawValue)
                    Text("停售").tag(SalesStatus.discontinued.rawValue)
                    Text("未確認").tag(SalesStatus.unknown.rawValue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }
}
