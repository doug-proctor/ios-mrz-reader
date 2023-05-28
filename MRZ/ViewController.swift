//
//  ViewController.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 16/05/2023.
//

import Foundation
import SwiftUI
import AVFoundation
import Vision

import MRZParser

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var appModel: AppModel
    private var screenRect: CGRect! = nil
    private var roiRect: CGRect! = nil
    private var cropRect: CGRect! = nil
    private var cameraPermissionGranted = false
    private let avCaptureSession = AVCaptureSession()
    private let avSessionQueue = DispatchQueue(label: "avSessionQueue")
    private let textRecognitionRequestQueue = DispatchQueue.global(qos: .userInitiated)
    private var avVideoOutput = AVCaptureVideoDataOutput()
    private var sampleBuffer: CMSampleBuffer! = nil
    private var shouldPerformTextRecognition = true
    private var photoLayer: CALayer! = nil
    private var extractor = MRZExtractor(mrzType: .td3)
    private let generator = UINotificationFeedbackGenerator()
    
    // Logging & debug etc
    private var endlessMode = false
    private var successCount = 0
    private var visionStartTime: TimeInterval! = nil
    private var scanStartTime: TimeInterval! = nil
    
    init(appModel: AppModel) {
        self.appModel = appModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        screenRect = UIScreen.main.bounds
        checkCameraPermission()
        
        avSessionQueue.async { [unowned self] in
            guard cameraPermissionGranted else { return }
            self.setupCaptureSession()
            self.avCaptureSession.startRunning()
            self.generator.prepare()
        }
    }
    
    
    // MARK: - Vision
    
    func handleRecognisedText(request: VNRequest?, error: Error?) {
        if let nsError = error as NSError? {
            print("Error handling detected text, %@", nsError)
            return
        }
            
        guard let observations = request?.results as? [VNRecognizedTextObservation] else {
            return
        }
                    
        if let fields = extractor.extract(observations: observations) {
            // Model timer
            let visionEndTime = (Date().timeIntervalSince1970 * 1000).rounded()
            let visionDuration = visionEndTime - visionStartTime
            print("Vision duration: ", visionDuration)
            
            // Scan timer
            let scanEndTime = (Date().timeIntervalSince1970 * 1000).rounded()
            var scanDuration: Double = 0.0
            if scanStartTime != nil {
                scanDuration = scanEndTime - scanStartTime
                scanStartTime = nil
            }
            
            // Success count
            successCount += 1
            print("Success count: ", successCount)
            
            if !endlessMode {
                avCaptureSession.stopRunning()
            }
            
            print("\(fields["documentNumber"] == "518931376" ? "✅" : "❌") Document number: \(fields["documentNumber"]!)")
            print("\(fields["expiryDate"] == "250706" ? "✅" : "❌") Expiry date: \(fields["expiryDate"]!)")
            print("\(fields["birthDate"] == "831021" ? "✅" : "❌") Birth date: \(fields["birthDate"]!)")
            
            DispatchQueue.global(qos: .userInitiated).async {
                log(scanDuration: scanDuration, visionDuration: visionDuration, documentNumber: fields["documentNumber"]!, expiryDate: fields["expiryDate"]!, birthDate: fields["birthDate"]!)
            }
            
            if endlessMode {
                self.shouldPerformTextRecognition = true
            }
            
            if !endlessMode {
                DispatchQueue.main.async {
                    // Buzzzzz
                    self.generator.notificationOccurred(.success)
                    
                    // Present the captured document photo
                    let image = self.sampleBuffer.cgImage()
                    self.photoLayer.contents = image
                    
                    // Update the app model
                    self.appModel.isScanComplete = true
                    self.appModel.image = image
                    
                    if let documentNumber = fields["documentNumber"], let expiryDate = fields["expiryDate"], let birthDate = fields["birthDate"] {
                        self.appModel.documentNumber = documentNumber
                        self.appModel.expiryDate = expiryDate
                        self.appModel.birthDate = birthDate
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1000)) {
                        self.appModel.step = .end
                    }
                }
            }
        } else {
            self.shouldPerformTextRecognition = true
            
            // Overall scan timer
            scanStartTime = scanStartTime == nil ? (Date().timeIntervalSince1970 * 1000).rounded() : nil
        }
    }
    
    
    // MARK: - Drawing
    
    func normalisedFlippedRectFromScreenRect(rect: CGRect) -> CGRect {
        var adjustedRect = rect
        adjustedRect.size.width /= 1.219
        adjustedRect.origin.x += 35 // wtf does this number come from???

        var normalisedRect = VNNormalizedRectForImageRect(adjustedRect, Int(screenRect.width), Int(screenRect.height))
        normalisedRect.origin.y = 1 - normalisedRect.size.height - normalisedRect.origin.y
        
        return normalisedRect
    }
    
    func flippedAdjustedScreenRectFromNormalisedRect(rect: CGRect) -> CGRect {
        let sideBleed = 43.0
        let cropFactor = 1.219

        var rect = VNImageRectForNormalizedRect(rect, Int(self.screenRect.size.width * cropFactor), Int(self.screenRect.size.height))
        
        // Adjust for the video bleed
        rect.origin.x -= sideBleed
        
        // Invert the y-axis
        rect.origin.y = self.screenRect.size.height - rect.origin.y - rect.height
        
        // Add padding
        let padding = 10.0
        rect.size.width += padding * 2
        rect.size.height += padding * 2
        rect.origin.x -= padding
        rect.origin.y -= padding
        
        return rect
    }

    func drawBoundingBox(_ bounds: CGRect) -> CALayer {
        let boxLayer = CALayer()
        boxLayer.frame = bounds
        boxLayer.borderWidth = 5.0
        boxLayer.borderColor = CGColor.init(red: 0, green: 1, blue: 0, alpha: 1)
        boxLayer.cornerRadius = 4
        return boxLayer
    }
    
    
    // MARK: - AV & Vision setup
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !shouldPerformTextRecognition { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        self.sampleBuffer = sampleBuffer
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let textRecognitionRequest = VNRecognizeTextRequest(completionHandler: self.handleRecognisedText)
        textRecognitionRequest.recognitionLevel = VNRequestTextRecognitionLevel.fast
        textRecognitionRequest.regionOfInterest = normalisedFlippedRectFromScreenRect(rect: roiRect)
        
        textRecognitionRequestQueue.async {
            do {
                self.shouldPerformTextRecognition = false
                
                // Vision request / model timer
                self.visionStartTime = (Date().timeIntervalSince1970 * 1000).rounded()
                                
                try imageRequestHandler.perform([textRecognitionRequest])
            } catch let error as NSError {
                print("Failed to perform image request: \(error)")
                self.shouldPerformTextRecognition = true
                return
            }
        }
    }
    
    func setupCaptureSession() {
        guard let videoDevice = AVCaptureDevice.default(.builtInDualCamera,for: .video, position: .back) else {
            return
        }
        
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.autoFocusRangeRestriction = .near
            videoDevice.videoZoomFactor = 1.5
            videoDevice.unlockForConfiguration()
        } catch {
            print("Could not set zoom level due to error: \(error)")
            return
        }
        
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("Camera not found on this device")
            return
        }
        
        guard avCaptureSession.canAddInput(videoDeviceInput) else {
            return
        }

        avCaptureSession.sessionPreset = .high
        avCaptureSession.addInput(videoDeviceInput)
        avCaptureSession.addOutput(avVideoOutput)

        avVideoOutput.connection(with: .video)?.videoOrientation = .portrait
        avVideoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "avSampleBufferQueue")) // Put this on class so we can suspend it?
        
        // Create a preview layer...
        let avPreviewLayer = AVCaptureVideoPreviewLayer(session: avCaptureSession)
        avPreviewLayer.frame = screenRect
        avPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        avPreviewLayer.connection?.videoOrientation = .portrait
        
        // And a document photo layer...
        let sideBleed = 43.0
        let cropFactor = 1.219
        var rect = screenRect!
        rect.origin.x -= sideBleed
        rect.size.width *= cropFactor
        photoLayer = CALayer()
        photoLayer.frame = rect
        
        // Then present the layers
        DispatchQueue.main.async { [weak self] in
            self!.view.layer.addSublayer(avPreviewLayer)
            self!.view.layer.addSublayer(self!.photoLayer)
        }
        
        // Calculate the region of interest
        let screenHeight = screenRect.size.height
        let guideHeight = 260.0
        let roiHeight = guideHeight * (1 - 0.74)
        let roiY = screenHeight - roiHeight - (screenHeight - guideHeight) / 2
        
        let screenWidth = screenRect.size.width
        let guideWidth = 360.0
        let roiWidth = guideWidth
        let roiX = (screenWidth - guideWidth) / 2
        
        self.roiRect = CGRect(x: roiX, y: roiY, width: roiWidth, height: roiHeight)
    }
    
    
    // MARK: - Camera permission
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
        case .notDetermined:
            requestPermission()
        default:
            cameraPermissionGranted = false
        }
    }
    
    func requestPermission() {
        avSessionQueue.suspend()
        
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            self.cameraPermissionGranted = granted
            self.avSessionQueue.resume()
        }
    }
}


// MARK: - SwiftUI bridge

struct HostedViewController: UIViewControllerRepresentable {
    @EnvironmentObject var appModel: AppModel
    
    func makeUIViewController(context: Context) -> UIViewController {
        return ViewController(appModel: appModel)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        //
    }
}

extension CMSampleBuffer {
    /// https://stackoverflow.com/questions/15726761/make-an-uiimage-from-a-cmsamplebuffer
    func uiImage(orientation: UIImage.Orientation = .up, scale: CGFloat = 1.0) -> UIImage? {
        if let buffer = CMSampleBufferGetImageBuffer(self) {
            let ciImage = CIImage(cvPixelBuffer: buffer)
            
            return UIImage(ciImage: ciImage, scale: scale, orientation: orientation)
        }
        
        return nil
    }
    
    /// https://stackoverflow.com/questions/14402413/getting-a-cgimage-from-ciimage
    func cgImage() -> CGImage? {
        if let buffer = CMSampleBufferGetImageBuffer(self) {
            let context = CIContext(options: nil)
            let ciImage = CIImage(cvPixelBuffer: buffer)
            
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                return cgImage
            }
            
            return nil
        }
        
        return nil
    }
}

func log(scanDuration: Double, visionDuration: Double, documentNumber: String, expiryDate: String, birthDate: String) {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 120
    let session = URLSession(configuration: configuration)
    
    let url = URL(string: "https://mrzlog.dougproctor.co.uk/log")!
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    
    let parameters: [String: Any] = [
        "vision_duration": visionDuration,
        "scan_duration": scanDuration,
        "document_number": documentNumber,
        "expiry_date": expiryDate,
        "birth_date": birthDate
    ]
        
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: .prettyPrinted)
    } catch let error {
        print("Error", error.localizedDescription)
    }
    
    let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in
        if error != nil || data == nil {
            print("Client error!")
            return
        }
        
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            print("Oops!! there is server error!")
            return
        }
        
        guard let mime = response.mimeType, mime == "application/json" else {
            print("response is not json")
            return
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data!, options: [])
        } catch {
            print("JSON error: \(error.localizedDescription)")
        }
    })
    
    task.resume()
}
