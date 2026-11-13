import Foundation

/// 從醫囑／診斷證明文字取出「候選欄位」。只做文字比對，不判斷診斷是否成立、也不推定手術表項目或金額。
struct MedicalOrderAnalysis: Equatable {
    var laterality: String?
    var diagnosis: String?
    var procedure: String?
    var hospitalDays: Int?
    var isOutpatient = false
    var accidentSuspected = false
    var fractureSuspected = false
    /// 供使用者在各家條款「手術表」中比對的關鍵字。
    var tableKeywords: [String] = []
    var notes: [String] = []

    var hasFindings: Bool {
        diagnosis != nil || procedure != nil || hospitalDays != nil || isOutpatient || accidentSuspected || fractureSuspected
    }
}

enum MedicalOrderParser {
    private static let procedureTerms = [
        "內視鏡", "腹腔鏡", "關節鏡", "輸尿管鏡", "輸尿管", "雙J", "結石", "碎石", "取石",
        "切除", "切開", "縫合", "復位", "固定", "置換", "清創", "導管", "支架",
        "電燒", "冷凍", "引流", "移植", "重建", "切片", "修補"
    ]

    static func parse(_ rawText: String) -> MedicalOrderAnalysis {
        var result = MedicalOrderAnalysis()
        let text = rawText
            .replacingOccurrences(of: "臺", with: "台")
            .replacingOccurrences(of: "雙 J", with: "雙J")
            .replacingOccurrences(of: "雙ｊ", with: "雙J")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return result }

        result.laterality = laterality(in: text)

        if let procedure = firstCapture(#"(?:執行|施行|接受|安排|進行)\s*([^，,。；;\n]{2,40})"#, in: text) {
            result.procedure = procedure.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let clauses = text
            .components(separatedBy: CharacterSet(charactersIn: "，,。；;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let first = clauses.first {
            let stripped = first.replacingOccurrences(of: #"^(?:診斷|Dx)\s*[：:]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            let looksLikeProcedureOrStay = stripped.range(of: "執行|施行|住院|手術", options: .regularExpression) != nil
            if !stripped.isEmpty && !looksLikeProcedureOrStay { result.diagnosis = stripped }
        }

        result.tableKeywords = procedureTerms.filter { text.contains($0) }

        result.isOutpatient = text.range(of: "門診手術|日間手術|當日出院|當天出院|免住院|不需住院|無需住院", options: .regularExpression) != nil
        if let days = hospitalDays(in: text) {
            if (0...365).contains(days) {
                result.hospitalDays = days
            } else {
                result.notes.append("醫囑中的住院天數（\(days) 天）超出可試算範圍 0–365 天，請手動確認。")
            }
        } else if result.isOutpatient {
            result.hospitalDays = 0
        }

        result.accidentSuspected = text.range(of: "意外|車禍|跌倒|跌落|摔傷|摔倒|墜落|外傷|撞傷|被撞|燙傷|刀傷|咬傷", options: .regularExpression) != nil
        result.fractureSuspected = text.range(of: "骨折|fracture|\\bFx\\b", options: [.regularExpression, .caseInsensitive]) != nil

        if result.procedure == nil && result.diagnosis == nil && result.hospitalDays == nil {
            result.notes.append("沒有找到明確的診斷、手術或住院天數；請改用手動輸入。")
        }
        if result.procedure != nil {
            result.notes.append("手術名稱以醫囑原文為準；各公司手術表名稱與給付級距不同，請用關鍵字到該保單條款的手術表核對。")
        }
        return result
    }

    private static func laterality(in text: String) -> String? {
        if let direct = firstCapture("(右側|左側|雙側|右邊|左邊|雙邊)", in: text) {
            return direct.replacingOccurrences(of: "邊", with: "側")
        }
        if let side = firstCapture("([右左])(?=[腎肺眼耳膝肩髖腳足手踝肘腕腿臂乳腹])", in: text) {
            return side + "側"
        }
        return nil
    }

    private static func hospitalDays(in text: String) -> Int? {
        let patterns = [
            #"(?:住院|住)\s*(?:共|約|預計)?\s*([0-9]{1,3}|[零一二兩三四五六七八九十百]{1,4})\s*(?:天|日)"#,
            #"(?:共|約|預計)?\s*([0-9]{1,3}|[零一二兩三四五六七八九十百]{1,4})\s*(?:天|日)\s*住院"#
        ]
        for pattern in patterns {
            if let captured = firstCapture(pattern, in: text), let value = number(from: captured) {
                return value
            }
        }
        return nil
    }

    /// 阿拉伯數字或 0–999 的中文數字。
    static func number(from text: String) -> Int? {
        if let value = Int(text) { return value }
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        var total = 0
        var pending = 0
        for character in text {
            if let digit = digits[character] {
                pending = digit
            } else if character == "十" {
                total += (pending == 0 ? 1 : pending) * 10
                pending = 0
            } else if character == "百" {
                total += (pending == 0 ? 1 : pending) * 100
                pending = 0
            } else {
                return nil
            }
        }
        return total + pending
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
