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
    
    override func viewDidLoad() {
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
            let topCandidate = currentObservation.topCandidates(1).first
            if let topCandidate {
                if let mrz = topCandidate.string.checkMrz() {
                    let parsed = self.mrzParser.parse(mrzString: mrz)
                    
                    if let documentNumber = parsed?.documentNumber, let expiryDate = parsed?.expiryDate, let dateOfBirth = parsed?.birthdate {
                        self.isGateOpen = false
                        
                        print("\(documentNumber == "518931376" ? "✅" : "❌") Document number: \(documentNumber)")
                        print("\(expiryDate.description == "2025-07-06 00:00:00 +0000" ? "✅" : "❌") Expiry date: \(expiryDate)")
                        print("\(dateOfBirth.description == "1983-10-21 00:00:00 +0000" ? "✅" : "❌") Birth date: \(dateOfBirth)")
                        
                        DispatchQueue.main.async {
                            let outline = Outline(frame: self.screenRectFromNormalisedRect(rect: currentObservation.boundingBox))
                            self.view.addSubview(outline)
                        }
                        
//                        let image = sampleBuffer.image()                        
                        
                        return
                    } else {
                        print("Couldn't parse: \(mrz)")
                    }
                }
            }
        }
    }
    
    func screenRectFromNormalisedRect(rect: CGRect) -> CGRect {
        let sideBleed = 43.0
        let cropFactor = 1.219

        var rect = VNImageRectForNormalizedRect(rect, Int(self.screenRect.size.width * cropFactor), Int(self.screenRect.size.height))
        
        // Adjust for the video bleed
        rect.origin.x -= sideBleed
        
        // Invert the y-axis
        rect.origin.y = self.screenRect.size.height - rect.origin.y - rect.height
        
        return rect
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

        avCaptureSession.sessionPreset = .hd1280x720 // Or which preset should we use?
        avCaptureSession.addInput(videoDeviceInput)
        avCaptureSession.addOutput(avVideoOutput)

        avVideoOutput.connection(with: .video)?.videoOrientation = .portrait
        avVideoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "avSampleBufferQueue")) // Put this on class so we can suspend it?
        
        // Create a preview layer
        screenRect = UIScreen.main.bounds
        let avPreviewLayer = AVCaptureVideoPreviewLayer(session: avCaptureSession)
        avPreviewLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        avPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        avPreviewLayer.connection?.videoOrientation = .portrait
        
        // Present the preview layer
        DispatchQueue.main.async { [weak self] in
            self!.view.layer.addSublayer(avPreviewLayer)
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


class Outline: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .red
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
