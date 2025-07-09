import Foundation

// MARK: - Confidence Scoring Utilities

struct ConfidenceUtils {
    
    /// Calculate confidence score for OCR text
    static func calculateConfidence(for text: String, field: FlightField) -> ConfidenceResult {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Empty text gets low confidence
        if normalizedText.isEmpty {
            return ConfidenceResult(
                level: .low,
                score: 0.0,
                reason: "Empty text"
            )
        }
        
        var score = 0.0
        var reasons: [String] = []
        
        // Length-based scoring
        let lengthScore = min(Double(normalizedText.count) / 10.0, 1.0)
        score += lengthScore * 0.2
        reasons.append("Length: \(normalizedText.count) chars")
        
        // Character quality scoring
        let alphaNumericRatio = Double(normalizedText.filter { $0.isLetter || $0.isNumber }.count) / Double(normalizedText.count)
        score += alphaNumericRatio * 0.3
        reasons.append("Alphanumeric ratio: \(String(format: "%.1f", alphaNumericRatio * 100))%")
        
        // Field-specific validation
        let fieldScore = validateFieldSpecific(text: normalizedText, field: field)
        score += fieldScore * 0.5
        reasons.append("Field validation: \(String(format: "%.1f", fieldScore * 100))%")
        
        // Determine confidence level
        let level: ConfidenceLevel
        if score >= 0.8 {
            level = .high
        } else if score >= 0.5 {
            level = .medium
        } else {
            level = .low
        }
        
        return ConfidenceResult(
            level: level,
            score: score,
            reason: reasons.joined(separator: ", ")
        )
    }
    
    /// Validate text based on field type
    private static func validateFieldSpecific(text: String, field: FlightField) -> Double {
        switch field {
        case .flightNumber:
            return validateFlightNumber(text)
        case .aircraftReg:
            return validateAircraftRegistration(text)
        case .aircraftType:
            return validateAircraftType(text)
        case .departure, .arrival:
            return validateAirportCode(text)
        case .date:
            return validateDate(text)
        case .day:
            return validateDayOfWeek(text)
        case .outTime, .offTime, .onTime, .inTime, .schedDep, .schedArr:
            return validateTime(text)
        }
    }
    
    /// Validate flight number format
    private static func validateFlightNumber(_ text: String) -> Double {
        let flightNumberPattern = "^[A-Z]{2,3}\\d{1,4}$"
        if text.range(of: flightNumberPattern, options: .regularExpression) != nil {
            return 1.0
        }
        
        // Partial matches
        if text.contains(where: { $0.isLetter }) && text.contains(where: { $0.isNumber }) {
            return 0.7
        }
        
        return 0.3
    }
    
    /// Validate aircraft registration format
    private static func validateAircraftRegistration(_ text: String) -> Double {
        let regPattern = "^[A-Z]-[A-Z]{4,5}$"
        if text.range(of: regPattern, options: .regularExpression) != nil {
            return 1.0
        }
        
        // Partial matches
        if text.contains("-") && text.count >= 6 {
            return 0.8
        }
        
        if text.count >= 4 && text.allSatisfy({ $0.isLetter || $0 == "-" }) {
            return 0.6
        }
        
        return 0.3
    }
    
    /// Validate aircraft type
    private static func validateAircraftType(_ text: String) -> Double {
        let commonTypes = ["A320", "A321", "A330", "A350", "A380", "B737", "B747", "B777", "B787"]
        let upperText = text.uppercased()
        
        if commonTypes.contains(upperText) {
            return 1.0
        }
        
        if upperText.hasPrefix("A") || upperText.hasPrefix("B") {
            return 0.8
        }
        
        if text.count >= 3 && text.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return 0.6
        }
        
        return 0.3
    }
    
    /// Validate airport code
    private static func validateAirportCode(_ text: String) -> Double {
        let airportPattern = "^[A-Z]{3}$"
        if text.range(of: airportPattern, options: .regularExpression) != nil {
            return 1.0
        }
        
        if text.count == 3 && text.allSatisfy({ $0.isLetter }) {
            return 0.9
        }
        
        if text.count >= 2 && text.allSatisfy({ $0.isLetter }) {
            return 0.6
        }
        
        return 0.3
    }
    
    /// Validate date format
    private static func validateDate(_ text: String) -> Double {
        let numberPattern = "^\\d{1,2}$"
        if text.range(of: numberPattern, options: .regularExpression) != nil {
            if let day = Int(text), day >= 1 && day <= 31 {
                return 1.0
            }
        }
        
        if text.allSatisfy({ $0.isNumber }) {
            return 0.7
        }
        
        return 0.3
    }
    
    /// Validate day of week
    private static func validateDayOfWeek(_ text: String) -> Double {
        let days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        let lowerText = text.lowercased()
        
        if days.contains(lowerText) {
            return 1.0
        }
        
        if days.contains(where: { lowerText.hasPrefix($0) }) {
            return 0.8
        }
        
        if text.count >= 3 && text.allSatisfy({ $0.isLetter }) {
            return 0.5
        }
        
        return 0.2
    }
    
    /// Validate time format
    private static func validateTime(_ text: String) -> Double {
        let timePattern = "^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$"
        if text.range(of: timePattern, options: .regularExpression) != nil {
            return 1.0
        }
        
        if text.contains(":") && text.count >= 4 {
            return 0.8
        }
        
        if text.allSatisfy({ $0.isNumber || $0 == ":" }) {
            return 0.6
        }
        
        return 0.3
    }
    
    /// Get confidence color for UI
    static func getConfidenceColor(_ level: ConfidenceLevel) -> String {
        switch level {
        case .high: return "green"
        case .medium: return "yellow"
        case .low: return "red"
        }
    }
    
    /// Get confidence description for UI
    static func getConfidenceDescription(_ level: ConfidenceLevel) -> String {
        switch level {
        case .high: return "High confidence - likely accurate"
        case .medium: return "Medium confidence - review recommended"
        case .low: return "Low confidence - manual review needed"
        }
    }
} 