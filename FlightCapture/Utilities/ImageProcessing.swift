import UIKit
import Vision

// MARK: - Image Processing Utilities

struct ImageProcessing {
    
    /// Crop image to specified ROI coordinates
    static func cropImage(_ image: UIImage, to roi: ROICoordinates) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        // Convert normalized coordinates to pixel coordinates
        let x = roi.x * imageWidth
        let y = roi.y * imageHeight
        let width = roi.width * imageWidth
        let height = roi.height * imageHeight
        
        // Ensure coordinates are within bounds
        let cropX = max(0, min(x, imageWidth - width))
        let cropY = max(0, min(y, imageHeight - height))
        let cropWidth = min(width, imageWidth - cropX)
        let cropHeight = min(height, imageHeight - cropY)
        
        guard cropWidth > 0 && cropHeight > 0 else { return nil }
        
        // Create cropping rectangle
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        // Perform cropping
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        
        return UIImage(cgImage: croppedCGImage)
    }
    
    /// Resize image to specified dimensions
    static func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    /// Convert UIImage to CGImage
    static func convertToCGImage(_ image: UIImage) -> CGImage? {
        return image.cgImage
    }
    
    /// Create UIImage from data
    static func createImage(from data: Data) -> UIImage? {
        return UIImage(data: data)
    }
    
    /// Get image dimensions
    static func getImageDimensions(_ image: UIImage) -> CGSize {
        return CGSize(width: image.size.width, height: image.size.height)
    }
    
    /// Normalize coordinates for different image sizes
    static func normalizeCoordinates(_ coordinates: ROICoordinates, for imageSize: CGSize) -> ROICoordinates {
        return ROICoordinates(
            x: coordinates.x / imageSize.width,
            y: coordinates.y / imageSize.height,
            width: coordinates.width / imageSize.width,
            height: coordinates.height / imageSize.height
        )
    }
}

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
        DispatchQueue.main.async {
            completion("")
        }
        return
    }
    let request = VNRecognizeTextRequest { request, error in
        if let error = error {
            print("[DEBUG] [\(label)] Vision OCR error: \(error)")
            DispatchQueue.main.async {
                completion("")
            }
            return
        }
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            print("[DEBUG] [\(label)] No text observations found.")
            DispatchQueue.main.async {
                completion("")
            }
            return
        }
        let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = recognizedStrings.joined(separator: ", ")
        print("[DEBUG] [\(label)] OCR recognized text: \(text)")
        DispatchQueue.main.async {
            completion(text)
        }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try handler.perform([request])
        } catch {
            print("[DEBUG] [\(label)] Vision request error: \(error)")
            DispatchQueue.main.async {
                completion("")
            }
        }
    }
}

// Helper to normalize aircraft registration (e.g., BLRU -> B-LRU)
func normalizeAircraftReg(_ reg: String?) -> String? {
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

// Confidence calculation functions
func calculateFlightNumberConfidence(_ text: String) -> ConfidenceLevel {
    let pattern = "^[A-Z]{2,3}\\d{2,4}$"
    if text.range(of: pattern, options: .regularExpression) != nil {
        return .high
    }
    if text.contains(where: { $0.isLetter }) && text.contains(where: { $0.isNumber }) {
        return .medium
    }
    return .low
}

func calculateAircraftRegConfidence(_ text: String) -> ConfidenceLevel {
    let pattern = "^[A-Z]-[A-Z0-9]{3,4}$"
    if text.range(of: pattern, options: .regularExpression) != nil {
        return .high
    }
    if text.contains("-") && text.count >= 6 {
        return .medium
    }
    return .low
}

func calculateAirportConfidence(_ text: String) -> ConfidenceLevel {
    let pattern = "^[A-Z]{3,4}$"
    if text.range(of: pattern, options: .regularExpression) != nil {
        return .high
    }
    if text.count == 3 && text.allSatisfy({ $0.isLetter }) {
        return .medium
    }
    return .low
}

func calculateCrewNameConfidence(_ text: String) -> ConfidenceLevel {
    if text.count >= 3 && text.allSatisfy({ $0.isLetter || $0.isWhitespace }) {
        return .high
    }
    if text.count >= 2 {
        return .medium
    }
    return .low
} 