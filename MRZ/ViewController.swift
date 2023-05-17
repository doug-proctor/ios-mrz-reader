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
    private var screenRect: CGRect! = nil
    private var cameraPermissionGranted = false
    private let avCaptureSession = AVCaptureSession()
    private let avSessionQueue = DispatchQueue(label: "avSessionQueue") // on class so we can suspend, but do we need to?
    private let textRecognitionRequestQueue = DispatchQueue.global(qos: .userInitiated)
    private var avVideoOutput = AVCaptureVideoDataOutput()
    private var sampleBuffer: CMSampleBuffer! = nil
    private let mrzParser = MRZParser(isOCRCorrectionEnabled: false)
    private var isGateOpen = true
    private var detectionLayer: CALayer! = nil
    private var latestBoundingBoxes = (line1: CGRectNull, line2: CGRectNull)
    
    override func viewDidLoad() {
        screenRect = UIScreen.main.bounds
        checkCameraPermission()
        
        avSessionQueue.async { [unowned self] in
            guard cameraPermissionGranted else { return }
            self.setupCaptureSession()
            self.avCaptureSession.startRunning()
        }
    }
    
    
    // MARK: - Vision
    
    func handleRecognisedText(request: VNRequest?, error: Error?) {
        if !isGateOpen {
            request?.cancel()
            return
        }

        if let nsError = error as NSError? {
            print("Error handling detected text, %@", nsError)
            return
        }
            
        guard let observations = request?.results as? [VNRecognizedTextObservation] else {
            return
        }
        
        for currentObservation in observations {
            if let topCandidate = currentObservation.topCandidates(1).first {
                if let mrz = topCandidate.string.checkMrz(callback: { line in
                    
                    // might not need this, currentObservation seems reliable now
                    if line == 0 {
                        self.latestBoundingBoxes.0 = currentObservation.boundingBox
                    }
                    if line == 1 {
                        self.latestBoundingBoxes.1 = currentObservation.boundingBox
                    }
                }) {
                    let parsed = self.mrzParser.parse(mrzString: mrz)
                    
                    if let documentNumber = parsed?.documentNumber, let expiryDate = parsed?.expiryDate, let dateOfBirth = parsed?.birthdate {
                        avCaptureSession.stopRunning()
                        self.isGateOpen = false // rename shouldacceptrequests
                        
                        print("[ ] \(currentObservation.topCandidates(1).first!.string)")
                        print("\(documentNumber == "518931376" ? "✅" : "❌") Document number: \(documentNumber)")
                        print("\(expiryDate.description == "2025-07-06 00:00:00 +0000" ? "✅" : "❌") Expiry date: \(expiryDate)")
                        print("\(dateOfBirth.description == "1983-10-21 00:00:00 +0000" ? "✅" : "❌") Birth date: \(dateOfBirth)")
                        
                        let bounds = self.latestBoundingBoxes.0.union(self.latestBoundingBoxes.1)
                        
                        DispatchQueue.main.async {
                            let boxBounds = self.screenRectFromNormalisedRect(rect: bounds)
                            let boxLayer = self.drawBoundingBox(boxBounds)
                            self.detectionLayer.addSublayer(boxLayer)
                        }
                        
                        
                        let _ = sampleBuffer.image() // show this image on the screen instead of the last frame of the av session because last frame could be later and blurry
                        
                        // todo clear the collected MRZ
                        
                        return
                    } else {
                        print("Couldn't parse: \(mrz)")
                        
                        // Remove previous layers
                        self.detectionLayer.sublayers = nil
                    }
                }
            }
        }
    }
    
    
    // MARK: - Drawing
    
    func screenRectFromNormalisedRect(rect: CGRect) -> CGRect {
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
        boxLayer.borderWidth = 3.0
        boxLayer.borderColor = CGColor.init(red: 7.0, green: 8.0, blue: 7.0, alpha: 1.0)
        boxLayer.cornerRadius = 4
        return boxLayer
    }
    
    // MARK: - AV & Vision setup
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !isGateOpen { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        self.sampleBuffer = sampleBuffer
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let textRecognitionRequest = VNRecognizeTextRequest(completionHandler: self.handleRecognisedText)
        textRecognitionRequest.recognitionLevel = VNRequestTextRecognitionLevel.fast
        
        textRecognitionRequestQueue.async {
            do {
                try imageRequestHandler.perform([textRecognitionRequest])
            } catch let error as NSError {
                print("Failed to perform image request: \(error)")
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
//            videoDevice.videoZoomFactor = 1.5
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
        avPreviewLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        avPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        avPreviewLayer.connection?.videoOrientation = .portrait
        
        // And create a drawing layer
        detectionLayer = CALayer()
        detectionLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        self.view.layer.addSublayer(detectionLayer)
        
        // Present the layers
        DispatchQueue.main.async { [weak self] in
            self!.view.layer.addSublayer(avPreviewLayer)
            self!.view.layer.addSublayer(self!.detectionLayer)
        }
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
    func makeUIViewController(context: Context) -> UIViewController {
        return ViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        //
    }
}

extension CMSampleBuffer {
    /// https://stackoverflow.com/questions/15726761/make-an-uiimage-from-a-cmsamplebuffer
    func image(orientation: UIImage.Orientation = .up, scale: CGFloat = 1.0) -> UIImage? {
        if let buffer = CMSampleBufferGetImageBuffer(self) {
            let ciImage = CIImage(cvPixelBuffer: buffer)
            
            return UIImage(ciImage: ciImage, scale: scale, orientation: orientation)
        }
        
        return nil
    }
    
    func imageWithCGImage(orientation: UIImage.Orientation = .up, scale: CGFloat = 1.0) -> UIImage? {
        if let buffer = CMSampleBufferGetImageBuffer(self) {
            let ciImage = CIImage(cvPixelBuffer: buffer)
            
            let context = CIContext(options: nil)
            
            guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            
            return UIImage(cgImage: cg, scale: scale, orientation: orientation)
        }
        
        return nil
    }
}


//class Outline: UIView {
//    override init(frame: CGRect) {
//        super.init(frame: frame)
//
//        backgroundColor = .red
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
