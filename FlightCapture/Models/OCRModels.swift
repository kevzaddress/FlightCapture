import Foundation
import UIKit
import Vision

// MARK: - OCR Models

struct OCRFieldResult {
    let field: String
    let text: String
    let confidence: ConfidenceResult
    let croppedImage: UIImage?
}

struct OCRProcessingResult {
    let flightNumber: OCRFieldResult?
    let aircraftType: OCRFieldResult?
    let aircraftReg: OCRFieldResult?
    let departure: OCRFieldResult?
    let arrival: OCRFieldResult?
    let date: OCRFieldResult?
    let day: OCRFieldResult?
    let outTime: OCRFieldResult?
    let offTime: OCRFieldResult?
    let onTime: OCRFieldResult?
    let inTime: OCRFieldResult?
    let schedDep: OCRFieldResult?
    let schedArr: OCRFieldResult?
}

// MARK: - ROI Definitions

struct ROIDefinition {
    let name: String
    let coordinates: ROICoordinates
    let field: FlightField
}

// MARK: - OCR Processing State

enum OCRProcessingState {
    case idle
    case processing
    case completed
    case failed(Error)
}

extension OCRProcessingState: Equatable {
    static func == (lhs: OCRProcessingState, rhs: OCRProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.processing, .processing): return true
        case (.completed, .completed): return true
        case let (.failed(le), .failed(re)):
            return (le as NSError).domain == (re as NSError).domain && (le as NSError).code == (re as NSError).code
        default: return false
        }
    }
}

// MARK: - OCR Configuration

struct OCRConfiguration {
    let recognitionLevel: VNRequestTextRecognitionLevel
    let usesLanguageCorrection: Bool
    let minimumTextHeight: Float
    
    static let `default` = OCRConfiguration(
        recognitionLevel: .accurate,
        usesLanguageCorrection: true,
        minimumTextHeight: 0.01
    )
}

// MARK: - OCR Error Types

enum OCRError: Error, LocalizedError {
    case imageConversionFailed
    case noTextFound
    case processingFailed(String)
    case invalidROI
    
    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image for OCR processing"
        case .noTextFound:
            return "No text was found in the image"
        case .processingFailed(let reason):
            return "OCR processing failed: \(reason)"
        case .invalidROI:
            return "Invalid ROI coordinates"
        }
    }
}

// FieldROI struct for normalized ROI (percentages of width/height)
struct FieldROI {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

// Pixel-perfect ROIs for 2360x1640 screenshots (from user)
let flightNumberROI = FieldROI(x: 8/2360, y: 41.8/1640, width: (235-8)/2360, height: (147-41.8)/1640)
let aircraftTypeROI = FieldROI(x: 28/2360, y: 223/1640, width: (171-28)/2360, height: (297-223)/1640)
let aircraftRegROI  = FieldROI(x: 241/2360, y: 223/1640, width: (352-241)/2360, height: (297-223)/1640)
let dayDateROI = FieldROI(x: 480/2360, y: 56/1640, width: (543-480)/2360, height: (130-56)/1640)
let departureROI = FieldROI(x: 560/2360, y: 60/1640, width: (641-560)/2360, height: (96-60)/1640)
let arrivalROI = FieldROI(x: 807/2360, y: 60/1640, width: (894-807)/2360, height: (96-60)/1640)
let schedDepROI = FieldROI(x: 647/2360, y: 60/1640, width: (750-647)/2360, height: (96-60)/1640)
let schedArrROI = FieldROI(x: 900/2360, y: 60/1640, width: (1026-900)/2360, height: (96-60)/1640)
let outTimeROI = FieldROI(x: 1970/2360, y: 1128/1640, width: (2055-1970)/2360, height: (1166-1128)/1640)
let offTimeROI = FieldROI(x: 1970/2360, y: 1170/1640, width: (2055-1970)/2360, height: (1208-1170)/1640)
let onTimeROI = FieldROI(x: 1970/2360, y: 1230/1640, width: (2055-1970)/2360, height: (1270-1230)/1640)
let inTimeROI = FieldROI(x: 1970/2360, y: 1270/1640, width: (2055-1970)/2360, height: (1305-1270)/1640) 