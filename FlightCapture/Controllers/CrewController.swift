import Foundation
import SwiftUI

// MARK: - Models

@MainActor
class CrewController: ObservableObject {
    // MARK: - Properties
    @Published var cockpitCrew: [CrewMember] = []
    @Published var cabinCrew: [CrewMember] = []
    @Published var crewNamesNeedingReview: [CrewReviewItem] = []
    
    // Track crew processing completion
    @Published var isCrewProcessingComplete = false
    
    // OCR Results
    @Published var ocrCockpitResults: [(String, String)] = []
    @Published var ocrCabinResults: [(String, String)] = []
    
    init() {
        resetCrew()
    }
    
    /// Reset all crew data
    func resetCrew() {
        cockpitCrew.removeAll()
        cabinCrew.removeAll()
        crewNamesNeedingReview.removeAll()
        ocrCockpitResults.removeAll()
        ocrCabinResults.removeAll()
    }
    
    /// Update crew from OCR results
    func updateFromOCRResults(cockpitResults: [(String, String)], cabinResults: [(String, String)]) {
        self.ocrCockpitResults = cockpitResults
        self.ocrCabinResults = cabinResults
        
        updateParsedCrewList(cockpitResults: cockpitResults, cabinResults: cabinResults)
    }
    
    /// Update parsed crew list with new display labels and grouping
    func updateParsedCrewList(cockpitResults: [(String, String)], cabinResults: [(String, String)]) {
        let nonEmptyCockpit = cockpitResults.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let nonEmptyCabin = cabinResults.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        DispatchQueue.main.async {
            self.cockpitCrew.removeAll()
            self.cabinCrew.removeAll()
        }
        
        // Use the role assignments that are passed in (from dashboard crew parsing)
        // The roles are already assigned correctly in the calling function
        for (role, text) in nonEmptyCockpit.prefix(4) {
            let rawName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let formattedName = titleCase(rawName)
            DispatchQueue.main.async {
                self.cockpitCrew.append(CrewMember(role: role, name: formattedName))
            }
            print("[DEBUG] Added cockpit crew with assigned role: \(role) - \(formattedName)")
        }
        
        // Use the role assignments that are passed in for cabin crew
        for (role, text) in nonEmptyCabin.prefix(7) {
            let rawName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let formattedName = titleCase(rawName)
            DispatchQueue.main.async {
                self.cabinCrew.append(CrewMember(role: role, name: formattedName))
            }
            print("[DEBUG] Added cabin crew with assigned role: \(role) - \(formattedName)")
        }
    }
    
    /// Update crew from review modal
    func updateFromReview(cockpitCrew: [CrewMember], cabinCrew: [CrewMember]) {
        DispatchQueue.main.async {
            self.cockpitCrew = cockpitCrew
            self.cabinCrew = cabinCrew
        }
    }
    
    /// Get crew for LogTen export
    func getCrewForExport() -> (cockpit: [CrewMember], cabin: [CrewMember]) {
        return (cockpit: cockpitCrew, cabin: cabinCrew)
    }
    
    /// Check if crew needs review
    func needsReview() -> Bool {
        return !crewNamesNeedingReview.isEmpty
    }
    
    /// Add crew member for review
    func addForReview(role: String, original: String, corrected: String) {
        let reviewItem = CrewReviewItem(role: role, original: original, corrected: corrected)
        DispatchQueue.main.async {
            self.crewNamesNeedingReview.append(reviewItem)
        }
    }
    
    /// Clear review items
    func clearReviewItems() {
        DispatchQueue.main.async {
            self.crewNamesNeedingReview.removeAll()
        }
    }
    
    /// Get crew display members with confidence
    func getCrewDisplayMembers() -> (cockpit: [CrewDisplayMember], cabin: [CrewDisplayMember]) {
        let cockpitDisplay = cockpitCrew.map { member in
            CrewDisplayMember(
                role: member.role,
                name: member.name,
                confidence: .medium // Default confidence for crew
            )
        }
        
        let cabinDisplay = cabinCrew.map { member in
            CrewDisplayMember(
                role: member.role,
                name: member.name,
                confidence: .medium // Default confidence for crew
            )
        }
        
        return (cockpit: cockpitDisplay, cabin: cabinDisplay)
    }
    
    /// Process crew list from OCR text
    func processCrewList(_ text: String) -> (cockpit: [(String, String)], cabin: [(String, String)]) {
        let lines = text.components(separatedBy: .newlines)
        var cockpitResults: [(String, String)] = []
        var cabinResults: [(String, String)] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLine.isEmpty {
                // Simple parsing - assume first word is role, rest is name
                let components = trimmedLine.components(separatedBy: .whitespaces)
                if components.count >= 2 {
                    let role = components[0]
                    let name = components.dropFirst().joined(separator: " ")
                    
                    // Determine if cockpit or cabin based on role
                    if isCockpitRole(role) {
                        cockpitResults.append((role, name))
                    } else {
                        cabinResults.append((role, name))
                    }
                }
            }
        }
        
        return (cockpit: cockpitResults, cabin: cabinResults)
    }
    
    /// Process crew ROIs from dashboard image (crew names section)
    @MainActor
    func processDashboardCrewROIs(from uiImage: UIImage) {
        print("[DEBUG] Processing dashboard crew ROIs")
        
        // Dashboard crew names ROI (for single image import) - calibrated for 2360x1640
        let dashboardCrewNamesROI = FieldROI(x: 26/2360, y: 1205/1640, width: (460-26)/2360, height: (1395-1205)/1640)
        
        guard let croppedImage = cropImage(uiImage, to: dashboardCrewNamesROI) else {
            print("[DEBUG] Failed to crop dashboard crew ROI")
            return
        }
        
        ocrText(from: croppedImage, label: "DashboardCrewNames") { [weak self] crewText in
            print("[DEBUG] Dashboard crew names OCR: \(crewText)")
            
            // Parse the crew text and extract names
            let crewNames = self?.parseDashboardCrewText(crewText) ?? []
            print("[DEBUG] Parsed crew names: \(crewNames)")
            
            // For dashboard crew parsing, assign roles based on order in OCR text
            // The crew names appear in order: [Kevin Smith, Daniel Tan, Nick Tam, Kit Wong]
            // Assign roles as: PIC, Relief, SIC, Relief2
            let cockpitLabels = ["PIC", "Relief", "SIC", "Relief2"]
            var cockpitResults: [(String, String)] = []
            
            for (i, name) in crewNames.enumerated() {
                let label = i < cockpitLabels.count ? cockpitLabels[i] : "Relief"
                let formattedName = self?.titleCase(name) ?? name
                cockpitResults.append((label, formattedName))
                print("[DEBUG] Assigned \(formattedName) to role \(label)")
            }
            
            // Update crew data
            self?.updateParsedCrewList(cockpitResults: cockpitResults, cabinResults: [])
        }
    }
    
    /// Process crew ROIs from dedicated crew list image
    @MainActor
    func processCrewROIs(from uiImage: UIImage) {
        print("[DEBUG] Processing crew ROIs from crew list image")
        
        // Clear existing crew data
        cockpitCrew.removeAll()
        cabinCrew.removeAll()
        
        // Calibrated crew ROIs for 2360x1640 screenshots (from original code)
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
        
        // Collect all crew members in order, then assign roles based on seniority
        var cockpitNames: [String] = []
        var cabinNames: [String] = []
        
        let group = DispatchGroup()
        
        // Process cockpit crew ROIs in order (Commander, SIC, Relief, Relief2)
        let cockpitROIs: [(String, FieldROI)] = [
            ("Commander", crewCommanderROI),
            ("SIC", crewSICROI),
            ("Relief", crewReliefROI),
            ("Relief2", crewRelief2ROI)
        ]
        
        for (i, (role, roi)) in cockpitROIs.enumerated() {
            processCrewROI(uiImage: uiImage, roi: roi, field: role, group: group) { text in
                print("[DEBUG] \(role) OCR result: \(text)")
                let name = self.extractCrewName(from: text, role: role)
                if !name.isEmpty {
                    // Store in order based on index
                    DispatchQueue.main.async {
                        while cockpitNames.count <= i {
                            cockpitNames.append("")
                        }
                        cockpitNames[i] = name
                    }
                }
            }
        }
        
        // Process cabin crew ROIs in order
        let cabinROIs: [(String, FieldROI)] = [
            ("ISM", crewCustom2ISMROI),
            ("SP", crewCustom4SPROI),
            ("FP", crewCustom1FPROI),
            ("FA", crewFlightAttendantROI),
            ("FA2", crewFlightAttendant2ROI),
            ("FA3", crewFlightAttendant3ROI),
            ("FA4", crewFlightAttendant4ROI)
        ]
        
        for (i, (role, roi)) in cabinROIs.enumerated() {
            processCrewROI(uiImage: uiImage, roi: roi, field: role, group: group) { text in
                print("[DEBUG] \(role) OCR result: \(text)")
                let name = self.extractCrewName(from: text, role: role)
                if !name.isEmpty {
                    // Store in order based on index
                    DispatchQueue.main.async {
                        while cabinNames.count <= i {
                            cabinNames.append("")
                        }
                        cabinNames[i] = name
                    }
                }
            }
        }
        
        // When all OCR is complete, assign roles based on seniority
        group.notify(queue: .main) {
            print("[DEBUG] All crew OCR complete. Cockpit names: \(cockpitNames), Cabin names: \(cabinNames)")
            
            // Filter out empty names
            let nonEmptyCockpit = cockpitNames.filter { !$0.isEmpty }
            let nonEmptyCabin = cabinNames.filter { !$0.isEmpty }
            
            print("[DEBUG] Non-empty cockpit names: \(nonEmptyCockpit)")
            print("[DEBUG] Non-empty cabin names: \(nonEmptyCabin)")
            
            // Assign cockpit crew roles based on order from OCR
            // The crew names are collected in order: [Kevin Smith, Daniel Tan, Nick Tam, Kit Wong]
            // But we need to assign roles as: PIC, Relief, SIC, Relief2
            // So we need to map: 0->PIC, 1->Relief, 2->SIC, 3->Relief2
            let cockpitLabels = ["PIC", "Relief", "SIC", "Relief2"]
            for (i, name) in nonEmptyCockpit.prefix(4).enumerated() {
                let label = i < cockpitLabels.count ? cockpitLabels[i] : "Relief"
                let crewMember = CrewMember(role: label, name: name)
                DispatchQueue.main.async {
                    self.cockpitCrew.append(crewMember)
                }
                print("[DEBUG] Added cockpit crew: \(label) - \(name)")
            }
            
            // Assign cabin crew roles based on order (like original code)
            let cabinLabels = ["ISM", "SP", "FP", "FA", "FA2", "FA3", "FA4"]
            for (i, name) in nonEmptyCabin.prefix(7).enumerated() {
                let label = i < cabinLabels.count ? cabinLabels[i] : "FA"
                let crewMember = CrewMember(role: label, name: name)
                DispatchQueue.main.async {
                    self.cabinCrew.append(crewMember)
                }
                print("[DEBUG] Added cabin crew: \(label) - \(name)")
            }
            
            // Sort crew by seniority
            DispatchQueue.main.async {
                self.sortCrewBySeniority()
                // Mark crew processing as complete
                self.isCrewProcessingComplete = true
                // Notify flight data controller of completion
                NotificationCenter.default.post(name: .crewProcessingComplete, object: nil)
            }
        }
    }
    
    /// Process a single crew ROI with dispatch group
    private func processCrewROI(uiImage: UIImage, roi: FieldROI, field: String, group: DispatchGroup, completion: @escaping (String) -> Void) {
        group.enter()
        guard let croppedImage = cropImage(uiImage, to: roi) else {
            print("[DEBUG] Failed to crop ROI for \(field)")
            completion("")
            group.leave()
            return
        }
        
        ocrText(from: croppedImage, label: "Crew_\(field)") { text in
            print("[DEBUG] OCR result for \(field): \(text)")
            completion(text)
            group.leave()
        }
    }
    
    /// Extract crew name from OCR text with cleanup
    private func extractCrewName(from ocrText: String, role: String? = nil) -> String {
        print("[DEBUG] extractCrewName called for role: \(role ?? "nil") with OCR text: '\(ocrText)'")
        let knownBases = ["HKG", "SIN", "BKK", "ICN", "KIX", "LAX", "JFK", "LHR", "CDG", "SYD", "MEL", "DXB", "FRA", "SFO", "ORD", "NRT", "CAN", "SZX", "PVG", "PEK", "DEL", "BOM", "AMS", "ZRH", "YYZ", "YVR", "YUL"]
        let parts = ocrText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nameParts = parts.filter { part in
            let upper = part.uppercased()
            return !knownBases.contains(upper) && upper.range(of: "^[A-Z\\s\\-\\.]+$", options: .regularExpression) != nil && upper.count > 1
        }
        var name = nameParts.joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
        let original = name
        print("[DEBUG] Extracted name: '\(name)' from OCR text: '\(ocrText)'")
        
        // Remove trailing dots
        if let dotRange = name.range(of: "[.]+$", options: .regularExpression) {
            print("[DEBUG] Trailing dots detected in name: '\(name)'")
            name.removeSubrange(dotRange)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let role = role, !name.isEmpty {
                // Add to review list if not already present
                if !crewNamesNeedingReview.contains(where: { $0.role == role }) {
                    print("[DEBUG] Adding to crewNamesNeedingReview: role=\(role), original=\(original), corrected=\(name)")
                    let reviewItem = CrewReviewItem(role: role, original: original, corrected: name)
                    DispatchQueue.main.async {
                        self.crewNamesNeedingReview.append(reviewItem)
                    }
                }
            }
        }
        return name.capitalized
    }
    

    
    /// Sort crew members by seniority order
    private func sortCrewBySeniority() {
        cockpitCrew.sort { getSeniorityOrder($0.role) < getSeniorityOrder($1.role) }
        cabinCrew.sort { getSeniorityOrder($0.role) < getSeniorityOrder($1.role) }
        print("[DEBUG] Sorted crew by seniority - Cockpit: \(cockpitCrew.count), Cabin: \(cabinCrew.count)")
    }
    
    /// Parse dashboard crew text
    private func parseDashboardCrewText(_ text: String) -> [String] {
        print("[DEBUG] parseDashboardCrewText called with text: '\(text)'")
        
        // Split by commas first, then process each part
        let commaSeparated = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var names: [String] = []
        
        for part in commaSeparated {
            if !part.isEmpty {
                // Extract individual name from this part
                let name = extractIndividualCrewName(from: part)
                if !name.isEmpty {
                    names.append(name)
                    print("[DEBUG] Extracted individual name: '\(name)' from part: '\(part)'")
                }
            }
        }
        
        print("[DEBUG] Final parsed crew names: \(names)")
        return names
    }
    
    /// Extract individual crew name from a single part
    private func extractIndividualCrewName(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Filter out known non-name patterns
        let knownBases = ["HKG", "SIN", "BKK", "ICN", "KIX", "LAX", "JFK", "LHR", "CDG", "SYD", "MEL", "DXB", "FRA", "SFO", "ORD", "NRT", "CAN", "SZX", "PVG", "PEK", "DEL", "BOM", "AMS", "ZRH", "YYZ", "YVR", "YUL"]
        let knownRoles = ["E-CN", "E-FO", "5-FO", "5-SO", "CN", "FO", "SO"]
        
        let upper = trimmed.uppercased()
        
        // Skip if it's a known base or role
        if knownBases.contains(upper) || knownRoles.contains(upper) {
            return ""
        }
        
        // Check if it looks like a name (contains letters and spaces)
        if upper.range(of: "^[A-Z\\s\\-\\.]+$", options: .regularExpression) != nil && upper.count > 2 {
            // Remove trailing dots and clean up
            var name = trimmed
            if let dotRange = name.range(of: "[.]+$", options: .regularExpression) {
                name.removeSubrange(dotRange)
            }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.capitalized
        }
        
        return ""
    }
    
    /// Check if role is cockpit role
    private func isCockpitRole(_ role: String) -> Bool {
        let cockpitRoles = ["PIC", "Commander", "SIC", "Relief", "Relief2"]
        return cockpitRoles.contains(role)
    }
    
    /// Convert string to title case
    private func titleCase(_ string: String) -> String {
        return string.capitalized
    }
    
    /// Get crew count
    func getCrewCount() -> (cockpit: Int, cabin: Int) {
        return (cockpit: cockpitCrew.count, cabin: cabinCrew.count)
    }
    
    /// Check if crew data is complete
    func isCrewComplete() -> Bool {
        return !cockpitCrew.isEmpty || !cabinCrew.isEmpty
    }
    
    /// Map OCR role to display role
    private func mapRoleToDisplay(_ role: String) -> String {
        print("[DEBUG] Mapping role: '\(role)' to display role")
        
        let roleMapping: [String: String] = [
            "Commander": "PIC",
            "PIC": "PIC", 
            "SIC": "SIC",
            "Relief": "Relief",
            "Relief2": "Relief",
            "ISM": "ISM",
            "SP": "SP",
            "FA": "FA",
            "FA2": "FA2", 
            "FA3": "FA3",
            "FA4": "FA4",
            "FP": "FP"
        ]
        
        let displayRole = roleMapping[role] ?? role
        print("[DEBUG] Mapped '\(role)' to '\(displayRole)'")
        return displayRole
    }
    
    /// Get seniority order for crew roles
    private func getSeniorityOrder(_ role: String) -> Int {
        let seniorityOrder: [String: Int] = [
            "PIC": 1,
            "SIC": 2, 
            "Relief": 3,
            "Relief2": 4,
            "ISM": 5,
            "SP": 6,
            "FP": 7,
            "FA": 8,
            "FA2": 9,
            "FA3": 10,
            "FA4": 11
        ]
        return seniorityOrder[role] ?? 999
    }
} 