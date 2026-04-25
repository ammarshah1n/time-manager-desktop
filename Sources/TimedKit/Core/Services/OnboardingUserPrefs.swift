// OnboardingUserPrefs.swift — Timed Core / Services
// Read-only access to all onboarding-set preferences from UserDefaults.
// Extracted from OnboardingFlow.swift so EmailSyncService (and any other
// non-Onboarding caller) can read these values on iOS where the
// OnboardingFlow.swift view file is gated #if os(macOS).

import Foundation

struct OnboardingUserPrefs {
    static var userName: String {
        UserDefaults.standard.string(forKey: "onboarding_userName") ?? ""
    }

    static var email: String {
        UserDefaults.standard.string(forKey: "onboarding_email") ?? ""
    }

    static var workdayHours: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_workdayHours")
        return v == 0 ? 9 : v
    }

    static var todayHours: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_todayHours")
        return v == 0 ? 7 : v
    }

    static var emailCadence: Int {
        UserDefaults.standard.integer(forKey: "onboarding_emailCadence")
    }

    static var emailCadenceLabel: String {
        let options = ["Once", "Twice", "3 × daily", "4+ times"]
        let idx = emailCadence
        return options.indices.contains(idx) ? options[idx] : options[2]
    }

    static var familySurname: String {
        UserDefaults.standard.string(forKey: "onboarding_familySurname") ?? ""
    }

    static var replyMins: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_replyMins")
        return v == 0 ? 5 : v
    }

    static var actionMins: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_actionMins")
        return v == 0 ? 30 : v
    }

    static var callMins: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_callMins")
        return v == 0 ? 15 : v
    }

    static var readMins: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_readMins")
        return v == 0 ? 20 : v
    }

    static var transitModes: [String] {
        let raw = UserDefaults.standard.string(forKey: "onboarding_transitModes") ?? ""
        return raw.isEmpty ? [] : raw.split(separator: ",").map(String.init)
    }

    static var hasChauffeur: Bool    { transitModes.contains("chauffeur") }
    static var hasTrainTravel: Bool  { transitModes.contains("train") }
    static var hasPlaneTravel: Bool  { transitModes.contains("plane") }
    static var drivesSelf: Bool      { transitModes.contains("drive") }

    static var paEmail: String {
        UserDefaults.standard.string(forKey: "onboarding_paEmail") ?? ""
    }

    static var paEnabled: Bool {
        UserDefaults.standard.bool(forKey: "onboarding_paEnabled")
    }

    static var workStartHour: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_workStartHour")
        return v == 0 ? 9 : v
    }

    static var workEndHour: Int {
        let v = UserDefaults.standard.integer(forKey: "onboarding_workEndHour")
        return v == 0 ? 18 : v
    }

    static var outlookConnected: Bool {
        UserDefaults.standard.bool(forKey: "accounts.outlook.connected")
    }

    static var supabaseConnected: Bool {
        UserDefaults.standard.bool(forKey: "accounts.supabase.connected")
    }
}
