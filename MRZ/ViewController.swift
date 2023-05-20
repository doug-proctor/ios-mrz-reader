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
    private var detectionLayer: CALayer! = nil
    private var photoLayer: CALayer! = nil
    private var extractor = MRZExtractor(mrzType: .td3)
    private let generator = UINotificationFeedbackGenerator()
    
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
        
        self.detectionLayer.sublayers = nil
                    
        if let reading = extractor.extract(observations: observations), let fields = reading.fields {
            avCaptureSession.stopRunning()
            
            print("\(fields.documentNumber == "518931376" ? "✅" : "❌") Document number: \(fields.documentNumber!)")
            print("\(fields.countryCode == "GBR" ? "✅" : "❌") Country code: \(fields.countryCode)")
            print("\(fields.expiryDate!.description == "2025-07-06 00:00:00 +0000" ? "✅" : "❌") Expiry date: \(fields.expiryDate!)")
            print("\(fields.birthdate!.description == "1983-10-21 00:00:00 +0000" ? "✅" : "❌") Birth date: \(fields.birthdate!)")
            print("\(fields.surnames == "PROCTOR" ? "✅" : "❌") Surnames: \(fields.surnames)")
            print("\(fields.givenNames == "DOUGLAS JOHN BEAUCHAMP" ? "✅" : "❌") Given names: \(fields.givenNames)")
            print("\(fields.sex == .male ? "✅" : "❌") Sex: \(fields.sex)")
            print("\(fields.documentType == .passport ? "✅" : "❌") Doc type: \(fields.documentType)")
            print("\(fields.nationalityCountryCode == "GBR" ? "✅" : "❌") Nationality: \(fields.nationalityCountryCode)")            
            
            DispatchQueue.main.async {
                // Buzzzzz
                self.generator.notificationOccurred(.success)
                
                // Present the captured document photo
                let image = self.sampleBuffer.cgImage()
                self.photoLayer.contents = image
                
                // Update the app model
                self.appModel.isScanComplete = true
                self.appModel.image = image
                self.appModel.documentNumber = fields.documentNumber
                self.appModel.expiryDate = fields.expiryDate
                self.appModel.birthDate = fields.birthdate
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(600)) {
                    self.appModel.step = .end
                }

                // Draw a box around the MRZ
//                let boxLayer = self.drawBoundingBox(self.screenRectFromNormalisedRect(rect: reading.boundingBox))
//                self.detectionLayer.addSublayer(boxLayer)
            }
        } else {
            self.shouldPerformTextRecognition = true
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
        
        // And a drawing layer...
        detectionLayer = CALayer()
        detectionLayer.frame = screenRect
        
        // Then present the layers
        DispatchQueue.main.async { [weak self] in
            self!.view.layer.addSublayer(avPreviewLayer)
            self!.view.layer.addSublayer(self!.photoLayer)
            self!.view.layer.addSublayer(self!.detectionLayer)
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

extension CATransaction {
    // https://stackoverflow.com/questions/5833488/how-to-disable-calayer-implicit-animations
    static func disableAnimations(_ completion: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        completion()
        CATransaction.commit()
    }
}

//extension CGImage {
//    func resize(size:CGSize) -> CGImage? {
//        let width: Int = Int(size.width)
//        let height: Int = Int(size.height)
//
//        let bytesPerPixel = self.bitsPerPixel / self.bitsPerComponent
//        let destBytesPerRow = width * bytesPerPixel
//
//        guard let colorSpace = self.colorSpace else { return nil }
//        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: self.bitsPerComponent, bytesPerRow: destBytesPerRow, space: colorSpace, bitmapInfo: self.alphaInfo.rawValue) else { return nil }
//
//        context.interpolationQuality = .high
//        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
//
//        return context.makeImage()
//    }
//}
