//
//  PassportOverlay.swift
//  MRZ
//
//  Created by doug.proctor@bidbax.no on 22/05/2023.
//

import SwiftUI

struct PassportOverlay: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        ZStack {
            PassportOutline()
                .stroke(.white, lineWidth: 4)
                .frame(width: overlayWidth, height: overlayHeight)
                .opacity(appModel.isScanComplete ? 0 : 1)
//                .scaleEffect(x: appModel.isScanComplete ? 1 : 1, y: appModel.isScanComplete ? 2 : 1)
                .animation(.easeIn(duration: 0.1), value: appModel.isScanComplete)
            
            MRZOutline()
                .stroke(.white, lineWidth: 4)
                .frame(width: overlayWidth, height: overlayHeight)
                .opacity(appModel.isScanComplete ? 0 : 1)
                .animation(.easeOut(duration: 0.1), value: appModel.isScanComplete)
            
            Image(systemName: "checkmark.circle.fill")
                .frame(width: 100, height: 100)
                .foregroundColor(.green)
                .font(.system(size: 130))
                .scaleEffect(x: appModel.isScanComplete ? 1 : 0, y: appModel.isScanComplete ? 1 : 0)
                .animation(.interpolatingSpring(stiffness: 800, damping: 30), value: appModel.isScanComplete)
            
//            HStack {
//                VStack(spacing: 0) {
//                    Circle()
//                        .stroke(.white, lineWidth: 4)
//                        .frame(width: 80, height: 80)
//                    RoundedRectangle(cornerRadius: 40)
//                        .stroke(.white, lineWidth: 4)
//                        .frame(width: 120, height: 50)
//                    Spacer()
//                }.padding(35)
//                Spacer()
//            }
//            .opacity(appModel.isScanComplete ? 0 : 1)
//            .animation(.easeOut(duration: 0.2), value: appModel.isScanComplete)
            
            VStack(spacing: 14) {
                Spacer()
                ChevronRow()
                ChevronRow()
            }
            .padding(14)
//            .scaleEffect(x: success ? 10 : 1, y: success ? 10 : 1, anchor: UnitPoint(x: 0.5, y: 0.87))
//            .blur(radius: success ? 1 : 0)
            .opacity(appModel.isScanComplete ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: appModel.isScanComplete)
        }
        .frame(width: overlayWidth, height: overlayHeight)
    }
}

struct Chevron: Shape {
    func path(in rect: CGRect) -> Path {
        return Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minX))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}

struct MRZOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = 20.0
        let prop = 0.74
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY * prop))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * prop))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX , y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * prop))
            path.closeSubpath()
        }
    }
}

struct PassportOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = 20.0
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX , y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
        }
    }
}

struct ChevronRow: View {
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<10) { _ in
                    Chevron()
                        .stroke(.white, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                        .frame(width: 6, height: 12)
                }
            }
            HStack(spacing: 10) {
                ForEach(0..<10) { _ in
                    Chevron()
                        .stroke(.white, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                        .frame(width: 6, height: 12)
                }
            }
        }
    }
}

struct PassportOverlay_Previews: PreviewProvider {
    static var previews: some View {
        PassportOverlay()
            .environmentObject(AppModel())
    }
}
