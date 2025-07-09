import Foundation

// MARK: - Date Utilities

struct DateUtils {
    
    /// Parse date from day number and day of week
    static func parseDateFromDayAndWeekday(day: Int, weekday: String) -> Date? {
        let calendar = Calendar.current
        let today = Date()
        
        // Try to find the date by working backwards from today
        for monthOffset in -1...1 {
            guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: today) else { continue }
            
            let year = calendar.component(.year, from: targetMonth)
            let month = calendar.component(.month, from: targetMonth)
            
            // Create date components
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            
            guard let candidateDate = calendar.date(from: components) else { continue }
            
            // Check if the weekday matches
            let weekdaySymbol = calendar.weekdaySymbols[calendar.component(.weekday, from: candidateDate) - 1]
            let shortWeekday = String(weekdaySymbol.prefix(3))
            
            if shortWeekday.lowercased() == weekday.lowercased() || 
               weekdaySymbol.lowercased() == weekday.lowercased() {
                return candidateDate
            }
        }
        
        return nil
    }
    
    /// Extract date from full OCR text using regex patterns
    static func extractDateFromFullText(_ fullText: String) -> (dayOfWeek: String, dayOfMonth: Int)? {
        print("[DEBUG] Attempting fallback date extraction from full text")
        
        // Look for patterns like "DASH, DEP, 6, Sun" or similar
        let patterns = [
            "DASH,\\s*DEP,\\s*(\\d+),\\s*([A-Za-z]+)",
            "DEP,\\s*(\\d+),\\s*([A-Za-z]+)",
            "(\\d+),\\s*([A-Za-z]+),\\s*VHHH",
            "([A-Za-z]+),\\s*(\\d+),\\s*VHHH",
            "DASH,\\s*DEP,\\s*(\\d+)\\s*,\\s*([A-Za-z]+)",
            "DEP,\\s*(\\d+)\\s*,\\s*([A-Za-z]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(fullText.startIndex..<fullText.endIndex, in: fullText)
                if let match = regex.firstMatch(in: fullText, options: [], range: range) {
                    if match.numberOfRanges >= 3 {
                        let dayRange = match.range(at: 1)
                        let dayOfWeekRange = match.range(at: 2)
                        
                        if let dayString = Range(dayRange, in: fullText).map({ String(fullText[$0]) }),
                           let dayOfWeekString = Range(dayOfWeekRange, in: fullText).map({ String(fullText[$0]) }),
                           let dayOfMonth = Int(dayString) {
                            
                            print("[DEBUG] Fallback found date: \(dayOfMonth) \(dayOfWeekString)")
                            return (dayOfWeek: dayOfWeekString, dayOfMonth: dayOfMonth)
                        }
                    }
                }
            }
        }
        
        // Also try to find "Mon 7 Jul" pattern from the beginning of the text
        if let regex = try? NSRegularExpression(pattern: "([A-Za-z]+)\\s+(\\d+)\\s+([A-Za-z]+)", options: []) {
            let range = NSRange(fullText.startIndex..<fullText.endIndex, in: fullText)
            if let match = regex.firstMatch(in: fullText, options: [], range: range) {
                if match.numberOfRanges >= 4 {
                    let dayOfWeekRange = match.range(at: 1)
                    let dayOfMonthRange = match.range(at: 2)
                    
                    if let dayOfWeekString = Range(dayOfWeekRange, in: fullText).map({ String(fullText[$0]) }),
                       let dayString = Range(dayOfMonthRange, in: fullText).map({ String(fullText[$0]) }),
                       let dayOfMonth = Int(dayString) {
                        
                        print("[DEBUG] Fallback found date from beginning: \(dayOfMonth) \(dayOfWeekString)")
                        return (dayOfWeek: dayOfWeekString, dayOfMonth: dayOfMonth)
                    }
                }
            }
        }
        
        print("[DEBUG] Fallback date extraction failed")
        return nil
    }
    
    /// Format date for display
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Format time for display
    static func formatTime(_ timeString: String) -> String {
        // Remove any extra whitespace and normalize
        return timeString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Validate time format (HH:MM)
    static func isValidTimeFormat(_ timeString: String) -> Bool {
        let timeRegex = "^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$"
        return timeString.range(of: timeRegex, options: .regularExpression) != nil
    }
    
    /// Get current date as fallback
    static func getCurrentDate() -> Date {
        return Date()
    }
} 