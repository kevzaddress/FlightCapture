//
//  FlightCaptureApp.swift
//  FlightCapture
//
//  Created by Kevin Smith on 29/6/2025.
//

import SwiftUI

@main
struct FlightCaptureApp: App {
    @State private var incomingImageURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView(incomingImageURL: $incomingImageURL)
                .onOpenURL { url in
                    incomingImageURL = url
                }
        }
    }
}
