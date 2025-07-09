import SwiftUI

// MARK: - Debug View

struct DebugView: View {
    @ObservedObject var ocrController: OCRController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.orange)
                Text("ROI Debug View")
                    .font(.headline)
            }
            
            if let results = ocrController.results {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        // Flight Number ROI
                        if let flightNumber = results.flightNumber {
                            DebugROICard(
                                title: "Flight Number",
                                image: flightNumber.croppedImage,
                                text: flightNumber.text,
                                confidence: flightNumber.confidence
                            )
                        }
                        
                        // Aircraft Type ROI
                        if let aircraftType = results.aircraftType {
                            DebugROICard(
                                title: "Aircraft Type",
                                image: aircraftType.croppedImage,
                                text: aircraftType.text,
                                confidence: aircraftType.confidence
                            )
                        }
                        
                        // Aircraft Reg ROI
                        if let aircraftReg = results.aircraftReg {
                            DebugROICard(
                                title: "Aircraft Reg",
                                image: aircraftReg.croppedImage,
                                text: aircraftReg.text,
                                confidence: aircraftReg.confidence
                            )
                        }
                        
                        // Date ROI
                        if let date = results.date {
                            DebugROICard(
                                title: "Date",
                                image: date.croppedImage,
                                text: date.text,
                                confidence: date.confidence
                            )
                        }
                        
                        // Day ROI
                        if let day = results.day {
                            DebugROICard(
                                title: "Day",
                                image: day.croppedImage,
                                text: day.text,
                                confidence: day.confidence
                            )
                        }
                        
                        // Departure ROI
                        if let departure = results.departure {
                            DebugROICard(
                                title: "Departure",
                                image: departure.croppedImage,
                                text: departure.text,
                                confidence: departure.confidence
                            )
                        }
                        
                        // Arrival ROI
                        if let arrival = results.arrival {
                            DebugROICard(
                                title: "Arrival",
                                image: arrival.croppedImage,
                                text: arrival.text,
                                confidence: arrival.confidence
                            )
                        }
                        
                        // OUT Time ROI
                        if let outTime = results.outTime {
                            DebugROICard(
                                title: "OUT Time",
                                image: outTime.croppedImage,
                                text: outTime.text,
                                confidence: outTime.confidence
                            )
                        }
                        
                        // OFF Time ROI
                        if let offTime = results.offTime {
                            DebugROICard(
                                title: "OFF Time",
                                image: offTime.croppedImage,
                                text: offTime.text,
                                confidence: offTime.confidence
                            )
                        }
                        
                        // ON Time ROI
                        if let onTime = results.onTime {
                            DebugROICard(
                                title: "ON Time",
                                image: onTime.croppedImage,
                                text: onTime.text,
                                confidence: onTime.confidence
                            )
                        }
                        
                        // IN Time ROI
                        if let inTime = results.inTime {
                            DebugROICard(
                                title: "IN Time",
                                image: inTime.croppedImage,
                                text: inTime.text,
                                confidence: inTime.confidence
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                Text("No OCR results available")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Debug ROI Card

struct DebugROICard: View {
    let title: String
    let image: UIImage?
    let text: String
    let confidence: ConfidenceResult
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 60)
                    .border(Color.gray, width: 1)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 60)
                    .overlay(
                        Text("No Image")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    )
            }
            
            Text(text.isEmpty ? "Empty" : text)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 4) {
                Circle()
                    .fill(confidence.level.color)
                    .frame(width: 6, height: 6)
                
                Text(String(format: "%.1f", confidence.score * 100))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    DebugView(ocrController: OCRController())
        .padding()
} 