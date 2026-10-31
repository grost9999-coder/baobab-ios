import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var policies: [UserPolicy] = []
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var ocrText = ""
    @State private var hospitalDays = 0
    @State private var surgery = ""
    @State private var outpatient = false
    @State private var dailyBenefit = ""
    @State private var surgeryBenefit = ""
    @State private var hasVerifiedClause = false
    @State private var clauseVersion = ""
    @State private var clauseReference = ""
    @State private var clauseSourceURL = ""

    private var clauseIsTraceable: Bool {
        hasVerifiedClause && !clauseVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !clauseReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        URL(string: clauseSourceURL)?.scheme?.lowercased() == "https"
    }

    private var estimate: ClaimEstimate {
        let benefits = [
            PolicyBenefit(kind: .inpatientDaily, label: "住院日額（條款 \(clauseReference)）", amountNTD: Int(dailyBenefit), maxDays: nil, clauseReference: clauseReference, verifiedEligible: clauseIsTraceable),
            PolicyBenefit(kind: outpatient ? .outpatientSurgery : .surgerySchedule, label: surgery.isEmpty ? "手術給付（條款 \(clauseReference)）" : "\(surgery)（條款 \(clauseReference)）", amountNTD: Int(surgeryBenefit), maxDays: nil, clauseReference: clauseReference, verifiedEligible: clauseIsTraceable)
        ]
        return ClaimEstimator.estimate(input: ClaimInput(hospitalDays: hospitalDays, surgeryName: surgery, outpatientSurgery: outpatient, explicitSurgeryBenefitNTD: Int(surgeryBenefit)), benefits: benefits, clauseVerified: clauseIsTraceable)
    }

    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section {
                        ContentUnavailableView("尚未建立保單", systemImage: "doc.text.viewfinder", description: Text("拍攝保單頁面開始整理。辨識結果會先成為草稿，需由你核對後才加入。"))
                    }
                    Section("保障缺口檢視") {
                        Label("依保障類別整理你已確認的保單", systemImage: "checklist")
                        Text("缺少資料會標示為「未知」，不會直接判定沒有保障。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("保單總覽")
            }
            .tabItem { Label("總覽", systemImage: "square.grid.2x2") }

            NavigationStack {
                Form {
                    Section("拍照辨識") {
                        Button {
                            showCamera = true
                        } label: {
                            Label("開啟相機拍攝", systemImage: "camera")
                        }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        .sheet(isPresented: $showCamera) {
                            CameraPicker(image: $capturedImage)
                        }
                        .onChange(of: capturedImage) { _, image in
                            guard let image else { return }
                            Task { ocrText = (try? await PolicyPhotoOCR.recognize(image)) ?? "無法辨識，請手動輸入。" }
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("選擇保單照片", systemImage: "camera")
                        }
                        .onChange(of: selectedPhoto) { _, item in
                            Task {
                                guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                                ocrText = (try? await PolicyPhotoOCR.recognize(image)) ?? "無法辨識，請手動輸入。"
                            }
                        }
                        Text("照片僅用於本機 OCR 草稿；辨識文字可能有誤，請逐欄核對。")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextEditor(text: $ocrText).frame(minHeight: 160)
                    }
                    Section("確認後再儲存") {
                        Text("正式版本應在使用者確認公司、商品、保單年度、附約與給付額後才建立保單紀錄。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("拍照建檔")
            }
            .tabItem { Label("拍照", systemImage: "camera.viewfinder") }

            NavigationStack {
                List {
                    Section {
                        ContentUnavailableView("商品資料待匯入與核驗", systemImage: "books.vertical", description: Text("每筆商品需包含公司、商品代碼、現售/停售狀態、條款版本、原始來源與最近核對日期。未核驗資料不會用於理賠估算。"))
                    }
                    Section("資料範圍") {
                        Text("官方商品查詢資料庫自 2004 年底建置；更早商品及尚未上傳的新品需向保險公司補查。")
                            .font(.footnote)
                    }
                }
                .navigationTitle("商品與條款")
            }
            .tabItem { Label("商品", systemImage: "books.vertical") }

            NavigationStack {
                Form {
                    Section("醫師告知的就醫資訊") {
                        Stepper("住院天數：\(hospitalDays) 天", value: $hospitalDays, in: 0...365)
                        TextField("手術項目/名稱", text: $surgery)
                        Toggle("門診手術", isOn: $outpatient)
                    }
                    Section("逐項輸入已核對的保單給付") {
                        TextField("條款版本/修訂日期", text: $clauseVersion)
                        TextField("條號與頁碼", text: $clauseReference)
                        TextField("官方條款 HTTPS 連結", text: $clauseSourceURL).keyboardType(.URL).textInputAutocapitalization(.never)
                        TextField("住院每日給付（元）", text: $dailyBenefit).keyboardType(.numberPad)
                        TextField("依條款核對的手術給付金額（元）", text: $surgeryBenefit).keyboardType(.numberPad)
                        Toggle("我已核對此版本條款與給付條件", isOn: $hasVerifiedClause)
                        if !clauseIsTraceable {
                            Text("需填條款版本、條號/頁碼及 HTTPS 原始來源，並確認核對後才會試算。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("保守估算結果") {
                        if estimate.canProduceFloor {
                            Text("已知最低估算：NT$\(estimate.minimumKnownNTD.formatted())")
                                .font(.headline)
                            ForEach(estimate.includedItems, id: \.self) { Text("• \($0)") }
                        } else {
                            Text("目前無法提供可靠金額。請先核對保單條款及商品版本。")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(estimate.excludedItems, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                        Text("此為依已輸入且核對的給付條件所做之保守試算，不是理賠承諾。實際金額由保險公司依完整條款、診斷、手術代碼、收據、除外責任及理賠文件審核。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("理賠試算")
            }
            .tabItem { Label("試算", systemImage: "function") }
        }
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
