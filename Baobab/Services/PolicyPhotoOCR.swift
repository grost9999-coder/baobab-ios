import Foundation
import Vision
import UIKit

/// OCR creates an untrusted draft only; extracted text never becomes coverage or claim evidence by itself.
enum PolicyPhotoOCR {
    static func recognize(_ image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw NSError(domain: "PolicyPhotoOCR", code: 1) }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            }
        }
    }
}
