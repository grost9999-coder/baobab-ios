import Foundation
import Combine

@MainActor
final class PolicyStore: ObservableObject {
    @Published private(set) var policies: [UserPolicy] = []
    @Published private(set) var storageMessage: String?

    private let fileURL: URL

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = root.appendingPathComponent("Baobab", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("policies.json")
        load()
    }

    func add(_ policy: UserPolicy) {
        policies.insert(policy, at: 0)
        save()
    }

    func update(_ policy: UserPolicy) {
        guard let index = policies.firstIndex(where: { $0.id == policy.id }) else { return }
        policies[index] = policy
        save()
    }

    func remove(_ policy: UserPolicy) {
        policies.removeAll { $0.id == policy.id }
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            policies = try JSONDecoder().decode([UserPolicy].self, from: data)
        } catch {
            storageMessage = "無法讀取本機保單資料。原始檔案保留未修改；請先匯出或聯絡支援。"
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(policies)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedURL = fileURL
            try protectedURL.setResourceValues(values)
            storageMessage = nil
        } catch {
            storageMessage = "本機儲存失敗；資料目前可能只暫存在記憶體，請勿依賴此資料或用來試算，關閉 App 前需重新保存。"
        }
    }
}
