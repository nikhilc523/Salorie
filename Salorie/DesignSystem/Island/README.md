# Fly-into-the-Dynamic-Island collect animations

A custom SwiftUI overlay that mimics an Apple-keynote "collect into the island"
motion. **No ActivityKit** — iOS hides your own Live Activity while the app is in
the foreground, so this is a black continuous-corner capsule drawn *over* the
hardware Dynamic Island (or growing down from under the status bar on older
devices).

## Files

| File | Role |
|---|---|
| `IslandController.swift` | `@Observable` state machine + `IslandMotion` constants. Screens call `log` / `addToTray` / `removeFromTray` / `createMeal`; it choreographs shape + content via animation completions and keyframe triggers — never `asyncAfter`. |
| `IslandOverlay.swift` | The one continuous capsule. Morphs between sizes; content layers on top at the final fixed size and blur-replaces in/out. Gulp/spit squash via `keyframeAnimator`. Owns the `LogCardContent` / `TrayContent` / `MealCardContent` layouts + all `#Preview`s. |
| `FlightLayer.swift` | `Flight` model + the `BezierFlight` `Animatable` `ViewModifier` (quadratic Bézier on progress `t`), the flying token + trail dots, and the `FlightLayer` ZStack. |
| `MiniSemicircleRings.swift` | The upper-half three-ring "rising sun" sized for the island card. `.drawingGroup()` for a single composited layer. |

## Wiring

* `SalorieApp` creates one `IslandController`, injects it with `.environment(island)`, and `island.bind(store:)` so a landed flight (which carries no store) can still read slot totals.
* `RootView` wraps the `TabView` in a `ZStack`, mounts `IslandOverlay()` at `zIndex(1000)`, and sets `.coordinateSpace(.named("screen"))`.
* Row tiles (`AddView.AddRow`, `MealBuilderView` ingredient rows) report their frame in the `"screen"` space via `onGeometryChange` and hand it to the controller, so a token flies from exactly the tile.

> **Layering note.** The overlay lives in the root `ZStack`, so it renders *above the tabs* but *below system sheets*. The **log-item** flow (Add tab) is fully visible. The **meal-building** tray/create flow is driven from inside sheets (`MealBuilderView` → ingredient-picker `AddView`), so in-app it's occluded by the sheet; the `#Preview`s ("Build a 4-item meal", "Remove one item", "Create the meal") are the source of truth for that choreography. Lift `MealBuilderView` out of a sheet (present it at the root) to see the tray live.

## Motion constants — the single tuning surface

All of these live in `enum IslandMotion` (`IslandController.swift`). Tune there.

### Springs & curves
| Name | Value | Used for |
|---|---|---|
| `morph` | `.spring(duration: 0.5, bounce: 0.22)` | island shape morphing between sizes |
| `content` | `.smooth(duration: 0.35)` | card content blur/crossfade in |
| `numberRoll` | `.smooth(duration: 0.9)` | meal-total roll |
| `ringFill` | `.smooth(duration: 0.9)` | mini rings filling |
| `tray` | `.spring(duration: 0.42, bounce: 0.24)` | tray grow/narrow, chip in/out |
| `flight` | `.timingCurve(0.45, 0.05, 0.35, 1, duration: 0.65)` | the Bézier flight |
| `fadeOut` | `.easeOut(duration: 0.2)` | content folding out before close |
| `reduced` | `.smooth(duration: 0.3)` | Reduce-Motion replacement for all of the above |

### Durations (seconds)
| Name | Value | Meaning |
|---|---|---|
| `flightDuration` | `0.65` | token flight length |
| `autoClose` | `2.6` | log card auto-close after the last tap |
| `mealCardHold` | `3.4` | created-meal card hold before folding |
| `checkPopDelay` | `0.9` | success check pop on the meal card |

### Island geometry (points)
| Name | Value |
|---|---|
| `idleSize` | `126 × 37` |
| `logCardSize` | `350 × 90` |
| `mealCardSize` | `352 × 176` |
| `trayHeight` | `37` |
| `trayWidth(count:)` | `min(124 + 40 + 14·n, 250)` |
| `idleCorner` / `logCorner` / `mealCorner` / `trayCorner` | `18.5` / `42` / `44` / `18.5` |

### Placement
| Name | Value | Meaning |
|---|---|---|
| `islandTopInset` | `11` | top gap on Dynamic-Island devices |
| `dynamicIslandThreshold` | `51` | top safe-area inset ≥ this ⇒ device has a DI (else grow down from status bar) |
| `statusBarHideWidth` | `130` | hide the status bar while the shape is wider than this |

### Squash (keyframe, in `IslandOverlay`)
* **Gulp** (log / tray add) — triggered by `gulpCount`: `scaleX 1 → 1.12 → 0.98 → 1`, `scaleY 1 → 1.18 → 0.96 → 1` over ~0.42 s, `.light` haptic.
* **Spit** (remove) — triggered by `spitCount`: `scaleX 1 → 0.9 → 1.06 → 1`, `scaleY 1 → 0.84 → 1.1 → 1` over ~0.40 s, `.soft` haptic.
* **Meal created** — `mealCreatedCount` fires a `.success` haptic.

### Flight token (in `BezierFlight`)
Forward (row → island): `scale 1 → 0.3` (ease `t^1.4`), `rotation 0 → −25°`, `corner 12 → 21`, opacity → 0 in the last 8%. Three 6-pt trail dots lag 7% each at opacity `0.45 / 0.33 / 0.21`. Reverse (island → row) mirrors the curve and grows `0.3 → 1`, `corner 21 → 12`, fades in over the first 8%, no trail.

## Accessibility

`IslandController.reduceMotion` mirrors `@Environment(\.accessibilityReduceMotion)`.
When on: no flight, no squash — the island cross-fades between states and numbers
still roll. Every add/remove/create posts an `AccessibilityNotification.Announcement`.

## Performance

`.geometryGroup()` on the island content, `.compositingGroup()` on the shape,
`.drawingGroup()` on the mini rings, and the scrolling list does no
layout-affecting work during a flight (only the `+`/check and a small press
scale). Target: zero hitches in Instruments → Animation Hitches with 7 rapid taps.
