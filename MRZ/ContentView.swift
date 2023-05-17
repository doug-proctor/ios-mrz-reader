//
//  ContentView.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 16/05/2023.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            HostedViewController()
        }
        .edgesIgnoringSafeArea(.vertical)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
