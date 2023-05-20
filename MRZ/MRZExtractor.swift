//
//  MrzExtractor.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 20/05/2023.
//

import Foundation
import Vision
import MRZParser

enum MRZType {
    case td1, td3
}

// Regex for TD1 (ID cards)
let td1Line1Regex = "(I|C|A).[A-Z0<]{3}[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0-9<]{14,22}"
let td1Line2Regex = "[0-9O]{7}(M|F|<)[0-9O]{7}[A-Z0<]{3}[A-Z0-9<]{11}[0-9O]"
let td1Line3Regex = "([A-Z<]{30})" // No numbers...
//let td1Line3Regex = "([A-Z0]+<)+<([A-Z0]+<)+<+" // Assumes multiple names?

// Regex for TD3 (passports)
//let td3Line1Regex = "P.[A-Z0<]{3}([A-Z0]+<)+<([A-Z0]+<)+<+"
let td3Line1Regex = "P.[A-Z]{3}([A-Z0]+<)+<([A-Z0]+<)+<+"
let td3Line2Regex = "[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0<]{3}[0-9]{7}(M|F|<)[0-9O]{7}[A-Z0-9<]+"

// Todo: move those regexes into a tuple

struct MRZReading {
    var isComplete = false
    
//    var documentNumber: String?
//    var expiryDate: Date?
//    var birthDate: Date?
    
    var fields: MRZResult?
    
    var mrzType: MRZType
    
    // Line 1
    var line1String: String?
    var line1BoundingBox: CGRect?
    
    // Line 2
    var line2String: String?
    var line2BoundingBox: CGRect?
    
    // Line 3
    var line3String: String?
    var line3BoundingBox: CGRect?
    
    // All lines
    var lines: String? {
        if mrzType == .td1 {
            if let line1String, let line2String, let line3String {
                return line1String + "\n" + line2String + "\n" + line3String
            }
            
            return nil
        }

        if mrzType == .td3 {
            if let line1String, let line2String {
                return line1String + "\n" + line2String
            }
            
            return nil
        }
        
        return nil
    }
    
    // Full bounding box
    var boundingBox: CGRect {
        if mrzType == .td1 {
            if let line1BoundingBox, let line2BoundingBox, let line3BoundingBox {
                return line1BoundingBox.union(line2BoundingBox).union(line3BoundingBox)
            }
        }
        
        if mrzType == .td3 {
            if let line1BoundingBox, let line2BoundingBox {
                return line1BoundingBox.union(line2BoundingBox)
            }
        }
        
        return CGRectNull
    }
}

class MRZExtractor {
    private let mrzParser = MRZParser(isOCRCorrectionEnabled: false)
    private var mrzType: MRZType
    var reading: MRZReading
    
    init(mrzType: MRZType) {
        self.mrzType = mrzType
        self.reading = MRZReading(mrzType: mrzType)
    }
    
    func reset() {
        reading = MRZReading(mrzType: mrzType)
    }
        
    func parse() -> MRZReading? {
        if let lines = reading.lines {
            if let parsed = mrzParser.parse(mrzString: lines) {
                reading.fields = parsed
                
                return reading
            }
        }
        
        return nil
    }
    
    func extract(observations: [VNRecognizedTextObservation]) -> MRZReading? {
        reset()
        
        for observation in observations {
            if let candidate = observation.topCandidates(1).first {
                if reading.mrzType == .td1 {
                    // Line 1
                    if let _ = candidate.string.range(of: td1Line1Regex, options: .regularExpression, range: nil, locale: nil) {
                        reading.line1String = candidate.string
                        reading.line1BoundingBox = observation.boundingBox
                        print("set line 1", candidate.string)
                    }
                    // Line 2
                    if let _ = candidate.string.range(of: td1Line2Regex, options: .regularExpression, range: nil, locale: nil) {
                        reading.line2String = candidate.string
                        reading.line2BoundingBox = observation.boundingBox
                        print("set line 2", candidate.string)
                    }
                    // Line 3
                    if let _ = candidate.string.range(of: td1Line3Regex, options: .regularExpression, range: nil, locale: nil) {
                        reading.line3String = candidate.string
                        reading.line3BoundingBox = observation.boundingBox
                        print("set line 3", candidate.string)
                    }
                }
                
                if reading.mrzType == .td3 {
                    // Line 1
                    if let _ = candidate.string.range(of: td3Line1Regex, options: .regularExpression, range: nil, locale: nil) {
                        reading.line1String = candidate.string
                        reading.line1BoundingBox = observation.boundingBox
                        print("set line 1", candidate.string)
                    }
                    // Line 2
                    if let _ = candidate.string.range(of: td3Line2Regex, options: .regularExpression, range: nil, locale: nil) {
                        reading.line2String = candidate.string
                        reading.line2BoundingBox = observation.boundingBox
                        print("set line 2", candidate.string)
                    }
                }
            }
        }
        
        return parse()
    }
}
