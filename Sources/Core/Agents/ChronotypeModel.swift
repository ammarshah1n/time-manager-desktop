import Foundation

/// Models the executive's chronotype from first/last activity, email send times, and keystroke velocity.
/// Produces an energy curve prediction and chronotype classification.
/// Target: r=0.74-0.80 correlation with sleep onset/offset.
actor ChronotypeModel {
    static let shared = ChronotypeModel()

    struct EnergyProfile: Sendable {
        let chronotype: Chronotype
        let peakHours: ClosedRange<Int>
        let troughHours: ClosedRange<Int>
        let predictedEnergyByHour: [Int: Double] // 0-23 → 0.0-1.0
    }

    enum Chronotype: String, Sendable {
        case earlyBird   // peak before 10 AM
        case intermediate // peak 10 AM - 2 PM
        case nightOwl    // peak after 2 PM
    }

    private var firstActivityTimes: [TimeInterval] = [] // seconds since midnight
    private var lastActivityTimes: [TimeInterval] = []
    private var emailSendHours: [Int] = []
    private var keystrokeVelocityByHour: [Int: [Double]] = [:] // hour → [WPM values]

    private let minimumDays = 14

    func recordFirstActivity(at date: Date) {
        let seconds = secondsSinceMidnight(date)
        firstActivityTimes.append(seconds)
        trimToWindow()
    }

    func recordLastActivity(at date: Date) {
        let seconds = secondsSinceMidnight(date)
        lastActivityTimes.append(seconds)
        trimToWindow()
    }

    func recordEmailSend(at date: Date) {
        let hour = Calendar.current.component(.hour, from: date)
        emailSendHours.append(hour)
        if emailSendHours.count > 1000 { emailSendHours.removeFirst(500) }
    }

    func recordKeystrokeVelocity(wpm: Double, at date: Date) {
        let hour = Calendar.current.component(.hour, from: date)
        keystrokeVelocityByHour[hour, default: []].append(wpm)
        // Trim per-hour arrays
        if let count = keystrokeVelocityByHour[hour]?.count, count > 200 {
            keystrokeVelocityByHour[hour]?.removeFirst(100)
        }
    }

    func currentProfile() -> EnergyProfile? {
        guard firstActivityTimes.count >= minimumDays else { return nil }

        let avgFirstActivity = firstActivityTimes.reduce(0, +) / Double(firstActivityTimes.count)
        let avgFirstHour = Int(avgFirstActivity / 3600)

        // Classify chronotype from first activity time
        let chronotype: Chronotype
        if avgFirstHour < 7 {
            chronotype = .earlyBird
        } else if avgFirstHour < 9 {
            chronotype = .intermediate
        } else {
            chronotype = .nightOwl
        }

        // Build energy curve from keystroke velocity distribution
        var energyByHour: [Int: Double] = [:]
        for hour in 0...23 {
            if let velocities = keystrokeVelocityByHour[hour], !velocities.isEmpty {
                let avgWPM = velocities.reduce(0, +) / Double(velocities.count)
                energyByHour[hour] = avgWPM
            }
        }

        // Normalize to 0-1 range
        let maxEnergy = energyByHour.values.max() ?? 1
        let minEnergy = energyByHour.values.min() ?? 0
        let range = max(maxEnergy - minEnergy, 1)
        for (hour, value) in energyByHour {
            energyByHour[hour] = (value - minEnergy) / range
        }

        // Fill gaps with email send distribution as proxy
        if energyByHour.count < 12 {
            let emailHist = emailHourHistogram()
            let maxEmail = emailHist.values.max() ?? 1.0
            for hour in 6...22 where energyByHour[hour] == nil {
                energyByHour[hour] = (emailHist[hour] ?? 0) / maxEmail
            }
        }

        // Find peak and trough
        let sortedHours = energyByHour.sorted { $0.value > $1.value }
        let peakStart = sortedHours.first?.key ?? 10
        let troughStart = sortedHours.last?.key ?? 15

        return EnergyProfile(
            chronotype: chronotype,
            peakHours: peakStart...min(peakStart + 2, 23),
            troughHours: troughStart...min(troughStart + 1, 23),
            predictedEnergyByHour: energyByHour
        )
    }

    private func emailHourHistogram() -> [Int: Double] {
        var hist: [Int: Double] = [:]
        for hour in emailSendHours {
            hist[hour, default: 0] += 1
        }
        return hist
    }

    private func secondsSinceMidnight(_ date: Date) -> TimeInterval {
        let cal = Calendar.current
        let components = cal.dateComponents([.hour, .minute, .second], from: date)
        return Double(components.hour ?? 0) * 3600 + Double(components.minute ?? 0) * 60 + Double(components.second ?? 0)
    }

    private func trimToWindow() {
        // Keep last 90 days of data
        let maxEntries = 90
        if firstActivityTimes.count > maxEntries { firstActivityTimes.removeFirst(firstActivityTimes.count - maxEntries) }
        if lastActivityTimes.count > maxEntries { lastActivityTimes.removeFirst(lastActivityTimes.count - maxEntries) }
    }
}
