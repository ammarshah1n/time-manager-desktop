import AppKit
import SwiftUI

enum TaskCompletionPresentation {
    static let coordinateSpaceName = "task-completion-space"
    static let celebrationDuration = 1.2
}

struct TaskCompletionOverlayState: Identifiable, Equatable {
    let id: UUID
    let taskID: String
    let frame: CGRect

    init(event: TaskCompletionCelebration, frame: CGRect) {
        self.id = event.id
        self.taskID = event.taskID
        self.frame = frame
    }
}

private struct ConfettiParticle {
    let angle: Double
    let speed: Double
    let spin: Double
    let initialRotation: Double
    let size: CGSize
    let color: Color
}

struct ConfettiView: View {
    private let particles: [ConfettiParticle]
    private let duration: Double
    @State private var timelineStart: TimeInterval

    init(seed: UUID, duration: Double = TaskCompletionPresentation.celebrationDuration, particleCount: Int = 40) {
        self.duration = duration
        self.particles = Self.makeParticles(seed: seed, count: particleCount)
        _timelineStart = State(initialValue: Date.timeIntervalSinceReferenceDate)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let elapsed = min(max(timeline.date.timeIntervalSinceReferenceDate - timelineStart, 0), duration)
                let progress = elapsed / duration
                let gravity = 340.0
                let origin = CGPoint(x: size.width / 2, y: size.height / 2)

                for particle in particles {
                    let radians = particle.angle * .pi / 180
                    let dx = CGFloat(cos(radians) * particle.speed * progress)
                    let dy = CGFloat(sin(radians) * particle.speed * progress + gravity * progress * progress)
                    let rotation = particle.initialRotation + particle.spin * progress
                    let opacity = 1 - progress
                    let rect = CGRect(
                        x: origin.x + dx - particle.size.width / 2,
                        y: origin.y + dy - particle.size.height / 2,
                        width: particle.size.width,
                        height: particle.size.height
                    )

                    var particleContext = context
                    particleContext.opacity = opacity
                    particleContext.translateBy(x: rect.midX, y: rect.midY)
                    particleContext.rotate(by: .degrees(rotation))

                    let centeredRect = CGRect(
                        x: -particle.size.width / 2,
                        y: -particle.size.height / 2,
                        width: particle.size.width,
                        height: particle.size.height
                    )
                    let path = RoundedRectangle(
                        cornerRadius: min(particle.size.width, particle.size.height) / 2,
                        style: .continuous
                    ).path(in: centeredRect)

                    particleContext.fill(path, with: .color(particle.color.opacity(opacity)))
                }
            }
        }
        .frame(width: 260, height: 160)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            TaskCompletionSoundPlayer.play()
        }
    }

    private static func makeParticles(seed: UUID, count: Int) -> [ConfettiParticle] {
        var generator = SeededGenerator(seed: seed)
        let colors: [Color] = [
            .white,
            Color(red: 1.0, green: 0.843, blue: 0.0),
            Color(red: 0.529, green: 0.808, blue: 0.922),
            Color(red: 0.565, green: 0.933, blue: 0.565)
        ]

        return (0..<count).map { _ in
            let angle = Double.random(in: 210...330, using: &generator)
            let speed = Double.random(in: 150...320, using: &generator)
            let spin = Double.random(in: -260...260, using: &generator)
            let rotation = Double.random(in: 0...360, using: &generator)
            let width = CGFloat(Double.random(in: 5...9, using: &generator))
            let height = CGFloat(Double.random(in: 8...14, using: &generator))
            let color = colors.randomElement(using: &generator) ?? .white

            return ConfettiParticle(
                angle: angle,
                speed: speed,
                spin: spin,
                initialRotation: rotation,
                size: CGSize(width: width, height: height),
                color: color
            )
        }
    }
}

struct TaskCompletionOverlay: View {
    let celebration: TaskCompletionOverlayState

    var body: some View {
        ConfettiView(seed: celebration.id)
            .position(x: celebration.frame.midX, y: celebration.frame.midY)
    }
}

private enum TaskCompletionSoundPlayer {
    static func play() {
        let candidateNames = ["Glass", "Tink"]
        for rawName in candidateNames {
            if let sound = NSSound(named: NSSound.Name(rawName)) {
                sound.play()
                return
            }
        }
    }
}

struct TaskCompletionFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct TaskCompletionFrameTracker: ViewModifier {
    let taskID: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TaskCompletionFramePreferenceKey.self,
                    value: [taskID: proxy.frame(in: .named(TaskCompletionPresentation.coordinateSpaceName))]
                )
            }
        )
    }
}

extension View {
    func trackTaskCompletionFrame(taskID: String) -> some View {
        modifier(TaskCompletionFrameTracker(taskID: taskID))
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UUID) {
        let digest = seed.uuidString.utf8.reduce(into: UInt64(0x9E3779B97F4A7C15)) { partialResult, byte in
            partialResult = partialResult &* 1099511628211
            partialResult ^= UInt64(byte)
        }
        self.state = digest == 0 ? 0xA0761D6478BD642F : digest
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
