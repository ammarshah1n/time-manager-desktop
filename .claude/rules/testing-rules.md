# Testing Rules

## Framework
- 49 tests pass via `swift-testing`

<important>
## Test Commands
- Test: `test_sim` — pass/fail per method, use `--filter` for single test
</important>

<important>
## Test Iteration Loop
1. Write/modify test
2. `test_sim --scheme Timed --filter TestName` via XcodeBuildMCP
3. Structured failure output -> fix immediately
4. Repeat until green
</important>
