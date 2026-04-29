import Foundation

@MainActor
final class DishMeUpStore: ObservableObject {
    static let shared = DishMeUpStore()

    @Published private(set) var latest: DishMeUpPlan?
    @Published private(set) var generatedAt: Date?
    @Published private(set) var availableMinutes: Int = 60

    private let legacyDefaultsKey = "dishMeUp.latestPlan.v1"

    private init() {
        let snapshot = loadFromKeychain() ?? migrateFromUserDefaults()
        if let snapshot {
            latest = snapshot.plan
            generatedAt = snapshot.generatedAt
            availableMinutes = snapshot.availableMinutes
        }
    }

    func update(plan: DishMeUpPlan, minutes: Int, at date: Date = Date()) {
        latest = plan
        generatedAt = date
        availableMinutes = minutes
        let snapshot = Snapshot(plan: plan, generatedAt: date, availableMinutes: minutes)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? KeychainStore.setData(data, for: .dishMeUpSnapshot)
        }
    }

    private func loadFromKeychain() -> Snapshot? {
        guard let data = KeychainStore.data(for: .dishMeUpSnapshot) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func migrateFromUserDefaults() -> Snapshot? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: legacyDefaultsKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        try? KeychainStore.setData(data, for: .dishMeUpSnapshot)
        defaults.removeObject(forKey: legacyDefaultsKey)
        return snapshot
    }

    private struct Snapshot: Codable {
        let plan: DishMeUpPlan
        let generatedAt: Date
        let availableMinutes: Int
    }
}
