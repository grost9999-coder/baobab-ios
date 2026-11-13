import SwiftUI
import PhotosUI

@MainActor
struct ContentView: View {
    @StateObject private var store = PolicyStore()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var policyEditorRoute: PolicyEditorRoute?
    @State private var ocrText = ""
    @State private var ocrBusy = false

    var body: some View {
        TabView {
            overviewTab
                .tabItem { Label("總覽", systemImage: "square.grid.2x2") }
            photoTab
                .tabItem { Label("拍照建檔", systemImage: "camera.viewfinder") }
            PolicyHealthCheckView(store: store) { policyEditorRoute = .edit($0) }
                .tabItem { Label("保單健檢", systemImage: "stethoscope") }
            CatalogView()
                .tabItem { Label("商品條款", systemImage: "books.vertical") }
            ClaimEstimateView(store: store)
                .tabItem { Label("理賠預估", systemImage: "function") }
        }
        .sheet(item: $policyEditorRoute, onDismiss: { ocrText = "" }) { route in
            switch route {
            case .new(let draft):
                PolicyEditorView(ocrDraft: draft) { store.add($0) }
            case .edit(let policy):
                PolicyEditorView(existingPolicy: policy) { store.update($0) }
            }
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
                        ContentUnavailableView("尚未建立保單", systemImage: "doc.text.viewfinder", description: Text("輸入保險公司簡稱與商品名稱，或拍攝保單頁面，建立第一筆保單。"))
                    } else {
                        ForEach(store.policies) { policy in
                            Button { policyEditorRoute = .edit(policy) } label: { policyRow(policy) }
                                .buttonStyle(.plain)
                                .accessibilityHint("點選以編輯這張保單資料")
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
                    Button { ocrText = ""; policyEditorRoute = .new(ocrDraft: "") } label: { Label("新增保單", systemImage: "plus") }
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
                        Button { policyEditorRoute = .new(ocrDraft: ocrText) } label: {
                            Label("核對欄位並建立保單", systemImage: "doc.badge.plus")
                        }
                    }
                }
                Section("未辨識或照片不清楚？") {
                    Button { ocrText = ""; policyEditorRoute = .new(ocrDraft: "") } label: {
                        Label("改為手動輸入", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationTitle("拍照建檔")
        }
    }

    private func policyRow(_ policy: UserPolicy) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(policy.productName).font(.headline)
            Text("\(policy.insurer) · \((policy.productRole ?? .unknown).rawValue)").font(.subheadline)
            Text(policy.clauseIsVerified ? "條款版本已核對" : "條款待核對；不納入金額試算")
                .font(.caption).foregroundStyle(policy.clauseIsVerified ? .secondary : .orange)
            if !policy.categories.isEmpty {
                Text(policy.categories.map(\.rawValue).joined(separator: "、"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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

private enum PolicyEditorRoute: Identifiable {
    case new(ocrDraft: String)
    case edit(UserPolicy)

    var id: String {
        switch self {
        case .new(_): return "new-policy"
        case .edit(let policy): return policy.id.uuidString
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
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
