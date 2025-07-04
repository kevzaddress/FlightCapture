import Foundation

// MARK: - LogTen API Data Models

struct FlightEntity: Codable {
    var entity_name: String = "Flight"
    var flight_flightDate: String? = nil
    var flight_number: String? = nil

    var flight_selectedAircraftType: String? = nil
    var flight_from: String? = nil
    var flight_to: String? = nil
    var flight_takeoffTime: String? = nil
    var flight_landingTime: String? = nil
    var flight_outTime: String? = nil
    var flight_inTime: String? = nil
    var flight_totalTime: String? = nil
    var flight_blockTime: String? = nil
    var flight_dayLandings: Int? = nil
    var flight_nightLandings: Int? = nil
    var flight_dayTakeoffs: Int? = nil
    var flight_nightTakeoffs: Int? = nil
    var flight_approaches: Int? = nil
    var flight_approachType: String? = nil
    var flight_remarks: String? = nil
    var flight_pilotInCommand: String? = nil
    var flight_secondInCommand: String? = nil
    var flight_crew: String? = nil
    var flight_reliefCrew: String? = nil
    var flight_reliefCrew2: String? = nil
    var flight_distance: Double? = nil
    var flight_IFRTime: String? = nil
    var flight_PIC: String? = nil
    var flight_nightTime: String? = nil
    var flight_dayTime: String? = nil
    var flight_onDutyTime: String? = nil
    var flight_offDutyTime: String? = nil
    var flight_pilotFlying: Bool? = nil
    // Add more fields as needed
}

struct LogTenMetadata: Codable {
    var dateAndTimeFormat: String = "MM/dd/yyyy HH:mm"
    var timesAreZulu: Bool = true
    var application: String = "FlightCapture"
    var dateFormat: String = "MM/dd/yyyy"
    var version: String = "1.0"
}

struct LogTenPackage: Codable {
    var entities: [FlightEntity]
    var metadata: LogTenMetadata
} 