import SwiftUI
import PhotosUI

@MainActor
struct ClaimEstimateView: View {
    @ObservedObject var store: PolicyStore
    @State private var orderText = ""
    @State private var analysis: MedicalOrderAnalysis?
    @State private var ocrBusy = false
    @State private var ocrMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var eventDate = Date()
    @State private var hospitalDays = 0
    @State private var surgeryName = ""
    @State private var outpatientSurgery = false
    @State private var isAccident = false
    @State private var hasFracture = false
    @State private var surgeryAmounts: [UUID: String] = [:]
    @State private var confirmedSurgeryPolicies: Set<UUID> = []

    private var estimate: ClaimEstimate {
        if store.storageMessage != nil {
            return ClaimEstimate(minimumKnownNTD: 0, includedItems: [], excludedItems: ["保單資料本機儲存狀態異常，暫停試算。"])
        }
        let amounts = surgeryAmounts.compactMapValues { Int($0) }
        var result = ClaimEstimator.estimate(
            input: ClaimInput(
                eventDate: eventDate,
                hospitalDays: hospitalDays,
                surgeryName: surgeryName,
                outpatientSurgery: outpatientSurgery,
                isAccident: isAccident,
                hasFracture: hasFracture
            ),
            policies: store.policies,
            surgeryAmounts: amounts,
            confirmedSurgeryPolicies: confirmedSurgeryPolicies
        )
        let invalidCount = surgeryAmounts.values.filter { !$0.isEmpty && Int($0) == nil }.count
        if invalidCount > 0 {
            result.excludedItems.insert("有 \(invalidCount) 筆手術金額不是有效整數，未納入；請重新輸入。", at: 0)
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                orderSection
                if let analysis, analysis.hasFindings || !analysis.notes.isEmpty { analysisSection(analysis) }
                Section("本次就醫資訊（可修改）") {
                    DatePicker("就醫日期", selection: $eventDate, displayedComponents: .date)
                    Stepper("住院天數：\(hospitalDays) 天", value: $hospitalDays, in: 0...365)
                    TextField("手術項目（請依醫師/病歷原文）", text: $surgeryName)
                    Toggle("門診手術（未住院）", isOn: $outpatientSurgery)
                    Toggle("因意外事故就醫", isOn: $isAccident)
                    if isAccident { Toggle("診斷為骨折", isOn: $hasFracture) }
                }
                Section("逐張保單核對本次手術給付") {
                    if store.policies.isEmpty {
                        Text("先在「拍照建檔」或「總覽」建立保單，才能依各保單試算。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.policies) { policy in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(policy.insurer)／\(policy.productName)").font(.headline)
                            Text(policy.clauseIsVerified ? "條款版本與來源已記錄" : "條款尚未核對；此保單不會納入")
                                .font(.caption).foregroundStyle(policy.clauseIsVerified ? .secondary : .orange)
                            Link("查看條款（核對手術表）", destination: clauseDestination(for: policy))
                                .font(.footnote)
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
                    let result = estimate
                    if result.canProduceFloor {
                        Text("已知最低估算：NT$\(result.minimumKnownNTD.formatted())")
                            .font(.title3.bold())
                        ForEach(result.includedItems, id: \.self) { Text("• \($0)").font(.footnote) }
                    } else {
                        Text("目前無法提供可靠金額；不以缺少資料推算。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(result.excludedItems, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    Text("此結果僅合計你輸入並逐張確認的定額給付，不是理賠承諾。實際理賠由保險公司依保單生效版本、診斷、手術代碼、除外責任、收據及完整理賠文件審核。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("理賠預估")
            .sheet(isPresented: $showCamera) { CameraPicker(image: $capturedImage) }
            .onChange(of: capturedImage) { _, image in
                guard let image else { return }
                Task { await recognize(image) }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    await recognize(image)
                }
            }
        }
    }

    private var orderSection: some View {
        Section("醫囑／診斷證明") {
            TextEditor(text: $orderText)
                .frame(minHeight: 110)
                .overlay(alignment: .topLeading) {
                    if orderText.isEmpty {
                        Text("例如：右側腎結石，執行雙J導管內視鏡結石取出，住院3天")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            Button { applyOrder() } label: { Label("解析醫囑並填入下方欄位", systemImage: "wand.and.stars") }
                .disabled(orderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button { showCamera = true } label: { Label("拍照辨識醫囑", systemImage: "camera") }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("從相簿選取醫囑照片", systemImage: "photo")
            }
            if ocrBusy { ProgressView("正在本機辨識文字…") }
            if let ocrMessage { Text(ocrMessage).font(.footnote).foregroundStyle(.orange) }
            Text("照片在裝置端以 Vision 辨識，辨識文字與照片不會上傳或保存。辨識可能誤讀，請核對後再使用；也可直接手動輸入。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func analysisSection(_ analysis: MedicalOrderAnalysis) -> some View {
        Section("醫囑解析結果（候選，需自行核對）") {
            if let diagnosis = analysis.diagnosis { LabeledContent("診斷", value: diagnosis) }
            if let side = analysis.laterality { LabeledContent("側別", value: side) }
            if let procedure = analysis.procedure { LabeledContent("手術／處置", value: procedure) }
            if let days = analysis.hospitalDays { LabeledContent("住院天數", value: "\(days) 天") }
            if analysis.isOutpatient { LabeledContent("住院型態", value: "門診／未住院") }
            if analysis.accidentSuspected { Text("文字含意外或外傷用語；是否屬「意外傷害」須依保單定義與診斷核對，請自行決定是否勾選意外。").font(.footnote) }
            if !analysis.tableKeywords.isEmpty {
                Text("手術表比對關鍵字：\(analysis.tableKeywords.joined(separator: "、"))").font(.footnote)
            }
            ForEach(analysis.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func applyOrder() {
        let parsed = MedicalOrderParser.parse(orderText)
        analysis = parsed
        if let days = parsed.hospitalDays { hospitalDays = days }
        outpatientSurgery = parsed.isOutpatient
        if let procedure = parsed.procedure { surgeryName = procedure }
        isAccident = parsed.accidentSuspected
        hasFracture = parsed.accidentSuspected && parsed.fractureSuspected
    }

    private func clauseDestination(for policy: UserPolicy) -> URL {
        ClauseLinks.directURL(policy.clauseURL) ?? ClauseLinks.webSearch(company: policy.insurer, product: policy.productName)
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

    private func recognize(_ image: UIImage) async {
        ocrBusy = true
        ocrMessage = nil
        defer { ocrBusy = false }
        if let text = try? await PolicyPhotoOCR.recognize(image), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            orderText = text
            applyOrder()
        } else {
            ocrMessage = "無法辨識這張照片，請手動輸入醫囑內容。"
        }
        capturedImage = nil
        selectedPhoto = nil
    }
}
