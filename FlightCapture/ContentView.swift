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
    
    // Edited values state variables (Phase 1)
    @State private var editedFlightNumber: String = ""
    @State private var editedAircraftReg: String = ""
    @State private var editedDeparture: String = ""
    @State private var editedArrival: String = ""
    @State private var editedOutTime: String = ""
    @State private var editedOffTime: String = ""
    @State private var editedOnTime: String = ""
    @State private var editedInTime: String = ""
    @State private var editedDate: Date? = nil
    
    // Day and Date: top-left (480, 56), bottom-right (543, 130)
    let dayDateROI = FieldROI(x: 480/2360, y: 56/1640, width: (543-480)/2360, height: (130-56)/1640)
    // Use OCR values if screenshot is imported, otherwise fallback to regex extraction
    var flightNumber: String? {
        // Use edited value if available, otherwise use OCR
        if !editedFlightNumber.isEmpty { return editedFlightNumber }
        let trimmed = ocrFlightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // fallback to regex/extraction from recognizedText
        return extractFlightNumber(from: recognizedText)
    }
    var departureAirport: String? {
        // Use edited value if available, otherwise use OCR
        if !editedDeparture.isEmpty { return editedDeparture }
        let trimmed = ocrDeparture.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // fallback to regex/extraction from recognizedText
        return extractDepartureAirport(from: recognizedText)
    }
    var arrivalAirport: String? {
        // Use edited value if available, otherwise use OCR
        if !editedArrival.isEmpty { return editedArrival }
        let trimmed = ocrArrival.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // fallback to regex/extraction from recognizedText
        return extractArrivalAirport(from: recognizedText)
    }
    var aircraftReg: String? {
        // Use edited value if available, otherwise use OCR
        if !editedAircraftReg.isEmpty { return editedAircraftReg }
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
        // Use edited value if available, otherwise use OCR
        if !editedOutTime.isEmpty { return editedOutTime }
        let trimmed = ocrOutTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return extractOutTime(from: trimmed) }
        return extractOutTime(from: recognizedText)
    }
    
    var offTime: String? {
        // Use edited value if available, otherwise use OCR
        if !editedOffTime.isEmpty { return editedOffTime }
        let trimmed = ocrOffTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return extractOffTime(from: trimmed) }
        return extractOffTime(from: recognizedText)
    }
    
    var onTime: String? {
        // Use edited value if available, otherwise use OCR
        if !editedOnTime.isEmpty { return editedOnTime }
        let trimmed = ocrOnTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return extractOnTime(from: trimmed) }
        return extractOnTime(from: recognizedText)
    }
    
    var inTime: String? {
        // Use edited value if available, otherwise use OCR
        if !editedInTime.isEmpty { return editedInTime }
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
        // Use edited date if available, otherwise infer from OCR
        if let editedDate = editedDate {
            return editedDate
        }
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
    func generateLogTenJSON(
        cockpitCrew: [CrewMember]? = nil,
        cabinCrew: [CrewMember]? = nil
    ) -> String {
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

        // Use the passed-in arrays if provided, else fall back to state
        let cockpit = cockpitCrew ?? (!editedCockpitCrew.isEmpty ? editedCockpitCrew : cockpitCrewDisplay.map { CrewMember(role: $0.role, name: $0.name) })
        let cabin = cabinCrew ?? (!editedCabinCrew.isEmpty ? editedCabinCrew : cabinCrewDisplay.map { CrewMember(role: $0.role, name: $0.name) })
        
        // Build a role->name dictionary from the edited arrays
        var crewDict: [String: String] = [:]
        for member in cockpit { crewDict[member.role] = member.name }
        for member in cabin { crewDict[member.role] = member.name }

        // Now use crewDict for mapping
        var crewFields: [String: String] = [:]
        for (role, logtenField) in [
            ("PIC", "flight_selectedCrewPIC"),
            ("Commander", "flight_selectedCrewCommander"),
            ("SIC", "flight_selectedCrewSIC"),
            ("Relief", "flight_selectedCrewRelief"),
            ("Relief2", "flight_selectedCrewRelief2"),
            ("ISM", "flight_selectedCrewCustom1"),
            ("SP", "flight_selectedCrewCustom4"),
            ("FP", "flight_selectedCrewCustom5"),
            ("FA", "flight_selectedCrewFlightAttendant"),
            ("FA2", "flight_selectedCrewFlightAttendant2"),
            ("FA3", "flight_selectedCrewFlightAttendant3"),
            ("FA4", "flight_selectedCrewFlightAttendant4")
        ] {
            if let name = crewDict[role], !name.isEmpty {
                crewFields[logtenField] = name
                print("[DEBUG] Assigned \(name) to \(logtenField) (\(role))")
            }
        }
        
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
    let crewCommanderROI = FieldROI(x: 180/2360, y: 380/1640, width: (645-180)/2360, height: (420-380)/1640)
    let crewSICROI = FieldROI(x: 685/2360, y: 380/1640, width: (1155-685)/2360, height: (420-380)/1640)
    let crewReliefROI = FieldROI(x: 1205/2360, y: 380/1640, width: (1675-1205)/2360, height: (420-380)/1640)
    let crewRelief2ROI = FieldROI(x: 1720/2360, y: 380/1640, width: (2185-1720)/2360, height: (420-380)/1640)
    let crewCustom2ISMROI = FieldROI(x: 180/2360, y: 750/1640, width: (645-180)/2360, height: (796-750)/1640)
    let crewCustom4SPROI = FieldROI(x: 685/2360, y: 750/1640, width: (1155-685)/2360, height: (796-750)/1640)
    let crewCustom1FPROI = FieldROI(x: 1205/2360, y: 750/1640, width: (1675-1205)/2360, height: (796-750)/1640)
    let crewFlightAttendantROI = FieldROI(x: 1720/2360, y: 750/1640, width: (2185-1720)/2360, height: (796-750)/1640)
    let crewFlightAttendant2ROI = FieldROI(x: 180/2360, y: 950/1640, width: (645-180)/2360, height: (995-950)/1640)
    let crewFlightAttendant3ROI = FieldROI(x: 685/2360, y: 950/1640, width: (1155-685)/2360, height: (995-950)/1640)
    let crewFlightAttendant4ROI = FieldROI(x: 1205/2360, y: 950/1640, width: (1675-1205)/2360, height: (995-950)/1640)
    
    // Dashboard crew names ROI (for single image import)
    let dashboardCrewNamesROI = FieldROI(x: 26/2360, y: 1205/1640, width: (460-26)/2360, height: (1395-1205)/1640)
    
    @State private var parsedCrewList: [String] = []
    @State private var cockpitCrewDisplay: [(role: String, name: String)] = []
    @State private var cabinCrewDisplay: [(role: String, name: String)] = []
    struct CrewNameReview: Identifiable {
        let id = UUID()
        let role: String
        let original: String
        var corrected: String
    }

    @State private var crewNamesNeedingReview: [CrewNameReview] = []
    @State private var showCrewReviewSheet = false
    @State private var showReviewAllDataSheet = false
    
    // Update extractCrewName to remove trailing dots and flag for review
    func extractCrewName(from ocrText: String, role: String? = nil) -> String {
        print("[DEBUG] extractCrewName called for role: \(role ?? "nil") with OCR text: '", ocrText, "'")
        let knownBases = ["HKG", "SIN", "BKK", "ICN", "KIX", "LAX", "JFK", "LHR", "CDG", "SYD", "MEL", "DXB", "FRA", "SFO", "ORD", "NRT", "CAN", "SZX", "PVG", "PEK", "DEL", "BOM", "AMS", "ZRH", "YYZ", "YVR", "YUL", "YVR", "YVR", "YVR"]
        let parts = ocrText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nameParts = parts.filter { part in
            let upper = part.uppercased()
            return !knownBases.contains(upper) && upper.range(of: "^[A-Z\\s\\-\\.]+$", options: .regularExpression) != nil && upper.count > 1
        }
        var name = nameParts.joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
        let original = name
        print("[DEBUG] Extracted name: '", name, "' from OCR text: '", ocrText, "'")
        // Remove trailing dots
        if let dotRange = name.range(of: "[.]+$", options: .regularExpression) {
            print("[DEBUG] Trailing dots detected in name: '", name, "'")
            name.removeSubrange(dotRange)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let role = role, !name.isEmpty {
                // Add to review list if not already present
                if !crewNamesNeedingReview.contains(where: { $0.role == role }) {
                    print("[DEBUG] Adding to crewNamesNeedingReview: role=\(role), original=\(original), corrected=\(name)")
                    crewNamesNeedingReview.append(CrewNameReview(role: role, original: original, corrected: name))
                }
            }
        }
        return name.capitalized
    }

    // Update crewNamesAndCodes to use consistent role names and correct order
    var crewNamesAndCodes: [(role: String, name: String)] {
        [
            ("Commander", extractCrewName(from: ocrCrewCommander, role: "Commander")),
            ("SIC", extractCrewName(from: ocrCrewSIC, role: "SIC")),
            ("Relief", extractCrewName(from: ocrCrewRelief, role: "Relief")),
            ("Relief2", extractCrewName(from: ocrCrewRelief2, role: "Relief2")),
            ("ISM", extractCrewName(from: ocrCrewCustom2ISM, role: "ISM")),
            ("SP", extractCrewName(from: ocrCrewCustom4SP, role: "SP")),
            ("FP", extractCrewName(from: ocrCrewCustom1FP, role: "FP")),
            ("FlightAttendant", extractCrewName(from: ocrCrewFlightAttendant, role: "FlightAttendant")),
            ("FlightAttendant2", extractCrewName(from: ocrCrewFlightAttendant2, role: "FlightAttendant2")),
            ("FlightAttendant3", extractCrewName(from: ocrCrewFlightAttendant3, role: "FlightAttendant3")),
            ("FlightAttendant4", extractCrewName(from: ocrCrewFlightAttendant4, role: "FlightAttendant4")),
        ]
    }

    // Step 3: Classification of each image as 'crewList' or 'dashboard'
    @State private var imageTypes: [String] = [] // 'crewList' or 'dashboard'
    
    @State private var ocrFieldHighlight: String? = nil
    
    @State private var ocrCrewCommander: String = ""
    @State private var ocrCrewSIC: String = ""
    @State private var ocrCrewRelief: String = ""
    @State private var ocrCrewRelief2: String = ""
    @State private var ocrCrewCustom2ISM: String = ""
    @State private var ocrCrewCustom4SP: String = ""
    @State private var ocrCrewCustom1FP: String = ""
    @State private var ocrCrewFlightAttendant: String = ""
    @State private var ocrCrewFlightAttendant2: String = ""
    @State private var ocrCrewFlightAttendant3: String = ""
    @State private var ocrCrewFlightAttendant4: String = ""
    
    // Add state for showing action sheets for each crew member
    @State private var cockpitRoleSheetIndex: Int? = nil
    @State private var cabinRoleSheetIndex: Int? = nil
    
    // ... inside struct ContentView, with other @State variables ...
    @State private var editedCockpitCrew: [CrewMember] = []
    @State private var editedCabinCrew: [CrewMember] = []
    // ... rest of @State variables ...
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                                Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.teal)
                        
                        Text("Flight Capture")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Import flight screenshots and export to LogTen Pro")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Import Section
                    VStack(spacing: 16) {
                        PhotosPicker(
                            selection: $selectedPhotos,
                            maxSelectionCount: 2,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title2)
                                Text("Import Screenshots")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.teal)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(color: Color.teal.opacity(0.18), radius: 6, x: 0, y: 3)
                            .accessibilityLabel("Import flight screenshots")
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Text("Select 1-2 screenshots (dashboard + crew list)")
                                    .font(.caption)
                            .foregroundColor(.secondary)
                            }
                    .padding(.horizontal)
                .onChange(of: selectedPhotos, initial: false) { _, newItems in
                    handlePhotoSelection(newItems)
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
                    // Export Section
                    if flightNumber != nil && aircraftReg != nil && departureAirport != nil && arrivalAirport != nil {
                        VStack(spacing: 16) {
                            // Review All Data button (Phase 2)
                            Button(action: {
                                print("[DEBUG] Opening Review All Data modal")
                                showReviewAllDataSheet = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "checklist")
                                        .font(.title2)
                                    Text("Review All Data")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(14)
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                // Check if any names need review first
                                if checkCrewNamesForReview() {
                                    print("[DEBUG] Names need review, showing modal. Count: \(crewNamesNeedingReview.count)")
                                    DispatchQueue.main.async {
                                        showCrewReviewSheet = true
                                    }
                                } else if isLogTenProInstalled() {
                                    exportToLogTen(jsonString: generateLogTenJSON())
                        } else {
                                    showLogTenAlert = true
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "paperplane.fill")
                                        .font(.title2)
                                    Text("Export to LogTen Pro")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    LinearGradient(gradient: Gradient(colors: [Color.teal, Color.cyan]), startPoint: .leading, endPoint: .trailing)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .shadow(color: Color.teal.opacity(0.18), radius: 6, x: 0, y: 3)
                                .accessibilityLabel("Export flight to LogTen Pro")
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Text("Flight data ready for export")
                                    .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        .padding(.horizontal)
                        .alert(isPresented: $showLogTenAlert) {
                            Alert(
                                title: Text("LogTen Pro Not Found"),
                                message: Text("LogTen Pro is not installed on this device. Please install it from the App Store."),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                    }
                    
                    // Flight Data Preview Section
                    if flightNumber != nil || aircraftReg != nil || departureAirport != nil || arrivalAirport != nil || outTime != nil || offTime != nil || onTime != nil || inTime != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "airplane.departure")
                                    .foregroundColor(.teal)
                                Text("Flight Details")
                                    .font(.headline)
                            }
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                if let flightNumber = flightNumber {
                                    FlightDataCard(
                                        icon: "number.circle.fill",
                                        title: "Flight",
                                        value: flightNumber,
                                        color: .teal,
                                        highlight: ocrFieldHighlight == "flightNumber",
                                        onEdit: { newValue in
                                            print("[DEBUG] Flight number edited: \(newValue)")
                                            editedFlightNumber = newValue
                                        }
                                    )
                                }
                                
                                if let aircraftReg = aircraftReg {
                                    FlightDataCard(
                                        icon: "airplane.circle.fill",
                                        title: "Aircraft",
                                        value: aircraftReg,
                                        color: .teal,
                                        highlight: ocrFieldHighlight == "aircraftReg",
                                        onEdit: { newValue in
                                            print("[DEBUG] Aircraft reg edited: \(newValue)")
                                            editedAircraftReg = newValue
                                        }
                                    )
                                }
                                
                                if let departureAirport = departureAirport {
                                    FlightDataCard(
                                        icon: "airplane.departure",
                                        title: "From",
                                        value: departureAirport,
                                        color: .teal,
                                        highlight: ocrFieldHighlight == "departureAirport",
                                        onEdit: { newValue in
                                            print("[DEBUG] Departure edited: \(newValue)")
                                            editedDeparture = newValue
                                        }
                                    )
                        }
                                
                                if let arrivalAirport = arrivalAirport {
                                    FlightDataCard(
                                        icon: "airplane.arrival",
                                        title: "To",
                                        value: arrivalAirport,
                                        color: .teal,
                                        highlight: ocrFieldHighlight == "arrivalAirport",
                                        onEdit: { newValue in
                                            print("[DEBUG] Arrival edited: \(newValue)")
                                            editedArrival = newValue
                                        }
                                    )
                    }
                }
                            
                            // Date card - full width below flight/aircraft cards
                            if let flightDate = inferredDate {
                                FlightDateCard(
                                    date: flightDate,
                                    onEdit: { newDate in
                                        print("[DEBUG] Date edited: \(newDate)")
                                        editedDate = newDate
                                    }
                                )
                            }
                            
                            // OUT, OFF, ON, IN cards as a separate grid for clarity and compiler performance
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                if let outTime = outTime {
                                    FlightDataCard(
                                        icon: "OUT",
                                        title: "OUT",
                                        value: outTime,
                                        color: .teal,
                                        isCustomIcon: true,
                                        highlight: ocrFieldHighlight == "outTime",
                                        onEdit: { newValue in
                                            print("[DEBUG] OUT time edited: \(newValue)")
                                            editedOutTime = newValue
                                        }
                                    )
                                }
                                if let offTime = offTime {
                                    FlightDataCard(
                                        icon: "OFF",
                                        title: "OFF",
                                        value: offTime,
                                        color: .teal,
                                        isCustomIcon: true,
                                        highlight: ocrFieldHighlight == "offTime",
                                        onEdit: { newValue in
                                            print("[DEBUG] OFF time edited: \(newValue)")
                                            editedOffTime = newValue
                                        }
                                    )
                                }
                                if let onTime = onTime {
                                    FlightDataCard(
                                        icon: "ON",
                                        title: "ON",
                                        value: onTime,
                                        color: .teal,
                                        isCustomIcon: true,
                                        highlight: ocrFieldHighlight == "onTime",
                                        onEdit: { newValue in
                                            print("[DEBUG] ON time edited: \(newValue)")
                                            editedOnTime = newValue
                                        }
                                    )
                                }
                                if let inTime = inTime {
                                    FlightDataCard(
                                        icon: "IN",
                                        title: "IN",
                                        value: inTime,
                                        color: .teal,
                                        isCustomIcon: true,
                                        highlight: ocrFieldHighlight == "inTime",
                                        onEdit: { newValue in
                                            print("[DEBUG] IN time edited: \(newValue)")
                                            editedInTime = newValue
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Crew List Section - Use actual cockpit/cabin split for two-image import
                    if !cockpitCrewDisplay.isEmpty || !cabinCrewDisplay.isEmpty {
                        VStack(spacing: 16) {
                            if !cockpitCrewDisplay.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "airplane.circle.fill")
                                            .foregroundColor(.teal)
                                        Text("Cockpit Crew")
                                            .font(.headline)
                                    }
                                    LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                                        ForEach(Array(cockpitCrewDisplay.enumerated()), id: \.offset) { index, crew in
                                            HStack(spacing: 12) {
                                                // Role card
                                                VStack {
                                                    Text(crew.role)
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(.secondary)
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, 6)
                                                        .background(Color(.systemGray5))
                                                        .cornerRadius(8)
                                                }
                                                .frame(width: 60)
                                                // Name card
                                                VStack {
                                                    Text(crew.name)
                                                        .font(.subheadline)
                                                        .foregroundColor(.primary)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .padding(.vertical, 8)
                                                        .padding(.horizontal, 12)
                                                        .background(Color(.systemGray6))
                                                        .cornerRadius(8)
                                                }
                Spacer()
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            if !cabinCrewDisplay.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "person.3.fill")
                                            .foregroundColor(.teal)
                                        Text("Cabin Crew")
                        .font(.headline)
                                    }
                                    LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                                        ForEach(Array(cabinCrewDisplay.enumerated()), id: \.offset) { index, crew in
                                            HStack(spacing: 12) {
                                                // Role card
                                                VStack {
                                                    Text(crew.role)
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(.secondary)
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, 6)
                                                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                                                .frame(width: 60)
                                                // Name card
                                                VStack {
                                                    Text(crew.name)
                                                        .font(.subheadline)
                                                        .foregroundColor(.primary)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .padding(.vertical, 8)
                                                        .padding(.horizontal, 12)
                                                        .background(Color(.systemGray6))
                                                        .cornerRadius(8)
                                                }
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    Spacer(minLength: 32)
                    .padding(.bottom, 24)
                }
                .padding(.bottom, 20)
             }
             .navigationBarHidden(true)
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
                                        DispatchQueue.main.async {
                                            ocrFlightNumber = text
                                            ocrFieldHighlight = "flightNumber"
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                        }
                                    }
                                }
                                if let img = croppedAircraftType {
                                    ocrText(from: img, label: "AircraftType") { text in
                                        DispatchQueue.main.async {
                                            ocrAircraftType = text
                                            ocrFieldHighlight = "aircraftType"
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                        }
                                    }
                                }
                                if let img = croppedAircraftReg {
                                    ocrText(from: img, label: "AircraftReg") { text in
                                        DispatchQueue.main.async {
                                            ocrAircraftReg = text
                                            ocrFieldHighlight = "aircraftReg"
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                        }
                                    }
                                }
                                if let img = croppedDeparture {
                                    ocrText(from: img, label: "Departure") { text in
                                        DispatchQueue.main.async {
                                            ocrDeparture = text
                                            ocrFieldHighlight = "departureAirport"
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                        }
                                    }
                                }
                                if let img = croppedArrival {
                                    ocrText(from: img, label: "Arrival") { text in
                                        DispatchQueue.main.async {
                                            ocrArrival = text
                                            ocrFieldHighlight = "arrivalAirport"
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                        }
                                    }
                                }
                                if let img = croppedSchedDep {
                                    ocrText(from: img, label: "SchedDep") { text in
                                        DispatchQueue.main.async {
                                            ocrSchedDep = text
                                            ocrFieldHighlight = "schedDep"
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                        }
                                    }
                                }
                                if let img = croppedSchedArr {
                                    ocrText(from: img, label: "SchedArr") { text in
                                        DispatchQueue.main.async {
                                            ocrSchedArr = text
                                            ocrFieldHighlight = "schedArr"
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                    }
                                }
                                }
                                if let img = croppedDayDate {
                                    ocrText(from: img, label: "DayDate") { text in
                                        DispatchQueue.main.async {
                                            ocrDayDate = text
                                            ocrFieldHighlight = "dayDate"
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                        }
                                    }
                                }
                        if let img = croppedOutTime {
                            ocrText(from: img, label: "OutTime") { text in
                                DispatchQueue.main.async {
                                    ocrOutTime = text
                                    ocrFieldHighlight = "outTime"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                }
                            }
                        }
                        if let img = croppedOffTime {
                            ocrText(from: img, label: "OffTime") { text in
                                DispatchQueue.main.async {
                                    ocrOffTime = text
                                    ocrFieldHighlight = "offTime"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                }
                            }
                        }
                        if let img = croppedOnTime {
                            ocrText(from: img, label: "OnTime") { text in
                                DispatchQueue.main.async {
                                    ocrOnTime = text
                                    ocrFieldHighlight = "onTime"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                }
                            }
                        }
                        if let img = croppedInTime {
                            ocrText(from: img, label: "InTime") { text in
                                DispatchQueue.main.async {
                                    ocrInTime = text
                                    ocrFieldHighlight = "inTime"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                                }
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
        .sheet(isPresented: $showCrewReviewSheet) {
            CrewReviewModal(
                crewNames: $crewNamesNeedingReview,
                onConfirm: {
                    for review in crewNamesNeedingReview {
                        switch review.role {
                        case "Commander": ocrCrewCommander = review.corrected
                        case "SIC": ocrCrewSIC = review.corrected
                        case "Relief": ocrCrewRelief = review.corrected
                        case "Relief2": ocrCrewRelief2 = review.corrected
                        case "ISM": ocrCrewCustom2ISM = review.corrected
                        case "SP": ocrCrewCustom4SP = review.corrected
                        case "FP": ocrCrewCustom1FP = review.corrected
                        case "FlightAttendant": ocrCrewFlightAttendant = review.corrected
                        case "FlightAttendant2": ocrCrewFlightAttendant2 = review.corrected
                        case "FlightAttendant3": ocrCrewFlightAttendant3 = review.corrected
                        case "FlightAttendant4": ocrCrewFlightAttendant4 = review.corrected
                        default: break
                        }
                    }
                    crewNamesNeedingReview.removeAll()
                    showCrewReviewSheet = false
                        if isLogTenProInstalled() {
                        exportToLogTen(jsonString: generateLogTenJSON())
                        } else {
                            showLogTenAlert = true
                        }
                },
                onCancel: {
                    showCrewReviewSheet = false
                }
            )
        }
        .sheet(isPresented: $showReviewAllDataSheet) {
            ReviewAllDataModal(
                isPresented: $showReviewAllDataSheet,
                flightData: prepareFlightDataForReview(),
                onSave: { reviewedData, newCockpitCrew, newCabinCrew in
                    print("[DEBUG] Applying reviewed data changes")
                    applyReviewedData(reviewedData)
                    // Export using the latest edits directly
                    exportToLogTen(jsonString: generateLogTenJSON(cockpitCrew: newCockpitCrew, cabinCrew: newCabinCrew))
                    showReviewAllDataSheet = false
                },
                cockpitCrew: cockpitCrewDisplay.map { CrewMember(role: $0.role, name: $0.name) },
                cabinCrew: cabinCrewDisplay.map { CrewMember(role: $0.role, name: $0.name) }
            )
        }
    }
    
    // MARK: - Review All Data Helper Functions (Phase 2)
    
    // Prepare current flight data for review modal
    func prepareFlightDataForReview() -> FlightDataForReview {
        print("[DEBUG] Preparing flight data for review")
        return FlightDataForReview(
            flightNumber: flightNumber ?? "",
            aircraftReg: aircraftReg ?? "",
            departure: departureAirport ?? "",
            arrival: arrivalAirport ?? "",
            date: inferredDate,
            outTime: outTime ?? "",
            offTime: offTime ?? "",
            onTime: onTime ?? "",
            inTime: inTime ?? ""
        )
    }
    
    // Apply reviewed data changes back to the main state
    func applyReviewedData(_ reviewedData: FlightDataForReview) {
        print("[DEBUG] Applying reviewed data changes")
        
        // Apply changes to edited values (these will override OCR values)
        editedFlightNumber = reviewedData.flightNumber
        editedAircraftReg = reviewedData.aircraftReg
        editedDeparture = reviewedData.departure
        editedArrival = reviewedData.arrival
        editedDate = reviewedData.date
        editedOutTime = reviewedData.outTime
        editedOffTime = reviewedData.offTime
        editedOnTime = reviewedData.onTime
        editedInTime = reviewedData.inTime
        
        print("[DEBUG] Applied reviewed data: Flight=\(reviewedData.flightNumber), Aircraft=\(reviewedData.aircraftReg), From=\(reviewedData.departure), To=\(reviewedData.arrival)")
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
    
    // Helper to update parsedCrewList after all OCRs, with new display labels and grouping
    func updateParsedCrewList(cockpitResults: [(String, String)], cabinResults: [(String, String)]) {
        let nonEmptyCockpit = cockpitResults.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let nonEmptyCabin = cabinResults.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        parsedCrewList = []
        cockpitCrewDisplay = []
        cabinCrewDisplay = []
        // Cockpit crew in order: PIC, SIC, Relief, Relief
        let cockpitLabels = ["PIC", "SIC", "Relief", "Relief"]
        for (i, (_, text)) in nonEmptyCockpit.prefix(4).enumerated() {
            let label = i < cockpitLabels.count ? cockpitLabels[i] : "Relief"
            let rawName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let formattedName = titleCase(rawName)
            parsedCrewList.append("\(label): \(formattedName)")
            cockpitCrewDisplay.append((role: label, name: formattedName))
        }
        // Cabin crew in order: ISM, SP, FP, FA, FA2, FA3, FA4
        let cabinLabels = ["ISM", "SP", "FP", "FA", "FA2", "FA3", "FA4"]
        for (i, (_, text)) in nonEmptyCabin.prefix(7).enumerated() {
            let label = i < cabinLabels.count ? cabinLabels[i] : "FA"
            let rawName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let formattedName = titleCase(rawName)
            parsedCrewList.append("\(label): \(formattedName)")
            cabinCrewDisplay.append((role: label, name: formattedName))
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
                DispatchQueue.main.async {
                    ocrFlightNumber = text
                    ocrFieldHighlight = "flightNumber"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedAircraftType {
            ocrText(from: img, label: "AircraftType") { text in
                DispatchQueue.main.async {
                    ocrAircraftType = text
                    ocrFieldHighlight = "aircraftType"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedAircraftReg {
            ocrText(from: img, label: "AircraftReg") { text in
                DispatchQueue.main.async {
                    ocrAircraftReg = text
                    ocrFieldHighlight = "aircraftReg"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedDeparture {
            ocrText(from: img, label: "Departure") { text in
                DispatchQueue.main.async {
                    ocrDeparture = text
                    ocrFieldHighlight = "departureAirport"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedArrival {
            ocrText(from: img, label: "Arrival") { text in
                DispatchQueue.main.async {
                    ocrArrival = text
                    ocrFieldHighlight = "arrivalAirport"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedSchedDep {
            ocrText(from: img, label: "SchedDep") { text in
                DispatchQueue.main.async {
                    ocrSchedDep = text
                    ocrFieldHighlight = "schedDep"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedSchedArr {
            ocrText(from: img, label: "SchedArr") { text in
                DispatchQueue.main.async {
                    ocrSchedArr = text
                    ocrFieldHighlight = "schedArr"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedDayDate {
            ocrText(from: img, label: "DayDate") { text in
                DispatchQueue.main.async {
                    ocrDayDate = text
                    ocrFieldHighlight = "dayDate"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedOutTime {
            ocrText(from: img, label: "OutTime") { text in
                DispatchQueue.main.async {
                    ocrOutTime = text
                    ocrFieldHighlight = "outTime"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedOffTime {
            ocrText(from: img, label: "OffTime") { text in
                DispatchQueue.main.async {
                    ocrOffTime = text
                    ocrFieldHighlight = "offTime"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedOnTime {
            ocrText(from: img, label: "OnTime") { text in
                DispatchQueue.main.async {
                    ocrOnTime = text
                    ocrFieldHighlight = "onTime"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
            }
        }
        if let img = croppedInTime {
            ocrText(from: img, label: "InTime") { text in
                DispatchQueue.main.async {
                    ocrInTime = text
                    ocrFieldHighlight = "inTime"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ocrFieldHighlight = nil }
                }
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
                    self.parsedCrewList = []
                    print("[DEBUG] Creating parsed crew list with \(crewNames.count) names")
                    if crewNames.count >= 3 {
                        let cockpitLabels = ["PIC", "SIC", "Relief", "Relief"]
                        // All except last are cockpit crew
                        for (i, name) in crewNames.dropLast().enumerated() {
                            let label = i < cockpitLabels.count ? cockpitLabels[i] : "Relief"
                            let formattedName = self.titleCase(name)
                            self.parsedCrewList.append("\(label): \(formattedName)")
                        }
                        // Last is always ISM (cabin crew)
                        let lastFormattedName = self.titleCase(crewNames.last!)
                        self.parsedCrewList.append("ISM: \(lastFormattedName)")
                    } else {
                        // Fallback: not enough names, show as-is
                        for name in crewNames {
                            let formattedName = self.titleCase(name)
                            self.parsedCrewList.append(formattedName)
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
            ("Commander", crewCommanderROI),
            ("SIC", crewSICROI),
            ("Relief", crewReliefROI),
            ("Relief2", crewRelief2ROI)
        ]
        // Cabin crew ROIs and roles
        let cabinROIs: [(String, FieldROI)] = [
            ("ISM", crewCustom2ISMROI),   // ISM role
            ("SP", crewCustom4SPROI),     // SP role
            ("FP", crewCustom1FPROI),     // FP role
            ("FlightAttendant", crewFlightAttendantROI),    // Primary FA
            ("FlightAttendant2", crewFlightAttendant2ROI),  // FA2
            ("FlightAttendant3", crewFlightAttendant3ROI),  // FA3
            ("FlightAttendant4", crewFlightAttendant4ROI)   // FA4
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
                        // Assign to state variable
                        switch role {
                        case "Commander": ocrCrewCommander = crewText
                        case "SIC": ocrCrewSIC = crewText
                        case "Relief": ocrCrewRelief = crewText
                        case "Relief2": ocrCrewRelief2 = crewText
                        default: break
                        }
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
                        // Assign to state variable
                        switch role {
                        case "ISM": ocrCrewCustom2ISM = crewText
                        case "SP": ocrCrewCustom4SP = crewText
                        case "FP": ocrCrewCustom1FP = crewText
                        case "FlightAttendant": ocrCrewFlightAttendant = crewText
                        case "FlightAttendant2": ocrCrewFlightAttendant2 = crewText
                        case "FlightAttendant3": ocrCrewFlightAttendant3 = crewText
                        case "FlightAttendant4": ocrCrewFlightAttendant4 = crewText
                        default: break
                        }
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

// Generate a robust, deterministic flight_key using date, flight number, from, and to
func generateFlightKey(date: String, flightNumber: String, from: String, to: String) -> String {
    let base = "\(date)_\(flightNumber)_\(from)_\(to)"
    let hash = SHA256.hash(data: Data(base.utf8))
    return "FC_" + hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16)
}

func titleCase(_ name: String) -> String {
    name
        .lowercased()
        .split(separator: " ")
        .map { $0.capitalized }
        .joined(separator: " ")
}

// Function to check if any crew names need review (without generating JSON)
func checkCrewNamesForReview() -> Bool {
    // Clear the review list first
    crewNamesNeedingReview.removeAll()
    
    // Check each crew role for trailing dots
    let crewRoles = [
        ("Commander", ocrCrewCommander),
        ("SIC", ocrCrewSIC),
        ("Relief", ocrCrewRelief),
        ("Relief2", ocrCrewRelief2),
        ("ISM", ocrCrewCustom2ISM),
        ("SP", ocrCrewCustom4SP),
        ("FP", ocrCrewCustom1FP),
        ("FlightAttendant", ocrCrewFlightAttendant),
        ("FlightAttendant2", ocrCrewFlightAttendant2),
        ("FlightAttendant3", ocrCrewFlightAttendant3),
        ("FlightAttendant4", ocrCrewFlightAttendant4)
    ]
    
    for (role, ocrText) in crewRoles {
        let trimmedText = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty && trimmedText.hasSuffix("...") {
            let correctedName = trimmedText.replacingOccurrences(of: "...", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !correctedName.isEmpty {
                print("[DEBUG] Adding to crewNamesNeedingReview: role=\(role), original=\(trimmedText), corrected=\(correctedName)")
                crewNamesNeedingReview.append(CrewNameReview(role: role, original: trimmedText, corrected: correctedName))
            }
        }
    }
    
    return !crewNamesNeedingReview.isEmpty
}

    // Helper function to handle photo selection (breaks up complex expression)
    func handlePhotoSelection(_ newItems: [PhotosPickerItem]) {
        print("[DEBUG] User selected photos: \(newItems.map { String(describing: $0) })")
        importedImages = []
        ocrResults = []
        imageTypes = []
        parsedCrewList = []
        cockpitCrewDisplay = []
        cabinCrewDisplay = []
        
        // Clear edited values for new flight (Phase 1 fix)
        editedFlightNumber = ""
        editedAircraftReg = ""
        editedDeparture = ""
        editedArrival = ""
        editedOutTime = ""
        editedOffTime = ""
        editedOnTime = ""
        editedInTime = ""
        editedDate = nil
        print("[DEBUG] Cleared all edited values for new flight")
        
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
}
#Preview {
    ContentView(incomingImageURL: .constant(nil))
}

// MARK: - Flight Data Card Component
struct FlightDataCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    var isCustomIcon: Bool = false
    var highlight: Bool = false
    var onEdit: ((String) -> Void)? = nil
    
    @State private var isEditing: Bool = false
    @State private var editedValue: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isCustomIcon {
                    Image(icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.teal)
                } else {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.title3)
                }
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                // Edit indicator
                if onEdit != nil {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                        .foregroundColor(isEditing ? .green : .teal)
                        .font(.caption)
                        .opacity(0.7)
                }
            }
            
            if isEditing {
                TextField("Enter \(title.lowercased())", text: $editedValue)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit {
                        saveEdit()
                    }
                    .onAppear {
                        editedValue = value
                    }
            } else {
                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
        }
        .padding(12)
        .background(highlight ? Color.yellow.opacity(0.3) : Color(.systemGray6))
        .cornerRadius(12)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .onTapGesture {
            if onEdit != nil {
                withAnimation {
                    isEditing.toggle()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isEditing ? Color.teal : Color.clear, lineWidth: 2)
        )
    }
    
    private func saveEdit() {
        print("[DEBUG] Saving edit for \(title): \(editedValue)")
        onEdit?(editedValue)
        withAnimation {
            isEditing = false
        }
    }
}

// MARK: - Flight Date Card Component
struct FlightDateCard: View {
    let date: Date
    var onEdit: ((Date) -> Void)? = nil
    
    @State private var isEditing: Bool = false
    @State private var editedDate: Date = Date()
    @State private var showDatePicker: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.circle.fill")
                .foregroundColor(.teal)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Date")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(formatDate(isEditing ? editedDate : date))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Edit indicator
            if onEdit != nil {
                Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                    .foregroundColor(isEditing ? .green : .teal)
                    .font(.caption)
                    .opacity(0.7)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .onTapGesture {
            if onEdit != nil {
                if isEditing {
                    saveEdit()
                } else {
                    withAnimation {
                        isEditing = true
                        editedDate = date
                        showDatePicker = true
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isEditing ? Color.teal : Color.clear, lineWidth: 2)
        )
        .sheet(isPresented: $showDatePicker) {
            NavigationView {
                VStack {
                    DatePicker(
                        "Select Date",
                        selection: $editedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(WheelDatePickerStyle())
                    .padding()
                    
                    HStack {
                        Button("Cancel") {
                            withAnimation {
                                isEditing = false
                                showDatePicker = false
                            }
                        }
                        .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Save") {
                            saveEdit()
                        }
                        .foregroundColor(.teal)
                        .fontWeight(.semibold)
                    }
                    .padding()
                }
                .navigationTitle("Edit Flight Date")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }
    
    private func saveEdit() {
        print("[DEBUG] Saving date edit: \(formatDate(editedDate))")
        onEdit?(editedDate)
        withAnimation {
            isEditing = false
            showDatePicker = false
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
}

struct CrewReviewModal: View {
    @Binding var crewNames: [ContentView.CrewNameReview]
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header explanation cards
                    VStack(spacing: 16) {
                        // Why am I seeing this card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.title3)
                                Text("Why am I seeing this?")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            
                            Text("To avoid duplicate crew entries in LogTen Pro, names must match exactly. The name below was flagged because it ends with \"...\" (indicating it may be incomplete or excessively long).")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        
                        // What should I do card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.teal)
                                    .font(.title3)
                                Text("What should I do?")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            
                            Text("Please review and correct the name to ensure it is complete and matches the official crew list. When you're satisfied, tap \"Confirm & Export\" to continue.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Crew names review section
                    if crewNames.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 40))
                            Text("No crew names need review")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("All crew names are complete and ready for export")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(32)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "person.3.fill")
                                    .foregroundColor(.teal)
                                    .font(.title3)
                                Text("Review Crew Names")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            LazyVStack(spacing: 12) {
                                ForEach(crewNames.indices, id: \.self) { index in
                                    CrewReviewCard(
                                        role: crewNames[index].role,
                                        original: crewNames[index].original,
                                        corrected: $crewNames[index].corrected
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Review Crew Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm & Export") {
                        onConfirm()
                    }
                    .disabled(crewNames.isEmpty)
                    .foregroundColor(.teal)
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Crew Review Card Component
struct CrewReviewCard: View {
    let role: String
    let original: String
    @Binding var corrected: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.teal)
                    .font(.title3)
                Text(role)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Original:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                Text(original)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Corrected:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                TextField(
                    "Enter corrected name",
                    text: Binding(
                        get: { titleCase(corrected) },
                        set: { newValue in corrected = titleCase(newValue) }
                    )
                )
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .onAppear {
                    // Force title case on appear
                    let formatted = titleCase(corrected)
                    if formatted != corrected {
                        corrected = formatted
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // Helper function to apply title case formatting
    private func titleCase(_ name: String) -> String {
        name
            .lowercased()
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Review All Data Modal Component
struct ReviewAllDataModal: View {
    @Binding var isPresented: Bool
    let flightData: FlightDataForReview
    var onSave: (FlightDataForReview, [CrewMember], [CrewMember]) -> Void

    // Add editable crew arrays
    @State private var editedCockpitCrew: [CrewMember] = []
    @State private var editedCabinCrew: [CrewMember] = []
    @State private var editedData: FlightDataForReview
    @State private var cockpitRoleSheetIndex: Int? = nil
    @State private var cabinRoleSheetIndex: Int? = nil
    @State private var openRoleDropdown: (isCockpit: Bool, index: Int)? = nil

    // Allowed roles
    let cockpitRoles = ["PIC", "SIC", "Relief", "Relief2"]
    let cabinRoles = ["ISM", "SP", "FP", "FA", "FA2", "FA3", "FA4"]

    init(isPresented: Binding<Bool>, flightData: FlightDataForReview, onSave: @escaping (FlightDataForReview, [CrewMember], [CrewMember]) -> Void, cockpitCrew: [CrewMember], cabinCrew: [CrewMember]) {
        self._isPresented = isPresented
        self.flightData = flightData
        self.onSave = onSave
        self._editedData = State(initialValue: flightData)
        self._editedCockpitCrew = State(initialValue: cockpitCrew)
        self._editedCabinCrew = State(initialValue: cabinCrew)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header explanation
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .foregroundColor(.teal)
                                .font(.title3)
                            Text("Review Flight Data")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        Text("Review and edit all extracted flight data before export. Any changes made here will be used for the LogTen export.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Flight Information Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Flight Information", icon: "airplane.circle.fill")
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ReviewDataField(
                                title: "Flight Number",
                                value: $editedData.flightNumber,
                                originalValue: flightData.flightNumber,
                                icon: "number.circle.fill"
                            )
                            
                            ReviewDataField(
                                title: "Aircraft",
                                value: $editedData.aircraftReg,
                                originalValue: flightData.aircraftReg,
                                icon: "airplane.circle.fill"
                            )
                            
                            ReviewDataField(
                                title: "From",
                                value: $editedData.departure,
                                originalValue: flightData.departure,
                                icon: "airplane.departure"
                            )
                            
                            ReviewDataField(
                                title: "To",
                                value: $editedData.arrival,
                                originalValue: flightData.arrival,
                                icon: "airplane.arrival"
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Date Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Flight Date", icon: "calendar.circle.fill")
                        
                        ReviewDateField(
                            date: $editedData.date,
                            originalDate: flightData.date
                        )
                        .padding(.horizontal)
                    }
                    
                    // Times Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Flight Times", icon: "clock.circle.fill")
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ReviewDataField(
                                title: "OUT",
                                value: $editedData.outTime,
                                originalValue: flightData.outTime,
                                icon: "OUT",
                                isCustomIcon: true
                            )
                            
                            ReviewDataField(
                                title: "OFF",
                                value: $editedData.offTime,
                                originalValue: flightData.offTime,
                                icon: "OFF",
                                isCustomIcon: true
                            )
                            
                            ReviewDataField(
                                title: "ON",
                                value: $editedData.onTime,
                                originalValue: flightData.onTime,
                                icon: "ON",
                                isCustomIcon: true
                            )
                            
                            ReviewDataField(
                                title: "IN",
                                value: $editedData.inTime,
                                originalValue: flightData.inTime,
                                icon: "IN",
                                isCustomIcon: true
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Crew Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Crew", icon: "person.3.fill")
                        // Cockpit
                        if !editedCockpitCrew.isEmpty {
                            Text("Cockpit Crew").font(.headline).padding(.leading, 4)
                            LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                                ForEach(Array(editedCockpitCrew.enumerated()), id: \.element.id) { idx, _ in
                                    CockpitCrewRowView(idx: idx, crew: $editedCockpitCrew[idx], openRoleDropdown: $openRoleDropdown, cockpitRoles: cockpitRoles, editedCockpitCrew: $editedCockpitCrew)
                                }
                            }
                        }
                        // Cabin
                        if !editedCabinCrew.isEmpty {
                            Text("Cabin Crew").font(.headline).padding(.leading, 4)
                            LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                                ForEach(Array(editedCabinCrew.enumerated()), id: \.element.id) { idx, _ in
                                    CabinCrewRowView(idx: idx, crew: $editedCabinCrew[idx], openRoleDropdown: $openRoleDropdown, cabinRoles: cabinRoles, editedCabinCrew: $editedCabinCrew)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 20)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Review All Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Export") {
                        print("[DEBUG] Saving reviewed data and exporting")
                        onSave(editedData, editedCockpitCrew, editedCabinCrew)
                        isPresented = false
                    }
                    .foregroundColor(.teal)
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
    // Helper for title case
    private func titleCase(_ name: String) -> String {
        name
            .lowercased()
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    // Helper for dropdown menu
    @ViewBuilder
    private func RoleDropdown(isCockpit: Bool, idx: Int, currentRole: String) -> some View {
        let roles = isCockpit ? cockpitRoles : cabinRoles
        if let openDropdown = openRoleDropdown, openDropdown == (isCockpit, idx) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(roles, id: \.self) { role in
                    Button(action: {
                        if isCockpit { editedCockpitCrew[idx].role = role } else { editedCabinCrew[idx].role = role }
                        openRoleDropdown = nil
                    }) {
                        HStack {
                            Text(role)
                                .font(.subheadline)
                                .foregroundColor(role == currentRole ? .teal : .primary)
                            Spacer()
                            if role == currentRole {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.teal)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }
                    .background(role == currentRole ? Color(.systemGray5) : Color(.systemBackground))
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(radius: 6)
            .padding(.top, 2)
            .frame(maxWidth: 120)
        }
    }

}

// MARK: - Review Data Field Component
struct ReviewDataField: View {
    let title: String
    @Binding var value: String
    let originalValue: String
    let icon: String
    var isCustomIcon: Bool = false
    
    @State private var isEditing: Bool = false
    @State private var editedValue: String = ""
    
    var hasChanges: Bool {
        value != originalValue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isCustomIcon {
                    Image(icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.teal)
                } else {
                    Image(systemName: icon)
                        .foregroundColor(.teal)
                        .font(.title3)
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if hasChanges {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else if isEditing {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.teal)
                        .font(.caption)
                }
            }
            
            if isEditing {
                TextField("Enter \(title.lowercased())", text: $editedValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        saveEdit()
                    }
                    .onAppear {
                        editedValue = value
                    }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(value.isEmpty ? "Not available" : value)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(value.isEmpty ? .secondary : .primary)
                    
                    if hasChanges {
                        Text("Original: \(originalValue)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(hasChanges ? Color.green.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(hasChanges ? Color.green : (isEditing ? Color.teal : Color.clear), lineWidth: 1)
        )
        .onTapGesture {
            withAnimation {
                isEditing.toggle()
            }
        }
    }
    
    private func saveEdit() {
        print("[DEBUG] Saving review edit for \(title): \(editedValue)")
        value = editedValue
        withAnimation {
            isEditing = false
        }
    }
}

// MARK: - Review Date Field Component
struct ReviewDateField: View {
    @Binding var date: Date?
    let originalDate: Date?
    
    @State private var isEditing: Bool = false
    @State private var editedDate: Date = Date()
    @State private var showDatePicker: Bool = false
    
    var hasChanges: Bool {
        guard let date = date, let originalDate = originalDate else { return false }
        return Calendar.current.compare(date, to: originalDate, toGranularity: .day) != .orderedSame
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar.circle.fill")
                    .foregroundColor(.teal)
                    .font(.title3)
                
                Text("Flight Date")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if hasChanges {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else if isEditing {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.teal)
                        .font(.caption)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(date))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if hasChanges, let originalDate = originalDate {
                    Text("Original: \(formatDate(originalDate))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(hasChanges ? Color.green.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(hasChanges ? Color.green : (isEditing ? Color.teal : Color.clear), lineWidth: 1)
        )
        .onTapGesture {
            if isEditing {
                saveEdit()
            } else {
                withAnimation {
                    isEditing = true
                    editedDate = date ?? Date()
                    showDatePicker = true
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationView {
                VStack {
                    DatePicker(
                        "Select Date",
                        selection: $editedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(WheelDatePickerStyle())
                    .padding()
                    
                    HStack {
                        Button("Cancel") {
                            withAnimation {
                                isEditing = false
                                showDatePicker = false
                            }
                        }
                        .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Save") {
                            saveEdit()
                        }
                        .foregroundColor(.teal)
                        .fontWeight(.semibold)
                    }
                    .padding()
                }
                .navigationTitle("Edit Flight Date")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }
    
    private func saveEdit() {
        print("[DEBUG] Saving review date edit: \(formatDate(editedDate))")
        date = editedDate
        withAnimation {
            isEditing = false
            showDatePicker = false
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Not available" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Section Header Component
struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.teal)
                .font(.title3)
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - Flight Data For Review Model
struct FlightDataForReview {
    var flightNumber: String
    var aircraftReg: String
    var departure: String
    var arrival: String
    var date: Date?
    var outTime: String
    var offTime: String
    var onTime: String
    var inTime: String
}

// Add CrewMember struct for editing
struct CrewMember: Identifiable, Equatable {
    let id = UUID()
    var role: String
    var name: String
}

// ... add these new structs at file scope ...
struct CockpitCrewRowView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    var idx: Int
    @Binding var crew: CrewMember
    @Binding var openRoleDropdown: (isCockpit: Bool, index: Int)?
    var cockpitRoles: [String]
    @Binding var editedCockpitCrew: [CrewMember]
    @State private var showRoleDialog = false
    
    // Helper function to apply title case formatting
    private func titleCase(_ name: String) -> String {
        name
            .lowercased()
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: {
                if UIDevice.current.userInterfaceIdiom == .pad || sizeClass == .regular {
                    openRoleDropdown = (true, idx)
                } else {
                    showRoleDialog = true
                }
            }) {
                HStack(spacing: 4) {
                    Text(crew.role)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 70) // Fixed width for role card
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: Binding(
                get: {
                    if let dropdown = openRoleDropdown {
                        return dropdown == (true, idx)
                    }
                    return false
                },
                set: { show in if !show { openRoleDropdown = nil } }
            )) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(cockpitRoles, id: \.self) { role in
                        Button(action: {
                            editedCockpitCrew[idx].role = role
                            openRoleDropdown = nil
                        }) {
                            HStack {
                                Text(role)
                                    .font(.subheadline)
                                    .foregroundColor(role == crew.role ? .teal : .primary)
                                Spacer()
                                if role == crew.role {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.teal)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                        }
                        .background(role == crew.role ? Color(.systemGray5) : Color(.systemBackground))
                    }
                }
                .frame(width: 140)
            }
            .confirmationDialog("Select Role", isPresented: $showRoleDialog, titleVisibility: .visible) {
                ForEach(cockpitRoles, id: \.self) { role in
                    Button(role) {
                        editedCockpitCrew[idx].role = role
                    }
                    if role == crew.role {
                        Image(systemName: "checkmark")
                            .foregroundColor(.teal)
                    }
                }
            }
            // Name Card
            TextField("Name", text: Binding(
                get: { titleCase(editedCockpitCrew[idx].name) },
                set: { newValue in editedCockpitCrew[idx].name = titleCase(newValue) }
            ))
            .textInputAutocapitalization(.words)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CabinCrewRowView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    var idx: Int
    @Binding var crew: CrewMember
    @Binding var openRoleDropdown: (isCockpit: Bool, index: Int)?
    var cabinRoles: [String]
    @Binding var editedCabinCrew: [CrewMember]
    @State private var showRoleDialog = false
    
    // Helper function to apply title case formatting
    private func titleCase(_ name: String) -> String {
        name
            .lowercased()
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: {
                if UIDevice.current.userInterfaceIdiom == .pad || sizeClass == .regular {
                    openRoleDropdown = (false, idx)
                } else {
                    showRoleDialog = true
                }
            }) {
                HStack(spacing: 4) {
                    Text(crew.role)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 70) // Fixed width for role card
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: Binding(
                get: {
                    if let dropdown = openRoleDropdown {
                        return dropdown == (false, idx)
                    }
                    return false
                },
                set: { show in if !show { openRoleDropdown = nil } }
            )) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(cabinRoles, id: \.self) { role in
                        Button(action: {
                            editedCabinCrew[idx].role = role
                            openRoleDropdown = nil
                        }) {
                            HStack {
                                Text(role)
                                    .font(.subheadline)
                                    .foregroundColor(role == crew.role ? .teal : .primary)
                                Spacer()
                                if role == crew.role {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.teal)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                        }
                        .background(role == crew.role ? Color(.systemGray5) : Color(.systemBackground))
                    }
                }
                .frame(width: 140)
            }
            .confirmationDialog("Select Role", isPresented: $showRoleDialog, titleVisibility: .visible) {
                ForEach(cabinRoles, id: \.self) { role in
                    Button(role) {
                        editedCabinCrew[idx].role = role
                    }
                    if role == crew.role {
                        Image(systemName: "checkmark")
                            .foregroundColor(.teal)
                    }
                }
            }
            // Name Card
            TextField("Name", text: Binding(
                get: { titleCase(editedCabinCrew[idx].name) },
                set: { newValue in editedCabinCrew[idx].name = titleCase(newValue) }
            ))
            .textInputAutocapitalization(.words)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
