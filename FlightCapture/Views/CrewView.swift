import SwiftUI

// MARK: - Crew View

struct CrewView: View {
    @ObservedObject var crewController: CrewController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Cockpit Crew Section
            if !crewController.cockpitCrew.isEmpty {
                HStack {
                    Image(systemName: "airplane.departure")
                        .foregroundColor(.blue)
                    Text("Cockpit Crew")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                ForEach(crewController.cockpitCrew) { member in
                    CrewMemberCard(member: member, confidence: .medium)
                }
            }
            // Cabin Crew Section
            if !crewController.cabinCrew.isEmpty {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.teal)
                    Text("Cabin Crew")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                ForEach(crewController.cabinCrew) { member in
                    CrewMemberCard(member: member, confidence: .medium)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Crew Member Card

struct CrewMemberCard: View {
    let member: CrewMember
    let confidence: ConfidenceLevel
    
    var body: some View {
        HStack(spacing: 12) {
            Text(member.role)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue)
                .cornerRadius(6)
            Text(member.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Circle()
                .fill(confidence.color)
                .frame(width: 8, height: 8)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    CrewView(crewController: CrewController())
        .padding()
} 