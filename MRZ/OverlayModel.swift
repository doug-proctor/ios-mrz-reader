//
//  OverlayModel.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 23/05/2023.
//

import Foundation
import UIKit

// MRZ overlay properties
let overlayAspectRatio: CGFloat = 0.7222
let overlayGutter: CGFloat = 20
let overlayWidth: CGFloat = UIScreen.main.bounds.width - overlayGutter * 2
let overlayHeight: CGFloat = overlayWidth * overlayAspectRatio
let overlayMrzHeightProportion: CGFloat = 0.25 // 1/4 the height of the overlay
let helpSheetMinimisedHeight: CGFloat = 100
