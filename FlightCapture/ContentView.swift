//
//  ContentView.swift
//  FlightCapture
//
//  Created by Kevin Smith on 29/6/2025.
//

import SwiftUI
import AVFoundation
import Vision
import UIKit

// Import the extraction function
// (Assume FieldExtraction.swift is in the same module)

struct CameraView: UIViewRepresentable {
    @Binding var recognizedText: String
    
    class CameraCoordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
        var parent: CameraView
        let session = AVCaptureSession()
        let videoOutput = AVCaptureVideoDataOutput()
        let queue = DispatchQueue(label: "camera.frame.processing")
        let visionQueue = DispatchQueue(label: "vision.ocr.queue")
        @Published var recognizedText: String = ""
        
        init(parent: CameraView) {
            self.parent = parent
            super.init()
            setupSession()
        }
        
        private func setupSession() {
            session.beginConfiguration()
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                print("Failed to setup camera input")
                return
            }
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            
            session.commitConfiguration()
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            let request = VNRecognizeTextRequest { [weak self] (request, error) in
                if let error = error {
                    print("Vision error: \(error)")
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = recognizedStrings.joined(separator: ", ")
                
                DispatchQueue.main.async {
                    self?.recognizedText = text
                    self?.parent.recognizedText = text
                }
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            visionQueue.async {
                do {
                    try requestHandler.perform([request])
                } catch {
                    print("Vision request error: \(error)")
                }
            }
        }
    }
    
    func makeCoordinator() -> CameraCoordinator {
        CameraCoordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: context.coordinator.session)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update binding
        context.coordinator.parent = self
    }
}

struct ContentView: View {
    @State private var recognizedText: String = ""
    @State private var showJSONAlert = false
    @State private var exportedJSON = ""
    @State private var showLogTenAlert = false
    
    // Computed properties for live extraction
    var extractedFlightNumber: String? {
        extractFlightNumber(from: recognizedText)
    }
    var extractedAircraftType: String? {
        extractAircraftType(from: recognizedText)
    }
    var extractedAircraftRegistration: String? {
        extractAircraftRegistration(from: recognizedText)
    }
    
    // Assemble LogTen-compatible JSON with metadata and required fields
    var logTenJSON: String {
        let flightKey = "RB_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let dateString = dateFormatter.string(from: now)
        let timeString = timeFormatter.string(from: now)
        let scheduledDeparture = "\(dateString) \(timeString)"
        let scheduledArrival = "\(dateString) \(timeString)"
        let entity: [String: Any?] = [
            "entity_name": "Flight",
            "flight_flightNumber": extractedFlightNumber ?? "TEST123",
            "flight_selectedAircraftType": extractedAircraftType ?? "A320",
            "flight_aircraftID": extractedAircraftRegistration ?? "B-TEST",
            "flight_from": "HKG", // Placeholder
            "flight_to": "LHR",   // Placeholder
            "flight_scheduledDepartureTime": scheduledDeparture,
            "flight_scheduledArrivalTime": scheduledArrival,
            "flight_type": 0,
            "flight_key": flightKey,
            "flight_customNote1": "HKG - LHR \(extractedFlightNumber ?? "TEST123")"
        ]
        let metadata: [String: Any] = [
            "application": "FlightCapture",
            "version": "1.0",
            "dateFormat": "dd/MM/yyyy",
            "dateAndTimeFormat": "dd/MM/yyyy HH:mm",
            "serviceID": "com.flightcapture.app",
            "numberOfEntities": 1,
            "timesAreZulu": false
        ]
        let payload: [String: Any] = [
            "metadata": metadata,
            "entities": [entity.compactMapValues { $0 }]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
    
    // Check if LogTen is installed
    func isLogTenProInstalled() -> Bool {
        let schemes = ["logten", "logtenprox", "logtenpro"]
        for scheme in schemes {
            if let url = URL(string: "\(scheme)://") {
                let canOpen = UIApplication.shared.canOpenURL(url)
                print("Checking URL scheme: \(scheme) -> \(canOpen)")
                if canOpen {
                    print("✅ Found working scheme: \(scheme)")
                    return true
                }
            } else {
                print("❌ Invalid URL for scheme: \(scheme)")
            }
        }
        print("❌ No valid LogTen Pro schemes found")
        return false
    }
    
    // Export to LogTen using URL scheme
    func exportToLogTen(jsonString: String) {
        let schemes = ["logten", "logtenprox", "logtenpro"]
        guard let encodedJson = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("❌ Failed to encode JSON for URL")
            return
        }
        for scheme in schemes {
            if let url = URL(string: "\(scheme)://v2/addEntities?package=\(encodedJson)") {
                let canOpen = UIApplication.shared.canOpenURL(url)
                print("Trying to open URL: \(url) -> canOpen: \(canOpen)")
                if canOpen {
                    print("✅ Opening LogTen with scheme: \(scheme)")
                    UIApplication.shared.open(url)
                    return
                }
            } else {
                print("❌ Invalid URL for scheme: \(scheme)")
            }
        }
        print("❌ Could not open LogTen with any scheme")
        showLogTenAlert = true
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            CameraView(recognizedText: $recognizedText)
                .edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
                Text("Live Camera Feed")
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                // Show extracted flight number
                if let flightNumber = extractedFlightNumber {
                    Text("Flight Number: \(flightNumber)")
                        .font(.headline)
                        .foregroundColor(.yellow)
                        .padding(.bottom, 2)
                } else {
                    Text("Flight Number: Not found")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding(.bottom, 2)
                }
                // Show extracted aircraft type
                if let aircraftType = extractedAircraftType {
                    Text("Aircraft Type: \(aircraftType)")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .padding(.bottom, 2)
                } else {
                    Text("Aircraft Type: Not found")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding(.bottom, 2)
                }
                // Show extracted aircraft registration
                if let aircraftReg = extractedAircraftRegistration {
                    Text("Aircraft Registration: \(aircraftReg)")
                        .font(.headline)
                        .foregroundColor(.cyan)
                        .padding(.bottom, 4)
                } else {
                    Text("Aircraft Registration: Not found")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding(.bottom, 4)
                }
                Button(action: {
                    exportedJSON = logTenJSON
                    showJSONAlert = true
                }) {
                    Text("Export as LogTen JSON")
                        .font(.headline)
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.bottom, 8)
                .alert(isPresented: $showJSONAlert) {
                    Alert(title: Text("LogTen JSON Export"), message: Text(exportedJSON), dismissButton: .default(Text("OK")))
                }
                // Send to LogTen button
                if extractedFlightNumber != nil && extractedAircraftType != nil && extractedAircraftRegistration != nil {
                    Button(action: {
                        if isLogTenProInstalled() {
                            exportToLogTen(jsonString: logTenJSON)
                        } else {
                            showLogTenAlert = true
                        }
                    }) {
                        Text("Send to LogTen")
                            .font(.headline)
                            .padding(10)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .alert(isPresented: $showLogTenAlert) {
                        Alert(title: Text("LogTen Not Installed"), message: Text("LogTen Pro is not installed on this device."), dismissButton: .default(Text("OK")))
                    }
                }
                ScrollView {
                    Text("Recognized Text:")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    Text(recognizedText.isEmpty ? "No text detected yet..." : recognizedText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.green)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .padding(.bottom, 20)
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    ContentView()
}
