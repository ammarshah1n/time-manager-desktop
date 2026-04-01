---
name: tca-patterns
description: The Composable Architecture patterns for Timed macOS app
trigger: When creating TCA features, reducers, state, actions, effects, or tests
---

# TCA Patterns for Timed

## State

Always use `@ObservableState`:

```swift
@Reducer
struct EmailTriage {
    @ObservableState
    struct State: Equatable {
        var emails: IdentifiedArrayOf<Email> = []
        var classification: Classification?
        var isLoading = false
    }
}
```

## Actions

Use `ViewAction` pattern with sub-enums:

```swift
enum Action: ViewAction {
    case view(View)
    case delegate(Delegate)
    case response(Response)

    enum View {
        case onAppear
        case emailTapped(Email.ID)
        case dragToBlackHole(Email.ID)
    }

    enum Delegate {
        case emailClassified(Email.ID, Classification)
    }

    enum Response {
        case classificationResult(Result<Classification, Error>)
        case emailsFetched(Result<[Email], Error>)
    }
}
```

## Reducer Body

Effects use `.run { send in }`:

```swift
var body: some ReducerOf<Self> {
    Reduce { state, action in
        switch action {
        case .view(.onAppear):
            state.isLoading = true
            return .run { send in
                let emails = try await graphClient.fetchDelta()
                await send(.response(.emailsFetched(.success(emails))))
            } catch: { error, send in
                await send(.response(.emailsFetched(.failure(error))))
            }

        case .view(.dragToBlackHole(let id)):
            return .run { send in
                try await classifier.classify(id, as: .blackHole)
                await send(.delegate(.emailClassified(id, .blackHole)))
            }

        case .response(.emailsFetched(.success(let emails))):
            state.isLoading = false
            state.emails = IdentifiedArray(uniqueElements: emails)
            return .none

        case .response(.emailsFetched(.failure)):
            state.isLoading = false
            return .none

        default:
            return .none
        }
    }
}
```

## Dependencies

Use `@Dependency` injection:

```swift
@Dependency(\.graphClient) var graphClient
@Dependency(\.classifier) var classifier
@Dependency(\.supabaseClient) var supabase

// Register in DependencyValues:
extension DependencyValues {
    var graphClient: GraphClient {
        get { self[GraphClient.self] }
        set { self[GraphClient.self] = newValue }
    }
}
```

## Testing

Use `TestStore`:

```swift
@Test func classifyEmailUpdatesState() async {
    let store = TestStore(
        initialState: EmailTriage.State(emails: [.mock]),
        reducer: { EmailTriage() },
        withDependencies: {
            $0.classifier.classify = { _, classification in classification }
        }
    )

    await store.send(.view(.dragToBlackHole("email-1")))
    await store.receive(.delegate(.emailClassified("email-1", .blackHole)))
}
```

## NEVER DO
- No `@State` for TCA-managed data — use `@ObservableState` in Reducer.State
- No `ObservableObject` — TCA replaces this entirely
- No `Task {}` in views — all async work goes in Reducer effects
- No direct Supabase/Graph calls in Reducers — always through `@Dependency`
- No `EnvironmentObject` — use TCA's dependency injection
