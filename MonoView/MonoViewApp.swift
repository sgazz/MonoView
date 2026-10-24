//
//  MonoViewApp.swift
//  MonoView
//
//  Created by Gazza on 21. 10. 2026..
//

import SwiftUI

@main
struct MonoViewApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-tilt") {
                TiltMenuTestHost()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}

#if DEBUG
private struct TiltMenuTestHost: View {
    @StateObject private var model = ViewerModel(tiltController: UITestTiltController())
    @State private var prepared = false

    var body: some View {
        ContentView(model: model)
            .task {
                guard !prepared else { return }
                prepared = true
                let data = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
                    UIColor.systemBlue.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 40, y: 80, width: 520, height: 440))
                    if !ProcessInfo.processInfo.arguments.contains("--ui-test-blank-photo") {
                        ("MonoView" as NSString).draw(at: CGPoint(x: 65, y: 110), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 46), .foregroundColor: UIColor.black])
                        for row in 0..<6 {
                            ("A clearer view, one hand." as NSString).draw(at: CGPoint(x: 65, y: 200 + row * 44), withAttributes: [.font: UIFont.systemFont(ofSize: 27), .foregroundColor: UIColor.black])
                        }
                    }
                    UIColor.systemRed.setFill()
                    context.fill(CGRect(x: 450, y: 100, width: 70, height: 70))
                }.pngData()
                await model.completeImport(data, id: model.beginImport())
                model.changeZoom(by: 2)
            }
    }
}

@MainActor
private final class UITestTiltController: TiltControlling {
    var sensitivity = 1.0
    func start(orientation: TiltOrientation, onMove: @escaping (CGSize) -> Void,
               onFailure: @escaping (String) -> Void) -> Bool { true }
    func stop() {}
    func recenter() {}
}
#endif
