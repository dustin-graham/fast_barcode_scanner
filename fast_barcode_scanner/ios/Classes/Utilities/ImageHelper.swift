import UIKit

class ImageHelper {
    private var savedCodes: [String: String] = [:]

    static let shared = ImageHelper()

    private init() {}

    // Store image to the path with barcode as filename
    private func storeImage(imageBytes: Data?, key: String) {

        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first

        do {
            let barcodeDirectory = documentDirectory.appendingPathComponent("barcode_images")
            try fileManager.createDirectory(at: barcodeDirectory, withIntermediateDirectories: true, attributes: nil)

            let imageFile = barcodeDirectory.appendingPathComponent(key + ".jpeg")
            try imageBytes.write(to: imageFile)

            savedCodes[key] = imageFile.absoluteString
        } catch {
            print("Error storing image: \(error)")
        }
    }

    private func isImageSaved(code: String) -> Bool {
        return savedCodes.keys.contains(code)
    }

    // Retrieve image from cache by barcode
    func retrieveImagePath(code: String) -> String? {
        return savedCodes[code]
    }

    func clearCache() {
        savedCodes.removeAll()

        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let barcodeDirectory = documentDirectory.appendingPathComponent("barcode_images")

        do {
            try fileManager.removeItem(at: barcodeDirectory)
        } catch {
            print("Error clearing cache: \(error)")
        }
    }

    func storeImageToCache(image: UIImage, code: String) {
        if isImageSaved(code) {
            return
        }

        // Convert UIImage to JPEG Data
        guard let jpegBytes = image.jpegData(compressionQuality: 1.0) else {
            print("Error converting image to JPEG")
            return
        }

        storeImage(imageBytes: jpegBytes, key: code)
    }
}
