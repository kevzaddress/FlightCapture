import Foundation
import SwiftUI
import PhotosUI

// MARK: - Notification Names
extension Notification.Name {
    static let crewProcessingComplete = Notification.Name("crewProcessingComplete")
}

// MARK: - Models

@MainActor
class FlightDataController: ObservableObject {
    @Published var flightData = FlightData()
    @Published var editedFlightData = FlightData()
    @Published var inferredDate: Date?
    @Published var dateConfidence: ConfidenceLevel = .low
    
    // OCR Results
    @Published var ocrResults: [String: String] = [:]
    @Published var confidenceResults: [String: ConfidenceLevel] = [:]
    @Published var recognizedText: String = ""
    
    // Image processing state
    @Published var importedImages: [UIImage] = []
    @Published var ocrResultsList: [String] = []
    @Published var imageTypes: [String] = []
    @Published var isOCRComplete: Bool = false
    
    // MARK: - Initialization
    init() {
        resetData()
        // Set up notification observer for crew processing completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCrewProcessingComplete),
            name: .crewProcessingComplete,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleCrewProcessingComplete() {
        DispatchQueue.main.async {
            self.markCrewProcessingComplete()
        }
    }
    
    /// Reset all flight data
    func resetData() {
        flightData = FlightData()
        editedFlightData = FlightData()
        inferredDate = nil
        dateConfidence = .low
        ocrResults.removeAll()
        confidenceResults.removeAll()
        importedImages.removeAll()
        ocrResultsList.removeAll()
        imageTypes.removeAll()
        isOCRComplete = false
    }
    
    /// Update flight data from OCR results
    func updateFromOCRResults(_ results: OCRProcessingResult) {
        // Update OCR results
        if let flightNumber = results.flightNumber {
            ocrResults["flightNumber"] = flightNumber.text
            confidenceResults["flightNumber"] = flightNumber.confidence.level
            flightData.flightNumber = flightNumber.text
        }
        
        if let aircraftType = results.aircraftType {
            ocrResults["aircraftType"] = aircraftType.text
            confidenceResults["aircraftType"] = aircraftType.confidence.level
            flightData.aircraftType = aircraftType.text
        }
        
        if let aircraftReg = results.aircraftReg {
            ocrResults["aircraftReg"] = aircraftReg.text
            confidenceResults["aircraftReg"] = aircraftReg.confidence.level
            flightData.aircraftReg = aircraftReg.text
        }
        
        if let departure = results.departure {
            ocrResults["departure"] = departure.text
            confidenceResults["departure"] = departure.confidence.level
            flightData.departureAirport = departure.text
        }
        
        if let arrival = results.arrival {
            ocrResults["arrival"] = arrival.text
            confidenceResults["arrival"] = arrival.confidence.level
            flightData.arrivalAirport = arrival.text
        }
        
        if let date = results.date {
            ocrResults["date"] = date.text
            confidenceResults["date"] = date.confidence.level
        }
        
        if let day = results.day {
            ocrResults["day"] = day.text
            confidenceResults["day"] = day.confidence.level
        }
        
        if let outTime = results.outTime {
            ocrResults["outTime"] = outTime.text
            confidenceResults["outTime"] = outTime.confidence.level
            flightData.outTime = outTime.text
        }
        
        if let offTime = results.offTime {
            ocrResults["offTime"] = offTime.text
            confidenceResults["offTime"] = offTime.confidence.level
            flightData.offTime = offTime.text
        }
        
        if let onTime = results.onTime {
            ocrResults["onTime"] = onTime.text
            confidenceResults["onTime"] = onTime.confidence.level
            flightData.onTime = onTime.text
        }
        
        if let inTime = results.inTime {
            ocrResults["inTime"] = inTime.text
            confidenceResults["inTime"] = inTime.confidence.level
            flightData.inTime = inTime.text
        }
        
        if let schedDep = results.schedDep {
            ocrResults["schedDep"] = schedDep.text
            confidenceResults["schedDep"] = schedDep.confidence.level
            flightData.schedDep = schedDep.text
        }
        
        if let schedArr = results.schedArr {
            ocrResults["schedArr"] = schedArr.text
            confidenceResults["schedArr"] = schedArr.confidence.level
            flightData.schedArr = schedArr.text
        }
        
        // Process date inference
        processDateInference()
    }
    
    /// Process date inference from date and day fields
    private func processDateInference() {
        let dateText = ocrResults["date"] ?? ""
        let dayText = ocrResults["day"] ?? ""
        
        if let day = Int(dateText), !dayText.isEmpty {
            if let inferredDate = DateUtils.parseDateFromDayAndWeekday(day: day, weekday: dayText) {
                DispatchQueue.main.async { [weak self] in
                    self?.inferredDate = inferredDate
                    self?.flightData.date = inferredDate
                }
                
                // Calculate date confidence based on OCR confidence
                let dateConf = confidenceResults["date"] ?? .low
                let dayConf = confidenceResults["day"] ?? .low
                
                let newConfidence: ConfidenceLevel
                if dateConf == .high && dayConf == .high {
                    newConfidence = .high
                } else if dateConf == .medium || dayConf == .medium {
                    newConfidence = .medium
                } else {
                    newConfidence = .low
                }
                
                DispatchQueue.main.async { [weak self] in
                    self?.dateConfidence = newConfidence
                }
                
                print("[DEBUG] Date inference successful: \(day) \(dayText) -> \(DateUtils.formatDate(inferredDate))")
            } else {
                print("[DEBUG] Date inference failed for: \(day) \(dayText)")
                DispatchQueue.main.async { [weak self] in
                    self?.dateConfidence = .low
                }
            }
        } else {
            print("[DEBUG] Date inference failed - missing data: date='\(dateText)' day='\(dayText)'")
            DispatchQueue.main.async { [weak self] in
                self?.dateConfidence = .low
            }
        }
    }
    
    /// Apply edited data
    func applyEditedData(_ editedData: FlightDataForReview) {
        print("[DEBUG] Applying edited flight data:")
        print("[DEBUG] - Flight Number: '\(editedData.flightNumber)'")
        print("[DEBUG] - Aircraft Reg: '\(editedData.aircraftReg)'")
        print("[DEBUG] - Departure: '\(editedData.departure)'")
        print("[DEBUG] - Arrival: '\(editedData.arrival)'")
        print("[DEBUG] - Out Time: '\(editedData.outTime)'")
        print("[DEBUG] - Off Time: '\(editedData.offTime)'")
        print("[DEBUG] - On Time: '\(editedData.onTime)'")
        print("[DEBUG] - In Time: '\(editedData.inTime)'")
        
        editedFlightData.flightNumber = editedData.flightNumber
        editedFlightData.aircraftReg = editedData.aircraftReg
        editedFlightData.departureAirport = editedData.departure
        editedFlightData.arrivalAirport = editedData.arrival
        editedFlightData.date = editedData.date
        editedFlightData.outTime = editedData.outTime
        editedFlightData.offTime = editedData.offTime
        editedFlightData.onTime = editedData.onTime
        editedFlightData.inTime = editedData.inTime
        
        print("[DEBUG] Updated editedFlightData properties:")
        print("[DEBUG] - Flight Number: '\(editedFlightData.flightNumber ?? "nil")'")
        print("[DEBUG] - Aircraft Reg: '\(editedFlightData.aircraftReg ?? "nil")'")
        print("[DEBUG] - Departure: '\(editedFlightData.departureAirport ?? "nil")'")
        print("[DEBUG] - Arrival: '\(editedFlightData.arrivalAirport ?? "nil")'")
        print("[DEBUG] - Out Time: '\(editedFlightData.outTime ?? "nil")'")
        print("[DEBUG] - Off Time: '\(editedFlightData.offTime ?? "nil")'")
        print("[DEBUG] - On Time: '\(editedFlightData.onTime ?? "nil")'")
        print("[DEBUG] - In Time: '\(editedFlightData.inTime ?? "nil")'")
        
        // Update confidence to high for edited fields
        confidenceResults["flightNumber"] = .high
        confidenceResults["aircraftReg"] = .high
        confidenceResults["departure"] = .high
        confidenceResults["arrival"] = .high
        confidenceResults["outTime"] = .high
        confidenceResults["offTime"] = .high
        confidenceResults["onTime"] = .high
        confidenceResults["inTime"] = .high
    }
    
    /// Get current flight data (edited takes precedence)
    func getCurrentFlightData() -> FlightData {
        var currentData = flightData
        
        print("[DEBUG] getCurrentFlightData - Original flight data:")
        print("[DEBUG] - Flight Number: '\(currentData.flightNumber ?? "nil")'")
        print("[DEBUG] - Aircraft Reg: '\(currentData.aircraftReg ?? "nil")'")
        print("[DEBUG] - Departure: '\(currentData.departureAirport ?? "nil")'")
        print("[DEBUG] - Arrival: '\(currentData.arrivalAirport ?? "nil")'")
        print("[DEBUG] - Out Time: '\(currentData.outTime ?? "nil")'")
        print("[DEBUG] - Off Time: '\(currentData.offTime ?? "nil")'")
        print("[DEBUG] - On Time: '\(currentData.onTime ?? "nil")'")
        print("[DEBUG] - In Time: '\(currentData.inTime ?? "nil")'")
        
        // Apply edited values if they exist
        if let editedFlightNumber = editedFlightData.flightNumber, !editedFlightNumber.isEmpty {
            currentData.flightNumber = editedFlightNumber
            print("[DEBUG] Applied edited flight number: '\(editedFlightNumber)'")
        }
        if let editedAircraftReg = editedFlightData.aircraftReg, !editedAircraftReg.isEmpty {
            currentData.aircraftReg = editedAircraftReg
            print("[DEBUG] Applied edited aircraft reg: '\(editedAircraftReg)'")
        }
        if let editedDeparture = editedFlightData.departureAirport, !editedDeparture.isEmpty {
            currentData.departureAirport = editedDeparture
            print("[DEBUG] Applied edited departure: '\(editedDeparture)'")
        }
        if let editedArrival = editedFlightData.arrivalAirport, !editedArrival.isEmpty {
            currentData.arrivalAirport = editedArrival
            print("[DEBUG] Applied edited arrival: '\(editedArrival)'")
        }
        if let editedOutTime = editedFlightData.outTime, !editedOutTime.isEmpty {
            currentData.outTime = editedOutTime
            print("[DEBUG] Applied edited out time: '\(editedOutTime)'")
        }
        if let editedOffTime = editedFlightData.offTime, !editedOffTime.isEmpty {
            currentData.offTime = editedOffTime
            print("[DEBUG] Applied edited off time: '\(editedOffTime)'")
        }
        if let editedOnTime = editedFlightData.onTime, !editedOnTime.isEmpty {
            currentData.onTime = editedOnTime
            print("[DEBUG] Applied edited on time: '\(editedOnTime)'")
        }
        if let editedInTime = editedFlightData.inTime, !editedInTime.isEmpty {
            currentData.inTime = editedInTime
            print("[DEBUG] Applied edited in time: '\(editedInTime)'")
        }
        
        print("[DEBUG] Final flight data for export:")
        print("[DEBUG] - Flight Number: '\(currentData.flightNumber ?? "nil")'")
        print("[DEBUG] - Aircraft Reg: '\(currentData.aircraftReg ?? "nil")'")
        print("[DEBUG] - Departure: '\(currentData.departureAirport ?? "nil")'")
        print("[DEBUG] - Arrival: '\(currentData.arrivalAirport ?? "nil")'")
        print("[DEBUG] - Out Time: '\(currentData.outTime ?? "nil")'")
        print("[DEBUG] - Off Time: '\(currentData.offTime ?? "nil")'")
        print("[DEBUG] - On Time: '\(currentData.onTime ?? "nil")'")
        print("[DEBUG] - In Time: '\(currentData.inTime ?? "nil")'")
        
        return currentData
    }
    
    // MARK: - Computed Properties (moved from ContentView)
    
    /// Computed flight number (edited takes precedence, then OCR, then extraction)
    var computedFlightNumber: String? {
        if let edited = editedFlightData.flightNumber, !edited.isEmpty { 
            return edited 
        }
        if let ocr = ocrResults["flightNumber"], !ocr.isEmpty { 
            return ocr.trimmingCharacters(in: .whitespacesAndNewlines) 
        }
        // Fallback to extraction from recognized text using global function
        return extractFlightNumber(from: recognizedText)
    }
    
    /// Computed aircraft registration
    var computedAircraftReg: String? {
        if let edited = editedFlightData.aircraftReg, !edited.isEmpty { 
            return edited 
        }
        if let ocr = ocrResults["aircraftReg"], !ocr.isEmpty { 
            return ocr.trimmingCharacters(in: .whitespacesAndNewlines) 
        }
        return extractAircraftRegistration(from: recognizedText)
    }
    
    /// Computed departure airport
    var computedDepartureAirport: String? {
        if let edited = editedFlightData.departureAirport, !edited.isEmpty { 
            return edited 
        }
        if let ocr = ocrResults["departure"], !ocr.isEmpty { 
            return ocr.trimmingCharacters(in: .whitespacesAndNewlines) 
        }
        return extractDepartureAirport(from: recognizedText)
    }
    
    /// Computed arrival airport
    var computedArrivalAirport: String? {
        if let edited = editedFlightData.arrivalAirport, !edited.isEmpty { 
            return edited 
        }
        if let ocr = ocrResults["arrival"], !ocr.isEmpty { 
            return ocr.trimmingCharacters(in: .whitespacesAndNewlines) 
        }
        return extractArrivalAirport(from: recognizedText)
    }
    
    /// Computed out time
    var computedOutTime: String? {
        if let edited = editedFlightData.outTime, !edited.isEmpty { 
            return edited 
        }
        if let ocr = ocrResults["outTime"], !ocr.isEmpty { 
            return ocr.trimmingCharacters(in: .whitespacesAndNewlines) 
        }
        return ocrResults["outTime"]
    }
    
    /// Computed off time
    var computedOffTime: String? {
        if let edited = editedFlightData.offTime, !edited.isEmpty { 
            return edited 
        }
        if let ocr = ocrResults["offTime"], !ocr.isEmpty { 
            return ocr.trimmingCharacters(in: .whitespacesAndNewlines) 
        }
        return ocrResults["offTime"]
    }
    
    /// Computed on time
    var computedOnTime: String? {
        if let edited = editedFlightData.onTime, !edited.isEmpty { 
            return edited 
        }
        if let ocr = ocrResults["onTime"], !ocr.isEmpty { 
            return ocr.trimmingCharacters(in: .whitespacesAndNewlines) 
        }
        return ocrResults["onTime"]
    }
    
    /// Computed in time
    var computedInTime: String? {
        if let edited = editedFlightData.inTime, !edited.isEmpty { 
            return edited 
        }
        if let ocr = ocrResults["inTime"], !ocr.isEmpty { 
            return ocr.trimmingCharacters(in: .whitespacesAndNewlines) 
        }
        return ocrResults["inTime"]
    }
    
    // MARK: - Date Inference Logic (moved from ContentView)
    
    /// Helper to infer the full date from OCR day-of-week and day-of-month
    func inferDate(dayOfWeek: String, dayOfMonth: Int, today: Date = Date()) -> (date: Date?, confidence: ConfidenceLevel) {
        let calendar = Calendar.current
        let maxYearsBack = 2
        let todayNoon = calendar.startOfDay(for: today).addingTimeInterval(12*3600)
        for yearOffset in 0...maxYearsBack {
            let year = calendar.component(.year, from: today) - yearOffset
            for month in (1...12).reversed() {
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = dayOfMonth
                if let candidate = calendar.date(from: comps), candidate <= todayNoon {
                    let weekdaySymbol = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: candidate) - 1]
                    if weekdaySymbol.lowercased().hasPrefix(dayOfWeek.lowercased()) {
                        // If this is the only match in the last 2 years, high confidence
                        return (candidate, .high)
                    }
                }
            }
        }
        return (nil, .low)
    }
    
    /// Helper to parse OCR string like "Mon 30" or "30, Mon" into ("Mon", 30)
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
    
    /// Returns inferred date if possible
    var inferredDateWithConfidence: (date: Date?, confidence: ConfidenceLevel) {
        if let editedDate = editedFlightData.date {
            return (editedDate, .high)
        }
        guard let (dow, dom) = parseDayDate(ocrResults["dayDate"] ?? "") else { return (nil, .low) }
        return inferDate(dayOfWeek: dow, dayOfMonth: dom)
    }
    

    
    /// Prepare flight data for review
    func prepareFlightDataForReview() -> FlightDataForReview {
        let currentData = getCurrentFlightData()
        
        return FlightDataForReview(
            flightNumber: currentData.flightNumber ?? "",
            aircraftReg: currentData.aircraftReg ?? "",
            departure: currentData.departureAirport ?? "",
            arrival: currentData.arrivalAirport ?? "",
            date: currentData.date ?? DateUtils.getCurrentDate(),
            outTime: currentData.outTime ?? "",
            offTime: currentData.offTime ?? "",
            onTime: currentData.onTime ?? "",
            inTime: currentData.inTime ?? ""
        )
    }
    
    /// Get confidence for a field
    func getConfidence(for field: String) -> ConfidenceLevel {
        return confidenceResults[field] ?? .low
    }
    
    /// Check if data is complete for export
    func isDataComplete() -> Bool {
        let data = getCurrentFlightData()
        return data.flightNumber != nil && 
               data.aircraftReg != nil && 
               data.departureAirport != nil && 
               data.arrivalAirport != nil &&
               data.date != nil
    }
    
    /// Handle photo selection, import, OCR, and classification (refactored from original ContentView)
    func handlePhotoSelection(_ newItems: [PhotosPickerItem], processDashboardROIs: @escaping (UIImage) -> Void, processDashboardCrewROIs: @escaping (UIImage) -> Void, processCrewROIs: @escaping (UIImage) -> Void) {
        print("[DEBUG] User selected photos: \(newItems.map { String(describing: $0) })")
        importedImages = []
        ocrResultsList = []
        imageTypes = []
        // Clear edited values for new flight (handled in view/controller as needed)
        // Temporary holders for dashboard/crewList images
        var dashboardImage: UIImage? = nil
        var crewListImage: UIImage? = nil
        
        // Initialize imageTypes array
        imageTypes = []
        
        // Track completion
        var processedCount = 0
        
        // Load and classify images
        for (idx, item) in newItems.enumerated() {
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    print("[DEBUG] Loaded image #\(idx+1) from picker, size: \(uiImage.size)")
                    
                    // Add image to importedImages array
                    DispatchQueue.main.async {
                        self.importedImages.append(uiImage)
                    }
                    
                    // Run OCR on the full image (no cropping yet)
                    ocrText(from: uiImage, label: "FullImage#\(idx+1)") { [self] text in
                        print("[DEBUG] OCR result for image #\(idx+1): \(text.prefix(100))...")
                        self.ocrResultsList.append(text)
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
                        
                        // Update the imageTypes array based on the classification result
                        DispatchQueue.main.async {
                            // Add the classification result to the imageTypes array (simple append like original)
                            self.imageTypes.append(type)
                            print("[DEBUG] Image #\(idx+1) classified as: \(type)")
                            
                            processedCount += 1
                            print("[DEBUG] Processed \(processedCount) of \(newItems.count) images")
                            
                            // After all images are classified, process ROIs
                            if processedCount == newItems.count {
                                print("[DEBUG] All images processed, starting ROI processing")
                                print("[DEBUG] Final imageTypes array: \(self.imageTypes)")
                                // If only one image, treat as dashboard and process both dashboard and crew ROIs
                                if newItems.count == 1, let img = self.importedImages.first {
                                    processDashboardROIs(img)
                                    processDashboardCrewROIs(img)
                                } else if newItems.count == 2 {
                                    // Two images: process dashboard for flight details, crewList for crew
                                    if let dashImg = dashboardImage {
                                        processDashboardROIs(dashImg)
                                    }
                                    if let crewImg = crewListImage {
                                        processCrewROIs(crewImg)
                                    }
                                }
                            }
                        }
                        print("[DEBUG] Image #\(idx+1) classified as: \(type)")
                    }
                } else {
                    print("[DEBUG] Failed to load image #\(idx+1) from picker.")
                }
            }
        }
    }
    
    /// Process dashboard ROIs for flight data extraction
    @MainActor
    func processDashboardROIs(from uiImage: UIImage) {
        print("[DEBUG] Processing dashboard ROIs for flight data")
        
        // Track completion of all ROIs
        var completedROIs = 0
        let totalROIs = 12 // flightNumber, aircraftType, aircraftReg, departure, arrival, schedDep, schedArr, dayDate, outTime, offTime, onTime, inTime
        
        // Calibrated ROIs for 2360x1640 screenshots (from original code)
        // Flight Number: top-left (8, 41.8), bottom-right (235, 147)
        let flightNumberROI = FieldROI(x: 8/2360, y: 41.8/1640, width: (235-8)/2360, height: (147-41.8)/1640)
        // Aircraft Type: top-left (28, 223), bottom-right (171, 297)
        let aircraftTypeROI = FieldROI(x: 28/2360, y: 223/1640, width: (171-28)/2360, height: (297-223)/1640)
        // Aircraft Reg: top-left (241, 223), bottom-right (352, 297)
        let aircraftRegROI = FieldROI(x: 241/2360, y: 223/1640, width: (352-241)/2360, height: (297-223)/1640)
        // Departure Airport: top-left (560, 60), bottom-right (641, 96)
        let departureROI = FieldROI(x: 560/2360, y: 60/1640, width: (641-560)/2360, height: (96-60)/1640)
        // Arrival Airport: top-left (807, 60), bottom-right (894, 96)
        let arrivalROI = FieldROI(x: 807/2360, y: 60/1640, width: (894-807)/2360, height: (96-60)/1640)
        // Scheduled Departure Time: top-left (647, 60), bottom-right (750, 96)
        let schedDepROI = FieldROI(x: 647/2360, y: 60/1640, width: (750-647)/2360, height: (96-60)/1640)
        // Scheduled Arrival Time: top-left (900, 60), bottom-right (1026, 96)
        let schedArrROI = FieldROI(x: 900/2360, y: 60/1640, width: (1026-900)/2360, height: (96-60)/1640)
        // Day and Date: top-left (480, 56), bottom-right (543, 130)
        let dayDateROI = FieldROI(x: 480/2360, y: 56/1640, width: (543-480)/2360, height: (130-56)/1640)
        // Time ROIs for OUT-OFF-ON-IN (adjusted to capture only time values, not labels)
        let outTimeROI = FieldROI(x: 1970/2360, y: 1128/1640, width: (2055-1970)/2360, height: (1166-1128)/1640)
        let offTimeROI = FieldROI(x: 1970/2360, y: 1170/1640, width: (2055-1970)/2360, height: (1208-1170)/1640)
        let onTimeROI = FieldROI(x: 1970/2360, y: 1230/1640, width: (2055-1970)/2360, height: (1270-1230)/1640)
        let inTimeROI = FieldROI(x: 1970/2360, y: 1270/1640, width: (2055-1970)/2360, height: (1305-1270)/1640)
        
        // Process each ROI
        processROI(uiImage: uiImage, roi: flightNumberROI, field: "flightNumber") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] Flight Number OCR result: \(text)")
                self?.flightData.flightNumber = text
                self?.ocrResults["flightNumber"] = text
                self?.confidenceResults["flightNumber"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: aircraftTypeROI, field: "aircraftType") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] Aircraft Type OCR result: \(text)")
                self?.flightData.aircraftType = text
                self?.ocrResults["aircraftType"] = text
                self?.confidenceResults["aircraftType"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: aircraftRegROI, field: "aircraftReg") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] Aircraft Reg OCR result: \(text)")
                let extracted = self?.extractRegFromOCR(text) ?? text
                let normalized = self?.normalizeAircraftReg(extracted) ?? extracted
                self?.flightData.aircraftReg = normalized
                self?.ocrResults["aircraftReg"] = text
                self?.confidenceResults["aircraftReg"] = .medium
                print("[DEBUG] Processed aircraft reg: '\(text)' -> '\(self?.flightData.aircraftReg ?? "")'")
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: departureROI, field: "departure") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] Departure OCR result: \(text)")
                self?.flightData.departureAirport = text
                self?.ocrResults["departure"] = text
                self?.confidenceResults["departure"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: arrivalROI, field: "arrival") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] Arrival OCR result: \(text)")
                self?.flightData.arrivalAirport = text
                self?.ocrResults["arrival"] = text
                self?.confidenceResults["arrival"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: schedDepROI, field: "schedDep") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] Scheduled Departure OCR result: \(text)")
                self?.flightData.schedDep = text
                self?.ocrResults["schedDep"] = text
                self?.confidenceResults["schedDep"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: schedArrROI, field: "schedArr") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] Scheduled Arrival OCR result: \(text)")
                self?.flightData.schedArr = text
                self?.ocrResults["schedArr"] = text
                self?.confidenceResults["schedArr"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: dayDateROI, field: "dayDate") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] Day/Date OCR result: \(text)")
                self?.ocrResults["dayDate"] = text
                self?.confidenceResults["dayDate"] = .medium
                // Process date inference
                self?.processDateInference()
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: outTimeROI, field: "outTime") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] OUT Time OCR result: \(text)")
                self?.flightData.outTime = text
                self?.ocrResults["outTime"] = text
                self?.confidenceResults["outTime"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: offTimeROI, field: "offTime") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] OFF Time OCR result: \(text)")
                self?.flightData.offTime = text
                self?.ocrResults["offTime"] = text
                self?.confidenceResults["offTime"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: onTimeROI, field: "onTime") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] ON Time OCR result: \(text)")
                self?.flightData.onTime = text
                self?.ocrResults["onTime"] = text
                self?.confidenceResults["onTime"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
        
        processROI(uiImage: uiImage, roi: inTimeROI, field: "inTime") { [weak self] text in
            DispatchQueue.main.async {
                print("[DEBUG] IN Time OCR result: \(text)")
                self?.flightData.inTime = text
                self?.ocrResults["inTime"] = text
                self?.confidenceResults["inTime"] = .medium
                completedROIs += 1
                if completedROIs == totalROIs {
                    self?.markFlightDataComplete()
                }
            }
        }
    }
    
    /// Process a single ROI and run OCR
    private func processROI(uiImage: UIImage, roi: FieldROI, field: String, completion: @escaping (String) -> Void) {
        guard let croppedImage = cropImage(uiImage, to: roi) else {
            print("[DEBUG] Failed to crop ROI for \(field)")
            completion("")
            return
        }
        
        ocrText(from: croppedImage, label: field) { text in
            print("[DEBUG] OCR result for \(field): \(text)")
            completion(text)
        }
    }

    // --- Begin original aircraft registration extraction/normalization ---
    /// Extract reg from OCR string (e.g., "Reg, BLRS")
    private func extractRegFromOCR(_ text: String) -> String? {
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
    /// Normalize aircraft registration (e.g., BLRU -> B-LRU)
    private func normalizeAircraftReg(_ reg: String?) -> String? {
        guard let reg = reg?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !reg.isEmpty else { return nil }
        if reg.hasPrefix("B-") && reg.count == 5 { return reg }
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
    
    /// Mark OCR processing as complete
    @MainActor
    func markOCRComplete() {
        print("[DEBUG] Marking OCR processing as complete")
        isOCRComplete = true
    }
    
    // Track flight data and crew processing completion
    private var flightDataProcessingComplete = false
    private var crewProcessingComplete = false

    /// Mark flight data processing as complete (coordinated with crew processing)
    @MainActor
    func markFlightDataComplete() {
        print("[DEBUG] Flight data processing complete")
        flightDataProcessingComplete = true
        if crewProcessingComplete {
            print("[DEBUG] Both flight data and crew processing complete - marking OCR complete")
            isOCRComplete = true
        } else {
            print("[DEBUG] Flight data complete, waiting for crew processing...")
        }
    }

    /// Mark crew processing as complete (coordinated with flight data processing)
    @MainActor
    func markCrewProcessingComplete() {
        print("[DEBUG] Crew processing complete")
        crewProcessingComplete = true
        if flightDataProcessingComplete {
            print("[DEBUG] Both flight data and crew processing complete - marking OCR complete")
            isOCRComplete = true
        } else {
            print("[DEBUG] Crew processing complete, waiting for flight data...")
        }
    }
    
    // --- End original code ---
} 