import Foundation
import SwiftUI

// MARK: - Flight Data Models

struct FlightData: Codable {
    var flightNumber: String?
    var aircraftReg: String?
    var aircraftType: String?
    var departureAirport: String?
    var arrivalAirport: String?
    var date: Date?
    var outTime: String?
    var offTime: String?
    var onTime: String?
    var inTime: String?
    var schedDep: String?
    var schedArr: String?
}

struct FlightDataForReview: Codable {
    var flightNumber: String
    var aircraftReg: String
    var departure: String
    var arrival: String
    var date: Date
    var outTime: String
    var offTime: String
    var onTime: String
    var inTime: String
}

// MARK: - Confidence Scoring

enum ConfidenceLevel: String, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    
    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }
    
    var description: String {
        switch self {
        case .high: return "High confidence - likely accurate"
        case .medium: return "Medium confidence - review recommended"
        case .low: return "Low confidence - manual review needed"
        }
    }
}

struct ConfidenceResult {
    let level: ConfidenceLevel
    let score: Double
    let reason: String
}

// MARK: - OCR Results

struct OCRResult {
    let text: String
    let confidence: ConfidenceResult
    let field: String
}

// MARK: - ROI Coordinates

struct ROICoordinates {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Flight Field Types

enum FlightField: String, CaseIterable {
    case flightNumber = "Flight Number"
    case aircraftReg = "Aircraft Registration"
    case aircraftType = "Aircraft Type"
    case departure = "Departure Airport"
    case arrival = "Arrival Airport"
    case date = "Date"
    case day = "Day"
    case outTime = "OUT Time"
    case offTime = "OFF Time"
    case onTime = "ON Time"
    case inTime = "IN Time"
    case schedDep = "Scheduled Departure"
    case schedArr = "Scheduled Arrival"
} 