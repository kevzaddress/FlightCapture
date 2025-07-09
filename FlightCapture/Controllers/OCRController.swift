import Foundation
import UIKit
import Vision

// MARK: - OCR Controller

class OCRController: ObservableObject {
    @Published var processingState: OCRProcessingState = .idle
    @Published var results: OCRProcessingResult?
    
    private let configuration: OCRConfiguration
    
    init(configuration: OCRConfiguration = .default) {
        self.configuration = configuration
    }
    
    /// Process image for OCR
    func processImage(_ image: UIImage, rois: [ROIDefinition]) async throws -> OCRProcessingResult {
        await MainActor.run {
            processingState = .processing
        }
        
        guard image.cgImage != nil else {
            await MainActor.run {
                processingState = .failed(OCRError.imageConversionFailed)
            }
            throw OCRError.imageConversionFailed
        }
        
        var results: [String: OCRFieldResult] = [:]
        
        // Process each ROI
        for roi in rois {
            do {
                let result = try await processROI(image: image, roi: roi)
                results[roi.field.rawValue] = result
            } catch {
                print("[DEBUG] Failed to process ROI \(roi.name): \(error)")
                // Continue with other ROIs
            }
        }
        
        let processingResult = OCRProcessingResult(
            flightNumber: results["Flight Number"],
            aircraftType: results["Aircraft Type"],
            aircraftReg: results["Aircraft Registration"],
            departure: results["Departure Airport"],
            arrival: results["Arrival Airport"],
            date: results["Date"],
            day: results["Day"],
            outTime: results["OUT Time"],
            offTime: results["OFF Time"],
            onTime: results["ON Time"],
            inTime: results["IN Time"],
            schedDep: results["Scheduled Departure"],
            schedArr: results["Scheduled Arrival"]
        )
        
        await MainActor.run {
            self.results = processingResult
            processingState = .completed
        }
        
        return processingResult
    }
    
    /// Process single ROI
    private func processROI(image: UIImage, roi: ROIDefinition) async throws -> OCRFieldResult {
        // Crop image to ROI
        guard let croppedImage = ImageProcessing.cropImage(image, to: roi.coordinates) else {
            throw OCRError.invalidROI
        }
        
        // Perform OCR
        let text = try await performOCR(on: croppedImage)
        
        // Calculate confidence
        let confidence = ConfidenceUtils.calculateConfidence(for: text, field: roi.field)
        
        return OCRFieldResult(
            field: roi.field.rawValue,
            text: text,
            confidence: confidence,
            croppedImage: croppedImage
        )
    }
    
    /// Perform OCR on image
    private func performOCR(on image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.imageConversionFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.processingFailed(error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }
                
                let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = recognizedStrings.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = configuration.recognitionLevel
            request.usesLanguageCorrection = configuration.usesLanguageCorrection
            request.minimumTextHeight = configuration.minimumTextHeight
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.processingFailed(error.localizedDescription))
            }
        }
    }
    
    /// Reset processing state
    func reset() {
        processingState = .idle
        results = nil
    }
    
    /// Get ROI definitions for dashboard
    static func getDashboardROIs() -> [ROIDefinition] {
        // Base image dimensions (these should match your screenshot dimensions)
        let baseImageWidth: CGFloat = 2200  // Approximate width of your screenshots
        let baseImageHeight: CGFloat = 1400 // Approximate height of your screenshots
        
        return [
            // Flight Data ROIs
            ROIDefinition(
                name: "Departure Airport",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 560, y: 60),
                    bottomRight: CGPoint(x: 641, y: 96),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .departure
            ),
            ROIDefinition(
                name: "Arrival Airport",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 807, y: 60),
                    bottomRight: CGPoint(x: 894, y: 96),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .arrival
            ),
            ROIDefinition(
                name: "Scheduled Departure Time",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 647, y: 60),
                    bottomRight: CGPoint(x: 750, y: 96),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .schedDep
            ),
            ROIDefinition(
                name: "Scheduled Arrival Time",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 900, y: 60),
                    bottomRight: CGPoint(x: 1026, y: 96),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .schedArr
            ),
            ROIDefinition(
                name: "Aircraft Registration",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 247, y: 258),
                    bottomRight: CGPoint(x: 330, y: 290),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .aircraftReg
            ),
            ROIDefinition(
                name: "Date",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 470, y: 60),
                    bottomRight: CGPoint(x: 540, y: 95),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .date
            ),
            ROIDefinition(
                name: "Day",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 470, y: 94),
                    bottomRight: CGPoint(x: 540, y: 127),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .day
            ),
            ROIDefinition(
                name: "OUT Time",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 1918, y: 1128),
                    bottomRight: CGPoint(x: 2055, y: 1166),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .outTime
            ),
            ROIDefinition(
                name: "OFF Time",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 1918, y: 1170),
                    bottomRight: CGPoint(x: 2055, y: 1208),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .offTime
            ),
            ROIDefinition(
                name: "ON Time",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 1918, y: 1230),
                    bottomRight: CGPoint(x: 2055, y: 1270),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .onTime
            ),
            ROIDefinition(
                name: "IN Time",
                coordinates: normalizeCoordinates(
                    topLeft: CGPoint(x: 1918, y: 1270),
                    bottomRight: CGPoint(x: 2055, y: 1305),
                    imageWidth: baseImageWidth,
                    imageHeight: baseImageHeight
                ),
                field: .inTime
            )
        ]
    }
    
    /// Convert pixel coordinates to normalized coordinates
    private static func normalizeCoordinates(
        topLeft: CGPoint,
        bottomRight: CGPoint,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> ROICoordinates {
        let x = topLeft.x / imageWidth
        let y = topLeft.y / imageHeight
        let width = (bottomRight.x - topLeft.x) / imageWidth
        let height = (bottomRight.y - topLeft.y) / imageHeight
        
        return ROICoordinates(x: x, y: y, width: width, height: height)
    }
} 