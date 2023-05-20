//
//  MRZApp.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 16/05/2023.
//

import SwiftUI

@main
struct MRZApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppModel())
        }
    }
}
