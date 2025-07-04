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
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var importedImages: [UIImage] = []
    @State private var ocrResults: [String] = []
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
        let trimmed = ocrFlightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // fallback to regex/extraction from recognizedText
        return extractFlightNumber(from: recognizedText)
    }
    var departureAirport: String? {
        let trimmed = ocrDeparture.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // fallback to regex/extraction from recognizedText
        return extractDepartureAirport(from: recognizedText)
    }
    var arrivalAirport: String? {
        let trimmed = ocrArrival.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // fallback to regex/extraction from recognizedText
        return extractArrivalAirport(from: recognizedText)
    }
    var aircraftReg: String? {
        let trimmed = ocrAircraftReg.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return normalizeAircraftReg(trimmed) }
        // fallback to regex/extraction from recognizedText
        return normalizeAircraftReg(extractAircraftRegistration(from: recognizedText))
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
    
    // Time field computed properties with fallback
    var outTime: String? {
        let trimmed = ocrOutTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return extractOutTime(from: trimmed) }
        return extractOutTime(from: recognizedText)
    }
    
    var offTime: String? {
        let trimmed = ocrOffTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return extractOffTime(from: trimmed) }
        return extractOffTime(from: recognizedText)
    }
    
    var onTime: String? {
        let trimmed = ocrOnTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return extractOnTime(from: trimmed) }
        return extractOnTime(from: recognizedText)
    }
    
    var inTime: String? {
        let trimmed = ocrInTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return extractInTime(from: trimmed) }
        return extractInTime(from: recognizedText)
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
        
        let aircraftID = aircraftReg ?? "B-TEST"
        print("[DEBUG] Normalized Aircraft ID for export: \(aircraftID)")

        // Crew mapping logic (map parsed roles to LogTen fields)
        var crewFields: [String: String] = [:]
        for (role, name) in crewNamesAndCodes {
            print("[DEBUG] Processing crew role: '\(role)' -> '\(name)'")
            switch role.lowercased() {
            case "commander":
                crewFields["flight_selectedCrewCommander"] = name
                crewFields["flight_selectedCrewPIC"] = name
            case "sic":
                crewFields["flight_selectedCrewSIC"] = name
            case "relief":
                crewFields["flight_selectedCrewRelief"] = name
            case "relief2":
                crewFields["flight_selectedCrewRelief2"] = name
            case "custom1_ism":
                crewFields["flight_selectedCrewCustom1"] = name  // ISM
                print("[DEBUG] Assigned \(name) to flight_selectedCrewCustom1 (ISM)")
            case "custom2_so":
                crewFields["flight_selectedCrewCustom2"] = name  // SO
            case "custom3_stc":
                crewFields["flight_selectedCrewCustom3"] = name  // STC
            case "custom4_sp":
                crewFields["flight_selectedCrewCustom4"] = name  // SP
                print("[DEBUG] Assigned \(name) to flight_selectedCrewCustom4 (SP)")
            case "custom5_fp":
                crewFields["flight_selectedCrewCustom5"] = name  // FP
                print("[DEBUG] Assigned \(name) to flight_selectedCrewCustom5 (FP)")
            case "flightattendant":
                crewFields["flight_selectedCrewFlightAttendant"] = name  // Primary FA
                print("[DEBUG] Assigned \(name) to flight_selectedCrewFlightAttendant (Primary FA)")
            case "flightattendant2":
                crewFields["flight_selectedCrewFlightAttendant2"] = name
            case "flightattendant3":
                crewFields["flight_selectedCrewFlightAttendant3"] = name
            case "flightattendant4":
                crewFields["flight_selectedCrewFlightAttendant4"] = name
            default:
                break
            }
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
    
    // Step 4: Crew list ROIs (normalized for 2360x1640)
    let commanderROI = FieldROI(x: 175/2360, y: 331/1640, width: (596-175)/2360, height: (538-331)/1640)
    let sicROI = FieldROI(x: 1212/2360, y: 331/1640, width: (1624-1212)/2360, height: (538-331)/1640)
    let reliefROI = FieldROI(x: 695/2360, y: 331/1640, width: (1111-695)/2360, height: (538-331)/1640)
    let relief2ROI = FieldROI(x: 1724/2360, y: 331/1640, width: (2140-1724)/2360, height: (538-331)/1640)
    let crewCustom1ROI = FieldROI(x: 1205/2360, y: 705/1640, width: (1674-1205)/2360, height: (850-705)/1640)
    let crewCustom2ROI = FieldROI(x: 175/2360, y: 705/1640, width: (635-175)/2360, height: (850-705)/1640)
    let crewCustom4ROI = FieldROI(x: 695/2360, y: 705/1640, width: (1154-695)/2360, height: (850-705)/1640)
    let crewFlightAttendantROI = FieldROI(x: 1715/2360, y: 705/1640, width: (2180-1715)/2360, height: (850-705)/1640)
    let crewFlightAttendant2ROI = FieldROI(x: 175/2360, y: 900/1640, width: (635-175)/2360, height: (1050-900)/1640)
    let crewFlightAttendant3ROI = FieldROI(x: 695/2360, y: 896/1640, width: (1153-695)/2360, height: (1053-896)/1640)
    let crewFlightAttendant4ROI = FieldROI(x: 1205/2360, y: 900/1640, width: (1672-1205)/2360, height: (1050-900)/1640)
    
    // Dashboard crew names ROI (for single image import)
    let dashboardCrewNamesROI = FieldROI(x: 26/2360, y: 1205/1640, width: (460-26)/2360, height: (1395-1205)/1640)
    
    @State private var parsedCrewList: [String] = []
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
    // Returns [(role, name)] for each parsed crew ROI result, extracting and title-casing the name
    var crewNamesAndCodes: [(role: String, name: String)] {
        parsedCrewList.compactMap { line in
            // Split "Role: OCRText"
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { return nil }
            let role = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let ocrText = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // For dashboard crew parsing, the name is directly after the colon
            // For crew list parsing, the name might be in a comma-separated list
            let name: String
            if ocrText.contains(",") {
                // Split OCR text by comma, trim, and filter empty
                let fields = ocrText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                // The name is usually the second field
                name = fields.count > 1 ? titleCase(fields[1]) : titleCase(fields.first ?? "")
            } else {
                // Direct name after colon (dashboard crew parsing)
                name = titleCase(ocrText)
            }
            
            print("[DEBUG] crewNamesAndCodes: role='\(role)', ocrText='\(ocrText)', name='\(name)'")
            return (role, name)
        }
    }
    
    // Step 3: Classification of each image as 'crewList' or 'dashboard'
    @State private var imageTypes: [String] = [] // 'crewList' or 'dashboard'
    
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
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 2, // Allow up to 2 images
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text("Import Screenshots")
                        .font(.headline)
                        .padding(10)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .onChange(of: selectedPhotos, initial: false) { _, newItems in
                    print("[DEBUG] User selected photos: \(newItems.map { String(describing: $0) })")
                    importedImages = []
                    ocrResults = []
                    imageTypes = []
                    parsedCrewList = []
                    // Temporary holders for dashboard/crewList images
                    var dashboardImage: UIImage? = nil
                    var crewListImage: UIImage? = nil
                    // Load and classify images
                    for (idx, item) in newItems.enumerated() {
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                print("[DEBUG] Loaded image #\(idx+1) from picker, size: \(uiImage.size)")
                                DispatchQueue.main.async {
                                    importedImages.append(uiImage)
                                }
                                // Run OCR on the full image (no cropping yet)
                                ocrText(from: uiImage, label: "FullImage#\(idx+1)") { text in
                                    DispatchQueue.main.async {
                                        print("[DEBUG] OCR result for image #\(idx+1): \(text.prefix(100))...")
                                        ocrResults.append(text)
                                        // Classification logic
                                        let lowerText = text.lowercased()
                                        let type: String
                                        if lowerText.contains("cockpit crew") || lowerText.contains("cabin crew") {
                                            type = "crewList"
                                            crewListImage = uiImage
                                        } else if lowerText.contains("fmc & ats") || lowerText.contains("out") || lowerText.contains("dashboard") {
                                            type = "dashboard"
                                            dashboardImage = uiImage
                                        } else {
                                            type = "unknown"
                                        }
                                        imageTypes.append(type)
                                        print("[DEBUG] Image #\(idx+1) classified as: \(type)")
                                        // After all images are classified, process ROIs
                                        if imageTypes.count == newItems.count {
                                            // If only one image, treat as dashboard and process both dashboard and crew ROIs
                                            if newItems.count == 1, let img = importedImages.first {
                                                processDashboardROIs(from: img)
                                                processDashboardCrewROIs(from: img)  // Use dashboard-specific crew ROIs
                                            } else if newItems.count == 2 {
                                                // Two images: process dashboard for flight details, crewList for crew
                                                if let dashImg = dashboardImage {
                                                    processDashboardROIs(from: dashImg)
                                                }
                                                if let crewImg = crewListImage {
                                                    processCrewROIs(from: crewImg)
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                print("[DEBUG] Failed to load image #\(idx+1) from picker.")
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
                // Place Export button here
                Button(action: {
                    exportedJSON = logTenJSON
                    showJSONAlert = true
                }) {
                    Text("Export as LogTen JSON")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .padding(.bottom, 8)
                .alert(isPresented: $showJSONAlert) {
                    Alert(title: Text("LogTen JSON Export"), message: Text(exportedJSON), dismissButton: .default(Text("OK")))
                }
                // Place Send to LogTen button here (no ScrollView)
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
                // Crew List (parsed)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crew List (parsed):")
                        .font(.headline)
                        .foregroundColor(.white)
                    ForEach(parsedCrewList, id: \ .self) { crew in
                        Text(crew)
                            .foregroundColor(.cyan)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
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
    
    // Helper to update parsedCrewList after all OCRs
    func updateParsedCrewList(cockpitResults: [(String, String)], cabinResults: [(String, String)]) {
        let nonEmptyCockpit = cockpitResults.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let nonEmptyCabin = cabinResults.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        parsedCrewList = []
        // Cockpit assignment logic
        if nonEmptyCockpit.count == 4 {
            parsedCrewList.append("Commander: \(nonEmptyCockpit[0].1)")
            parsedCrewList.append("Relief: \(nonEmptyCockpit[1].1)")
            parsedCrewList.append("SIC: \(nonEmptyCockpit[2].1)")
            parsedCrewList.append("Relief2: \(nonEmptyCockpit[3].1)")
        } else if nonEmptyCockpit.count == 3 {
            parsedCrewList.append("Commander: \(nonEmptyCockpit[0].1)")
            parsedCrewList.append("SIC: \(nonEmptyCockpit[1].1)")
            parsedCrewList.append("Relief2: \(nonEmptyCockpit[2].1)")
        } else if nonEmptyCockpit.count == 2 {
            parsedCrewList.append("Commander: \(nonEmptyCockpit[0].1)")
            parsedCrewList.append("SIC: \(nonEmptyCockpit[1].1)")
        } else {
            for (role, text) in nonEmptyCockpit {
                parsedCrewList.append("\(role): \(text)")
            }
        }
        // Cabin crew assignment (append after cockpit)
        for (role, text) in nonEmptyCabin {
            parsedCrewList.append("\(role): \(text)")
        }
    }
    
    // Helper: process all flight detail ROIs from dashboard image
    func processDashboardROIs(from uiImage: UIImage) {
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
    }
    
    // Helper: process crew ROIs from dashboard image (using original dashboard crew ROI)
    func processDashboardCrewROIs(from uiImage: UIImage) {
        print("[DEBUG] Processing dashboard crew ROIs using dashboardCrewNamesROI")
        
        // Crop the dashboard crew names section
        if let cropped = cropImage(uiImage, to: dashboardCrewNamesROI) {
            ocrText(from: cropped, label: "DashboardCrewNames") { crewText in
                DispatchQueue.main.async {
                    print("[DEBUG] Dashboard crew names OCR: \(crewText)")
                    
                    // Parse the crew text and extract names
                    let crewNames = self.parseDashboardCrewText(crewText)
                    
                    // Create parsed crew list entries
                    self.parsedCrewList = []
                    print("[DEBUG] Creating parsed crew list with \(crewNames.count) names")
                    for (index, name) in crewNames.enumerated() {
                        switch index {
                        case 0:
                            self.parsedCrewList.append("Commander: \(name)")
                            print("[DEBUG] Added Commander: \(name)")
                        case 1:
                            self.parsedCrewList.append("SIC: \(name)")
                            print("[DEBUG] Added SIC: \(name)")
                        case 2:
                            self.parsedCrewList.append("Relief: \(name)")
                            print("[DEBUG] Added Relief: \(name)")
                        case 3:
                            self.parsedCrewList.append("Relief2: \(name)")
                            print("[DEBUG] Added Relief2: \(name)")
                        default:
                            break
                        }
                    }
                    print("[DEBUG] Final parsedCrewList: \(self.parsedCrewList)")
                }
            }
        } else {
            print("[DEBUG] Failed to crop dashboard crew names ROI")
        }
    }
    
    // Helper function to parse crew names from dashboard crew ROI text
    func parseDashboardCrewText(_ text: String) -> [String] {
        var crewNames: [String] = []
        
        print("[DEBUG] Parsing dashboard crew text: '\(text)'")
        
        // Split by common separators used in crew lists
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ",~•@"))
        
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[DEBUG] Processing part: '\(trimmed)'")
            
            // Look for patterns that look like names (2+ words, starts with letter)
            let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if words.count >= 2 {
                let firstWord = words[0]
                let secondWord = words[1]
                
                print("[DEBUG] Checking words: '\(firstWord)' '\(secondWord)'")
                
                // Check if it looks like a name (starts with letter)
                if firstWord.first?.isLetter == true && 
                   secondWord.first?.isLetter == true {
                    
                    let name = titleCase("\(firstWord) \(secondWord)")
                    print("[DEBUG] Found name: '\(name)'")
                    if !crewNames.contains(name) && crewNames.count < 4 {
                        crewNames.append(name)
                        print("[DEBUG] Added name: '\(name)' to crew list")
                    }
                }
            }
        }
        
        print("[DEBUG] Final crew names: \(crewNames)")
        return crewNames
    }
    
    // Helper: process all crew ROIs from crew image
    func processCrewROIs(from uiImage: UIImage) {
        // Cockpit crew logic: OCR all 4, then assign roles after all are done
        let cockpitROIs: [(String, FieldROI)] = [
            ("Commander", commanderROI),
            ("Relief", reliefROI),
            ("SIC", sicROI),
            ("Relief2", relief2ROI)
        ]
        // Cabin crew ROIs and roles
        let cabinROIs: [(String, FieldROI)] = [
            ("Custom5_FP", crewCustom1ROI),   // FP role (Charmaine Fong)
            ("Custom1_ISM", crewCustom2ROI),  // ISM role (Aries Yip)
            ("Custom4_SP", crewCustom4ROI),   // SP role (Christie Leung)
            ("FlightAttendant", crewFlightAttendantROI),    // Primary FA (Michelle Liu)
            ("FlightAttendant2", crewFlightAttendant2ROI),  // FA2 (Venus Siu)
            ("FlightAttendant3", crewFlightAttendant3ROI),  // FA3 (Charlie Hui)
            ("FlightAttendant4", crewFlightAttendant4ROI)   // FA4 (Edmund Leung)
        ]
        var cockpitResults: [(String, String)] = Array(repeating: ("", ""), count: 4)
        var cabinResults: [(String, String)] = Array(repeating: ("", ""), count: cabinROIs.count)
        var completed = 0
        let totalToComplete = 4 + cabinROIs.count
        // Cockpit crew OCR
        for i in 0..<4 {
            let (role, roi) = cockpitROIs[i]
            if let cropped = cropImage(uiImage, to: roi) {
                ocrText(from: cropped, label: "Crew_\(role)_ROI") { crewText in
                    DispatchQueue.main.async {
                        cockpitResults[i] = (role, crewText)
                        completed += 1
                        if completed == totalToComplete {
                            updateParsedCrewList(cockpitResults: cockpitResults, cabinResults: cabinResults)
                        }
                    }
                }
            } else {
                print("[DEBUG] Failed to crop ROI for \(role) on crew image")
                completed += 1
            }
        }
        // Cabin crew OCR
        for i in 0..<cabinROIs.count {
            let (role, roi) = cabinROIs[i]
            if let cropped = cropImage(uiImage, to: roi) {
                ocrText(from: cropped, label: "Crew_\(role)_ROI") { crewText in
                    DispatchQueue.main.async {
                        cabinResults[i] = (role, crewText)
                        completed += 1
                        if completed == totalToComplete {
                            updateParsedCrewList(cockpitResults: cockpitResults, cabinResults: cabinResults)
                        }
                    }
                }
            } else {
                print("[DEBUG] Failed to crop ROI for \(role) on crew image")
                completed += 1
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
