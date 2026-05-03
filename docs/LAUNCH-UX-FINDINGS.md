# Timed Launch UX Findings

Date: 2026-05-03
Branch: `unified`
Scope: Installed app Computer Use pass, auth/login checks, app logs, and launch-gate code review findings.

## Verdict

The app opens and core navigation works, but it is not launch-ready. The highest-risk problems are installability, auth/linking, task persistence, morning review correctness, silent sync failure, and visible test pollution.

## P0

### Downloaded app is rejected by Gatekeeper

- Area: packaging / install
- Evidence: `scripts/package_app.sh:11`; packaged `dist.noindex/Timed.app` is ad-hoc signed, has no Team ID, and `spctl --assess --type execute` rejects it.
- User impact: a real downloaded DMG is not production-installable without bypass instructions.
- Fix direction: sign and notarize with a real Developer ID identity, preserve required entitlements, then re-run Gatekeeper assessment on the packaged app and DMG.

## P1

### Morning review can discard visible tasks

- Area: morning review / Today flow
- Evidence: Today showed a 5m Action task, morning review step 4 said `No due-today items detected`, step 5 showed the task, and step 6 said `No tasks confirmed. Your Today screen will be empty` if the user pressed Continue.
- User impact: a normal user can lose or hide work they can clearly see elsewhere in the app.
- Fix direction: unify due-today detection and confirmation state, block destructive completion when visible tasks are unconfirmed, and add a regression test for the mixed state.

### Real user UI contains test pollution

- Area: Today / Dish Me Up / seeded or smoke data
- Evidence: Today and Dish Me Up both showed `Timed DoD briefing smoke...`.
- User impact: synthetic smoke tasks appear as real user work, damaging trust immediately.
- Fix direction: delete remote/local smoke data from production-visible accounts and ensure smoke tests write to isolated test users/workspaces.

### Silent sync failure for task sections

- Area: sync / Supabase RLS / user feedback
- Evidence: app logs reported `Flush failed ... new row violates row-level security policy for table "task_sections"` after a 403 while the UI showed no error.
- User impact: users think edits are saved while remote sync is failing.
- Fix direction: fix `task_sections` insert/update RLS or payload ownership fields, surface sync failure in-app, and add a remote authenticated smoke for section writes.

### Settings account state is misleading

- Area: Settings / Accounts / auth model
- Evidence: `5066sim@gmail.com` displays as `Microsoft - sign-in completed, Outlook not yet linked`.
- User impact: the app misidentifies a Gmail/Supabase identity as Microsoft, making account state hard to trust.
- Code reference: `Sources/TimedKit/Features/Prefs/PrefsPane.swift:82`.
- Fix direction: store and display the actual Supabase provider separately from linked Outlook/Gmail providers.

### Gmail linking is stuck or broken

- Area: Settings / Accounts / Gmail OAuth
- Evidence: clicking `Add Gmail` changed the button to `Connecting Gmail`; no visible credential sheet appeared. Logs stopped at `GoogleAuth.signInInteractive: presenting sheet`. Earlier logs showed `AuthService.signInWithGoogle: THREW: keychain error`.
- User impact: users cannot connect Gmail, and the button can remain stuck without a visible recovery path.
- Fix direction: fix Google sign-in presentation/callback, reset loading state on cancellation/timeouts, and show a clear error.

### Outlook linking is stuck or not production-ready

- Area: Settings / Accounts / Microsoft Graph / MSAL
- Evidence: clicking `Connect Outlook` dimmed the app and logged `Start webview authorization session`, but no usable auth sheet appeared. MSAL logs showed keychain `-34018` and no cached account.
- User impact: users cannot reliably connect Outlook or Calendar.
- Code reference: `Sources/TimedKit/Core/Services/AuthService.swift:420`.
- Fix direction: properly sign with Team ID and keychain entitlements, remove the in-memory MSAL workaround, and verify silent refresh.

### Task delete is local-only

- Area: tasks / persistence
- Evidence: `Sources/TimedKit/Core/Services/DataBridge.swift:143`; deleting tasks removes them from the local array and saves remaining tasks but does not delete or cancel the remote row.
- User impact: synced deleted tasks can reappear on the next remote load.
- Fix direction: add remote delete or tombstone/cancel semantics and test reload-after-delete.

### Daily briefing is not actually scheduled

- Area: briefing / backend scheduling
- Evidence: `supabase/functions/generate-morning-briefing/index.ts:8`; the Edge Function has a cron comment, but no checked-in cron migration/job schedules it. Swift only reads an existing row.
- User impact: users may not get a briefing tomorrow even if manual smoke passes.
- Fix direction: add a checked-in `pg_cron` or Supabase schedule migration and prove a generated row appears for an eligible user.

### Offline learning events are dropped

- Area: learning / offline queue / behavior events
- Evidence: `Sources/TimedKit/Core/Services/DataBridge.swift:396`; task upserts are queued offline, but behavior events are inserted directly and ignored with `try?`.
- User impact: estimate override reasons, completions, bucket moves, and corrections can disappear offline.
- Fix direction: queue behavior events with the same offline durability as task upserts and replay them with error handling.

### Graph webhook acknowledges before queueing succeeds

- Area: Microsoft Graph webhook / backend queueing
- Evidence: `supabase/functions/graph-webhook/index.ts:39`; webhook returns 202 before proving `pgmq.send` succeeded and does not check the RPC error.
- User impact: Microsoft will not retry even when notification queueing failed, so mail/calendar updates can be missed.
- Fix direction: check the RPC result before returning 202 and return a retryable failure on queue errors.

### Voice setup state contradicts itself

- Area: Settings / Voice
- Evidence: Settings says `Voice setup is incomplete` and also `Voice confirmations are ready`.
- User impact: users cannot tell whether voice setup is done or incomplete.
- Fix direction: make the ready row conditional or rewrite it to clearly describe partial setup.

### Authenticated app shell restores, but authenticated writes are not healthy

- Area: auth / sync
- Evidence: relaunch logs showed `Executive bootstrapped` and `Session restored`, but the same run logged RLS failures for `task_sections`.
- User impact: login appears successful while core data writes can still fail.
- Fix direction: treat login health as session plus successful authenticated read/write smoke, not only restored session.

## P2

### Dish Me Up output feels unpolished

- Area: Dish Me Up
- Evidence: it recommended the smoke task and used copy like `gets the flywheel moving`.
- User impact: recommendations feel like internal/test output rather than a crisp executive assistant.
- Fix direction: remove smoke tasks, tighten recommendation copy, and add copy review for generated text templates/prompts.

### `Redish` button reads like a typo

- Area: Dish Me Up
- Evidence: button label is `Redish`.
- User impact: looks unpolished or misspelled.
- Fix direction: rename to a clear label such as `Re-dish`, `Refresh`, or `Try again`.

### Priority labels are color names

- Area: task add / priority menus
- Evidence: priority menus expose `Blue / Orange / Red`.
- User impact: users must infer urgency from colors instead of meaningful labels.
- Fix direction: use intent labels such as `Low`, `Normal`, `High`, `Urgent`, or product-specific urgency language.

### Triage empty state is Outlook-only

- Area: Triage
- Evidence: empty state says emails arrive from Outlook, with no Gmail-aware copy and no connect/sync recovery action.
- User impact: Gmail users see the wrong provider guidance and no next action.
- Fix direction: make copy provider-aware and include a connect/sync recovery CTA.

### Settings tabs are hidden in toolbar overflow

- Area: Settings navigation
- Evidence: most Settings pages are only reachable via the `>>` toolbar menu at the current window size.
- User impact: users may think settings pages are missing.
- Fix direction: increase Settings default width, use a sidebar/list Settings layout, or reduce tab count/labels.

### Task detail autofocus is wrong

- Area: task detail
- Evidence: opening a task focuses `Waiting On`.
- User impact: typing can accidentally edit the wrong field.
- Fix direction: focus the title or no field by default, and only focus `Waiting On` when explicitly creating/editing a waiting task.

### Waiting sheet leaks product-specific language

- Area: Waiting sheet
- Evidence: hard-coded `PFF` category appears.
- User impact: product feels contaminated by another project/client context.
- Fix direction: remove hard-coded project categories and source categories from user/workspace config.

### Resume voice setup button used oversized/rogue text

- Area: Settings / Voice
- Evidence: `Resume setup` button text was too large for the setup row.
- User impact: control dominated the row and looked inconsistent with Settings chrome.
- Status: fixed in commit `dd8e575` by using caption-sized text, small bordered chrome, and a 44pt tap target.

### Account provider buttons can leave no visible escape route

- Area: Settings / Accounts
- Evidence: Gmail and Outlook connect attempts started background auth/presentation states without a visible provider sheet from the tested app state.
- User impact: users are left staring at a disabled or dimmed Settings page.
- Fix direction: add timeout/cancel handling and explicit error/retry UI around provider connect flows.

## P3

### Briefing empty state is a dead end

- Area: Briefing
- Evidence: empty state says check back after overnight analysis but gives no refresh/manual generation path.
- User impact: users cannot recover or verify whether briefing generation is broken.
- Fix direction: add `Refresh` or `Generate briefing now` for eligible users, with clear loading/error states.

### Select mode appears on empty sections

- Area: task sections
- Evidence: empty Reply section still offers Select All/Deselect All after pressing Select.
- User impact: empty controls add confusion and make the app feel unfinished.
- Fix direction: hide bulk actions when a section has zero selectable rows.

### Test/log terminology leaks into user-facing paths

- Area: copy / generated output / smoke data
- Evidence: visible `DoD`, smoke task names, and internal-sounding recommendation language appeared in normal screens.
- User impact: users see implementation language instead of product language.
- Fix direction: block test data from production-visible accounts and add a copy lint/check for internal terms in seeded or generated user-facing content.

## Not Proved Yet

These are not confirmed failures, but launch cannot rely on them without proof:

- First-run sign-out and clean re-login were not tested because it would change the current user auth state and require credentials.
- End-to-end automatic "new task gets AI estimate within 5 seconds" still needs a full app-path timing smoke, not only direct function invocation.
- Yesterday override appears in next generated briefing still needs a real generated briefing smoke.
- Estimator signal sourcing was verified at source level, but function log proof was not captured.

## Recommended Fix Order

1. Make the packaged app installable: Developer ID signing, entitlements, notarization, Gatekeeper pass.
2. Remove smoke/test data from production-visible accounts and isolate future smoke tests.
3. Fix morning review task confirmation logic so visible tasks cannot be discarded.
4. Fix `task_sections` RLS/sync failure and surface sync errors in-app.
5. Fix account/provider truth: Supabase identity, Gmail, and Outlook must be separate and accurately displayed.
6. Fix Gmail and Outlook connect flows, including visible auth UI, cancellation, timeout, errors, and token persistence.
7. Add scheduled briefing generation and prove tomorrow's briefing appears.
8. Fix remote task delete/tombstone and offline behavior-event queueing.
9. Clean user-facing copy: Dish Me Up, priority labels, Triage empty state, Briefing empty state, Waiting category leak, and empty select mode.
