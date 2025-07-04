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
import PhotosUI
import Foundation
import UniformTypeIdentifiers
import CryptoKit

// Import the extraction function
// (Assume FieldExtraction.swift is in the same module)

// Struct for normalized ROI (percentages of width/height)
struct FieldROI {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

// Pixel-perfect ROIs for 2360x1640 screenshots (from user)
// Flight Number: top-left (8, 41.8), bottom-right (235, 147)
let flightNumberROI = FieldROI(x: 8/2360, y: 41.8/1640, width: (235-8)/2360, height: (147-41.8)/1640)
// Aircraft Type: top-left (28, 223), bottom-right (171, 297)
let aircraftTypeROI = FieldROI(x: 28/2360, y: 223/1640, width: (171-28)/2360, height: (297-223)/1640)
// Aircraft Reg: top-left (241, 223), bottom-right (352, 297)
let aircraftRegROI  = FieldROI(x: 241/2360, y: 223/1640, width: (352-241)/2360, height: (297-223)/1640)

// Helper to crop a UIImage to a normalized ROI
func cropImage(_ image: UIImage, to roi: FieldROI) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }
    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)
    let rect = CGRect(x: roi.x * width, y: roi.y * height, width: roi.width * width, height: roi.height * height)
    print("[DEBUG] Cropping image to rect: \(rect) for image size: \(width)x\(height)")
    guard let croppedCG = cgImage.cropping(to: rect) else { return nil }
    return UIImage(cgImage: croppedCG)
}

// Helper to run OCR on a cropped image
func ocrText(from image: UIImage, label: String, completion: @escaping (String) -> Void) {
    guard let cgImage = image.cgImage else {
        print("[DEBUG] [\(label)] Failed to get CGImage from UIImage.")
        completion("")
        return
    }
    let request = VNRecognizeTextRequest { request, error in
        if let error = error {
            print("[DEBUG] [\(label)] Vision OCR error: \(error)")
            completion("")
            return
        }
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            print("[DEBUG] [\(label)] No text observations found.")
            completion("")
            return
        }
        let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = recognizedStrings.joined(separator: ", ")
        print("[DEBUG] [\(label)] OCR recognized text: \(text)")
        completion(text)
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try handler.perform([request])
        } catch {
            print("[DEBUG] [\(label)] Vision request error: \(error)")
            completion("")
        }
    }
}

struct ContentView: View {
    @Binding var incomingImageURL: URL?
    @State private var recognizedText: String = ""
    @State private var showJSONAlert = false
    @State private var exportedJSON = ""
    @State private var showLogTenAlert = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var importedImage: UIImage? = nil
    @State private var isProcessingImage = false
    @State private var croppedFlightNumber: UIImage? = nil
    @State private var croppedAircraftType: UIImage? = nil
    @State private var croppedAircraftReg: UIImage? = nil
    @State private var ocrFlightNumber: String = ""
    @State private var ocrAircraftType: String = ""
    @State private var ocrAircraftReg: String = ""
    @State private var croppedDeparture: UIImage? = nil
    @State private var croppedArrival: UIImage? = nil
    @State private var croppedSchedDep: UIImage? = nil
    @State private var croppedSchedArr: UIImage? = nil
    @State private var ocrDeparture: String = ""
    @State private var ocrArrival: String = ""
    @State private var ocrSchedDep: String = ""
    @State private var ocrSchedArr: String = ""
    @State private var croppedDayDate: UIImage? = nil
    @State private var ocrDayDate: String = ""
    
    // Time state variables
    @State private var croppedOutTime: UIImage? = nil
    @State private var croppedOffTime: UIImage? = nil
    @State private var croppedOnTime: UIImage? = nil
    @State private var croppedInTime: UIImage? = nil
    @State private var ocrOutTime: String = ""
    @State private var ocrOffTime: String = ""
    @State private var ocrOnTime: String = ""
    @State private var ocrInTime: String = ""
    // Day and Date: top-left (480, 56), bottom-right (543, 130)
    let dayDateROI = FieldROI(x: 480/2360, y: 56/1640, width: (543-480)/2360, height: (130-56)/1640)
    // Use OCR values if screenshot is imported, otherwise fallback to regex extraction
    var flightNumber: String? {
        importedImage != nil ? ocrFlightNumber.trimmingCharacters(in: .whitespacesAndNewlines) : extractFlightNumber(from: recognizedText)
    }
    var departureAirport: String? {
        importedImage != nil ? ocrDeparture.trimmingCharacters(in: .whitespacesAndNewlines) : extractFlightNumber(from: recognizedText)
    }
    var arrivalAirport: String? {
        importedImage != nil ? ocrArrival.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
    // Helper to normalize aircraft registration (e.g., BLRU -> B-LRU)
    func normalizeAircraftReg(_ reg: String?) -> String? {
        guard let reg = reg?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !reg.isEmpty else { return nil }
        // Already normalized (B-xxxx)
        if reg.hasPrefix("B-") && reg.count == 5 { return reg }
        // 4-char (BLRU) or 5-char (B1234) starting with B, not already B-
        if reg.count == 4 && reg.hasPrefix("B") {
            let suffix = reg.dropFirst()
            return "B-" + suffix
        }
        if reg.count == 5 && reg.hasPrefix("B") && !reg.hasPrefix("B-") {
            let suffix = reg.dropFirst()
            return "B-" + suffix
        }
        return reg
    }
    var aircraftReg: String? {
        return normalizeAircraftReg(importedImage != nil ? ocrAircraftReg : extractAircraftRegistration(from: recognizedText))
    }
    // Helper to extract ICAO airport code from OCR string (e.g., "OERK, RUH" -> "OERK")
    func extractICAOCode(_ text: String) -> String? {
        let parts = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Look for 4-letter ICAO codes (A-Z only)
        for part in parts {
            if part.range(of: "^[A-Z]{4}$", options: .regularExpression) != nil {
                return part
            }
        }
        return nil
    }
    // Helper to extract reg from OCR string (e.g., "Reg, BLRU")
    func extractRegFromOCR(_ text: String) -> String? {
        let parts = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        // Pick the last part that matches 4-5 uppercase letters/numbers
        for part in parts.reversed() {
            if part.range(of: "^[A-Z0-9]{4,5}$", options: .regularExpression) != nil {
                // If starts with B and not already B-, format as B-LRU
                if part.hasPrefix("B") && !part.hasPrefix("B-") {
                    let suffix = part.dropFirst()
                    return "B-" + suffix
                }
                return part
            }
        }
        return nil
    }
    // Calibrated ROIs for 2360x1640 screenshots (from user)
    // Departure Airport: top-left (560, 60), bottom-right (641, 96)
    let departureROI = FieldROI(x: 560/2360, y: 60/1640, width: (641-560)/2360, height: (96-60)/1640)
    // Arrival Airport: top-left (807, 60), bottom-right (894, 96)
    let arrivalROI = FieldROI(x: 807/2360, y: 60/1640, width: (894-807)/2360, height: (96-60)/1640)
    // Scheduled Departure Time: top-left (647, 60), bottom-right (750, 96)
    let schedDepROI = FieldROI(x: 647/2360, y: 60/1640, width: (750-647)/2360, height: (96-60)/1640)
    // Scheduled Arrival Time: top-left (900, 60), bottom-right (1026, 96)
    let schedArrROI = FieldROI(x: 900/2360, y: 60/1640, width: (1026-900)/2360, height: (96-60)/1640)
    // AircraftReg: top-left (247, 258), bottom-right (330, 290)
    let aircraftRegROI = FieldROI(x: 247/2360, y: 258/1640, width: (330-247)/2360, height: (290-258)/1640)

// Time ROIs for OUT-OFF-ON-IN (adjusted to capture only time values, not labels)
let outTimeROI = FieldROI(x: 1970/2360, y: 1128/1640, width: (2055-1970)/2360, height: (1166-1128)/1640)
let offTimeROI = FieldROI(x: 1970/2360, y: 1170/1640, width: (2055-1970)/2360, height: (1208-1170)/1640)
let onTimeROI = FieldROI(x: 1970/2360, y: 1230/1640, width: (2055-1970)/2360, height: (1270-1230)/1640)
let inTimeROI = FieldROI(x: 1970/2360, y: 1270/1640, width: (2055-1970)/2360, height: (1305-1270)/1640)
    // Helper to extract Zulu time and check for +1 day indicator
    func extractZuluTime(_ text: String) -> (time: String?, isNextDay: Bool) {
        let parts = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for part in parts {
            if let match = part.range(of: "^[0-9]{4}Z(\\+1)?$", options: .regularExpression) {
                var zulu = String(part[match])
                let isNextDay = zulu.hasSuffix("+1")
                if isNextDay {
                    zulu = String(zulu.dropLast(2))
                }
                return (zulu, isNextDay)
            }
        }
        // fallback: just return the first part, stripped of +1 if present
        if let first = parts.first {
            var zulu = first
            let isNextDay = zulu.hasSuffix("+1")
            if isNextDay {
                zulu = String(zulu.dropLast(2))
            }
            return (zulu, isNextDay)
        }
        return (nil, false)
    }
    var scheduledDepartureZulu: String? {
        importedImage != nil ? extractZuluTime(ocrSchedDep).time : nil
    }
    var scheduledArrivalZulu: String? {
        importedImage != nil ? extractZuluTime(ocrSchedArr).time : nil
    }
    
    // Time field computed properties
    var outTime: String? {
        importedImage != nil ? extractOutTime(from: ocrOutTime) : nil
    }
    
    var offTime: String? {
        importedImage != nil ? extractOffTime(from: ocrOffTime) : nil
    }
    
    var onTime: String? {
        importedImage != nil ? extractOnTime(from: ocrOnTime) : nil
    }
    
    var inTime: String? {
        importedImage != nil ? extractInTime(from: ocrInTime) : nil
    }
    // Helper to infer the full date from OCR day-of-week and day-of-month
    func inferDate(dayOfWeek: String, dayOfMonth: Int, today: Date = Date()) -> Date? {
        let calendar = Calendar.current
        for offset in 0..<21 {
            guard let candidate = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekdaySymbol = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: candidate) - 1]
            let day = calendar.component(.day, from: candidate)
            if weekdaySymbol.lowercased().hasPrefix(dayOfWeek.lowercased()) && day == dayOfMonth {
                return candidate
            }
        }
        return nil // No match found
    }
    // Helper to parse OCR string like "Mon 30" or "30, Mon" into ("Mon", 30)
    func parseDayDate(_ text: String) -> (String, Int)? {
        // Accepts "Mon 30", "30 Mon", "Mon, 30", "30, Mon"
        let cleaned = text.replacingOccurrences(of: ",", with: " ")
        let parts = cleaned.split(separator: " ").map { String($0) }
        if parts.count == 2 {
            if let day = Int(parts[0]) {
                return (parts[1], day)
            } else if let day = Int(parts[1]) {
                return (parts[0], day)
            }
        }
        return nil
    }
    // Returns inferred date if possible
    var inferredDate: Date? {
        guard let (dow, dom) = parseDayDate(ocrDayDate) else { return nil }
        return inferDate(dayOfWeek: dow, dayOfMonth: dom)
    }
    // Helper to format scheduled time as dd/MM/yyyy HH:mm for LogTen
    func formatScheduledTime(ocrTime: String, fallback: String) -> String {
        guard let date = inferredDate else { return fallback }
        // Extract Zulu time and check for +1 day indicator
        let (zulu, isNextDay) = extractZuluTime(ocrTime)
        guard let zulu = zulu, zulu.count >= 5 else { return fallback }
        
        let hour = Int(zulu.prefix(2)) ?? 0
        let minute = Int(zulu.dropFirst(2).prefix(2)) ?? 0
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        
        // Add one day if +1 indicator is present
        if isNextDay {
            comps.day = (comps.day ?? 1) + 1
        }
        
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard let fullDate = Calendar.current.date(from: comps) else { return fallback }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: fullDate)
    }
    
    // Helper function to format actual times with full date-time
    func formatActualTime(ocrTime: String?, scheduledTime: String) -> String? {
        guard let ocrTime = ocrTime else { return nil }
        
        // Extract the date from the scheduled time (e.g., "30/06/2025 18:35")
        let scheduledComponents = scheduledTime.components(separatedBy: " ")
        guard scheduledComponents.count >= 2 else { return ocrTime }
        
        let datePart = scheduledComponents[0] // "30/06/2025"
        let timePart = ocrTime // "1852" or "1852z"
        
        // Remove 'z' or 'Z' from time if present
        let cleanTime = timePart.replacingOccurrences(of: "[zZ]", with: "", options: .regularExpression)
        
        // Format as HH:mm
        if cleanTime.count == 4 {
            let hour = String(cleanTime.prefix(2))
            let minute = String(cleanTime.suffix(2))
            let formattedTime = "\(hour):\(minute)"
            
            // Combine date and time
            return "\(datePart) \(formattedTime)"
        }
        
        return ocrTime
    }

    // Update logTenJSON to use all available aircraft info fields
    var logTenJSON: String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let dateString = dateFormatter.string(from: now)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: now)
        // Use inferred date + OCR time if possible, else fallback
        let scheduledDeparture = formatScheduledTime(ocrTime: ocrSchedDep, fallback: "\(dateString) \(timeString)")
        let scheduledArrival = formatScheduledTime(ocrTime: ocrSchedArr, fallback: "\(dateString) \(timeString)")
        let flightKey = generateFlightKey(
            date: scheduledDeparture.components(separatedBy: " ").first ?? dateString, // dd/MM/yyyy
            flightNumber: flightNumber ?? "TEST123",
            from: departureAirport ?? "VHHH",
            to: arrivalAirport ?? "OERK"
        )
        print("[DEBUG] Generated flight_key: \(flightKey)")
        
        let aircraftID = normalizeAircraftReg(importedImage != nil ? ocrAircraftReg : extractAircraftRegistration(from: recognizedText)) ?? "B-TEST"
        print("[DEBUG] Normalized Aircraft ID for export: \(aircraftID)")

        // Crew mapping logic
        var crewFields: [String: String] = [:]
        if crewNamesAndCodes.count > 0 {
            crewFields["flight_selectedCrewCommander"] = crewNamesAndCodes[0].name
        }
        if crewNamesAndCodes.count > 1 {
            crewFields["flight_selectedCrewSIC"] = crewNamesAndCodes[1].name
        }
        if crewNamesAndCodes.count == 3 {
            crewFields["flight_selectedCrewRelief2"] = crewNamesAndCodes[2].name
        }
        if crewNamesAndCodes.count == 4 {
            crewFields["flight_selectedCrewRelief"] = crewNamesAndCodes[2].name
            crewFields["flight_selectedCrewRelief2"] = crewNamesAndCodes[3].name
        }

        // Use flightKey in the exported entity
        let flightEntity: [String: Any?] = [
            "entity_name": "Flight",
            "flight_key": flightKey,
            "flight_flightNumber": flightNumber,
            "flight_from": departureAirport ?? "VHHH",
            "flight_to": arrivalAirport ?? "OERK",
            "flight_scheduledDepartureTime": scheduledDeparture,
            "flight_scheduledArrivalTime": scheduledArrival,
            "flight_selectedAircraftID": aircraftID,
            "flight_type": 0,
            "flight_customNote1": "\(departureAirport ?? "VHHH") - \(arrivalAirport ?? "OERK") \(flightNumber ?? "TEST123")",
            // Add actual times if available (with full date-time format)
            "flight_actualDepartureTime": formatActualTime(ocrTime: outTime, scheduledTime: scheduledDeparture),
            "flight_takeoffTime": formatActualTime(ocrTime: offTime, scheduledTime: scheduledDeparture),
            "flight_landingTime": formatActualTime(ocrTime: onTime, scheduledTime: scheduledArrival),
            "flight_actualArrivalTime": formatActualTime(ocrTime: inTime, scheduledTime: scheduledArrival)
        ].merging(crewFields) { $1 }
        
        let metadata: [String: Any] = [
            "application": "FlightCapture",
            "version": "1.0",
            "dateFormat": "dd/MM/yyyy",
            "dateAndTimeFormat": "dd/MM/yyyy HH:mm",
            "serviceID": "com.flightcapture.app",
            "numberOfEntities": 1,
            "timesAreZulu": true
        ]
        
        let payload: [String: Any] = [
            "metadata": metadata,
            "entities": [flightEntity.compactMapValues { $0 }]
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
    
    // Crew list ROI: top-left (26, 1205), bottom-right (460, 1395)
    let crewListROI = FieldROI(x: 26/2360, y: 1205/1640, width: (460-26)/2360, height: (1395-1205)/1640)

    @State private var croppedCrewList: UIImage? = nil
    @State private var ocrCrewList: String = ""
    // Helper to title-case a name (first letter of each word uppercase, rest lowercase)
    func titleCase(_ name: String) -> String {
        return name
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
    var crewNamesAndCodes: [(name: String, code: String)] {
        // Split by comma, trim, filter empty
        let items = ocrCrewList
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            // Remove all bullet and dot characters (• · ● ▪️ and similar)
            .map { $0.replacingOccurrences(of: "[\u{2022}\u{00b7}\u{25cf}\u{25aa}\u{fe0f}\u{2024}\u{2219}\u{2027}]", with: "", options: .regularExpression) }
            .map { $0.replacingOccurrences(of: "[^A-Za-z0-9 -]", with: "", options: .regularExpression) } // Remove extraneous except space and hyphen
        // Heuristic: codes are always at the end, one per name
        let codePattern = "^[0-9E]-[A-Z]{2}$"
        let codeCount = items.filter { $0.range(of: codePattern, options: .regularExpression) != nil }.count
        let nameCount = items.count - codeCount
        guard nameCount > 0, codeCount > 0, nameCount == codeCount else {
            // fallback: just return names, no codes, title-case names
            return items.map { (titleCase($0), "") }
        }
        let names = Array(items.prefix(nameCount)).map { titleCase($0) }
        let codes = Array(items.suffix(codeCount)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return zip(names, codes).map { ($0, $1) }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // CameraView(recognizedText: $recognizedText)
            //     .edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
                Text("Import Screenshot")
                    .font(.headline)
                    .padding(10)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Text("Import Screenshot")
                        .font(.headline)
                        .padding(10)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .onChange(of: selectedPhoto, initial: false) { _, newItem in
                    print("[DEBUG] User selected a photo: \(String(describing: newItem))")
                    if let newItem = newItem {
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                importedImage = uiImage
                                print("[DEBUG] Successfully loaded image from picker.")
                                // Crop to ROIs
                                croppedFlightNumber = cropImage(uiImage, to: flightNumberROI)
                                croppedAircraftType = cropImage(uiImage, to: aircraftTypeROI)
                                croppedAircraftReg  = cropImage(uiImage, to: aircraftRegROI)
                                // New fields: placeholder ROIs (update with real coordinates as needed)
                                croppedDeparture = cropImage(uiImage, to: departureROI)
                                croppedArrival = cropImage(uiImage, to: arrivalROI)
                                croppedSchedDep = cropImage(uiImage, to: schedDepROI)
                                croppedSchedArr = cropImage(uiImage, to: schedArrROI)
                                // Run OCR on each cropped region
                                if let img = croppedFlightNumber {
                                    ocrText(from: img, label: "FlightNumber") { text in
                                        DispatchQueue.main.async { ocrFlightNumber = text }
                                    }
                                }
                                if let img = croppedAircraftType {
                                    ocrText(from: img, label: "AircraftType") { text in
                                        DispatchQueue.main.async { ocrAircraftType = text }
                                    }
                                }
                                if let img = croppedAircraftReg {
                                    ocrText(from: img, label: "AircraftReg") { text in
                                        DispatchQueue.main.async { ocrAircraftReg = text }
                                    }
                                }
                                if let img = croppedDeparture {
                                    ocrText(from: img, label: "Departure") { text in
                                        DispatchQueue.main.async { ocrDeparture = text }
                                    }
                                }
                                if let img = croppedArrival {
                                    ocrText(from: img, label: "Arrival") { text in
                                        DispatchQueue.main.async { ocrArrival = text }
                                    }
                                }
                                if let img = croppedSchedDep {
                                    ocrText(from: img, label: "SchedDep") { text in
                                        DispatchQueue.main.async { ocrSchedDep = text }
                                    }
                                }
                                if let img = croppedSchedArr {
                                    ocrText(from: img, label: "SchedArr") { text in
                                        DispatchQueue.main.async { ocrSchedArr = text }
                                    }
                                }
                                croppedDayDate = cropImage(uiImage, to: dayDateROI)
                                if let img = croppedDayDate {
                                    ocrText(from: img, label: "DayDate") { text in
                                        DispatchQueue.main.async { ocrDayDate = text }
                                    }
                                }
                                
                                // Time field processing
                                croppedOutTime = cropImage(uiImage, to: outTimeROI)
                                croppedOffTime = cropImage(uiImage, to: offTimeROI)
                                croppedOnTime = cropImage(uiImage, to: onTimeROI)
                                croppedInTime = cropImage(uiImage, to: inTimeROI)
                                
                                if let img = croppedOutTime {
                                    ocrText(from: img, label: "OutTime") { text in
                                        DispatchQueue.main.async { ocrOutTime = text }
                                    }
                                }
                                if let img = croppedOffTime {
                                    ocrText(from: img, label: "OffTime") { text in
                                        DispatchQueue.main.async { ocrOffTime = text }
                                    }
                                }
                                if let img = croppedOnTime {
                                    ocrText(from: img, label: "OnTime") { text in
                                        DispatchQueue.main.async { ocrOnTime = text }
                                    }
                                }
                                if let img = croppedInTime {
                                    ocrText(from: img, label: "InTime") { text in
                                        DispatchQueue.main.async { ocrInTime = text }
                                    }
                                }
                                croppedCrewList = cropImage(uiImage, to: crewListROI)
                                if let img = croppedCrewList {
                                    ocrText(from: img, label: "CrewList") { text in
                                        DispatchQueue.main.async { ocrCrewList = text }
                                    }
                                }
                            } else {
                                print("[DEBUG] Failed to load image from picker.")
                            }
                        }
                    }
                }
                if let importedImage = importedImage {
                    Text("Screenshot Preview:")
                        .font(.headline)
                        .foregroundColor(.white)
                    Image(uiImage: importedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(12)
                        .padding(.bottom, 8)
                }
                // Show cropped debug previews
                HStack {
                    if let croppedFlightNumber = croppedFlightNumber {
                        VStack {
                            Text("Flight # ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedFlightNumber)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.yellow, width: 2)
                        }
                    }
                    if let croppedAircraftType = croppedAircraftType {
                        VStack {
                            Text("Type ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedAircraftType)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.orange, width: 2)
                        }
                    }
                    if let croppedAircraftReg = croppedAircraftReg {
                        VStack {
                            Text("Reg ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedAircraftReg)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.cyan, width: 2)
                        }
                    }
                }
                // New ROI debug previews
                HStack {
                    if let croppedDeparture = croppedDeparture {
                        VStack {
                            Text("Departure ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedDeparture)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.blue, width: 2)
                        }
                    }
                    if let croppedArrival = croppedArrival {
                        VStack {
                            Text("Arrival ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedArrival)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.purple, width: 2)
                        }
                    }
                    if let croppedSchedDep = croppedSchedDep {
                        VStack {
                            Text("Sched Dep ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedSchedDep)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.mint, width: 2)
                        }
                    }
                    if let croppedSchedArr = croppedSchedArr {
                        VStack {
                            Text("Sched Arr ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedSchedArr)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.teal, width: 2)
                        }
                    }
                }
                // Time field debug previews
                HStack {
                    if let croppedOutTime = croppedOutTime {
                        VStack {
                            Text("OUT Time ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedOutTime)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.red, width: 2)
                        }
                    }
                    if let croppedOffTime = croppedOffTime {
                        VStack {
                            Text("OFF Time ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedOffTime)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.pink, width: 2)
                        }
                    }
                    if let croppedOnTime = croppedOnTime {
                        VStack {
                            Text("ON Time ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedOnTime)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.indigo, width: 2)
                        }
                    }
                    if let croppedInTime = croppedInTime {
                        VStack {
                            Text("IN Time ROI")
                                .font(.caption)
                                .foregroundColor(.white)
                            Image(uiImage: croppedInTime)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .border(Color.brown, width: 2)
                        }
                    }
                }
                // Show OCR results for each field
                VStack(alignment: .leading) {
                    Text("Flight Number OCR: \(ocrFlightNumber)")
                        .foregroundColor(.yellow)
                    Text("Aircraft Type OCR: \(ocrAircraftType)")
                        .foregroundColor(.orange)
                    Text("Aircraft Reg OCR: \(ocrAircraftReg)")
                        .foregroundColor(.cyan)
                    Text("Departure OCR: \(ocrDeparture)")
                        .foregroundColor(.blue)
                    Text("Arrival OCR: \(ocrArrival)")
                        .foregroundColor(.purple)
                    Text("Sched Dep OCR: \(ocrSchedDep)")
                        .foregroundColor(.mint)
                    Text("Sched Arr OCR: \(ocrSchedArr)")
                        .foregroundColor(.teal)
                    Text("OUT Time OCR: \(ocrOutTime)")
                        .foregroundColor(.red)
                    Text("OFF Time OCR: \(ocrOffTime)")
                        .foregroundColor(.pink)
                    Text("ON Time OCR: \(ocrOnTime)")
                        .foregroundColor(.indigo)
                    Text("IN Time OCR: \(ocrInTime)")
                        .foregroundColor(.brown)
                }
                .padding(.vertical, 4)
                // Show extracted flight number/type/reg from OCR or regex
                if let flightNumber = flightNumber {
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
                if let departureAirport = departureAirport {
                    Text("Departure Airport: \(departureAirport)")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding(.bottom, 2)
                } else {
                    Text("Departure Airport: Not found")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding(.bottom, 2)
                }
                if let arrivalAirport = arrivalAirport {
                    Text("Arrival Airport: \(arrivalAirport)")
                        .font(.headline)
                        .foregroundColor(.purple)
                        .padding(.bottom, 2)
                } else {
                    Text("Arrival Airport: Not found")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding(.bottom, 2)
                }
                if let aircraftReg = aircraftReg {
                    Text("Aircraft Registration: \(aircraftReg)")
                        .font(.headline)
                        .foregroundColor(.cyan)
                        .padding(.bottom, 2)
                    

                } else {
                    Text("Aircraft Registration: Not found")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding(.bottom, 4)
                }
                
                // Show extracted time values
                VStack(alignment: .leading, spacing: 4) {
                    if let outTime = outTime {
                        Text("OUT Time: \(outTime)")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    if let offTime = offTime {
                        Text("OFF Time: \(offTime)")
                            .font(.subheadline)
                            .foregroundColor(.pink)
                    }
                    if let onTime = onTime {
                        Text("ON Time: \(onTime)")
                            .font(.subheadline)
                            .foregroundColor(.indigo)
                    }
                    if let inTime = inTime {
                        Text("IN Time: \(inTime)")
                            .font(.subheadline)
                            .foregroundColor(.brown)
                    }
                }
                .padding(.bottom, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crew List (parsed):")
                        .font(.headline)
                        .foregroundColor(.white)
                    if crewNamesAndCodes.isEmpty {
                        Text("No crew detected")
                            .foregroundColor(.red)
                    } else {
                        ForEach(Array(crewNamesAndCodes.enumerated()), id: \ .offset) { idx, pair in
                            Text("\(pair.name) [\(pair.code)]")
                                .foregroundColor(.cyan)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
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
                if flightNumber != nil && aircraftReg != nil && departureAirport != nil && arrivalAirport != nil {
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
                // Add debug preview for croppedDayDate
                if let croppedDayDate = croppedDayDate {
                    VStack {
                        Text("Day/Date ROI")
                            .font(.caption)
                            .foregroundColor(.white)
                        Image(uiImage: croppedDayDate)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 40)
                            .border(Color.gray, width: 2)
                    }
                }
            }
            .padding(.horizontal)
        }
        .onChange(of: incomingImageURL, initial: false) { _, newURL in
            print("[DEBUG] onChange incomingImageURL: \(String(describing: newURL))")
            if let url = newURL {
                do {
                    let data = try Data(contentsOf: url)
                    print("[DEBUG] Loaded data from URL: \(url), size: \(data.count) bytes")
                    if let uiImage = UIImage(data: data) {
                        print("[DEBUG] Created UIImage from data")
                        importedImage = uiImage
                        // Crop to ROIs
                        croppedFlightNumber = cropImage(uiImage, to: flightNumberROI)
                        croppedAircraftType = cropImage(uiImage, to: aircraftTypeROI)
                        croppedAircraftReg  = cropImage(uiImage, to: aircraftRegROI)
                        croppedDeparture = cropImage(uiImage, to: departureROI)
                        croppedArrival = cropImage(uiImage, to: arrivalROI)
                        croppedSchedDep = cropImage(uiImage, to: schedDepROI)
                        croppedSchedArr = cropImage(uiImage, to: schedArrROI)
                        croppedDayDate = cropImage(uiImage, to: dayDateROI)
                        croppedOutTime = cropImage(uiImage, to: outTimeROI)
                        croppedOffTime = cropImage(uiImage, to: offTimeROI)
                        croppedOnTime = cropImage(uiImage, to: onTimeROI)
                        croppedInTime = cropImage(uiImage, to: inTimeROI)
                        croppedCrewList = cropImage(uiImage, to: crewListROI)
                        // Run OCR on each cropped region
                        if let img = croppedFlightNumber {
                            ocrText(from: img, label: "FlightNumber") { text in
                                DispatchQueue.main.async { ocrFlightNumber = text }
                            }
                        }
                        if let img = croppedAircraftType {
                            ocrText(from: img, label: "AircraftType") { text in
                                DispatchQueue.main.async { ocrAircraftType = text }
                            }
                        }
                        if let img = croppedAircraftReg {
                            ocrText(from: img, label: "AircraftReg") { text in
                                DispatchQueue.main.async { ocrAircraftReg = text }
                            }
                        }
                        if let img = croppedDeparture {
                            ocrText(from: img, label: "Departure") { text in
                                DispatchQueue.main.async { ocrDeparture = text }
                            }
                        }
                        if let img = croppedArrival {
                            ocrText(from: img, label: "Arrival") { text in
                                DispatchQueue.main.async { ocrArrival = text }
                            }
                        }
                        if let img = croppedSchedDep {
                            ocrText(from: img, label: "SchedDep") { text in
                                DispatchQueue.main.async { ocrSchedDep = text }
                            }
                        }
                        if let img = croppedSchedArr {
                            ocrText(from: img, label: "SchedArr") { text in
                                DispatchQueue.main.async { ocrSchedArr = text }
                            }
                        }
                        if let img = croppedDayDate {
                            ocrText(from: img, label: "DayDate") { text in
                                DispatchQueue.main.async { ocrDayDate = text }
                            }
                        }
                        if let img = croppedOutTime {
                            ocrText(from: img, label: "OutTime") { text in
                                DispatchQueue.main.async { ocrOutTime = text }
                            }
                        }
                        if let img = croppedOffTime {
                            ocrText(from: img, label: "OffTime") { text in
                                DispatchQueue.main.async { ocrOffTime = text }
                            }
                        }
                        if let img = croppedOnTime {
                            ocrText(from: img, label: "OnTime") { text in
                                DispatchQueue.main.async { ocrOnTime = text }
                            }
                        }
                        if let img = croppedInTime {
                            ocrText(from: img, label: "InTime") { text in
                                DispatchQueue.main.async { ocrInTime = text }
                            }
                        }
                        if let img = croppedCrewList {
                            ocrText(from: img, label: "CrewList") { text in
                                DispatchQueue.main.async { ocrCrewList = text }
                            }
                        }
                    } else {
                        print("[DEBUG] Failed to create UIImage from data")
                    }
                } catch {
                    print("[DEBUG] Error loading data from URL: \(error)")
                }
            }
        }
    }
    
    func runOCR(on image: UIImage) {
        print("[DEBUG] Starting OCR on imported image...")
        isProcessingImage = true
        recognizedText = ""
        guard let cgImage = image.cgImage else {
            print("[DEBUG] Failed to get CGImage from UIImage.")
            isProcessingImage = false
            return
        }
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("[DEBUG] Vision OCR error: \(error)")
                isProcessingImage = false
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("[DEBUG] No text observations found.")
                isProcessingImage = false
                return
            }
            let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
            let text = recognizedStrings.joined(separator: ", ")
            print("[DEBUG] OCR recognized text: \(text)")
            DispatchQueue.main.async {
                recognizedText = text
                isProcessingImage = false
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("[DEBUG] Vision request error: \(error)")
                DispatchQueue.main.async { isProcessingImage = false }
            }
        }
    }
}

// Generate a robust, deterministic flight_key using date, flight number, from, and to
func generateFlightKey(date: String, flightNumber: String, from: String, to: String) -> String {
    let base = "\(date)_\(flightNumber)_\(from)_\(to)"
    let hash = SHA256.hash(data: Data(base.utf8))
    return "FC_" + hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16)
}

#Preview {
    ContentView(incomingImageURL: .constant(nil))
}
