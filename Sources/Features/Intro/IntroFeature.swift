// IntroFeature.swift — Timed macOS
// TCA 1.15+ reducer driving the first-launch cinematic intro.
// Sole responsibility: orchestrate the intro phase machine and emit
// a `.delegate(.completed)` action when the sequence finishes (either
// naturally or via Skip). The view layer renders each phase.

import ComposableArchitecture
import Foundation

@Reducer
struct IntroFeature {

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var phase: Phase = .reveal
        var skipAvailable: Bool = false
        var reduceMotion: Bool = false
    }

    enum Phase: Equatable {
        /// Logo mask-revealing + fading in.
        case reveal
        /// Tagline words appearing one by one.
        case tagline
        /// Holding on the composed frame.
        case holding
        /// Logo shrinking + background morphing toward app surface.
        case exiting
        /// Sequence complete — parent should dismiss.
        case finished
    }

    // MARK: - Action

    enum Action: Equatable {
        case onAppear(reduceMotion: Bool)
        case skipCooldownElapsed
        case skipTapped
        case revealCompleted
        case taglineCompleted
        case holdElapsed
        case exitCompleted
        case delegate(Delegate)

        enum Delegate: Equatable {
            case completed
        }
    }

    // MARK: - Dependencies

    @Dependency(\.continuousClock) var clock

    // MARK: - Body

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case let .onAppear(reduceMotion):
                state.reduceMotion = reduceMotion
                if reduceMotion {
                    // Collapse the entire sequence to a short cross-fade.
                    return .run { send in
                        try await clock.sleep(for: .milliseconds(Int(BrandMotion.reducedTotal * 1000)))
                        await send(.exitCompleted)
                    }
                }
                return .run { send in
                    try await clock.sleep(for: .milliseconds(Int(BrandMotion.skipGrace * 1000)))
                    await send(.skipCooldownElapsed)
                }

            case .skipCooldownElapsed:
                state.skipAvailable = true
                return .none

            case .skipTapped:
                guard state.phase != .exiting, state.phase != .finished else { return .none }
                state.phase = .exiting
                return .run { send in
                    try await clock.sleep(for: .milliseconds(600))
                    await send(.exitCompleted)
                }

            case .revealCompleted:
                guard state.phase == .reveal else { return .none }
                state.phase = .tagline
                return .none

            case .taglineCompleted:
                guard state.phase == .tagline else { return .none }
                state.phase = .holding
                return .run { send in
                    try await clock.sleep(for: .milliseconds(1200))
                    await send(.holdElapsed)
                }

            case .holdElapsed:
                guard state.phase == .holding else { return .none }
                state.phase = .exiting
                return .run { send in
                    try await clock.sleep(for: .milliseconds(800))
                    await send(.exitCompleted)
                }

            case .exitCompleted:
                state.phase = .finished
                return .send(.delegate(.completed))

            case .delegate:
                return .none
            }
        }
    }
}
