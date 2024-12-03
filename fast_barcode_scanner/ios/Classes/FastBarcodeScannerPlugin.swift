import Flutter
import AVFoundation
import UIKit
import CryptoKit

@available(iOS 11.0, *)
public class FastBarcodeScannerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    let commandChannel: FlutterMethodChannel
    let barcodeEventChannel: FlutterEventChannel
    let factory: PreviewViewFactory

    var camera: Camera?
    var picker: ImagePicker?
    var detectionsSink: FlutterEventSink?

    init(commands: FlutterMethodChannel,
         events: FlutterEventChannel,
         factory: PreviewViewFactory
    ) {
        commandChannel = commands
        barcodeEventChannel = events
        self.factory = factory
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let commandChannel = FlutterMethodChannel(name: "com.jhoogstraat/fast_barcode_scanner",
                binaryMessenger: registrar.messenger())

        let barcodeEventChannel = FlutterEventChannel(name: "com.jhoogstraat/fast_barcode_scanner/detections",
                binaryMessenger: registrar.messenger())

        let instance = FastBarcodeScannerPlugin(commands: commandChannel,
                events: barcodeEventChannel,
                factory: PreviewViewFactory())

        registrar.register(instance.factory, withId: "fast_barcode_scanner.preview")
        registrar.addMethodCallDelegate(instance, channel: commandChannel)
        barcodeEventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            var response: Any?

            switch call.method {
            case "init": response = try initialize(args: call.arguments).asDict
            case "start": try start()
            case "stop": try stop()
            case "startDetector": try startDetector()
            case "stopDetector": try stopDetector()
            case "torch": response = try toggleTorch()
            case "config": response = try updateConfiguration(call: call).asDict
            case "scan": try analyzeImage(args: call.arguments, on: result); return
            case "dispose": dispose()
            case "retrieveCachedImage": response = try retrieveCachedImage(code: (call.arguments as! [String: String])["code"]!)
            case "clearCachedImage": try clearCachedImage()
            default: response = FlutterMethodNotImplemented
            }

            result(response)
        } catch {
            print(error)
            result(error.flutterError)
        }
    }

    func initialize(args: Any?) throws -> PreviewConfiguration {
        if camera != nil {
            dispose()
        }

        guard let configuration = ScannerConfiguration(args) else {
            throw ScannerError.invalidArguments(args)
        }
        let scanner: BarcodeScanner
        if configuration.apiMode == ApiMode.avFoundation {
            scanner = AVFoundationBarcodeScanner(barcodeObjectLayerConverter: { barcodes in
                self.factory.preview?.videoPreviewLayer.transformedMetadataObject(for: barcodes) as? AVMetadataMachineReadableCodeObject
            }, onCacheImage: onCacheImage) { [unowned self] barcodes in
                self.detectionsSink?(barcodes)
            }
        } else {
            scanner = VisionBarcodeScanner(cornerPointConverter: { observation in

                func convert(point: CGPoint) -> CGPoint? {
                    self.factory.preview?.videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: point)
                }

                guard let topLeft = convert(point: CGPoint(x: observation.topLeft.x, y: 1 - observation.topLeft.y)),
                      let topRight = convert(point: CGPoint(x: observation.topRight.x, y: 1 - observation.topRight.y)),
                      let bottomRight = convert(point: CGPoint(x: observation.bottomRight.x, y: 1 - observation.bottomRight.y)),
                      let bottomLeft = convert(point: CGPoint(x: observation.bottomLeft.x, y: 1 - observation.bottomLeft.y)) else {
                    return []
                }
                return [
                    [Int(topRight.x), Int(topRight.y)],
                    [Int(topLeft.x), Int(topLeft.y)],
                    [Int(bottomLeft.x), Int(bottomLeft.y)],
                    [Int(bottomRight.x), Int(bottomRight.y)]
                ]
            }, confidence: configuration.confidence, onCacheImage: onCacheImage, resultHandler: { [unowned self] barcodes in
                self.detectionsSink?(barcodes)
            },
errorHandler: { [unowned self] error in
                self.detectionsSink?(error)
            }
            )
        }

        let camera = try Camera(configuration: configuration, scanner: scanner)

        // AVCaptureVideoPreviewLayer shows the current camera's session
        factory.session = camera.session

        try camera.start()

        self.camera = camera

        return camera.previewConfiguration
    }

    func start() throws {
        guard let camera = camera else {
            throw ScannerError.notInitialized
        }
        try camera.start()
    }

    func stop() throws {
        guard let camera = camera else {
            throw ScannerError.notInitialized
        }
        camera.stop()
    }

    func dispose() {
        camera?.stop()
        camera = nil
    }

    func startDetector() throws {
        guard let camera = camera else {
            throw ScannerError.notInitialized
        }
        camera.startDetector()
    }

    func stopDetector() throws {
        guard let camera = camera else {
            throw ScannerError.notInitialized
        }
        camera.stopDetector()
    }

    func toggleTorch() throws -> Bool {
        guard let camera = camera else {
            throw ScannerError.notInitialized
        }
        return try camera.toggleTorch()
    }

    func updateConfiguration(call: FlutterMethodCall) throws -> PreviewConfiguration {
        guard let camera = camera else {
            throw ScannerError.notInitialized
        }

        guard let config = camera.configuration.copy(with: call.arguments) else {
            throw ScannerError.invalidArguments(call.arguments)
        }

        try camera.configureSession(configuration: config)

        return camera.previewConfiguration
    }

    func retrieveCachedImage(code: String) throws -> String? {
        if let imagePath = ImageHelper.shared.retrieveImagePath(code: code) {
            return imagePath
        }
        return nil
    }

    func clearCachedImage() throws {
        ImageHelper.shared.clearCache()
    }

    func analyzeImage(args: Any?, on resultHandler: @escaping (Any?) -> Void) throws {
        let visionResultHandler: BarcodeScanner.ResultHandler = { result in
                resultHandler(result)
        }

        let visionErrorHandler: VisionBarcodeScanner.ErrorHandler = { error in
                resultHandler(error)
        }

        if let container = args as? [Any] {
            guard
                    let byteBuffer = container[0] as? FlutterStandardTypedData,
                    let image = UIImage(data: byteBuffer.data),
                    let cgImage = image.cgImage
                    else {
                throw ScannerError.loadingDataFailed
            }

            let scanner = VisionBarcodeScanner(cornerPointConverter: { _ in [] }, confidence: 0.6, onCacheImage: onCacheImage, resultHandler: visionResultHandler, errorHandler: visionErrorHandler)
            scanner.process(cgImage)
        } else {
            guard

                    let root = UIApplication.shared.delegate?.window??.rootViewController
                    else {
                return resultHandler(nil)
            }

            let imagePickerResultHandler: ImagePicker.ResultHandler = { [weak self] image in
                guard let uiImage = image,
                      let cgImage = uiImage.cgImage
                        else {
                    return resultHandler(nil)
                }

                self?.picker = nil
                let scanner = VisionBarcodeScanner(cornerPointConverter: { _ in [] }, confidence: 0.6, onCacheImage: self!.onCacheImage, resultHandler: visionResultHandler, errorHandler: visionErrorHandler)
                scanner.process(cgImage)
            }

            if #available(iOS 14, *) {
                picker = PHImagePicker(resultHandler: imagePickerResultHandler)
            } else {
                picker = UIImagePicker(resultHandler: imagePickerResultHandler)
            }

            picker!.show(over: root)
        }

    }

    func onCacheImage(code: String, scanImage: UIImage) {
        ImageHelper.shared.storeImageToCache(image: scanImage, code: code)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        detectionsSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        detectionsSink = nil
        return nil
    }
}

class ImageHelper {
    private var savedCodes: [String: String] = [:]

    static let shared = ImageHelper()

    private init() {}

    // Store image to the path with barcode as filename
    private func storeImage(imageBytes: Data, key: String) {

        let fileManager = FileManager.default
        if let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let barcodeDirectory = documentDirectory.appendingPathComponent("barcode_images")

                if fileManager.fileExists(atPath: barcodeDirectory.path) {
                    print("Directory does not exist: \(barcodeDirectory.path)")
                }

                try fileManager.createDirectory(at: barcodeDirectory, withIntermediateDirectories: true, attributes: nil)

                let fileName = key
                if #available(iOS 13.0, *) {
                    let fileName = stringToMD5(string: key)
                }

                let imageFile = barcodeDirectory.appendingPathComponent(fileName + ".jpeg")
                try imageBytes.write(to: imageFile)

                savedCodes[key] = imageFile.absoluteString
            } catch {
                print("Error storing image: \(error)")
            }
        }
    }

    @available(iOS 13.0, *)
    private func stringToMD5(string: String) -> String {
      guard let data = string.data(using: .utf8) else {
        fatalError("Failed to convert string to data")
      }

      let digest = Insecure.MD5.hash(data: data)

      return digest.map { String(format: "%02hhx", $0) }.joined()
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
        if let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let barcodeDirectory = documentDirectory.appendingPathComponent("barcode_images")
                guard fileManager.fileExists(atPath: barcodeDirectory.path) else {
                    print("Directory does not exist: \(barcodeDirectory.path)")
                    return
                }

                try fileManager.removeItem(at: barcodeDirectory)
            } catch {
                print("Error clearing cache: \(error)")
            }
        }
    }

    func storeImageToCache(image: UIImage, code: String) {
        if isImageSaved(code: code) {
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
