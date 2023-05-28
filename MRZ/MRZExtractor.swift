//
//  MrzExtractor.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 20/05/2023.
//

import Foundation
import Vision

enum MRZType {
    case td1, td3
}

// Regex for TD1 (ID cards)
let td1Line1Regex = "(I|C|A).[A-Z0<]{3}[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0-9<]{14,22}"
let td1Line2Regex = "[0-9O]{7}(M|F|<)[0-9O]{7}[A-Z0<]{3}[A-Z0-9<]{11}[0-9O]"
let td1Line3Regex = "([A-Z<]{30})"

// Regex for TD3 (passports)
let td3Line1Regex = "(P[A-Z<])([A-Z]{3}|D<<)([A-Z<]{39})"
let td3Line2Regex = "([A-Z0-9<]{9})([0-9]{1})([A-Z08]{3}|D<<)([0-9<]{6})([0-9]{1})([MFX<])([0-9]{6})([0-9]{1})([A-Z0-9<]{14})([0-9]{1})([0-9]{1})"
let td3LineLength = 44

let weights = [7, 3, 1]
let values: [Character: Int] = [
    "<": 0,
    "0": 0,
    "1": 1,
    "2": 2,
    "3": 3,
    "4": 4,
    "5": 5,
    "6": 6,
    "7": 7,
    "8": 8,
    "9": 9,
    "A": 10,
    "B": 11,
    "C": 12,
    "D": 13,
    "E": 14,
    "F": 15,
    "G": 16,
    "H": 17,
    "I": 18,
    "J": 19,
    "K": 20,
    "L": 21,
    "M": 22,
    "N": 23,
    "O": 24,
    "P": 25,
    "Q": 26,
    "R": 27,
    "S": 28,
    "T": 29,
    "U": 30,
    "V": 31,
    "W": 32,
    "X": 33,
    "Y": 34,
    "Z": 35,
]

struct MRZReading {
    var isComplete = false
    var mrzType: MRZType
    var line2String: String?
}

class MRZExtractor {
    private var mrzType: MRZType
    var reading: MRZReading
    
    init(mrzType: MRZType) {
        self.mrzType = mrzType
        self.reading = MRZReading(mrzType: mrzType)
    }
    
    func reset() {
        reading = MRZReading(mrzType: mrzType)
    }
    
    func calculateCheckDigit(mrz: String) -> Int {
        var check = 0
        for (index, _) in mrz.enumerated() {
            let charIndex: String.Index = mrz.index(mrz.startIndex, offsetBy: index)
            let char: Character = mrz[charIndex]
            let weight: Int = weights[(index) % weights.count]
            let value: Int? = values[char]
            check += (weight * (value ?? 0)) % 10
        }
        
        return check % 10
    }
    
    func checkMrz(mrz: String) -> Bool {
        if let checkChar: Character = mrz.last {
            if let checkDigit = checkChar.wholeNumberValue {
                let calculatedDigit = calculateCheckDigit(mrz: String(mrz.dropLast()))
                return calculatedDigit % 10 == checkDigit
            }
        }
        
        return false
    }
    
    func parse() -> [String: String]? {
        if let mrz = self.reading.line2String {
            
            let fields = [
                String(Array(mrz)[0...9]), // document number
                String(Array(mrz)[13...19]), // birth date
                String(Array(mrz)[21...27]), // expiry date
                String(Array(mrz)[28...42]) // optional data
            ]
            
            // Check the full MRZ line first
            let fullMrz = fields.joined() + [mrz.last!]
            if !checkMrz(mrz: fullMrz) {
                print("TD3 line 2 fail:  ", mrz)
                return nil
            }
            
            // Now check the individual fields
            let namedFields = [
                "documentNumber": fields[0],
                "birthDate": fields[1],
                "expiryDate": fields[2],
                "optionalData": fields[3],
            ]
            var validatedFields = [String: String]()
            
            for (name, mrz) in namedFields {
                if checkMrz(mrz: mrz) {
                    validatedFields[name] = String(mrz.dropLast()).replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    return nil
                }
            }
            
            return validatedFields
        }
        
        return nil
    }
    
    func extract(observations: [VNRecognizedTextObservation]) -> [String: String]? {
        reset()
        
        for observation in observations {
            for candidate in observation.topCandidates(1) {
                // Passports
                if reading.mrzType == .td3 && candidate.string.count == td3LineLength {
                    if let _ = candidate.string.range(of: td3Line2Regex, options: .regularExpression, range: nil, locale: nil) {
                        reading.line2String = candidate.string
                        print("TD3 line 2 match: ", candidate.string)
                    }
                }
            }
        }

        return parse()
    }
}
