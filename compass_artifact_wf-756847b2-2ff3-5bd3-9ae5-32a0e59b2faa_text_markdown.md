# Best Claude Code Skills & MCP Servers for Building MiniLog (Native iOS 26/27, SwiftUI, Liquid Glass)

## TL;DR
- **Build the MiniLog stack around three pillars:** (1) a *knowledge layer* of SwiftUI/Liquid Glass + Swift 6 skills (Paul Hudson's `swiftui-pro`, Thomas Ricouard's `swiftui-liquid-glass`, and dpearson2699's 86-skill `swift-ios-skills` collection plus n0an's App Intents skill for the fast-moving iOS 27 surfaces); (2) a *discipline layer* (obra/superpowers for TDD + verification, plus Paul Hudson's `swift-testing-pro`); and (3) an *execution/verification layer* (XcodeBuildMCP for build→run→screenshot→snapshot_ui loops, backed by Xcode 26.3+'s built-in `xcrun mcpbridge` MCP that can render SwiftUI previews).
- **Liquid Glass is genuinely well-covered by community skills** — `Dimillian/Skills` (swiftui-liquid-glass) and `dpearson2699/swift-ios-skills` (swiftui-liquid-glass) both teach `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `glassEffectID` morphing and `#available(iOS 26, *)` gating — exactly what MiniLog's ~4 Liquid Glass screens need.
- **Automatic UI verification is the highest-leverage capability and is production-ready today:** XcodeBuildMCP (acquired by Sentry in Feb 2026) gives the agent `build_run_sim → screenshot → snapshot_ui → tap/type → screenshot` so Claude can visually confirm the glass UI, while Apple's own Xcode MCP `RenderPreview` tool renders SwiftUI previews as images. One caveat: as of the Xcode 27 beta, XcodeBuildMCP's semantic UI automation had a known breakage; verify it works on your toolchain.

## Key Findings
- **Liquid Glass / iOS 26–27 SwiftUI:** The strongest, most current skills are `Dimillian/Skills → swiftui-liquid-glass` (MIT, 1.6k stars/88 forks on the repo page; SKILL.md last updated 2026-03-29) and `dpearson2699/swift-ios-skills → swiftui-liquid-glass` (part of an **86-skill** iOS-26+/Swift 6.3 collection, ~1,129 stars, last pushed May 28, 2026). Paul Hudson's `twostraws/swiftui-agent-skill → swiftui-pro` is the best "prevent-deprecated-API" reviewer (catches `ObservableObject`, `foregroundColor()`, `NavigationView`, etc.).
- **TDD / Testing:** `obra/superpowers` (the most-starred Claude Code skills repo — 224,691 stars per Ry Walker Research in June 2026, up to 265.8k+ per some directory listings; latest release v5.1.0 shipped May 4, 2026) enforces RED-GREEN-REFACTOR and adds `verification-before-completion`. Pair with `twostraws/swift-testing-agent-skill → swift-testing-pro` or `AvdLee/Swift-Testing-Agent-Skill` for `@Test`/`#expect` correctness, and `pointfreeco/swift-snapshot-testing` for screenshot/snapshot regression tests.
- **Auto UI verification / Simulator:** `XcodeBuildMCP` (Cameron Cooke → getsentry, ~5.4–6.4k stars, **up to 82 tools across 15 workflows** in v2.7.0) is the primary tool; `joshuayoes/ios-simulator-mcp` is a lighter idb-based alternative (screenshot + accessibility-tree tools). Apple's built-in Xcode MCP (Xcode 26.3+, `xcrun mcpbridge`, 20 tools incl. `RenderPreview`, `BuildProject`, `RunAllTests`) is complementary.
- **Siri/App Intents, HealthKit, SwiftData, Concurrency:** `n0an/App-Intents-Agent-Skill` is explicitly WWDC26/iOS 27-updated (App Schemas, SiriKit deprecation) — critical for MiniLog. `twostraws/swiftdata-agent-skill` and `AvdLee/Swift-Concurrency-Agent-Skill` cover SwiftData and Swift 6 strict concurrency. HealthKit is covered inside dpearson2699's collection.
- **Distribution:** No fastlane toolchain is strictly required — App Store Connect MCP servers (`pofky/asc-mcp`, `rabdulsal/appstore-release-mcp`, `OrellBuehler/testflight-mcp`) drive TestFlight via the ASC API + `xcrun altool`.
- **Apple's own Xcode 27 skills:** Xcode 27 (WWDC26) bundles 7 Apple-authored agent skills exportable via `xcrun agent skills export` — but notably NO explicit Liquid Glass skill.

## Details

### Category 1 — SwiftUI / iOS 27 & Liquid Glass

**1. Dimillian/Skills — `swiftui-liquid-glass`** (top pick for Liquid Glass)
- Author: Thomas Ricouard (Dimillian, author of Ice Cubes). URL: `https://github.com/Dimillian/Skills`
- What it does: Implements/reviews SwiftUI Liquid Glass. Explicitly teaches native `glassEffect`, `GlassEffectContainer`, glass button styles, `.interactive()`, `glassEffectID` + `@Namespace` for morphing, correct modifier order (glass after layout/appearance), and `#available(iOS 26, *)` gating with fallbacks.
- iOS 26/27 & Liquid Glass coverage: Excellent, purpose-built.
- License MIT, **1.6k stars / 88 forks** on the repo page; SKILL.md last updated 2026-03-29. The repo self-describes as "My Codex Skills" and contains **16 Codex skills** total: also `swiftui-ui-patterns`, `swiftui-view-refactor`, `swiftui-performance-audit`, `swift-concurrency-expert`, `ios-debugger-agent` (uses XcodeBuildMCP), `app-store-changelog`, `bug-hunt-swarm`, `review-swarm`, `orchestrate-batch-refactor`, and more.
- Install (Claude Code): `npx skills add dimillian/skills` (CLI) or copy the skill folder to `.claude/skills/`.
- Caveat: The SKILL.md is guidance-only (no scripts); it does not build/run. Verify iOS 27-specific deltas against Apple docs.

**2. dpearson2699/swift-ios-skills — `swiftui-liquid-glass` (+ 85 others)**
- URL: `https://github.com/dpearson2699/swift-ios-skills`. ~1,129 stars, Swift 6.3 / iOS 26+, PolyForm Perimeter license, last pushed May 28, 2026.
- What it does: **86 self-contained skills** ("Every skill is self-contained. No skill depends on another. Install only what you need") covering the full modern surface: `swiftui-liquid-glass` (covers `glassEffect`, `GlassEffectContainer`, glass toolbar/tab bar, `ToolbarSpacer`, `scrollEdgeEffectStyle`, `backgroundExtensionEffect`, availability gating), plus `swiftui-navigation`, `swift-concurrency`, `swiftdata`, `swift-testing`, `healthkit`, `app-intents`, `foundation-models` (LanguageModelSession, @Generable, @Guide), `swiftlint`, `ios-simulator`, `swift-charts`, `storekit`, `widgetkit`, and more. Installable individually or as 10 themed plugin bundles (swiftui-skills, swift-core-skills, ios-ai-ml-skills, etc.).
- Why it matters for MiniLog: This single repo covers nearly every MiniLog framework (SwiftData, HealthKit, App Intents, Foundation Models, VisionKit/Vision, Liquid Glass, concurrency, SwiftLint).
- Install: `npx skills add https://github.com/dpearson2699/swift-ios-skills --skill swiftui-liquid-glass` (per skill) or `/plugin marketplace add dpearson2699/swift-ios-skills` then `/plugin install swiftui-skills@swift-ios-skills` (bundled plugins).
- Caveat: README states skills "were generated with the assistance of Claude Code. Content may contain inaccuracies." A large installed count can dilute Claude's skill-selection (a documented issue where 150+ skills strip skill descriptions) — install only the subset MiniLog needs.

**3. twostraws/swiftui-agent-skill — `swiftui-pro`** (best deprecated-API guardrail)
- Author: Paul Hudson (Hacking with Swift). URL: `https://github.com/twostraws/swiftui-agent-skill`. MIT; author reported it became "the #1 most starred skill for Swift developers on all of GitHub" (~1800+ stars within a week of its March 2026 launch).
- What it does: Comprehensive SwiftUI reviewer. `references/api.md` flags deprecated APIs; enforces `@Observable` over `ObservableObject`, avoiding `foregroundColor()`, avoiding `Text` `+` concatenation, `NavigationStack` over `NavigationView`, accessibility labeling, Dynamic Type, and performance (no work in `init`/`body`).
- Liquid Glass coverage: Not its focus — pair it with a dedicated Liquid Glass skill.
- Install (Claude Code): `/plugin marketplace add twostraws/SwiftUI-Agent-Skill` then `/plugin install swiftui-pro@swiftui-agent-skill`; or `npx skills add https://github.com/twostraws/swiftui-agent-skill --skill swiftui-pro`.
- Companion repos by the same author (all MIT): `SwiftData-Agent-Skill` (swiftdata-pro), `Swift-Concurrency-Agent-Skill` (swift-concurrency-pro), `Swift-Testing-Agent-Skill` (swift-testing-pro). Directory of all: `twostraws/swift-agent-skills`.

**4. AvdLee/SwiftUI-Agent-Skill — `swiftui-expert-skill`**
- Author: Antoine van der Lee (SwiftLee). URL: `https://github.com/AvdLee/SwiftUI-Agent-Skill`. Includes optional iOS 26+ Liquid Glass styling with availability gating; strong on state management, ForEach identity, and Instruments trace analysis.
- Install: `/plugin marketplace add AvdLee/SwiftUI-Agent-Skill`; or `npx skills add https://github.com/avdlee/swiftui-agent-skill --skill swiftui-expert-skill`.

**5. Apple HIG / design skills (supporting):** `tzzs/apple-design-skill` and `dickwu/apple-design-skill` (HIG reference + sitemap, Liquid Glass, tab bars); `haider-nawaz/liquid-glass-skill` (5-phase migration workflow, `/plugin marketplace add haider-nawaz/liquid-glass-skill`); `rshankras/claude-code-apple-skills` (164-skill indie stack, iOS 27/macOS 27 frontmatter, includes Liquid Glass + SF Symbols + ASO). Treat these as HIG-compliance reviewers, not code generators; several are Claude-generated and warrant scrutiny.

### Category 2 — TDD & Testing

**1. obra/superpowers** (the discipline layer)
- Author: Jesse Vincent (obra) / Prime Radiant. URL: `https://github.com/obra/superpowers`. MIT. The most-starred Claude Code skills repo — 224,691 stars per Ry Walker Research (June 2026, "roughly 4x its February 2026 count"), listed as high as 265.8k+ in some skill directories; latest release v5.1.0 shipped May 4, 2026.
- What it does: Bundles composable, auto-triggering skills: `brainstorming`, `writing-plans`, `test-driven-development` (RED-GREEN-REFACTOR: write failing test → watch it fail → minimal code → watch it pass → commit; "Deletes code written before tests"), `verification-before-completion` (forces name-command → run → paste output → only-then-claim-done; and for regression tests requires Write → Run pass → Revert fix → Run MUST FAIL → Restore → Run pass), `systematic-debugging`, `subagent-driven-development`, `requesting-code-review`, `using-git-worktrees`.
- Install (Claude Code, official marketplace): `/plugin install superpowers@claude-plugins-official`; or marketplace `/plugin marketplace add obra/superpowers-marketplace` then `/plugin install superpowers@superpowers-marketplace`; or clone to `~/.claude/skills/superpowers`.
- Why for MiniLog: "accuracy-first" is the app's core value — TDD + verification-before-completion directly serve that. The methodology is language-agnostic; the TDD cycle applies to Swift Testing.

**2. twostraws/swift-testing-agent-skill — `swift-testing-pro`**
- Covers `@Test`, `#expect`, `#require`, parameterized testing, traits, exit tests, confirmations — targeting LLM mistakes. Install: `/plugin marketplace add twostraws/Swift-Testing-Agent-Skill` then `/plugin install swift-testing-pro@swift-testing-agent-skill`.
- Alternative: `AvdLee/Swift-Testing-Agent-Skill` (`swift-testing-expert`) — XCTest→Swift Testing migration, flaky parallel behavior, actor isolation.

**3. pointfreeco/swift-snapshot-testing** (library, not a skill)
- URL: `https://github.com/pointfreeco/swift-snapshot-testing`. The de-facto Swift snapshot library; image + text/JSON/recursive-view-description strategies. Add to the test target only (from ~1.17.0). Enables screenshot-diff regression tests of the Liquid Glass screens that a skill/agent can run and compare. The community write-up "Giving Claude Code Eyes to See Your SwiftUI Views" documents the exact CC + snapshot-testing loop.

### Category 3 — Automatic UI Verification / Simulator (highest leverage for MiniLog)

**1. XcodeBuildMCP** (primary — build, run, screenshot, accessibility tree)
- Author: Cameron Cooke; acquired by Sentry in February 2026 (the announcement cited "more than 4,000 GitHub stars"; Cameron Cooke joined Sentry, the repo moved to the `getsentry` org and the old `cameroncooke/XcodeBuildMCP` URL 301-redirects; still MIT, npm package still `xcodebuildmcp`). Now ~5.4–6.4k stars. Per the official docs (v2.7.0) it "gives AI coding agents up-to 82 tools across 15 workflows for iOS, iPadOS, macOS, watchOS, tvOS, and visionOS development."
- How it auto-verifies UI: Tools `build_sim`/`build_run_sim`, `screenshot` (image), `snapshot_ui` (semantic accessibility hierarchy with stable element refs + screen hash), `tap`/`swipe`/`type_text` (by accessibility id/label, not brittle coordinates), `test_sim` (XCUITest with structured failure lists), plus stateful LLDB debugging. The canonical loop: `build_run_sim → screenshot → snapshot_ui → tap by id → type → screenshot → "tell me what visually changed."` A recent release added compact post-action snapshots that cut wall-clock ~70%, tokens ~68%, and tool calls ~76% in a benchmark task.
- Install (Claude Code): `claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp`; or Homebrew `brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp`. Ships an optional MCP Skill/CLI Skill to prime the agent.
- MiniLog tip: Add `.accessibilityIdentifier("...")` to controls (e.g. `today_add_button`) as you build — this makes `snapshot_ui`/`tap` reliable AND completes VoiceOver support. XcodeBuildMCP proxies Xcode 26.3's own MCP tools, so you only configure one server.
- **Caveat (important for iOS 27):** On the Xcode 27 beta, XcodeBuildMCP's semantic UI automation was reported broken (bundled AXe looked for `SimulatorKit.framework` under the old Xcode 26 PrivateFrameworks path — issues #446/#453); build/install/launch/screenshot still worked, but `snapshot_ui`/element-ref tapping failed. Also a foldable iPhone Duo simulator input bug (#537). Confirm current status against your installed Xcode/XcodeBuildMCP versions before relying on tap automation.

**2. joshuayoes/ios-simulator-mcp** (lighter idb-based alternative)
- URL: `https://github.com/joshuayoes/ios-simulator-mcp`. MIT, npm `ios-simulator-mcp`. Tools: `ui_describe_all` (full accessibility tree), `ui_tap`, `ui_type`, `ui_swipe`, `ui_describe_point`, `ui_find_element` (search AX tree by label/id/type), `ui_view` (compressed base64 screenshot), `screenshot`, `record_video`, `install_app`, `launch_app`, `get_booted_sim_id`.
- Install: `claude mcp add ios-simulator -- npx -y ios-simulator-mcp`; requires Facebook `idb`. Featured in Anthropic's Claude Code best-practices article.
- **Security caveat:** Command-injection (CWE-78) vulnerability in versions < 1.3.3 — use ≥ 1.3.3 (fixed in that release).
- When to prefer: If you want screenshot + accessibility inspection without XcodeBuildMCP's full build stack, or as a fallback if XcodeBuildMCP's UI automation is blocked on your Xcode beta.

**3. Apple's built-in Xcode MCP (Xcode 26.3+, `xcrun mcpbridge`)** — complementary, first-party
- Xcode 26.3 (released Feb 3, 2026) ships a built-in MCP server exposing 20 native tools; Xcode now natively hosts Claude Agent and Codex, and agents can render SwiftUI previews to visually verify results.
- Setup: In Xcode → Settings → Intelligence → Model Context Protocol → toggle Xcode Tools ON; then `claude mcp add --transport stdio xcode -- xcrun mcpbridge` (Xcode must be running with a project open; mcpbridge auto-detects the PID). For Codex: `codex mcp add xcode -- xcrun mcpbridge`.
- Tools (20): `XcodeRead/Write/Update/Glob/Grep/LS/MakeDir/RM/MV`, `BuildProject`, `GetBuildLog`, `RunAllTests`, `RunSomeTests`, `GetTestList`, `XcodeListNavigatorIssues`, `XcodeRefreshCodeIssuesInFile`, `ExecuteSnippet` (Swift REPL), `RenderPreview` (renders SwiftUI previews as images for visual verification), `DocumentationSearch` (Apple docs + WWDC video transcripts), `XcodeListWindows`. Most tools take a `tabIdentifier` from `XcodeListWindows`.
- Why for MiniLog: `RenderPreview` lets the agent *see* a Liquid Glass view without a full run; `DocumentationSearch` grounds it in current Apple docs/WWDC (mitigating stale training data on iOS 27). Xcode 27 (WWDC26) added debugger/run-state/scheme/build-settings MCP tools.
- Caveat: Xcode 26.3 RC 1 had a `structuredContent` schema bug affecting spec-strict clients like Cursor (fixed in RC 2). Requires a paid Apple Developer account to obtain the beta.

### Category 4 — Siri/App Intents, HealthKit, SwiftData, Concurrency

- **n0an/App-Intents-Agent-Skill** (`app-intents`) — URL `https://github.com/n0an/App-Intents-Agent-Skill`. Explicitly "Updated for WWDC 2026 / iOS 27": long-running & cancellable intents, on-screen awareness, EntityCollection, SyncableEntity, the AppIntentsTesting framework, plus the SiriKit→App Intents migration map. Directly addresses MiniLog's constraint (SiriKit deprecated at WWDC26; App Intents + AppShortcutsProvider). Warns against the exact traps MiniLog will hit (SwiftData `@Model` can't conform to `AppEntity` under Swift 6 because `AppEntity` requires `Sendable`; `@Query` silently does nothing in intents; create/inject `ModelContext` correctly in `perform()`). Install: `npx skills add n0an/app-intents-agent-skill --skill app-intents`. (Note: there is NO nutrition App Schema domain, consistent with MiniLog's plan — this skill covers custom intents, which is the right path.) A separate `alexey1312/agents-plugins → ios27-app-intents` skill also targets iOS 27 App Intents with a 12-rung adoption ladder + audit checklist.
- **twostraws/SwiftData-Agent-Skill** (`swiftdata-pro`) — @Model, @Query, predicates, indexes, migrations, relationships, iCloud sync; Swift 6.2+, iOS 18+ indexing, iOS 26+ class inheritance; special handling for CloudKit predicate constraints. Author wrote the SwiftData book. Install: `npx skills add https://github.com/twostraws/swiftdata-agent-skill --skill swiftdata-pro`.
- **AvdLee/Swift-Concurrency-Agent-Skill** (`swift-concurrency`) — ~1.1k stars. Data races, async/await, actor isolation, Sendable, Swift 6 strict-concurrency migration, SwiftLint-aware; reads build settings first, prefers structured concurrency over `Task.detached`. Install: `/plugin marketplace add AvdLee/Swift-Concurrency-Agent-Skill` then `/plugin install swift-concurrency@swift-concurrency-agent-skill`. (twostraws' `swift-concurrency-pro` and Dimillian's `swift-concurrency-expert` are alternatives.)
- **HealthKit** — Covered inside `dpearson2699/swift-ios-skills` (`healthkit`: HKHealthStore authorization, sample/statistics/collection queries, background delivery). For MiniLog's `HKCorrelation .food` writes + edit/delete sync there's no dedicated star skill — lean on dpearson2699's skill + Apple `DocumentationSearch` and verify against Apple docs.

### Category 5 — Build / Distribution (TestFlight)

- **pofky/asc-mcp** — App Store Connect MCP: 41 opinionated tools + 6 slash-command prompts + a bundled Claude Skill; drives metadata, screenshots, builds, TestFlight, submit/release via ASC API `.p8` key. Notes fastlane's deliver/pilot are "just calls to the same ASC REST API," so no Ruby toolchain is needed except the build/sign step (`build_and_archive`/`upload_binary` via Xcode). Paid: 7-day trial then subscription. Install: `npx @pofky/asc-mcp init --write`.
- **rabdulsal/appstore-release-mcp** — `asc_upload_build` (runs your fastlane lane as an async job with log polling) or `asc_upload_ipa` (direct `xcrun altool`, no fastlane), version bumping in `project.pbxproj`. Credential names match fastlane's `app_store_connect_api_key`.
- **OrellBuehler/testflight-mcp** — read-only TestFlight feedback (tester comments, screenshot URLs, device/OS, resolved build). `claude mcp add testflight --env ASC_KEY_ID=... --env ASC_ISSUER_ID=... --env ASC_PRIVATE_KEY_PATH=... -- npx -y @orellbuehler/testflight-mcp`. Good for the "few friends" TestFlight loop.
- **fastlane itself** — still viable via `upload_to_testflight`; requires App Manager/Admin ASC role. A community "Fastlane iOS Beta Release" Claude skill wraps Match/Gym/Pilot.

### Category 6 — Code Quality (Lint/Format)

- **dpearson2699/swift-ios-skills → `swiftlint`** and Paul Hudson's `swiftui-pro` (deprecated-API review) cover most quality needs. Community `swiftlint-autofix` skills and the Grade-A `aiskillstore/marketplace → swift-development` skill (build/test/simctl/SwiftFormat/SwiftLint/SPM/Swift 6 concurrency) exist. For a project-scoped SwiftLint/SwiftFormat pipeline, the Medium write-up "Agent Skills in Xcode 26.3" shows a `swift-formatter` skill pattern stored in `.agents/skills/` that applies your `only_rules` whitelist to changed files. Use SwiftLint/SwiftFormat as tools invoked by a thin skill rather than trusting the model to format by hand.

### Apple's own Xcode 27 bundled skills (WWDC26)
Xcode 27 ships **7 Apple-authored agent skills** in the toolchain (open SKILL.md format): `swiftui-specialist`, `swiftui-whats-new-27`, `uikit-app-modernization`, `test-modernizer`, `audit-xcode-security-settings`, `c-bounds-safety`, `device-interaction`. Export them with `xcrun agent skills export --output-dir ~/Downloads/xcode-skills` and drop the folders into `.claude/skills/`. `swiftui-whats-new-27` is valuable because it's exactly the area LLMs are least trained on. Apple also shipped open-source Metal agent skills as part of Game Porting Toolkit 4 (not relevant to MiniLog). **Caveat:** No explicit Liquid Glass skill among the seven — still pair with Dimillian/dpearson2699 for glass. (Source: community DEV article, not official Apple docs — verify with your Xcode 27 install.)

## Recommended Starter Stack for MiniLog

**Install now (core loop):**
1. `obra/superpowers` — TDD + verification-before-completion discipline (`/plugin install superpowers@claude-plugins-official`).
2. `XcodeBuildMCP` — build/run/screenshot/snapshot_ui auto-verification (`claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp`).
3. `Dimillian/Skills → swiftui-liquid-glass` — Liquid Glass correctness (`npx skills add dimillian/skills`, keep just the glass skill).
4. `twostraws/swiftui-agent-skill → swiftui-pro` — deprecated-API guardrail.
5. `twostraws/swift-testing-agent-skill → swift-testing-pro` — Swift Testing correctness.
6. `n0an/App-Intents-Agent-Skill` — iOS 27 App Intents/Siri (MiniLog's SiriKit-deprecated path).
7. `twostraws/swiftdata-agent-skill → swiftdata-pro` + `AvdLee/Swift-Concurrency-Agent-Skill` — data + Swift 6 concurrency.
8. From `dpearson2699/swift-ios-skills`: install just `healthkit`, `swiftui-liquid-glass` (as a cross-check), `foundation-models`, `swiftlint`, `ios-simulator`.

**Add for distribution:** `OrellBuehler/testflight-mcp` (feedback) + `rabdulsal/appstore-release-mcp` (upload) or fastlane.

**Add if on Xcode 26.3+/27:** Apple's built-in Xcode MCP (`claude mcp add --transport stdio xcode -- xcrun mcpbridge`) for `RenderPreview` + `DocumentationSearch`; export Apple's `swiftui-whats-new-27` skill.

**Thresholds that change the plan:**
- If Claude's skill list gets diluted (bare skill names, wrong skill firing) → move iOS skills to project scope (`.claude/skills/`) and prune to <~20 active skills.
- If XcodeBuildMCP `snapshot_ui`/tap fails on your Xcode beta → fall back to `joshuayoes/ios-simulator-mcp` (≥1.3.3) for screenshots/AX tree, or Apple's `RenderPreview` for preview images, and rely on snapshot-testing for regression.
- If accuracy bugs slip through → add `pointfreeco/swift-snapshot-testing` image tests for the 4 screens and gate merges on them.

### Concrete Claude Code workflow (TDD → implement → build → run → auto-verify UI → iterate)
1. **RED:** Ask Claude (superpowers active) to write a failing Swift Testing test for a unit (e.g. serving-size calorie math, USDA/OFF DB query via GRDB/FTS5). Watch it fail via XcodeBuildMCP `test_sim`.
2. **GREEN:** Implement minimal code; `swiftui-pro`/`swiftdata-pro`/`swift-concurrency` skills keep APIs modern and Swift 6-safe.
3. **BUILD:** XcodeBuildMCP `build_sim` — structured errors returned (no giant log dumps); Claude fixes and rebuilds.
4. **RUN + UI VERIFY:** `build_run_sim` on an iPhone 17/iOS 27 sim → `screenshot` → `snapshot_ui` to confirm the Liquid Glass Today-log renders (glass tab bar/toolbar, `.buttonStyle(.glass)`), `tap`/`type` to exercise Add-via-Search/Scan, `screenshot` again; use Apple MCP `RenderPreview` for isolated view checks. The `swiftui-liquid-glass` skill reviews `glassEffect`/`GlassEffectContainer` usage.
5. **VERIFY-BEFORE-DONE:** superpowers `verification-before-completion` forces Claude to run tests, paste output, and prove the glass UI matches before claiming done.
6. **REGRESSION:** Record `swift-snapshot-testing` snapshots for the 4 screens; re-run each iteration.
7. **SHIP:** `appstore-release-mcp`/fastlane upload to TestFlight; `testflight-mcp` pulls friend feedback.

### Example CLAUDE.md (enforce TDD + UI verification)
```markdown
# MiniLog — Agent Operating Rules

## Non-negotiables
- TDD ALWAYS. Before writing implementation, write a failing Swift Testing test (@Test/#expect) and RUN it via XcodeBuildMCP test_sim to confirm it fails for the right reason. Never write implementation before a red test. Delete code written before its test.
- Swift 6 strict concurrency, iOS 26 minimum. Use @Observable (never ObservableObject), NavigationStack (never NavigationView), SwiftData for user data.
- Liquid Glass: use native glassEffect / GlassEffectContainer / .buttonStyle(.glass) / glassEffectID; gate with #available(iOS 26, *) + fallback. No custom blurs. Invoke the swiftui-liquid-glass skill for any glass UI.

## Definition of done (verification-before-completion)
- Name the exact test command, RUN it, and PASTE the output. Do not claim done without it.
- After any UI change: build_run_sim on "iPhone 17" (iOS 27), then screenshot + snapshot_ui. Confirm the changed element exists in the accessibility tree AND looks correct in the screenshot. Report what visually changed.
- Every interactive control gets .accessibilityIdentifier(...) (stable snapshot_ui targeting + VoiceOver).

## Tools
- Build/run/UI: XcodeBuildMCP (build_sim, build_run_sim, screenshot, snapshot_ui, tap, type_text, test_sim). Xcode MCP RenderPreview for isolated view previews.
- Skills: swiftui-pro (deprecated-API review), swiftdata-pro, swift-concurrency, app-intents, swift-testing-pro, swiftui-liquid-glass.

## Review gate
- Run swiftui-pro + swiftlint before marking a task complete. Record swift-snapshot-testing snapshots for Today/Add/Detail/MyItems and keep them green.
```

## Recommendations
1. **Start minimal (Week 1):** superpowers + XcodeBuildMCP + swiftui-liquid-glass + swiftui-pro + swift-testing-pro. This gives you the full TDD→build→run→verify loop and correct glass from day one. Add the CLAUDE.md above.
2. **Add framework skills as you touch each area (Week 2+):** swiftdata-pro when wiring SwiftData; app-intents (n0an) when adding Siri; dpearson2699 `healthkit` + `foundation-models` when adding HealthKit writes and on-device NL parsing.
3. **Wire distribution last:** appstore-release-mcp or fastlane for TestFlight uploads; testflight-mcp for feedback.
4. **Vet every third-party skill before install** (they run in your dev environment): read the SKILL.md, confirm author identity, pin versions (ios-simulator-mcp ≥1.3.3), prefer project scope (`.claude/skills/`) over global, and prune to keep Claude's skill selection sharp.
5. **Treat community "iOS 27/Liquid Glass" claims as provisional** and cross-check against Apple's `DocumentationSearch`/live HIG, since much tooling was authored around iOS 26 and WWDC26 is recent.

## Caveats
- **Stars/dates are moving targets:** figures cited (superpowers ~224k–265k, XcodeBuildMCP ~5.4–6.4k, dpearson2699 ~1,129, Dimillian 1.6k) come from GitHub pages and third-party skill directories captured at different dates in 2026; verify live before relying on them.
- **Xcode 27 beta breakage:** XcodeBuildMCP semantic UI automation (snapshot_ui/tap) had open issues on the Xcode 27 beta toolchain; screenshot/build/run were unaffected. Test before depending on tap automation.
- **AI-generated skill content:** dpearson2699 and several apple-design skills were partly Claude-generated and self-flag possible inaccuracies; use them as accelerators, not authorities.
- **Apple's 7 bundled Xcode 27 skills** are documented via a community DEV article, not official Apple docs seen here — and include NO explicit Liquid Glass skill. Verify names/export command on your install.
- **HealthKit gap:** No standout dedicated HealthKit skill for `HKCorrelation .food` edit/delete sync; rely on dpearson2699's healthkit skill + Apple docs.
- **Paid/beta requirements:** Apple's Xcode MCP needs Xcode 26.3+/27 (Developer Program); asc-mcp is subscription-based after a trial.
- **Security:** ios-simulator-mcp <1.3.3 had a command-injection CVE-class bug (fixed in 1.3.3); all MCP servers holding ASC `.p8` keys handle sensitive credentials — scope keys to App Manager and store `.p8` securely (download-once).