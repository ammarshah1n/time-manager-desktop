# iOS Port Security Audit — Consolidated Findings

**Branch:** `ios/port-bootstrap`
**Audit date:** 2026-04-26
**Audit method:** 10 parallel GPT-5.5 xhigh agents (one per attack surface), each scoped to a specific iOS-only risk domain. No cross-talk between agents.
**Findings format:** severity (critical / high / medium / low / informational) → file:line → remediation route.

---

## Severity tally

| Tier | Count | Status |
|---|---|---|
| Critical | 0 | — |
| High | 14 | 6 remediated, 8 deferred |
| Medium | 17 | 1 remediated, 16 deferred |
| Low | 6 | 0 remediated |
| Informational | 14 | — |

The deferred items either require coordination with the in-flight voice fix on `ui/today-feature`, depend on AuthService API surface that doesn't exist yet (e.g. `currentJWT()`, `revoke-push-token` Edge Function), or need on-device verification before settling on a fix. None are blockers for further code work, but **all High items must be closed before TestFlight**.

---

## High-severity findings

### Remediated in this branch

1. **URL gate too loose — TimedAppShell.swift** ✓ FIXED
   The `host == "auth"` check accepted any scheme, including `msauth.com.timed.app://auth`. Replaced with `scheme == "timed"` + `host == "auth"` + `path == "/callback"`. `timed://capture` now has its own narrow route.

2. **Share Extension 64KB cap not enforced before load — ShareViewController.swift** ✓ FIXED
   Reject `Data` payload before UTF-8 decoding when `data.count > maxPayloadBytes`. Added `cap(_:)` helper that truncates by UTF-8 byte length, not grapheme cluster count.

3. **Share Extension public.message accepts raw RFC822 — ShareViewController.swift** ✓ FIXED
   Removed `UTType.message.identifier` from the allow-list. Plain text + URL only.

4. **App Group share queue unbounded — ShareViewController.swift** ✓ FIXED
   1 MB hard cap on `share-queue.jsonl`. Reject new writes once cap is reached.

5. **GraphClient over-broad MSAL scopes — GraphClient.swift** ✓ FIXED
   Removed `Mail.ReadWrite`, `Mail.Send`, `Calendars.ReadWrite`. Read-only scopes only — aligns with `.claude/rules/ai-assistant-rules.md` "Timed never acts on the world."

6. **Live Activity Dynamic Island bottom unredacted — TimedConversationLiveActivity.swift** ✓ FIXED
   Expanded `.bottom` region now uses `redactedSummary(of:)` instead of raw transcript. Lock Screen presentation also redacted.

### Deferred

7. **AuthService missing OAuth state / PKCE validation — AuthService.swift:60–80**
   `signInWithMicrosoft()` and `handleAuthCallback(url:)` rely entirely on Supabase SDK behaviour. Verification needed: does `supabase-swift` 2.5+ apply PKCE + state validation on `client.auth.session(from:)`? If yes, document it. If no, store an app-owned nonce before opening the OAuth URL and reject callbacks without matching `state`.

8. **GraphClient silent auth picks first cached account — GraphClient.swift:230**
   `accounts.first(where: { $0.identifier == accountId }) ?? accounts.first` plus callers passing `accountId = ""` means a multi-account user can fetch the wrong inbox. Persist `result.account.identifier` after interactive auth and require exact match on silent acquisition.

9. **PrivacyInfo collected data under-declared — PrivacyInfo.xcprivacy:22**
   Missing: email subjects/bodies/snippets, calendar event titles, contact-derived names, tier0 observations. Add the App Store data categories that match what actually crosses the wire to Supabase.

10. **EmailSyncService cancellation not robust — EmailSyncService.swift:260**
    `syncOnce` `while hasMore` loop doesn't check `Task.isCancelled` between Graph delta pages. BG handler `Task.cancel()` is cooperative — needs explicit checkpoints inside `syncOnce`.

11. **EmailSyncService flooded mailbox exhaustion — EmailSyncService.swift:260, GraphClient.swift:271**
    Page size 50, no per-run wall-clock or message cap. A spam flood drives the BG handler past iOS's 30s budget, getting Timed deprioritised. Add `max pages`, `max messages`, `wall-clock deadline`, persist delta state on cap hit.

12. **IOSPushManager tokenSink not installed — IOSPushManager.swift:30**
    Default `tokenSink = { _ in }`. Install on auth completion (post-`bootstrapExecutive`); sink must POST with current JWT bound to `executive_id` derived server-side from `verifyAuth(req)`.

13. **AuthService no sign-out push-token revocation — AuthService.swift:133**
    Sign-out calls `client.auth.signOut()` but doesn't unregister APNs token server-side. Add authenticated `revoke-push-token` Edge Function call before Supabase signOut. Otherwise alerts continue going to a signed-out device.

14. **Snooze action global across accounts — TimediOSAppMain.swift:114**
    `alert.snoozedUntil` written to App Group UserDefaults without binding to current `executiveId`. Namespace by `executiveId` (e.g. `alert.snoozedUntil.\(executiveId)`) or route the snooze action through the server.

---

## Medium-severity findings (selected)

15. **App Intent flags consume-and-clear** ✓ FIXED — TimediOSRootView.swift now reads `intent.openCapture` / `intent.openTab` from App Group, clamps the tab via `TimedTab(rawValue:)`, and immediately removes the keys.

16. **PlatformAudio reference leak on throw** ✓ FIXED — `acquirePlayAndRecord()` rolls back `activeRefs--` if `setCategory` or `setActive` throws.

17. **TodaySnapshot fall-through to placeholder** ✓ FIXED — non-preview contexts use `.empty`. Real placeholder content swapped to bland demo strings.

18. **Stale snapshot day-rollover** ✓ FIXED — `TodaySnapshot.isFreshToday` checks generated date; widget timeline reloads at midnight.

19. **TimedAppShell timed://capture handler missing** ✓ FIXED — new narrow route in `routeIncoming(url:)` sets the App Group capture flag.

### Deferred medium

- **MSAL broker discovery enabled** — `LSApplicationQueriesSchemes` lists `msauthv2` + `msauthv3`. If broker auth is undesired for v1, set `MSALWebviewParameters.webviewType = .wkWebView` and remove the schemes.
- **Azure portal redirect URI** — Verify `msauth.com.timed.app://auth` exactly matches the iOS slice in the Azure registration.
- **PlatformAuthPresenter iOS multi-scene fallback** — Pass the presenting controller from the active SwiftUI scene; fail closed if absent.
- **PlatformAuthPresenter macOS empty NSViewController fallback** — Throw if no real key-window content controller is available.
- **APNs token rotation** — Track last-known token; revoke old token on rotation.
- **APNs Release uses development entitlement** — Split per-config `aps-environment`; production must say `production`.
- **APNs silent push handler missing account guard** — Once the silent push sync sink is installed, derive account from JWT and reject body-supplied executive IDs.
- **BG default-success no-op when unauthenticated** — Should still complete success, but should also cancel/suppress scheduling to avoid burning iOS BG budget on signed-out users.
- **BG no failure backoff** — Track consecutive failures; exponential backoff + jitter.
- **BG first-launch unauthenticated** — Auth-guard the handler.
- **Synthesis BG over-constrained** — `requiresExternalPower: true` is heavy if work is just an Edge Function ping. Switch to BGAppRefreshTask if that's all it does.
- **Mic permission flow split** — VoiceCaptureService prompts SFSpeechRecognizer + AVCaptureDevice separately; PlatformAudio.requestMicPermission() is unused. Consolidate.
- **Background audio declaration not justified by current code** — `Info.plist` declares `audio` background mode but ConversationView ends the session when scene goes inactive. Either deliver background continuity OR drop the entitlement; current state risks App Store rejection ("declared audio but doesn't use it").
- **Widget extension privacy manifest missing** — Add an extension-specific `PrivacyInfo.xcprivacy` declaring no tracking / no collection.
- **SDK privacy manifest status unverified** — Inspect resolved Supabase, MSAL, ElevenLabs, GRDB, USearch package artifacts for embedded manifests; declare overrides at the app level for any missing.
- **Audio leaves device via server proxy** — Privacy manifest is honest about audio collection; ensure App Store Privacy answers also disclose service-provider processing (Deepgram via Edge Function).

---

## Low-severity (deferred)

- Share extension silent drop on write failure — surface a generic "Could not save" UI state.
- Share extension awaits write before completion — keep synchronous if cheap, otherwise add a 1s timeout.
- Transcript not cleared in RAM at end of conversation — `ConversationModel.end()` should clear transcript + `aiClient.reset()`.
- TodayPriorityWidget accessibility label missing on `accessoryRectangular` — add explicit `.accessibilityLabel`.
- TimedWidgets target packageProductDependencies should be empty — add a CI guard.
- TimedAppShell empty-string scheme/host edge cases.

---

## Informational confirmations

- KeychainStore uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, not `kSecAttrAccessibleAlways`. ✓ Strong.
- KeychainStore is main-app-only (no `kSecAttrAccessGroup`). Matches the entitlements declaring App Groups but not keychain access groups. ✓ Documented intent.
- No third-party SDK App Group UserDefaults override observed. ✓
- No "Hey Timed" wake-word / always-listening VAD. ✓ Mic is only active inside an explicit conversation.
- No Critical Alerts entitlement attempt. ✓ Standard alerts only at first ship.
- App Intents only navigate or open capture — no privileged actions. ✓ Aligns with "Timed never acts."
- AppShortcut phrases are enum-constrained, not free-text. ✓ Prompt-injection-safe.
- URL schemes don't enable cross-app tracking (only `msauthv2`/`msauthv3` in LSApplicationQueriesSchemes). ✓
- `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` is correct for observed paths. ✓
- No children / GDPR-K data observed. ✓
- The `macOS` package_app.sh build path is unaffected by the iOS port — same `time-manager-desktop` executable name preserved. ✓

---

## Next pass

1. **Run `/collab` against branch ios/port-bootstrap** (Ammar, in a fresh terminal under `caffeinate`):
   ```bash
   caffeinate -dimsu -t 18000 ~/.claude/skills/collab/run.sh \
     --mode code --scope branch \
     /Users/integrale/time-manager-desktop-wt/ios-port
   ```
2. Triage the deferred High items (8 of them) in a focused remediation pass. Most need ~15-30 min each.
3. Once the in-flight voice fix lands on `ui/today-feature`, rebase `ios/port-bootstrap` onto it and wire `PlatformAudio.acquirePlayAndRecord()` / `release()` into DeepgramSTT + StreamingTTS at session boundaries.
4. iOS sim runtime install (currently downloading via `xcodebuild -downloadPlatform iOS`) → resume Step 10 verification (XcodeBuildMCP `build_run_sim` for iPhone 15 Pro + iPad Air M2).
5. Step 13 distribution prep — `aps-environment` per-config, App Store Connect record for `com.timed.ios`, TestFlight setup.
