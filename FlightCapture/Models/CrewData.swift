import Foundation

// MARK: - Crew Data Models

struct CrewMember: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var role: String
    var name: String
    
    static func == (lhs: CrewMember, rhs: CrewMember) -> Bool {
        return lhs.role == rhs.role && lhs.name == rhs.name
    }
}

struct CrewDisplayMember {
    var role: String
    var name: String
    var confidence: ConfidenceLevel
}

struct CrewReviewItem: Identifiable {
    let id = UUID()
    var role: String
    var original: String
    var corrected: String
}

// MARK: - Crew Roles

enum CockpitRole: String, CaseIterable {
    case pic = "PIC"
    case sic = "SIC"
    case relief = "Relief"
    case relief2 = "Relief2"
    
    var displayName: String {
        return self.rawValue
    }
}

enum CabinRole: String, CaseIterable {
    case ism = "ISM"
    case sp = "SP"
    case fp = "FP"
    case fa = "FA"
    case fa2 = "FA2"
    case fa3 = "FA3"
    case fa4 = "FA4"
    
    var displayName: String {
        return self.rawValue
    }
}

// MARK: - Crew Assignment Logic

struct CrewAssignment {
    static func assignCockpitRoles(crewCount: Int) -> [String] {
        switch crewCount {
        case 2:
            return ["PIC", "SIC"]
        case 3:
            return ["PIC", "SIC", "Relief"]
        case 4:
            return ["PIC", "SIC", "Relief", "Relief2"]
        default:
            return ["PIC", "SIC", "Relief", "Relief2"]
        }
    }
    
    static func assignCabinRoles(crewCount: Int) -> [String] {
        let roles = ["ISM", "SP", "FP", "FA", "FA2", "FA3", "FA4"]
        return Array(roles.prefix(crewCount))
    }
} 