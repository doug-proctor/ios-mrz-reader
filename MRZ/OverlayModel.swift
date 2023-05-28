//
//  OverlayModel.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 23/05/2023.
//

import Foundation
import UIKit

// MRZ overlay properties
let overlayRatio: CGFloat = 0.7222
let overlayGutter: CGFloat = 20
let overlayWidth: CGFloat = UIScreen.main.bounds.width - overlayGutter * 2
let overlayHeight: CGFloat = overlayWidth * overlayRatio
let helpSheetMinimisedHeight: CGFloat = 100

//final class OverlayModel: ObservableObject {
//    @Published var ratio: CGFloat = 0.7222
//    @Published var gutter: CGFloat
//    @Published var width: CGFloat
//    @Published var height: CGFloat?
//    @Published var something: String
//}
