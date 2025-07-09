import Foundation
import UIKit
import CryptoKit

// MARK: - LogTen Controller

class LogTenController: ObservableObject {
    @Published var isExporting = false
    @Published var exportError: String?
    
    init() {}
    
    // Generate flight key (from original code)
    func generateFlightKey(date: String, flightNumber: String, from: String, to: String) -> String {
        let input = "\(date)\(flightNumber)\(from)\(to)"
        let hash = SHA256.hash(data: input.data(using: .utf8) ?? Data())
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    // Helper to extract Zulu time and check for +1 day indicator (from original code)
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

    // Helper to format scheduled time as dd/MM/yyyy HH:mm for LogTen (from original code)
    func formatScheduledTime(ocrTime: String, fallback: String, inferredDate: Date?) -> String {
        guard let date = inferredDate else { return fallback }
        // Extract Zulu time and check for +1 day indicator
        let (zulu, isNextDay) = extractZuluTime(ocrTime)
        guard let zulu = zulu, zulu.count >= 4 else { return fallback }
        
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
    
    // Helper function to format actual times with full date-time (from original code)
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

    // Generate LogTen JSON (exact implementation from original code)
    func generateLogTenJSON(flightNumber: String?, aircraftReg: String?, departureAirport: String?, arrivalAirport: String?, outTime: String?, offTime: String?, onTime: String?, inTime: String?, schedDep: String?, schedArr: String?, inferredDate: Date?, cockpitCrew: [CrewMember]? = nil, cabinCrew: [CrewMember]? = nil) -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let dateString = dateFormatter.string(from: now)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: now)
        
        // Use inferred date + OCR time if possible, else fallback (from original code)
        let scheduledDeparture = formatScheduledTime(ocrTime: schedDep ?? "", fallback: "\(dateString) \(timeString)", inferredDate: inferredDate)
        let scheduledArrival = formatScheduledTime(ocrTime: schedArr ?? "", fallback: "\(dateString) \(timeString)", inferredDate: inferredDate)
        
        let flightKey = generateFlightKey(
            date: scheduledDeparture.components(separatedBy: " ").first ?? dateString,
            flightNumber: flightNumber ?? "TEST123",
            from: departureAirport ?? "VHHH",
            to: arrivalAirport ?? "OERK"
        )
        print("[DEBUG] Generated flight_key: \(flightKey)")
        
        let aircraftID = aircraftReg ?? "B-TEST"
        print("[DEBUG] Normalized Aircraft ID for export: \(aircraftID)")
        
        // Use the passed-in arrays if provided
        let cockpit = cockpitCrew ?? []
        let cabin = cabinCrew ?? []
        
        // Build a role->name dictionary from the arrays
        var crewDict: [String: String] = [:]
        for member in cockpit { crewDict[member.role] = member.name }
        for member in cabin { crewDict[member.role] = member.name }
        
        // Now use crewDict for mapping (from original code)
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
            "timesAreZulu": true,
            "shouldApplyAutoFillTimes": true
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

    // Check if LogTen is installed (exact implementation from original code)
    func isLogTenProInstalled() -> Bool {
        print("[DEBUG] Checking if LogTen Pro is installed...")
        let schemes = ["logten", "logtenprox", "logtenpro"]
        for scheme in schemes {
            let urlString = "\(scheme)://"
            print("[DEBUG] Testing URL: \(urlString)")
            
            if let url = URL(string: urlString) {
                let canOpen = UIApplication.shared.canOpenURL(url)
                print("[DEBUG] Checking URL scheme: \(scheme) -> \(canOpen)")
                if canOpen {
                    print("✅ Found working scheme: \(scheme)")
                    return true
                } else {
                    print("[DEBUG] Scheme \(scheme) cannot be opened")
                }
            } else {
                print("❌ Invalid URL for scheme: \(scheme)")
            }
        }
        print("❌ No valid LogTen Pro schemes found")
        return false
    }

    // Export to LogTen using URL scheme (exact implementation from original code)
    func exportToLogTen(jsonString: String) {
        print("[DEBUG] Starting LogTen export with JSON length: \(jsonString.count)")
        print("[DEBUG] JSON preview: \(String(jsonString.prefix(200)))...")
        
        let schemes = ["logten", "logtenprox", "logtenpro"]
        guard let encodedJson = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("❌ Failed to encode JSON for URL")
            return
        }
        print("[DEBUG] Encoded JSON length: \(encodedJson.count)")
        
        for scheme in schemes {
            let urlString = "\(scheme)://v2/addEntities?package=\(encodedJson)"
            print("[DEBUG] Trying URL: \(urlString)")
            
            if let url = URL(string: urlString) {
                let canOpen = UIApplication.shared.canOpenURL(url)
                print("[DEBUG] Can open URL with scheme \(scheme): \(canOpen)")
                
                if canOpen {
                    print("✅ Opening LogTen with scheme: \(scheme)")
                    print("[DEBUG] About to call UIApplication.shared.open(\(url))")
                    UIApplication.shared.open(url) { success in
                        print("[DEBUG] UIApplication.shared.open result: \(success)")
                    }
                    return
                } else {
                    print("[DEBUG] Cannot open URL with scheme \(scheme)")
                }
            } else {
                print("❌ Invalid URL for scheme: \(scheme)")
            }
        }
        print("❌ Could not open LogTen with any scheme")
        // Note: In the original code, this would set showLogTenAlert = true
        // In our MVC implementation, we'll handle this differently
    }
    
    /// Export flight data to LogTen Pro (simplified version for MVC)
    func exportToLogTen(flightData: FlightData, cockpitCrew: [CrewMember], cabinCrew: [CrewMember]) async {
        print("[DEBUG] Starting async exportToLogTen")
        await MainActor.run {
            isExporting = true
            exportError = nil
        }
        
        print("[DEBUG] Generating LogTen JSON with provided flight data:")
        print("[DEBUG] - Flight Number: '\(flightData.flightNumber ?? "nil")'")
        print("[DEBUG] - Aircraft Reg: '\(flightData.aircraftReg ?? "nil")'")
        print("[DEBUG] - Departure: '\(flightData.departureAirport ?? "nil")'")
        print("[DEBUG] - Arrival: '\(flightData.arrivalAirport ?? "nil")'")
        print("[DEBUG] - Out Time: '\(flightData.outTime ?? "nil")'")
        print("[DEBUG] - Off Time: '\(flightData.offTime ?? "nil")'")
        print("[DEBUG] - On Time: '\(flightData.onTime ?? "nil")'")
        print("[DEBUG] - In Time: '\(flightData.inTime ?? "nil")'")
        
        let jsonString = generateLogTenJSON(
            flightNumber: flightData.flightNumber,
            aircraftReg: flightData.aircraftReg,
            departureAirport: flightData.departureAirport,
            arrivalAirport: flightData.arrivalAirport,
            outTime: flightData.outTime,
            offTime: flightData.offTime,
            onTime: flightData.onTime,
            inTime: flightData.inTime,
            schedDep: flightData.schedDep,
            schedArr: flightData.schedArr,
            inferredDate: flightData.date,
            cockpitCrew: cockpitCrew,
            cabinCrew: cabinCrew
        )
        
        await MainActor.run {
            exportToLogTen(jsonString: jsonString)
            isExporting = false
        }
    }
    
    /// Export with custom crew data
    func exportWithCustomCrew(flightData: FlightData, cockpitCrew: [CrewMember], cabinCrew: [CrewMember]) async {
        await exportToLogTen(flightData: flightData, cockpitCrew: cockpitCrew, cabinCrew: cabinCrew)
    }
    
    /// Get export status
    func getExportStatus() -> (isExporting: Bool, error: String?) {
        return (isExporting: isExporting, error: exportError)
    }
    
    /// Clear export error
    func clearExportError() {
        exportError = nil
    }
    
    /// Validate flight data for export
    func validateFlightData(_ flightData: FlightData) -> Bool {
        return flightData.flightNumber != nil &&
               flightData.aircraftReg != nil &&
               flightData.departureAirport != nil &&
               flightData.arrivalAirport != nil &&
               flightData.date != nil
    }
    
    /// Get export preview
    func getExportPreview(flightData: FlightData, cockpitCrew: [CrewMember], cabinCrew: [CrewMember]) -> String {
        let jsonString = generateLogTenJSON(
            flightNumber: flightData.flightNumber,
            aircraftReg: flightData.aircraftReg,
            departureAirport: flightData.departureAirport,
            arrivalAirport: flightData.arrivalAirport,
            outTime: flightData.outTime,
            offTime: flightData.offTime,
            onTime: flightData.onTime,
            inTime: flightData.inTime,
            schedDep: flightData.schedDep,
            schedArr: flightData.schedArr,
            inferredDate: flightData.date,
            cockpitCrew: cockpitCrew,
            cabinCrew: cabinCrew
        )
        return jsonString
    }
} 