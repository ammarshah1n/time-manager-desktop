# Timed — iOS SwiftUI Mockups

Six files. Drop them into a blank iOS 17+ Xcode project. Run on Simulator.

## Files

| File | Screen |
|------|--------|
| `TimedApp.swift` | `@main` entry + `TabView` wiring all 4 tabs |
| `MockModels.swift` | All data types + sample data (no network calls) |
| `InboxView.swift` | Email list — swipe actions, pull-to-refresh, time-block sheet |
| `CalendarView.swift` | Weekly grid — time blocks, current-time line, detail sheet |
| `FocusTimerView.swift` | Circular countdown — start / pause / stop |
| `SettingsView.swift` | Accounts, sync frequency, default duration, theme |

## Xcode setup

1. File → New → Project → App (iOS, SwiftUI, Swift)
2. Delete `ContentView.swift` and the generated `App.swift`
3. Drag all 6 `.swift` files into the project
4. Set deployment target to **iOS 17.0**
5. Run on any iPhone simulator

## Swipe actions (Inbox)

| Direction | Action |
|-----------|--------|
| Leading (full-swipe) | Block time → opens duration picker |
| Leading (half) | Snooze |
| Trailing (full-swipe) | Archive |

## Design decisions

- Single accent: system blue (`Color.blue`) — swap to `#D32F2F` for Facilitated brand
- No gradients, no heavy shadows — one `shadow(color:radius:y:)` on the primary timer button only
- Dark mode: uses semantic colors (`Color(.secondarySystemBackground)` etc.) throughout
- Tab icons: SF Symbols `envelope`, `calendar`, `timer`, `gear`

## Not yet implemented (intentionally)

- Real drag-and-drop from Inbox rows to Calendar (uses system `draggable` / `dropDestination`)
- Push notifications
- Email authentication (Microsoft Graph / MSAL)
- Persistence
