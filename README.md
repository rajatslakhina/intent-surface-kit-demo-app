# IntentSurfaceKit Demo App

**Talk to a document list the way you'd talk to Siri — and watch every resolution decision happen in front of you.**

This is the runnable companion to **[intent-surface-kit](https://github.com/rajatslakhina/intent-surface-kit)**: an iPhone app where an on-screen document list is annotated for an assistant, and a built-in console lets you throw utterances at it — *"share the third one"*, *"open the budget"*, *"summarize this"*, *"delete meeting notes"* — and see exactly how the semantic-contract layer resolves, clarifies, refuses, or streams.

This repo deliberately contains **no library code**. `Demo.xcodeproj` consumes `IntentSurfaceKit` as a **remote Swift Package dependency by its published GitHub URL** (`XCRemoteSwiftPackageReference`, branch `main`) — the same way any external team would. The rejected alternative was an `XCLocalSwiftPackageReference` to a sibling checkout: easier to iterate on, but it silently exempts the package from ever being consumed the way it's published, which is exactly the failure mode this split exists to catch. If the library repo breaks its API, this project breaks. That's the point: the split is the proof that the package stands on its own.

## Why this matters

App Intents 2.0 turns "your app" into "a tool an OS-level agent can invoke." The demos that matter for that world aren't feature demos — they're **trust demos**: does the app act on the right thing, ask when it isn't sure, refuse when it can't be sure, and stay honest about progress? This app makes those behaviors visible:

- **Ordinal resolution against the live screen** — say *"share the third one"*; row 3 is what the tracker says row 3 is. Delete a row and ordinals re-resolve against what's actually visible, not a stale list.
- **Focus-driven deixis** — tap a row (scope icon appears), then *"summarize this"* targets it. Nothing focused with several rows visible? You get a clarification, not a guess.
- **Multi-turn disambiguation** — *"open meeting notes"* matches two documents; the assistant asks, chips appear, and *"the second one"* answers **within the offered candidates**, bounds-checked. Answer *"the fifth one"* and it re-asks instead of crashing.
- **Typed refusals** — *"open item 9"* with six rows visible tells you it can only see six. Empty screen, sub-confidence matches, and stale annotations each produce their own message, because each is a distinct failure mode in the library.
- **Streaming execution with cancellation** — *"summarize this"* runs a three-step plan with live progress and a working Cancel button; commands issued mid-run are rejected as busy, not silently queued.

## How to run it

1. Clone this repo and open `Demo.xcodeproj` in Xcode (15 or later; any recent Xcode works — the code uses iOS 17-era APIs only).
2. Let Xcode resolve the remote package — it will fetch `intent-surface-kit` from GitHub automatically.
3. Select the `Demo` scheme, pick any iPhone Simulator, and **Build & Run**.
4. Try the suggestion chips, or type your own utterances. Tap rows to move focus. Delete things and watch ordinals stay honest.

## Verification status (honest)

This project was produced by an automated, unattended pipeline run, and that run could not open Xcode: interactive computer control requires a human present to approve screen access, which a scheduled run does not have. So, plainly: **this demo app has not yet been launched on a Simulator, and there are no screenshots in this repo yet.** No `Screenshots/` folder will pretend otherwise.

What *was* verified before pushing, all reproducibly:

- The library it depends on passed `swift build` and all **50 XCTest cases** (Swift 6.0.3, Linux, `StrictConcurrency` checking enabled) — including the edge cases this demo exercises (out-of-range ordinals, stale annotations, clarification staleness/expiry, cancellation mid-stream, overlapping-execution rejection).
- **The remote dependency path was proven end-to-end**: a scratch consumer package depending on `https://github.com/rajatslakhina/intent-surface-kit.git` (branch `main`) was resolved *from the pushed GitHub repo* and compiled a probe file exercising the exact API surface this app uses (`IntentSurface.handle`, `beginStreamingExecution`, `ScreenContextTracker`, `ScreenSnapshot`, `IntentPlan`/`IntentStep`, `IntentExecutionHandle`). Package resolution in Xcode follows the same path.
- `project.pbxproj` was checked for structural soundness (balanced braces/parens; single app target; remote-not-local package reference), and the shared `Demo.xcscheme` is XML-validated.
- `Demo/DemoApp.swift` passes `swiftc -parse` (syntax); its SwiftUI layer could not be type-checked headlessly (no macOS SDK in the pipeline's Linux sandbox) and received careful manual review instead: every list render is a `ForEach` over `Identifiable` values, every candidate/index access is bounds-checked, and there are zero force-unwraps.

The known residual risk is therefore the SwiftUI/Xcode layer only. If it fails to build for you, that's exactly the feedback loop the split-repo design is for — please open an issue.

## What it depends on

| | |
|---|---|
| Library | [intent-surface-kit](https://github.com/rajatslakhina/intent-surface-kit) |
| Reference kind | `XCRemoteSwiftPackageReference` → `https://github.com/rajatslakhina/intent-surface-kit.git`, branch `main` |
| Library verification | `swift build` + 50/50 XCTests (headless CI-style run) |
