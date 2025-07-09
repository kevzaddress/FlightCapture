import SwiftUI

// MARK: - Flight Details View

struct FlightDetailsView: View {
    @ObservedObject var flightDataController: FlightDataController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Image(systemName: "airplane.circle")
                    .foregroundColor(.blue)
                    .font(.title3)
                Text("Flight Details")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            // Flight Info Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                FlightDetailCard(
                    title: "Flight",
                    value: flightDataController.getCurrentFlightData().flightNumber ?? "",
                    confidence: flightDataController.getConfidence(for: "flightNumber"),
                    icon: Image(systemName: "number"),
                    iconColor: .blue
                )
                FlightDetailCard(
                    title: "Aircraft",
                    value: flightDataController.getCurrentFlightData().aircraftReg ?? "",
                    confidence: flightDataController.getConfidence(for: "aircraftReg"),
                    icon: Image(systemName: "airplane"),
                    iconColor: .blue
                )
                FlightDetailCard(
                    title: "From",
                    value: flightDataController.getCurrentFlightData().departureAirport ?? "",
                    confidence: flightDataController.getConfidence(for: "departure"),
                    icon: Image(systemName: "airplane.departure"),
                    iconColor: .blue
                )
                FlightDetailCard(
                    title: "To",
                    value: flightDataController.getCurrentFlightData().arrivalAirport ?? "",
                    confidence: flightDataController.getConfidence(for: "arrival"),
                    icon: Image(systemName: "airplane.arrival"),
                    iconColor: .blue
                )
            }
            // Date (full width)
            FlightDetailCard(
                title: "Date",
                value: formatDate(flightDataController.getCurrentFlightData().date),
                confidence: flightDataController.dateConfidence,
                icon: Image(systemName: "calendar"),
                iconColor: .blue
            )
            // Times Section
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                FlightDetailCard(
                    title: "OUT",
                    value: flightDataController.getCurrentFlightData().outTime ?? "",
                    confidence: flightDataController.getConfidence(for: "outTime"),
                    icon: Image(systemName: "airplane.departure"),
                    iconColor: .green
                )
                FlightDetailCard(
                    title: "OFF",
                    value: flightDataController.getCurrentFlightData().offTime ?? "",
                    confidence: flightDataController.getConfidence(for: "offTime"),
                    icon: Image(systemName: "airplane"),
                    iconColor: .blue
                )
                FlightDetailCard(
                    title: "ON",
                    value: flightDataController.getCurrentFlightData().onTime ?? "",
                    confidence: flightDataController.getConfidence(for: "onTime"),
                    icon: Image(systemName: "airplane"),
                    iconColor: .orange
                )
                FlightDetailCard(
                    title: "IN",
                    value: flightDataController.getCurrentFlightData().inTime ?? "",
                    confidence: flightDataController.getConfidence(for: "inTime"),
                    icon: Image(systemName: "airplane.arrival"),
                    iconColor: .green
                )
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Flight Detail Card

struct FlightDetailCard: View {
    let title: String
    let value: String
    let confidence: ConfidenceLevel
    let icon: Image
    let iconColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(confidence.color)
                    .frame(width: 8, height: 8)
            }
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    FlightDetailsView(flightDataController: FlightDataController())
        .padding()
} 