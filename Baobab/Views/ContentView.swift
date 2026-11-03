import SwiftUI
import PhotosUI

@MainActor
struct ContentView: View {
    @StateObject private var store = PolicyStore()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var showPolicyEditor = false
    @State private var ocrText = ""
    @State private var ocrBusy = false
    @State private var eventDate = Date()
    @State private var hospitalDays = 0
    @State private var surgeryName = ""
    @State private var outpatientSurgery = false
    @State private var surgeryAmounts: [UUID: String] = [:]
    @State private var confirmedSurgeryPolicies: Set<UUID> = []
    @State private var diagnosisPhoto: PhotosPickerItem?
    @State private var diagnosisBusy = false
    @State private var diagnosisText = ""
    @State private var treatmentText = ""
    @State private var treatmentKind: TreatmentKind = .inpatientSurgery

    private var estimate: ClaimEstimate {
        if store.storageMessage != nil {
            return ClaimEstimate(minimumKnownNTD: 0, includedItems: [], excludedItems: ["保單資料本機儲存狀態異常，暫停試算。"])
        }
        let amounts = surgeryAmounts.compactMapValues { Int($0) }
        return ClaimEstimator.estimate(
            input: ClaimInput(eventDate: eventDate, hospitalDays: hospitalDays, surgeryName: surgeryName, outpatientSurgery: outpatientSurgery),
            policies: store.policies,
            surgeryAmounts: amounts,
            confirmedSurgeryPolicies: confirmedSurgeryPolicies
        )
    }

    var body: some View {
        TabView {
            overviewTab
                .tabItem { Label("總覽", systemImage: "square.grid.2x2") }
            photoTab
                .tabItem { Label("拍照建檔", systemImage: "camera.viewfinder") }
            gapsTab
                .tabItem { Label("保障檢視", systemImage: "checklist") }
            CatalogView()
                .tabItem { Label("商品條款", systemImage: "books.vertical") }
            claimTab
                .tabItem { Label("理賠試算", systemImage: "function") }
        }
        .sheet(isPresented: $showPolicyEditor, onDismiss: { ocrText = "" }) {
            PolicyEditorView(ocrDraft: ocrText) { store.add($0) }
        }
    }

    private var overviewTab: some View {
        NavigationStack {
            List {
                if let message = store.storageMessage {
                    Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
                Section("你的保單") {
                    if store.policies.isEmpty {
                        ContentUnavailableView("尚未建立保單", systemImage: "doc.text.viewfinder", description: Text("拍攝保單頁面或手動輸入，建立第一筆保單。"))
                    } else {
                        ForEach(store.policies) { policy in
                            policyRow(policy)
                                .swipeActions {
                                    Button("刪除", systemImage: "trash", role: .destructive) { store.remove(policy) }
                                }
                        }
                    }
                }
                Section("保障資料狀態") {
                    Text("已記錄 \(store.policies.count) 張保單；\(store.policies.filter(\.clauseIsVerified).count) 張有可追溯且已確認的條款資料。")
                    Text("「目前未找到紀錄」是待確認項目，不代表你一定沒有保障，也不是購買建議。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("保單總覽")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ocrText = ""; showPolicyEditor = true } label: { Label("新增保單", systemImage: "plus") }
                }
            }
        }
    }

    private var photoTab: some View {
        NavigationStack {
            Form {
                Section("拍攝或選取保單頁面") {
                    Button { showCamera = true } label: { Label("開啟相機拍攝", systemImage: "camera") }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        .sheet(isPresented: $showCamera) { CameraPicker(image: $capturedImage) }
                        .onChange(of: capturedImage) { _, image in
                            guard let image else { return }
                            Task { await recognize(image) }
                        }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("從相簿選取照片", systemImage: "photo")
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        Task {
                            guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                            await recognize(image)
                        }
                    }
                    if ocrBusy { ProgressView("正在本機辨識文字…") }
                    Text("照片在裝置端以 Vision 辨識；請勿拍入不必要的身分證、地址或其他人的資料。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !ocrText.isEmpty {
                    Section("辨識結果草稿") {
                        TextEditor(text: $ocrText).frame(minHeight: 180)
                        Text("OCR 可能誤讀公司名稱、保額或條號。建立保單前請逐項核對；辨識原文不會被保存。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button { showPolicyEditor = true } label: {
                            Label("核對欄位並建立保單", systemImage: "doc.badge.plus")
                        }
                    }
                }
                Section("未辨識或照片不清楚？") {
                    Button { ocrText = ""; showPolicyEditor = true } label: {
                        Label("改為手動輸入", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationTitle("拍照建檔")
        }
    }

    private var gapsTab: some View {
        NavigationStack {
            List {
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
                Section("想確認自己的保障缺口？") {
                    ContactCard(context: "我想請你協助檢視我的保單保障缺口")
                }
                Section("如何解讀") {
                    Text("這是依你自行建檔的保障清單所做的整理，不會判斷適不適合、保額是否足夠，也不會把「未找到」當成確定缺口。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("若商品名稱、附約或條款版本不確定，先回到保單及保險公司原始條款核對。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("保障檢視")
        }
    }

    private var claimTab: some View {
        NavigationStack {
            Form {
                Section("診斷書／醫師說明") {
                    PhotosPicker(selection: $diagnosisPhoto, matching: .images) {
                        Label("上傳診斷書照片（本機辨識文字）", systemImage: "doc.text.viewfinder")
                    }
                    .onChange(of: diagnosisPhoto) { _, item in
                        Task {
                            guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                            diagnosisBusy = true
                            defer { diagnosisBusy = false }
                            diagnosisText = (try? await PolicyPhotoOCR.recognize(image)) ?? "無法辨識，請手動輸入。"
                            diagnosisPhoto = nil
                        }
                    }
                    if diagnosisBusy { ProgressView("正在本機辨識文字…") }
                    TextField("疾病／診斷名稱（醫師告知或診斷書原文）", text: $diagnosisText, axis: .vertical)
                    TextField("治療方式（例如：腹腔鏡膽囊切除術）", text: $treatmentText, axis: .vertical)
                    Picker("治療類型", selection: $treatmentKind) {
                        ForEach(TreatmentKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: treatmentKind) { _, kind in
                        outpatientSurgery = (kind == .outpatientSurgery)
                    }
                    Text("診斷書照片與辨識文字不會被保存。請核對辨識內容，並以醫師原文為準。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("本次就醫資訊") {
                    DatePicker("就醫日期", selection: $eventDate, displayedComponents: .date)
                    Stepper("住院天數：\(hospitalDays) 天", value: $hospitalDays, in: 0...365)
                    TextField("手術項目（請依醫師/病歷原文）", text: $surgeryName)
                    Toggle("門診手術", isOn: $outpatientSurgery)
                }
                Section("逐張保單核對本次手術給付") {
                    if store.policies.isEmpty {
                        Text("先在「拍照建檔」建立保單，才能依各保單試算。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.policies) { policy in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(policy.insurer)／\(policy.productName)").font(.headline)
                            Text(policy.clauseIsVerified ? "條款版本與來源已記錄" : "條款尚未核對；此保單不會納入")
                                .font(.caption).foregroundStyle(policy.clauseIsVerified ? .secondary : .orange)
                            TextField("此保單對本手術已核對的定額金額（元）", text: amountBinding(for: policy))
                                .keyboardType(.numberPad)
                            Toggle("已依此保單條款/手術表核對本次項目", isOn: confirmationBinding(for: policy))
                                .font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }
                    Text("若未在保單建檔時記錄條款版本/頁碼/來源，該保單不參與估算。實支實付不以保額代替實際可賠金額。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("保守估算結果") {
                    if estimate.canProduceFloor {
                        Text("已知最低估算：NT$\(estimate.minimumKnownNTD.formatted())")
                            .font(.title3.bold())
                        ForEach(estimate.includedItems, id: \.self) { Text("• \($0)").font(.footnote) }
                    } else {
                        Text("目前無法提供可靠金額；不以缺少資料推算。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(estimate.excludedItems, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    Text("此結果僅合計你輸入並逐張確認的定額給付，不是理賠承諾。實際理賠由保險公司依保單生效版本、診斷、手術代碼、除外責任、收據及完整理賠文件審核。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("需要協助申請理賠？") {
                    ContactCard(context: "我要申請理賠，診斷：\(diagnosisText.prefix(60))；治療：\(treatmentText.prefix(60))；類型：\(treatmentKind.rawValue)")
                }
            }
            .navigationTitle("理賠試算")
        }
    }

    private func policyRow(_ policy: UserPolicy) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(policy.productName).font(.headline)
            Text(policy.insurer).font(.subheadline)
            Text(policy.clauseIsVerified ? "條款版本已核對" : "條款待核對；不納入金額試算")
                .font(.caption).foregroundStyle(policy.clauseIsVerified ? .secondary : .orange)
            if !policy.categories.isEmpty {
                Text(policy.categories.map(\.rawValue).joined(separator: "、"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func amountBinding(for policy: UserPolicy) -> Binding<String> {
        Binding(get: { surgeryAmounts[policy.id, default: ""] }, set: { surgeryAmounts[policy.id] = $0 })
    }

    private func confirmationBinding(for policy: UserPolicy) -> Binding<Bool> {
        Binding(get: { confirmedSurgeryPolicies.contains(policy.id) }, set: { confirmed in
            if confirmed { confirmedSurgeryPolicies.insert(policy.id) }
            else { confirmedSurgeryPolicies.remove(policy.id) }
        })
    }

    @MainActor
    private func recognize(_ image: UIImage) async {
        ocrBusy = true
        defer { ocrBusy = false }
        ocrText = (try? await PolicyPhotoOCR.recognize(image)) ?? "無法辨識，請手動輸入保單資料。"
        capturedImage = nil
        selectedPhoto = nil
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

enum TreatmentKind: String, CaseIterable, Identifiable {
    case outpatient = "門診"
    case inpatient = "住院（未手術）"
    case inpatientSurgery = "住院手術"
    case outpatientSurgery = "門診手術"
    var id: String { rawValue }
}

private struct ContactCard: View {
    let context: String
    private let phone = "0988777918"
    private let email = "grost9999@gmail.com"
    private let lineID = "0988777918"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("需要時可直接聯繫").font(.headline)
            if let url = URL(string: "https://line.me/ti/p/~\(lineID)") {
                Link(destination: url) { Label("LINE 聯絡", systemImage: "message") }
            }
            if let url = URL(string: "tel:\(phone)") {
                Link(destination: url) { Label("撥打 \(phone)", systemImage: "phone") }
            }
            if let url = mailURL {
                Link(destination: url) { Label("Email 聯絡", systemImage: "envelope") }
            }
            Text("Email 只會預填你在本頁輸入的摘要（理賠頁含診斷與治療文字），不會附上保單或照片；是否寄出由你決定。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var mailURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [
            URLQueryItem(name: "subject", value: "Baobab 保單諮詢"),
            URLQueryItem(name: "body", value: context)
        ]
        return c.url
    }
}
