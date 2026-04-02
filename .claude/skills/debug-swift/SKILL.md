---
name: debug-swift
description: Swift/Xcode-specific debugging workflow for Timed
---

When debugging a Swift issue:
1. Identify the exact error message and file/line number
2. Read the file containing the error
3. Check if the issue is related to:
   - Swift strict concurrency (@Sendable, actor isolation, @MainActor)
   - Optional unwrapping / nil access
   - Type mismatches between domain models and Supabase row types
   - TCA @Dependency registration
4. Fix the MINIMAL change that resolves the issue — do not rewrite surrounding code
5. Run `swift build` to verify the fix compiles
6. If the fix touches ML models or memory operations, run relevant tests

Common Timed-specific gotchas:
- All domain models are in PreviewData.swift (not where you'd expect)
- AuthService creates its own SupabaseClient (doesn't use DI)
- TCA is only used for @Dependency, not state management
- All UI state is @State in views, not in stores
