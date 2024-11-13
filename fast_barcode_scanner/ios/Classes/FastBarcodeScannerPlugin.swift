import Flutter
import AVFoundation

@available(iOS 11.0, *)
public class FastBarcodeScannerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    let commandChannel: FlutterMethodChannel
    let barcodeEventChannel: FlutterEventChannel
    let factory: PreviewViewFactory

    var camera: Camera?
    var picker: ImagePicker?
    var detectionsSink: FlutterEventSink?

    var captureImageDict: [String: [UInt8]?] = [String: [UInt8]?]()

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
            case "retrieveImageCache": response = try retrieveImageCache(code: (call.arguments as! [String: String])["code"]!)
            case "clearImageCache": try clearImageCache()
            default: response = FlutterMethodNotImplemented
            }

            result(response)
        } catch {
            print(error)
            result(error.flutterError)
        }
    }

    func initialize(args: Any?) throws -> PreviewConfiguration {
        guard camera == nil else {
            throw ScannerError.alreadyInitialized
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

    func retrieveImageCache(code: String) throws -> [UInt8]? {
        return captureImageDict[code] ?? nil
    }

    func clearImageCache() throws {
        captureImageDict.removeAll()
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

    func onCacheImage(key: String, value: [UInt8]?) {
        captureImageDict[key] = value
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
