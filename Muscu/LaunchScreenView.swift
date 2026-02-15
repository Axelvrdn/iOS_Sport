//
//  LaunchScreenView.swift
//  Muscu
//
//  Écran de lancement : logo Diamond sur fond noir, transition vers l'app.
//

import SwiftUI

struct LaunchScreenView: View {
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.85

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Image("DiamondLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                opacity = 1
                scale = 1
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
