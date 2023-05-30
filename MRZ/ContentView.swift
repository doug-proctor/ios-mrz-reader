//
//  ContentView.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 16/05/2023.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    
    var body: some View {
        Group {
            if appModel.step == .start {
                ZStack {
                    HostedViewController()
                    PassportOverlay()
//                        .padding(.bottom, 100) // to account for the help sheet
                }
                .edgesIgnoringSafeArea(.vertical)
                .transition(AnyTransition.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading))
                )
            }
            if appModel.step == .end {
                ZStack {
                    Color.black
                    VStack {
                        if let image = appModel.image {
                            Image(uiImage: UIImage(cgImage: image))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 450, height: 450)
                        }
                        if let documentNumber = appModel.documentNumber {
                            Text("Document number: \(documentNumber)").foregroundColor(.gray)
                        }
                        if let expiryDate = appModel.expiryDate {
                            Text("Expiry date: \(expiryDate)").foregroundColor(.gray)
                        }
                        if let birthDate = appModel.birthDate {
                            Text("Date of birth: \(birthDate)").foregroundColor(.gray)
                        }
                        Button("Restart") {
                            appModel.step = .start
                            appModel.isScanComplete = false
                        }
                    }
                }
                .edgesIgnoringSafeArea(.vertical)
                .transition(AnyTransition.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading))
                )
            }
        }
        .animation(.default, value: appModel.step)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppModel())
            .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
            .previewDisplayName("iPhone SE")
        ContentView()
            .environmentObject(AppModel())
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
            .previewDisplayName("iPhone 14")
        ContentView()
            .environmentObject(AppModel())
            .previewDevice(PreviewDevice(rawValue: "iPhone 14 Pro Max"))
            .previewDisplayName("iPhone 14 Pro Max")
    }
}
