import Foundation

/// Extracts the flight number (e.g., CPA648, CX876) from recognized text.
func extractFlightNumber(from recognizedText: String) -> String? {
    // Pattern: 2-3 uppercase letters followed by 2-4 digits
    let pattern = "\\b[A-Z]{2,3}\\d{2,4}\\b"
    let regex = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(recognizedText.startIndex..., in: recognizedText)
    if let match = regex?.firstMatch(in: recognizedText, options: [], range: range) {
        if let flightRange = Range(match.range, in: recognizedText) {
            return String(recognizedText[flightRange])
        }
    }
    return nil
}

// Example test function (for playground or debug use)
func testExtractFlightNumber() {
    let sample = "Flight CPA648, Aircraft: BLRU"
    print(extractFlightNumber(from: sample) ?? "Not found")
}

/// Extracts the aircraft registration (e.g., BLRU, N123AB, G-ABCD) from recognized text.
func extractAircraftRegistration(from recognizedText: String) -> String? {
    // Only match codes that appear after 'Reg' or 'Registration' (with optional comma/whitespace)
    let regPattern = "(?:Reg(?:istration)?[,:\\s]+)([A-Z0-9-]{4,6})"
    if let regex = try? NSRegularExpression(pattern: regPattern, options: .caseInsensitive) {
        let range = NSRange(recognizedText.startIndex..., in: recognizedText)
        if let match = regex.firstMatch(in: recognizedText, options: [], range: range),
           let regRange = Range(match.range(at: 1), in: recognizedText) {
            return String(recognizedText[regRange])
        }
    }
    // Do not fallback to any 4-letter code (to avoid picking up airport codes)
    return nil
}

// Example test function
func testExtractAircraftRegistration() {
    let sample = "Aircraft Type, A359, Reg, BLRU, Avg Wind, H021, Dep Rwy, OERK"
    print(extractAircraftRegistration(from: sample) ?? "Not found")
}

/// Extracts the aircraft type (e.g., A359, B738) from recognized text.
func extractAircraftType(from recognizedText: String) -> String? {
    // Try to find 'Aircraft Type' followed by a word
    let typePattern = "Aircraft Type[:\\s]*([A-Z0-9]{3,5})"
    if let regex = try? NSRegularExpression(pattern: typePattern, options: .caseInsensitive) {
        let range = NSRange(recognizedText.startIndex..., in: recognizedText)
        if let match = regex.firstMatch(in: recognizedText, options: [], range: range),
           let typeRange = Range(match.range(at: 1), in: recognizedText) {
            return String(recognizedText[typeRange])
        }
    }
    // Fallback: look for a pattern like A359, B738, etc. (A/B + 3 digits/letters)
    let fallbackPattern = "\\b[AB][0-9]{3}[A-Z]?\\b"
    if let regex = try? NSRegularExpression(pattern: fallbackPattern) {
        let range = NSRange(recognizedText.startIndex..., in: recognizedText)
        if let match = regex.firstMatch(in: recognizedText, options: [], range: range),
           let typeRange = Range(match.range, in: recognizedText) {
            return String(recognizedText[typeRange])
        }
    }
    return nil
}

// Example test function
func testExtractAircraftType() {
    let sample = "Aircraft Type: A359, Reg: BLRU, Registration: N123AB, G-ABCD"
    print(extractAircraftType(from: sample) ?? "Not found")
} 