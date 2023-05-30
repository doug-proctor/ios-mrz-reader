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
    private var videoDimensions: CMVideoDimensions! = nil
    private var videoAspectRatio: CGFloat! = nil
    private var videoWidth: CGFloat! = nil
    private var videoBleed: CGFloat! = nil
    private var videoScreenWidthRatio: CGFloat! = nil
    
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
            
            print("\(fields["documentNumber"]!), \(fields["expiryDate"]!), \(fields["birthDate"]!)")
            
            DispatchQueue.global(qos: .userInitiated).async {
                log(scanDuration: scanDuration, visionDuration: visionDuration, documentNumber: fields["documentNumber"]!, expiryDate: fields["expiryDate"]!, birthDate: fields["birthDate"]!)
            }
            
            if endlessMode {
                self.shouldPerformTextRecognition = true
            }
            
            if !endlessMode {
                DispatchQueue.main.async {
                    self.appModel.isScanComplete = true
                    
                    // Buzzzzz
                    self.generator.notificationOccurred(.success)
                    
                    // Present the image obtained from the last buffer
                    let image = self.sampleBuffer.cgImage()
                    self.photoLayer.contents = image
                    
                    // Store the cropped image
                    let croppedImage = image?.cropping(to: self.getCropRect())
                    self.appModel.image = croppedImage
                    
                    // Store the document details
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
    
    
    // MARK: - Coordinates
    
    func normalisedFlippedRectFromScreenRect(rect: CGRect) -> CGRect {
        var adjustedRect = rect

        // Adjust for aspeect ratio difference between the screen and the video
        adjustedRect.size.width /= self.videoScreenWidthRatio
        adjustedRect.origin.x += (self.videoBleed / 2) / self.videoScreenWidthRatio

        var normalisedRect = VNNormalizedRectForImageRect(adjustedRect, Int(screenRect.width), Int(screenRect.height))
        
        // Flip along the y-axis
        normalisedRect.origin.y = 1 - normalisedRect.size.height - normalisedRect.origin.y
        
        return normalisedRect
    }
    
    
    // MARK: - Cropping
    
    func getCropRect() -> CGRect {
        
        // Add padding to the top of the crop zone to ensure we always have the top of the doc in frame
        let verticalPadding = self.roiRect.size.height * 2
        
        // Get overlay height as a proportion of screen height
        let overlayHeightProportion = overlayHeight / self.screenRect.height //  (should be video height instead of screenRect height, but we know they are the same
        let overlayWidthProportion = overlayWidth / self.screenRect.width
        
        // Get overlay's projected height in the video frame
        let overlayProjectedHeight = (overlayHeightProportion * CGFloat(self.videoDimensions.width) + verticalPadding) // use width because the AR is landscape
        let overlayProjectedWidth = overlayWidthProportion * CGFloat(self.videoDimensions.height) // use height because the AR is landscape
        
        // Get overlay's y-offset
        let overlayProjectedY = ((CGFloat(self.videoDimensions.width) - overlayProjectedHeight) / 2)
        let overlayProjectedX = (CGFloat(self.videoDimensions.height) - overlayProjectedWidth) / 2
        
        // Crop the image
        return CGRect(x: overlayProjectedX, y: overlayProjectedY, width: overlayProjectedWidth, height: overlayProjectedHeight)
    }
    
    
    // MARK: - Vision setup
    
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
    
    
    // MARK: - AV setup
    
    func setupCaptureSession() {
        guard let videoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) else {
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

        avCaptureSession.sessionPreset = .high //  .high gives 1920x1080 on iPhone 14 Pro, same as not setting this property at all
        avCaptureSession.addInput(videoDeviceInput)
        avCaptureSession.addOutput(avVideoOutput)
        
        self.videoDimensions = CMVideoFormatDescriptionGetDimensions(videoDevice.activeFormat.formatDescription)
        self.videoAspectRatio = CGFloat(self.videoDimensions.height) / CGFloat(self.videoDimensions.width)
        self.videoWidth = self.screenRect.height * self.videoAspectRatio
        self.videoBleed = self.videoWidth - self.screenRect.width
        self.videoScreenWidthRatio = self.videoWidth / self.screenRect.width
        
        avVideoOutput.connection(with: .video)?.videoOrientation = .portrait
        avVideoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "avSampleBufferQueue")) // Put this on class so we can suspend it?
        
        // Create a preview layer...
        let avPreviewLayer = AVCaptureVideoPreviewLayer(session: avCaptureSession)
        avPreviewLayer.frame = screenRect
        avPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        avPreviewLayer.connection?.videoOrientation = .portrait
        
        // And a document photo layer...
        var rect = screenRect!
        rect.origin.x -= self.videoBleed / 2
        rect.size.width *= self.videoScreenWidthRatio
        photoLayer = CALayer()
        photoLayer.frame = rect
        
        // Then present the layers
        DispatchQueue.main.async { [weak self] in
            self!.view.layer.addSublayer(avPreviewLayer)
            self!.view.layer.addSublayer(self!.photoLayer)
        }
        
        // Calculate the region of interest
        let roiHeight = overlayHeight * overlayMrzHeightProportion
        let roiY = screenRect.size.height - roiHeight - (screenRect.size.height - overlayHeight) / 2
        
        let roiWidth = overlayWidth
        let roiX = (screenRect.size.width - overlayWidth) / 2
        
        self.roiRect = CGRect(x: roiX, y: roiY, width: roiWidth, height: roiHeight)
        
        // Draw the roi
//        let roiView = UIView(frame: self.roiRect)
//        roiView.layer.backgroundColor = .init(red: 1, green: 0, blue: 0, alpha: 0.5)
//        self.view.addSubview(roiView)
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


// MARK: - Extensions

extension CGImage {
    func resize(size: CGSize) -> CGImage? {
        let width: Int = Int(size.width)
        let height: Int = Int(size.height)
        
        let bytesPerPixel = self.bitsPerPixel / self.bitsPerComponent
        let destBytesPerRow = width * bytesPerPixel
        
        guard let colorSpace = self.colorSpace else { return nil }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: self.bitsPerComponent, bytesPerRow: destBytesPerRow, space: colorSpace, bitmapInfo: self.alphaInfo.rawValue) else { return nil }
        
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
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


// MARK: - Logger

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
