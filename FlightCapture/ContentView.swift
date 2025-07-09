//
//  ContentView.swift
//  FlightCapture
//
//  Created by Kevin Smith on 29/6/2025.
//

import SwiftUI
import AVFoundation
import Vision
import UIKit
import PhotosUI
import Foundation
import UniformTypeIdentifiers
import CryptoKit

// Use existing MVC types

struct ContentView: View {
    @Binding var incomingImageURL: URL?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showJSONAlert = false
    @State private var showLogTenAlert = false
    
    // Day and Date: top-left (480, 56), bottom-right (543, 130)
    let dayDateROI = FieldROI(x: 480/2360, y: 56/1640, width: (543-480)/2360, height: (130-56)/1640)
    
    // Use controller computed properties (proper MVC)
    var flightNumber: String? {
        return flightDataController.computedFlightNumber
    }
    
    var departureAirport: String? {
        return flightDataController.computedDepartureAirport
    }
    
    var arrivalAirport: String? {
        return flightDataController.computedArrivalAirport
    }
    
    var aircraftReg: String? {
        return flightDataController.computedAircraftReg
    }
    
    // Calibrated ROIs for 2360x1640 screenshots (from user)
    // Departure Airport: top-left (560, 60), bottom-right (641, 96)
    let departureROI = FieldROI(x: 560/2360, y: 60/1640, width: (641-560)/2360, height: (96-60)/1640)
    // Arrival Airport: top-left (807, 60), bottom-right (894, 96)
    let arrivalROI = FieldROI(x: 807/2360, y: 60/1640, width: (894-807)/2360, height: (96-60)/1640)
    // Scheduled Departure Time: top-left (647, 60), bottom-right (750, 96)
    let schedDepROI = FieldROI(x: 647/2360, y: 60/1640, width: (750-647)/2360, height: (96-60)/1640)
    // Scheduled Arrival Time: top-left (900, 60), bottom-right (1026, 96)
    let schedArrROI = FieldROI(x: 900/2360, y: 60/1640, width: (1026-900)/2360, height: (96-60)/1640)
    // AircraftReg: top-left (247, 258), bottom-right (330, 290)
    let aircraftRegROI = FieldROI(x: 247/2360, y: 258/1640, width: (330-247)/2360, height: (290-258)/1640)

    // Time ROIs for OUT-OFF-ON-IN (adjusted to capture only time values, not labels)
    let outTimeROI = FieldROI(x: 1970/2360, y: 1128/1640, width: (2055-1970)/2360, height: (1166-1128)/1640)
    let offTimeROI = FieldROI(x: 1970/2360, y: 1170/1640, width: (2055-1970)/2360, height: (1208-1170)/1640)
    let onTimeROI = FieldROI(x: 1970/2360, y: 1230/1640, width: (2055-1970)/2360, height: (1270-1230)/1640)
    let inTimeROI = FieldROI(x: 1970/2360, y: 1270/1640, width: (2055-1970)/2360, height: (1305-1270)/1640)
    
    // Time field computed properties (use controller)
    var outTime: String? {
        return flightDataController.computedOutTime
    }
    
    var offTime: String? {
        return flightDataController.computedOffTime
    }
    
    var onTime: String? {
        return flightDataController.computedOnTime
    }
    
    var inTime: String? {
        return flightDataController.computedInTime
    }
    
    // Use controller for date inference (proper MVC)
    var inferredDateWithConfidence: (date: Date?, confidence: ConfidenceLevel) {
        return flightDataController.inferredDateWithConfidence
    }
    
    // Add controller objects
    @StateObject private var flightDataController = FlightDataController()
    @StateObject private var logTenController = LogTenController()
    @StateObject private var crewController = CrewController()
    
    @State private var showReviewAllDataSheet = false
    @State private var showCrewReviewSheet = false
    

    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.teal)
                        Text("Flight Capture")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Import flight screenshots and export to LogTen Pro")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Import Section
                    VStack(spacing: 16) {
                        PhotosPicker(
                            selection: $selectedPhotos,
                            maxSelectionCount: 2,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title2)
                                Text("Import Screenshots")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.teal)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(color: Color.teal.opacity(0.18), radius: 6, x: 0, y: 3)
                            .accessibilityLabel("Import flight screenshots")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal)
                    .onChange(of: selectedPhotos) { _, newItems in
                        if !newItems.isEmpty {
                            flightDataController.handlePhotoSelection(
                                newItems,
                                processDashboardROIs: { img in
                                    flightDataController.processDashboardROIs(from: img)
                                },
                                processDashboardCrewROIs: { img in
                                    crewController.processDashboardCrewROIs(from: img)
                                },
                                processCrewROIs: { img in
                                    crewController.processCrewROIs(from: img)
                                }
                            )
                        }
                    }

                    // OCR Processing Card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.teal)
                                .font(.title3)
                            Text("OCR Processing")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FlightCapture uses AI to read flight data from your screenshots.\nEach field shows a confidence indicator:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack(spacing: 34) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 12, height: 12)
                                    Text("High\nconfidence")
                                        .font(.caption)
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                                        .frame(width: 12, height: 12)
                                    Text("Medium\nconfidence")
                                        .font(.caption)
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 12, height: 12)
                                    Text("Low\nconfidence")
                                        .font(.caption)
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .onAppear {
                        print("[DEBUG] OCR Processing card content appeared")
                    }
                    .padding(.horizontal)

                    // Export Button
                    if flightDataController.flightData.flightNumber != nil || flightDataController.flightData.aircraftReg != nil || flightDataController.flightData.departureAirport != nil || flightDataController.flightData.arrivalAirport != nil || flightDataController.flightData.outTime != nil || flightDataController.flightData.offTime != nil || flightDataController.flightData.onTime != nil || flightDataController.flightData.inTime != nil {
                        VStack(spacing: 16) {
                            Button(action: {
                                // Check if any names need review first
                                if crewController.needsReview() {
                                    print("[DEBUG] Names need review, showing modal. Count: \(crewController.crewNamesNeedingReview.count)")
                                    DispatchQueue.main.async {
                                        showCrewReviewSheet = true
                                    }
                                } else {
                                    Task {
                                        await logTenController.exportToLogTen(flightData: flightDataController.flightData, cockpitCrew: crewController.cockpitCrew, cabinCrew: crewController.cabinCrew)
                                    }
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "paperplane.fill")
                                        .font(.title2)
                                    Text("Export to LogTen Pro")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    LinearGradient(gradient: Gradient(colors: [Color.teal, Color.cyan]), startPoint: .leading, endPoint: .trailing)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .shadow(color: Color.teal.opacity(0.18), radius: 6, x: 0, y: 3)
                                .accessibilityLabel("Export flight to LogTen Pro")
                            }
                            .buttonStyle(PlainButtonStyle())
                            Text("Flight data ready for export")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .alert(isPresented: $showLogTenAlert) {
                            Alert(
                                title: Text("LogTen Pro Not Found"),
                                message: Text("LogTen Pro is not installed on this device. Please install it from the App Store."),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                    }

                    // Flight Details Section
                    if flightDataController.flightData.flightNumber != nil || flightDataController.flightData.aircraftReg != nil || flightDataController.flightData.departureAirport != nil || flightDataController.flightData.arrivalAirport != nil || flightDataController.flightData.outTime != nil || flightDataController.flightData.offTime != nil || flightDataController.flightData.onTime != nil || flightDataController.flightData.inTime != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "airplane.departure")
                                    .foregroundColor(.teal)
                                Text("Flight Details")
                                    .font(.headline)
                            }
                            // Flight/aircraft/from/to grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                if let flightNumber = flightDataController.flightData.flightNumber {
                                    FlightDataCard(
                                        icon: "number.circle.fill",
                                        title: "Flight",
                                        value: flightNumber,
                                        color: .teal,
                                        confidence: flightDataController.getConfidence(for: "flightNumber")
                                    )
                                }
                                if let aircraftReg = flightDataController.flightData.aircraftReg {
                                    FlightDataCard(
                                        icon: "airplane.circle.fill",
                                        title: "Aircraft",
                                        value: aircraftReg,
                                        color: .teal,
                                        confidence: flightDataController.getConfidence(for: "aircraftReg")
                                    )
                                }
                                if let departureAirport = flightDataController.flightData.departureAirport {
                                    FlightDataCard(
                                        icon: "airplane.departure",
                                        title: "From",
                                        value: departureAirport,
                                        color: .teal,
                                        confidence: flightDataController.getConfidence(for: "departure")
                                    )
                                }
                                if let arrivalAirport = flightDataController.flightData.arrivalAirport {
                                    FlightDataCard(
                                        icon: "airplane.arrival",
                                        title: "To",
                                        value: arrivalAirport,
                                        color: .teal,
                                        confidence: flightDataController.getConfidence(for: "arrival")
                                    )
                                }
                            }
                            // Date card
                            let (flightDate, dateConfidence) = (flightDataController.inferredDate, flightDataController.dateConfidence)
                            FlightDateCard(
                                date: flightDate,
                                confidence: dateConfidence
                            )
                            // OUT/OFF/IN/ON grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                if let outTime = flightDataController.flightData.outTime {
                                    FlightDataCard(
                                        icon: "OUT",
                                        title: "OUT",
                                        value: outTime,
                                        color: .teal,
                                        isCustomIcon: true,
                                        confidence: !outTime.isEmpty ? .high : .low
                                    )
                                }
                                if let offTime = flightDataController.flightData.offTime {
                                    FlightDataCard(
                                        icon: "OFF",
                                        title: "OFF",
                                        value: offTime,
                                        color: .teal,
                                        isCustomIcon: true,
                                        confidence: !offTime.isEmpty ? .high : .low
                                    )
                                }
                                if let inTime = flightDataController.flightData.inTime {
                                    FlightDataCard(
                                        icon: "IN",
                                        title: "IN",
                                        value: inTime,
                                        color: .teal,
                                        isCustomIcon: true,
                                        confidence: !inTime.isEmpty ? .high : .low
                                    )
                                }
                                if let onTime = flightDataController.flightData.onTime {
                                    FlightDataCard(
                                        icon: "ON",
                                        title: "ON",
                                        value: onTime,
                                        color: .teal,
                                        isCustomIcon: true,
                                        confidence: !onTime.isEmpty ? .high : .low
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Cockpit Crew Section
                    if !crewController.cockpitCrew.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "airplane")
                                    .foregroundColor(.teal)
                                Text("Cockpit Crew")
                                    .font(.headline)
                            }
                            ForEach(crewController.cockpitCrew, id: \.name) { crew in
                                CrewCard(
                                    role: crew.role,
                                    name: crew.name,
                                    confidence: .high // TODO: Bind to actual confidence
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Cabin Crew Section
                    if !crewController.cabinCrew.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "person.3.fill")
                                    .foregroundColor(.teal)
                                Text("Cabin Crew")
                                    .font(.headline)
                            }
                            ForEach(crewController.cabinCrew, id: \.name) { crew in
                                CrewCard(
                                    role: crew.role,
                                    name: crew.name,
                                    confidence: .high // TODO: Bind to actual confidence
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Review All Data button
                    if flightDataController.flightData.flightNumber != nil && flightDataController.flightData.aircraftReg != nil && flightDataController.flightData.departureAirport != nil && flightDataController.flightData.arrivalAirport != nil {
                        Button(action: {
                            showReviewAllDataSheet = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "checklist")
                                    .font(.title2)
                                Text("Review All Data")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(14)
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    // Image Gallery (moved below Review All Data for better workflow)
                    if !flightDataController.importedImages.isEmpty && flightDataController.isOCRComplete {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                    .foregroundColor(.secondary)
                                Text("Source Images")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            ImageGalleryView(images: flightDataController.importedImages, imageNames: flightDataController.imageTypes)
                                .onAppear {
                                    print("[DEBUG] ImageGalleryView received imageNames: \(flightDataController.imageTypes)")
                                }
                                .frame(height: 160)
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
            // ... modals ...
        }
        .sheet(isPresented: $showReviewAllDataSheet) {
            ReviewAllDataModal(
                isPresented: $showReviewAllDataSheet,
                flightData: flightDataController.prepareFlightDataForReview(),
                cockpitCrew: crewController.cockpitCrew,
                cabinCrew: crewController.cabinCrew,
                onSave: { reviewedData, newCockpitCrew, newCabinCrew in
                    print("[DEBUG] Applying reviewed data changes (from ReviewAllDataModal)")
                    flightDataController.applyEditedData(reviewedData)
                    crewController.updateFromReview(cockpitCrew: newCockpitCrew, cabinCrew: newCabinCrew)
                    Task {
                        print("[DEBUG] Triggering LogTen export from ReviewAllDataModal Save & Export button")
                        // Create FlightData from the reviewed data
                        let editedFlightData = FlightData(
                            flightNumber: reviewedData.flightNumber,
                            aircraftReg: reviewedData.aircraftReg,
                            departureAirport: reviewedData.departure,
                            arrivalAirport: reviewedData.arrival,
                            date: reviewedData.date,
                            outTime: reviewedData.outTime,
                            offTime: reviewedData.offTime,
                            onTime: reviewedData.onTime,
                            inTime: reviewedData.inTime,
                            schedDep: flightDataController.flightData.schedDep,
                            schedArr: flightDataController.flightData.schedArr
                        )
                        await logTenController.exportToLogTen(
                            flightData: editedFlightData,
                            cockpitCrew: newCockpitCrew,
                            cabinCrew: newCabinCrew
                        )
                    }
                    showReviewAllDataSheet = false
                }
            )
        }
        .sheet(isPresented: $showCrewReviewSheet) {
            Text("Crew Review Modal - implement as needed")
        }
    }

    // MARK: - View Helper Functions
    

}

// Flight Data Card Component
struct FlightDataCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    var isCustomIcon: Bool = false
    var confidence: ConfidenceLevel = .medium
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon on the left, centered vertically
            if isCustomIcon {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(color)
            } else {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                    .frame(width: 32, height: 32, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Text(value.isEmpty ? "—" : value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            // Confidence dot on the right, vertically centered
            Circle()
                .fill(confidence == .medium ? Color(red: 1.0, green: 0.8, blue: 0.0) : confidence.color)
                .frame(width: 12, height: 12) // Standardized size
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// Crew Card Component (for both Cockpit and Cabin Crew)
struct CrewCard: View {
    let role: String
    let name: String
    let confidence: ConfidenceLevel
    var body: some View {
        HStack(spacing: 8) {
            // Role badge as its own card
            Text(role)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .frame(width: 56, alignment: .center)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            // Name as its own card
            HStack {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Confidence dot (optional, can be hidden if not needed)
                Circle()
                    .fill(confidence == .medium ? Color(red: 1.0, green: 0.8, blue: 0.0) : confidence.color)
                    .frame(width: 12, height: 12) // Standardized size
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding(.horizontal, 0)
    }
}

// Flight Date Card Component
struct FlightDateCard: View {
    let date: Date?
    let confidence: ConfidenceLevel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.teal)
                    .font(.title3)
                Text("Date")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(confidence.color)
                    .frame(width: 12, height: 12) // Standardized size to match other cards
            }
            if let date = date {
                Text(formatDate(date))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// Confidence Dot Component
struct ConfidenceDot: View {
    let confidence: ConfidenceLevel
    
    var body: some View {
        Circle()
            .fill(confidence.color)
            .frame(width: 8, height: 8)
    }
}

#Preview {
    ContentView(incomingImageURL: .constant(nil))
} 