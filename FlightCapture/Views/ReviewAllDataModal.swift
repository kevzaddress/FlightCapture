import SwiftUI

// MARK: - Review All Data Modal

struct ReviewAllDataModal: View {
    @Binding var isPresented: Bool
    @State var flightData: FlightDataForReview
    @State var cockpitCrew: [CrewMember]
    @State var cabinCrew: [CrewMember]
    let onSave: (FlightDataForReview, [CrewMember], [CrewMember]) -> Void
    
    @State private var editingRoleIndex: Int? = nil
    @State private var editingCabinRoleIndex: Int? = nil
    @State private var showRolePicker = false
    @State private var showCabinRolePicker = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Review Flight Data info card
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.systemGray6))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass.circle")
                                    .foregroundColor(.teal)
                                Text("Review Flight Data")
                                    .font(.headline)
                            }
                            Text("Review and edit all extracted flight data before export. Any changes made here will be used for the LogTen export.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                    }
                    .padding(.bottom, 8)
                    // Flight Data Section
                    VStack(alignment: .leading, spacing: 12) {
                        // Flight Info Grid (Flight, Aircraft, From, To)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            // Flight Number
                            EditableFlightDataCard(
                                icon: "number.circle.fill",
                                title: "Flight Number",
                                text: $flightData.flightNumber
                            )
                            // Aircraft
                            EditableFlightDataCard(
                                icon: "airplane.circle.fill",
                                title: "Aircraft",
                                text: $flightData.aircraftReg
                            )
                            // From
                            EditableFlightDataCard(
                                icon: "airplane.departure",
                                title: "From",
                                text: $flightData.departure
                            )
                            // To
                            EditableFlightDataCard(
                                icon: "airplane.arrival",
                                title: "To",
                                text: $flightData.arrival
                            )
                        }
                        // Date card (full width)
                        EditableDateCard(
                            date: $flightData.date,
                            confidence: .high
                        )
                        // OUT/OFF/IN/ON times grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            EditableFlightDataCard(
                                icon: "OUT",
                                title: "OUT",
                                text: $flightData.outTime,
                                isCustomIcon: true
                            )
                            EditableFlightDataCard(
                                icon: "OFF",
                                title: "OFF",
                                text: $flightData.offTime,
                                isCustomIcon: true
                            )
                            EditableFlightDataCard(
                                icon: "IN",
                                title: "IN",
                                text: $flightData.inTime,
                                isCustomIcon: true
                            )
                            EditableFlightDataCard(
                                icon: "ON",
                                title: "ON",
                                text: $flightData.onTime,
                                isCustomIcon: true
                            )
                        }
                    }
                    // Cockpit Crew Section
                    if !cockpitCrew.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "airplane")
                                    .foregroundColor(.teal)
                                Text("Cockpit Crew")
                                    .font(.headline)
                            }
                            ForEach(cockpitCrew.indices, id: \.self) { i in
                                HStack(spacing: 8) {
                                    // Role picker as its own card
                                    Menu {
                                        ForEach(CockpitRole.allCases, id: \.self) { role in
                                            Button(role.rawValue) {
                                                cockpitCrew[i].role = role.rawValue
                                            }
                                        }
                                    } label: {
                                        Text(cockpitCrew[i].role)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                            .frame(width: 56, alignment: .center)
                                            .padding(.vertical, 8)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(8)
                                    }
                                    // Name as its own card
                                    TextField("Name", text: Binding(
                                        get: { titleCase(cockpitCrew[i].name) },
                                        set: { newValue in cockpitCrew[i].name = titleCase(newValue) }
                                    ))
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .textInputAutocapitalization(.words)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                        .onAppear {
                                            // Force title case on appear
                                            let formatted = titleCase(cockpitCrew[i].name)
                                            if formatted != cockpitCrew[i].name {
                                                cockpitCrew[i].name = formatted
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Cabin Crew Section
                    if !cabinCrew.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "person.3.fill")
                                    .foregroundColor(.teal)
                                Text("Cabin Crew")
                                    .font(.headline)
                            }
                            ForEach(cabinCrew.indices, id: \.self) { i in
                                HStack(spacing: 8) {
                                    // Role picker as its own card
                                    Menu {
                                        ForEach(CabinRole.allCases, id: \.self) { role in
                                            Button(role.rawValue) {
                                                cabinCrew[i].role = role.rawValue
                                            }
                                        }
                                    } label: {
                                        Text(cabinCrew[i].role)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                            .frame(width: 56, alignment: .center)
                                            .padding(.vertical, 8)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(8)
                                    }
                                    // Name as its own card
                                    TextField("Name", text: Binding(
                                        get: { titleCase(cabinCrew[i].name) },
                                        set: { newValue in cabinCrew[i].name = titleCase(newValue) }
                                    ))
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .textInputAutocapitalization(.words)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                        .onAppear {
                                            // Force title case on appear
                                            let formatted = titleCase(cabinCrew[i].name)
                                            if formatted != cabinCrew[i].name {
                                                cabinCrew[i].name = formatted
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Review All Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save & Export") {
                        onSave(flightData, cockpitCrew, cabinCrew)
                        isPresented = false
                    }
                }
            }
        }
    }
    // Helper for flight data text fields
    private func flightTextField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(title, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

// MARK: - Crew Review Modal

struct CrewReviewModal: View {
    @Binding var crewNames: [CrewReviewItem]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Crew Review")
                    .font(.title)
                    .padding()
                
                Text("This modal would allow reviewing and correcting crew names.")
                    .padding()
                
                Button("Confirm") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationBarItems(trailing: Button("Cancel") {
                onCancel()
            })
        }
    }
}

// MARK: - Helper Functions

// Helper function to apply title case formatting
private func titleCase(_ name: String) -> String {
    name
        .lowercased()
        .split(separator: " ")
        .map { $0.capitalized }
        .joined(separator: " ")
}

struct EditableFlightDataCard: View {
    let icon: String
    let title: String
    @Binding var text: String
    var isCustomIcon: Bool = false
    // Detect if this is a flight time field
    var isTimeField: Bool {
        ["OUT", "OFF", "ON", "IN"].contains(title.uppercased())
    }
    // Detect if this field should have caps lock enabled
    var shouldUseCapsLock: Bool {
        ["Flight Number", "Aircraft", "From", "To"].contains(title)
    }
    @FocusState private var isFocused: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if isCustomIcon {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(.teal)
            } else {
                Image(systemName: icon)
                    .foregroundColor(.teal)
                    .font(.title2)
                    .frame(width: 32, height: 32, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                TextField(title, text: $text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .keyboardType(isTimeField ? .numberPad : .default)
                    .textInputAutocapitalization(shouldUseCapsLock ? .characters : .words)
                    .focused($isFocused)
                    .toolbar {
                        if isFocused && isTimeField {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    isFocused = false
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                            }
                        }
                    }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}
struct EditableDateCard: View {
    @Binding var date: Date
    var confidence: ConfidenceLevel = .medium
    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(.teal)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Flight Date")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                DatePicker("Flight Date", selection: $date, displayedComponents: .date)
                    .labelsHidden()
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
} 