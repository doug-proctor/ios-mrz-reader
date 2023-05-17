//
//  StringUtils.swift
//  TwoWayDataFlow
//
//  Created by doug.proctor@bidbax.no on 11/05/2023.
//

import Foundation

var captureFirst = ""
var captureSecond = ""
var captureThird = ""
var mrz = ""
var temp_mrz = ""

extension String {
    func checkMrz(callback: (Int) -> Void) -> (String)? {
        
        let tdOneFirstRegex = "(I|C|A).[A-Z0<]{3}[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0-9<]{14,22}"
        let tdOneSecondRegex = "[0-9O]{7}(M|F|<)[0-9O]{7}[A-Z0<]{3}[A-Z0-9<]{11}[0-9O]"
        let tdOneThirdRegex = "([A-Z0]+<)+<([A-Z0]+<)+<+"
        let tdOneMrzRegex = "(I|C|A).[A-Z0<]{3}[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0-9<]{14,22}\n[0-9O]{7}(M|F|<)[0-9O]{7}[A-Z0<]{3}[A-Z0-9<]{11}[0-9O]\n([A-Z0]+<)+<([A-Z0]+<)+<+"
        
        let tdThreeFirstRegex = "P.[A-Z0<]{3}([A-Z0]+<)+<([A-Z0]+<)+<+"
        let tdThreeSecondRegex = "[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0<]{3}[0-9]{7}(M|F|<)[0-9O]{7}[A-Z0-9<]+"
        let tdThreeMrzRegex = "P.[A-Z0<]{3}([A-Z0]+<)+<([A-Z0]+<)+<+\n[A-Z0-9]{1,9}<?[0-9O]{1}[A-Z0<]{3}[0-9]{7}(M|F|<)[0-9O]{7}[A-Z0-9<]+"
        
        let tdOneFirstLine = self.range(of: tdOneFirstRegex, options: .regularExpression, range: nil, locale: nil)
        let tdOneSecondLine = self.range(of: tdOneSecondRegex, options: .regularExpression, range: nil, locale: nil)
        let tdOneThirdLine = self.range(of: tdOneThirdRegex, options: .regularExpression, range: nil, locale: nil)
        
        let tdThreeFirstLine = self.range(of: tdThreeFirstRegex, options: .regularExpression, range: nil, locale: nil)
        let tdThreeSeconddLine = self.range(of: tdThreeSecondRegex, options: .regularExpression, range: nil, locale: nil)
        
        if tdOneFirstLine != nil {
            if self.count == 30 {
                captureFirst = self
            }
        }
        if tdOneSecondLine != nil {
            if self.count == 30 {
                captureSecond = self
            }
        }
        if tdOneThirdLine != nil {
            if self.count == 30 {
                captureThird = self
            }
        }
        
        // Passports
        
        if tdThreeFirstLine != nil {
            if self.count == 44 {
                captureFirst = self
                callback(0)
                print("LINE ONE")
                return captureFirst
            }
        }
        
        if tdThreeSeconddLine != nil {
            if self.count == 44 {
                captureSecond = self
                callback(1)
                print("LINE TWO")
                return captureSecond
            }
        }
        
        if captureFirst.count == 30 && captureSecond.count == 30 && captureThird.count == 30 {
            temp_mrz = (captureFirst.stripped + "\n" + captureSecond.stripped + "\n" + captureThird.stripped).replacingOccurrences(of: " ", with: "<")
            
            let checkMrz = temp_mrz.range(of: tdOneMrzRegex, options: .regularExpression, range: nil, locale: nil)
            
            if checkMrz != nil {
                mrz = temp_mrz
            }
        }
        
        if captureFirst.count == 44 && captureSecond.count == 44 {
            temp_mrz = (captureFirst.stripped + "\n" + captureSecond.stripped).replacingOccurrences(of: " ", with: "<")
            
            let checkMrz = temp_mrz.range(of: tdThreeMrzRegex, options: .regularExpression, range: nil, locale: nil)
            
            if checkMrz != nil {
                mrz = temp_mrz
            }
        }
        
        return mrz == "" ? nil : mrz
    }
    
    var stripped: String {
        let okayChars = Set("ABCDEFGHIJKLKMNOPQRSTUVWXYZ1234567890<")
        return self.filter {okayChars.contains($0) }
    }
}
