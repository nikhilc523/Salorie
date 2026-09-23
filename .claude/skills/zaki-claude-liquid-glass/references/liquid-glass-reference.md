# Liquid Glass — Extended Reference

## Background

Liquid Glass shipped with iOS 26 (announced WWDC 2025, June 9, 2025) as Apple's biggest design language change since iOS 7's move to flat design. It's a real-time rendered material — it bends and focuses light (lensing) rather than just scattering it like a blur. It spans iOS 26, iPadOS 26, macOS Tahoe 26, watchOS 26, tvOS 26, and visionOS 26.

Key official references:
- Apple docs: `developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)`
- Apple docs: `developer.apple.com/documentation/swiftui/glasseffectcontainer`
- Apple docs: `developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views`
- HIG: `developer.apple.com/design/human-interface-guidelines/materials`
- WWDC 2025 Session 219 — "Meet Liquid Glass"
- WWDC 2025 Session 323 — "Build a SwiftUI app with the new design"
- WWDC 2025 Session 310 — "Build an AppKit app with the new design" (if targeting Mac Catalyst / AppKit)

## Concentricity

Liquid Glass shapes should nest concentrically with the shapes around them (e.g. a capsule button inside a rounded-rect card should share the same corner curvature logic as the card, not an arbitrary radius). When placing a custom `.glassEffect(in: .rect(cornerRadius:))`, check the corner radius against the container it sits inside so the curves read as "the same material, one size down" rather than mismatched shapes.

## Custom shapes

```swift
Text("Custom shape glass")
    .padding()
    .glassEffect(.regular, in: .rect(cornerRadius: 20))

Image(systemName: "star.fill")
    .frame(width: 56, height: 56)
    .glassEffect(.regular, in: .circle)
```

## Tint (use sparingly, semantically)

```swift
Button("Delete", role: .destructive) { }
    .buttonStyle(.glassProminent)
    .tint(.red)
```

## Morphing between two states with glassEffectID

```swift
@Namespace private var glassNamespace

GlassEffectContainer(spacing: 20) {
    if isExpanded {
        expandedMenu
            .glassEffectID("controlCluster", in: glassNamespace)
    } else {
        collapsedButton
            .glassEffectID("controlCluster", in: glassNamespace)
    }
}
.animation(.spring, value: isExpanded)
```

## Text rendered as glass (rare, expensive for long strings)

`.glassEffect(.clear, in: customShape)` is the supported path for text that should look like Liquid Glass rather than a frosted overlay. Keep this to short strings (timers, single glyphs) — a long paragraph rendered as glass is expensive since it's GPU-bound by glyph count.

## Toolbar nuance

If a toolbar item shouldn't share the toolbar's glass background (e.g. a profile photo that needs to render un-obscured), use `.sharedBackgroundVisibility(.hidden)` on that item rather than hiding the whole toolbar's glass.

For custom toolbar buttons, prefer `.buttonStyle(.glassProminent)` combined with `.buttonBorderShape(...)` over reaching for raw `.glassEffect()` directly on the button — this keeps behavior consistent with system-provided toolbar buttons.

## Testing checklist before shipping a glass surface

1. Physical device, not simulator — specular highlights and motion response don't render correctly in the simulator.
2. Settings → Accessibility → Reduce Transparency: ON — confirm content is still legible without the glass effect.
3. Settings → Accessibility → Increase Contrast: ON — confirm control edges are still visible.
4. Settings → Accessibility → Reduce Motion: ON — confirm morphing/spring animations degrade gracefully.
5. Confirm glass sits on the navigation/control layer, with real content scrolling underneath it — a glass surface with nothing behind it to refract looks flat and defeats the point.

## Known quirks (as of iOS 26.x)

- `.buttonStyle(.glassProminent)` combined with `.circle` shape can show rendering artifacts on some builds — prefer `.buttonStyle(.glass)` for circular icon buttons if you see banding/artifacts, or file it against a specific Xcode/iOS version rather than assuming it's permanent.
- Placing a `Menu` inside a `GlassEffectContainer` has been reported to break morphing animation on some point releases — if this happens, apply `.glassEffect(.regular.interactive())` directly to the `Menu` instead of wrapping it.

These are point-release quirks, not reasons to fall back to custom styling — check current Apple release notes if a specific combination misbehaves.

## React Native / Expo — native Liquid Glass details

Two native modules deliver real Liquid Glass to RN on iOS 26+. Never fake it with `expo-blur` on iOS.

### expo-glass-effect
- `GlassView` — a native glass surface. Props: `glassEffectStyle: 'regular' | 'clear'`, `tintColor` (rgba string), `isInteractive` (bool), plus standard `style`. Strip `backgroundColor`/`borderWidth`/`shadow*` from the style you pass in — the material provides them; keep only `borderRadius`, padding, and layout.
- `GlassContainer` — RN equivalent of SwiftUI `GlassEffectContainer`; wrap sibling `GlassView`s and pass `spacing` so they merge/morph as one blob instead of separate floaters.
- `isLiquidGlassAvailable()` and `isGlassEffectAPIAvailable()` — call both; render native glass only when both are true AND `Platform.OS === 'ios'`.

### expo-router native tabs
`import { NativeTabs } from 'expo-router/unstable-native-tabs'` gives the native Liquid Glass tab bar (system translucency, SF Symbols, native tab haptics, scroll-to-top). Use `_layout.ios.tsx` for it and keep any custom `BlurView` dock in `_layout.tsx` for Android/Web only. Icons: `icon: { sf: 'clock' }`, `selectedIcon: { sf: 'clock.fill' }`. Bar blur: `blurEffect="systemChromeMaterial"`.

### Availability + accessibility gate (required)
Wrap `GlassView` in one component that:
1. returns a plain `<View>` when `Platform.OS !== 'ios'` or the API is unavailable, and
2. subscribes to `AccessibilityInfo` `reduceTransparencyChanged` and also returns a plain `<View>` when Reduce Transparency is on.

This is the RN analog of `#available(iOS 26, *)` + the HIG Reduce-Transparency test. Never show fake/opacity glass when native glass is off — degrade to an ordinary opaque surface.

### glassStyle usage convention
- `regular` → cards, panels, modals, result surfaces (frosted, more opaque).
- `clear` → control chrome: buttons, pills, segmented controls, chips (lighter, more transparent).
- `tintColor` → only for semantic state/selection (e.g. selected pill, status color, destructive), matching the SwiftUI "tint with meaning" rule.

## Haptics — coverage expectation

The bar is: **there is no such thing as a silent tap.** Every interactive element in the reference apps (Halal-It, Akhi-AI `mobile`, Medhive `Frontend`) fires a haptic. Centralize it:
- RN: one `useHaptics()` hook wrapping `expo-haptics`; call the right intensity inside every `onPress`/gesture. Fire `success()`/`error()` on operation outcomes, not just presses.
- SwiftUI: one `HapticManager` + a `.hapticTap(_:)` `View` extension (attached via `simultaneousGesture(TapGesture())`), or `.sensoryFeedback`. Prepare the generator before firing to cut latency.
- `NativeTabs` (RN) and system controls already emit haptics — don't stack a manual one on top of those.
