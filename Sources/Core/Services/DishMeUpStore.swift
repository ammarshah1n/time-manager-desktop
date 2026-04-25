import Foundation

@MainActor
final class DishMeUpStore: ObservableObject {
    static let shared = DishMeUpStore()

    @Published private(set) var latest: DishMeUpPlan?
    @Published private(set) var generatedAt: Date?
    @Published private(set) var availableMinutes: Int = 60

    private let key = "dishMeUp.latestPlan.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            latest = snapshot.plan
            generatedAt = snapshot.generatedAt
            availableMinutes = snapshot.availableMinutes
        }
    }

    func update(plan: DishMeUpPlan, minutes: Int, at date: Date = Date()) {
        latest = plan
        generatedAt = date
        availableMinutes = minutes
        if let data = try? JSONEncoder().encode(Snapshot(plan: plan, generatedAt: date, availableMinutes: minutes)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private struct Snapshot: Codable {
        let plan: DishMeUpPlan
        let generatedAt: Date
        let availableMinutes: Int
    }
}
