//
//  AppModel.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 22/05/2023.
//

import Foundation
import UIKit

enum Step {
    case start, end
}

final class AppModel: ObservableObject {
    @Published var isScanComplete = false
    @Published var step = Step.start

    @Published var documentNumber: String?
    @Published var expiryDate: Date?
    @Published var birthDate: Date?

    @Published var image: CGImage?
}
