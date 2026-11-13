import Foundation

/// 搜尋用字串正規化：臺/台統一、忽略大小寫、全半形與空白。
enum SearchText {
    static func normalize(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "臺", with: "台")
        let folded = unified.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        return String(folded.filter { !$0.isWhitespace })
    }
}

struct InsurerMatch: Identifiable {
    let company: CatalogCompany
    let score: Int
    var id: String { company.code }
}

/// 由保發中心查詢公司索引推導簡稱，使「南山」可對應完整法定名稱。
/// 簡稱只用於搜尋；儲存與顯示一律使用索引中的完整名稱與公司代碼。
enum InsurerDirectory {
    /// 市場常用簡稱／英文名，以保發中心公司代碼為鍵。缺少的公司仍可用推導簡稱或全名搜尋。
    static let commonAliases: [String: [String]] = [
        "101": ["臺產", "台產"],
        "102": ["兆豐"],
        "105": ["富邦產", "富邦"],
        "108": ["明台"],
        "109": ["南山產", "南山"],
        "110": ["第一產", "第一"],
        "112": ["友聯", "旺旺"],
        "113": ["新光產"],
        "114": ["華南"],
        "115": ["國泰產", "國泰世紀", "國泰"],
        "117": ["新安", "東京海上"],
        "118": ["中信產", "中國信託"],
        "128": ["裕利安宜"],
        "129": ["AIG", "美國國際"],
        "130": ["科法斯", "Coface"],
        "132": ["安達產", "Chubb"],
        "201": ["臺銀壽", "台銀人壽", "臺銀"],
        "202": ["台壽", "台灣人壽", "臺灣人壽"],
        "203": ["保誠", "Prudential"],
        "204": ["國壽", "國泰"],
        "205": ["中壽", "中國人壽", "凱基"],
        "206": ["南山壽", "南山"],
        "208": ["新壽", "新光"],
        "209": ["富邦壽", "富壽", "富邦"],
        "211": ["三商", "美邦", "三商壽"],
        "216": ["遠雄"],
        "217": ["宏泰"],
        "218": ["安聯", "Allianz"],
        "220": ["郵局", "郵政", "郵政壽險"],
        "221": ["第一金"],
        "222": ["合庫"],
        "254": ["中信壽", "中信", "中國信託"],
        "255": ["台新"],
        "256": ["安達", "康健"],
        "257": ["友邦", "AIA"],
        "258": ["宏利", "Manulife"],
        "261": ["元大"],
        "264": ["全球"],
        "267": ["法巴", "BNP"],
        "270": ["安達", "Chubb"],
        "271": ["匯豐", "HSBC"],
        "272": ["蘇黎世", "Zurich"]
    ]

    private static let nationalityPrefixes = ["英屬百慕達商", "英屬曼島商", "比利時商", "新加坡商", "法商", "美商", "香港商"]
    private static let legalSuffixes = ["台灣分公司", "臺灣分公司", "台北分公司", "臺北分公司", "股份有限公司", "有限公司"]

    /// 由完整名稱推導的名稱變體（不含手寫簡稱）。
    static func derivedNames(for company: CatalogCompany) -> [String] {
        var names: [String] = []
        func add(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2 && !names.contains(trimmed) { names.append(trimmed) }
        }

        // 括號內「原○○」是歷史名稱，也可搜尋；其他括號註記（合併說明等）不當成名稱。
        if let regex = try? NSRegularExpression(pattern: "[（(]原([^）)]+)[）)]"),
           let match = regex.firstMatch(in: company.name, range: NSRange(company.name.startIndex..., in: company.name)),
           let range = Range(match.range(at: 1), in: company.name) {
            add(String(company.name[range]))
        }

        var base = company.name.replacingOccurrences(of: "\\s*[（(].*?[）)]", with: "", options: .regularExpression)
        for prefix in nationalityPrefixes where base.hasPrefix(prefix) {
            base = String(base.dropFirst(prefix.count))
        }
        for suffix in legalSuffixes {
            base = base.replacingOccurrences(of: suffix, with: "")
        }
        add(base)
        add(base.replacingOccurrences(of: "人壽保險事業", with: "人壽").replacingOccurrences(of: "人壽保險", with: "人壽"))
        add(base.replacingOccurrences(of: "產物保險", with: "產險"))

        var brand = base
        for token in ["人壽保險事業", "人壽保險", "產物保險", "合作社", "保險"] {
            brand = brand.replacingOccurrences(of: token, with: "")
        }
        add(brand)
        return names
    }

    /// 搜尋時比對的所有名稱：完整名稱、推導名稱與手寫簡稱。
    static func searchTerms(for company: CatalogCompany) -> [String] {
        [company.name] + derivedNames(for: company) + (commonAliases[company.code] ?? [])
    }

    /// 依相關度回傳公司。`lines` 可限制險種（例如只要壽險/產險）。
    static func search(_ query: String, in companies: [CatalogCompany], limit: Int = 8, lines: Set<String>? = nil) -> [InsurerMatch] {
        let normalizedQuery = SearchText.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        var matches: [InsurerMatch] = []
        for company in companies {
            if let lines, !lines.contains(company.line) { continue }
            let value = score(normalizedQuery, company)
            if value > 0 { matches.append(InsurerMatch(company: company, score: value)) }
        }
        matches.sort { left, right in
            if left.score != right.score { return left.score > right.score }
            if left.company.line != right.company.line { return left.company.line > right.company.line }
            return left.company.code < right.company.code
        }
        return Array(matches.prefix(limit))
    }

    /// 完整名稱（正規化後）完全相同才回傳，用於判斷使用者是否已選定公司。
    static func exactCompany(named name: String, in companies: [CatalogCompany]) -> CatalogCompany? {
        let normalized = SearchText.normalize(name)
        guard !normalized.isEmpty else { return nil }
        return companies.first { SearchText.normalize($0.name) == normalized }
    }

    private static func score(_ query: String, _ company: CatalogCompany) -> Int {
        if SearchText.normalize(company.code) == query { return 100 }
        var best = 0
        for term in searchTerms(for: company) {
            let normalized = SearchText.normalize(term)
            if normalized.isEmpty { continue }
            if normalized == query {
                best = max(best, 100)
            } else if normalized.hasPrefix(query) {
                best = max(best, 85)
            } else if normalized.contains(query) {
                best = max(best, 60)
            } else if normalized.count >= 3 && query.contains(normalized) {
                best = max(best, 50)
            }
        }
        return best
    }
}

/// 以關鍵字搜尋商品（含現售與停售）。多個關鍵字以空白分隔，需全部符合。
enum ProductSearch {
    static func search(
        products: [InsuranceProduct],
        companies: [CatalogCompany],
        query: String,
        companyCode: String? = nil,
        status: SalesStatus? = nil,
        role: ProductRole? = nil,
        limit: Int? = nil
    ) -> [InsuranceProduct] {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { SearchText.normalize(String($0)) }
            .filter { !$0.isEmpty }

        var companyTerms: [String: String] = [:]
        for company in companies {
            companyTerms[company.code] = InsurerDirectory.searchTerms(for: company)
                .map { SearchText.normalize($0) }
                .joined(separator: "|")
        }

        var results: [(product: InsuranceProduct, rank: Int)] = []
        for product in products {
            if let companyCode, product.companyCode != companyCode { continue }
            if let status, product.salesStatus != status { continue }
            if let role, (product.role ?? .unknown) != role { continue }

            let name = SearchText.normalize(product.name)
            let haystack = [
                name,
                SearchText.normalize(product.company),
                companyTerms[product.companyCode ?? ""] ?? "",
                SearchText.normalize(product.line),
                SearchText.normalize(product.productCode ?? ""),
                SearchText.normalize(product.clauseVersion ?? ""),
                SearchText.normalize((product.role ?? .unknown).rawValue)
            ].joined(separator: "|")
            guard tokens.allSatisfy({ haystack.contains($0) }) else { continue }

            var rank = 2
            if let first = tokens.first {
                if name.hasPrefix(first) { rank = 0 } else if name.contains(first) { rank = 1 }
            }
            results.append((product, rank))
        }

        results.sort { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            let leftOrder = statusOrder(left.product.salesStatus)
            let rightOrder = statusOrder(right.product.salesStatus)
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return left.product.name < right.product.name
        }
        let sorted = results.map(\.product)
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }

    private static func statusOrder(_ status: SalesStatus) -> Int {
        switch status {
        case .onSale: return 0
        case .discontinued: return 1
        case .unknown: return 2
        }
    }
}

/// 條款連結：優先使用已記錄的 HTTPS 條款網址；沒有時提供「間接」入口（官方查詢頁、網頁搜尋）。
/// 間接連結只是搜尋入口，不代表其結果已被本 App 核驗。
enum ClauseLinks {
    static let tiiQuery = URL(string: "https://insprod.tii.org.tw/Query.aspx")!

    static func webSearch(company: String, product: String) -> URL {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(company) \(product) 保險條款 pdf")]
        return components.url ?? tiiQuery
    }

    static func directURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}
