---
name: zaki-claude-liquid-glass
description: >
  Enforces native iOS 26+ Liquid Glass in all iOS UI — SwiftUI, UIKit, and React Native / Expo
  (expo-glass-effect + expo-router NativeTabs). Covers buttons, icons, navbars, tab bars, search
  bars, text inputs, sheets, cards, every interactive element. Two hard laws: (1) never hand-roll
  or custom-make Liquid Glass — always use the platform's native component (SwiftUI `.glassEffect`/
  `.buttonStyle(.glass)`, or RN `GlassView`/`GlassContainer`/`NativeTabs`); never fake it with
  BlurView/ultraThinMaterial/opacity on iOS. (2) every touch fires a haptic. Use when writing,
  reviewing, or refactoring any iOS UI code (Swift or React Native/Expo), even if the user just
  says "make a button" or "add a nav bar" without mentioning liquid glass, haptics, or iOS 26.
  Trigger on SwiftUI views, buttons, NavigationStack/toolbar, TabView, .searchable, TextField,
  sheets; and on RN/Expo Pressable/TouchableOpacity, expo-router layouts, expo-glass-effect,
  expo-haptics, or any styling / press-feedback decision.
---

# Claude Liquid Glass Skill

Applies to **both** native Apple UI (SwiftUI/UIKit) **and React Native / Expo** apps targeting iOS 26+.

## The Two Hard Laws

1. **Never custom-make Liquid Glass.** Always render it with the platform's own native component. Do not hand-roll glass from `BlurView`, `.ultraThinMaterial`, blur+opacity+border stacks, or gradients on iOS. If a native glass primitive exists for the job, you MUST use it and nothing else.
2. **Every single touch fires a haptic.** Every button, tab, toggle, card tap, chip, list row, and gesture triggers native haptic feedback. A tappable element with no haptic is a bug. (See [Mandatory Haptics](#mandatory-haptics).)

## Core Rule

This app uses **only the OS's native Liquid Glass material system** (shipped iOS 26, WWDC 2025). Every interactive surface — buttons, icons, nav bars, tab bars, search bars, text inputs, sheets, cards, toolbars — must use the real system APIs below. Never substitute:

- ❌ Manual "glassmorphism": `.background(.ultraThinMaterial)` / `Color.white.opacity(0.1)` + custom border/shadow, or RN `<BlurView>` used *as* glass on iOS
- ❌ Flat, opaque, hard-edged controls with no material
- ❌ RN/RN-style press feedback (`.opacity(pressed ? 0.5 : 1)`, manual `scaleEffect`/`Animated` on tap) instead of native glass button behavior
- ❌ Custom `RoundedRectangle`/`View` backgrounds that don't match system concentricity
- ❌ Reinventing blur/refraction by stacking `.blur()` + `.opacity()` layers

If you catch yourself about to write any of the above, stop and reach for the native glass primitive for that platform instead.

---

# Part A — Native SwiftUI / UIKit (iOS 26+)

## Golden Rules (from Apple's HIG)

1. **Glass belongs to the navigation/control layer, floating above content** — not the content itself. Don't apply glass to body text, list rows, or backgrounds behind bars.
2. **Recompiling with Xcode 26 already gives you most of this for free** — standard `NavigationStack`, `.toolbar`, `TabView`, `.searchable`, and sheets adopt Liquid Glass automatically. Only reach for manual `.glassEffect()` on *custom* controls.
3. **Group related glass elements** in a `GlassEffectContainer` so they blend/morph as one shape instead of separate floating blobs.
4. **Tint with meaning only** — reserve tint for real semantic state (destructive, primary, selection), not decoration.
5. **Test with Reduce Transparency, Increase Contrast, and Reduce Motion on.** If it breaks, it's decoration, not Liquid Glass.

## Component → API Map (SwiftUI)

| Component | Native API | Notes |
|---|---|---|
| Standard button | `.buttonStyle(.glass)` | default for secondary/tertiary actions |
| Primary/CTA button | `.buttonStyle(.glassProminent)` | one per screen, ideally |
| Circular icon button | `.buttonStyle(.glass or .glassProminent)` + `.buttonBorderShape(.circle)` | **preferred icon-button idiom** — not a fixed frame + raw glassEffect |
| Custom shaped control | `.glassEffect(.regular, in: shape)` | e.g. `.rect(cornerRadius:)`, `.circle`, `Capsule()` |
| Interactive glass (custom tappable) | `.glassEffect(.regular.interactive())` | for custom surfaces that respond to touch |
| **Tinted selectable glass** (pills, segmented, status chips) | `.glassEffect(.regular.tint(color).interactive(), in: shape)` | tint the **glass value itself**, chained — different from a Button's `.tint()` modifier |
| Grouped floating controls (icon clusters, FABs) | `GlassEffectContainer(spacing:) { ... }` | blends + enables morphing |
| Morph between states | `.glassEffectID(_:in:)` inside a container + matched transition | smooth shape transform |
| Nav bar / toolbar | `NavigationStack` + `.toolbar` (automatic) | don't hand-roll a bar |
| Tab bar | `TabView` (automatic) | don't hand-roll a bar |
| Search bar | `.searchable(text:)` (preferred) | see note below |
| Text input | System `TextField`/`SecureField`, wrapped in `.glassEffect(.regular, in:)` capsule/rect when custom-framed | avoid flat bordered fields |
| Sheet / popover | System `.sheet`/`.popover` (automatic) | glass chrome applied by system |

### Search bar nuance
Prefer `.searchable(text:)` — it adopts Liquid Glass automatically. A **custom `TextField` wrapped in a real `.glassEffect(.regular, in: RoundedRectangle(...))`** is acceptable when you need inline placement, a controlled placeholder color, or custom trailing controls (this is the pattern in the Halal-It reference app's search + sign-in fields). What is never acceptable is a search field faked with `.ultraThinMaterial`/opacity instead of `.glassEffect`.

## Quick Snippets (SwiftUI)

Tinted, selectable, interactive glass pill (the workhorse pattern for chips/segments):
```swift
Text(label)
    .padding(.horizontal, 14).padding(.vertical, 8)
    .glassEffect(.regular.tint(isOn ? Brand.greenSoft : .clear).interactive(), in: Capsule())
```

Circular icon button:
```swift
Button { HapticManager.shared.trigger(.lightImpact); action() } label: {
    Image(systemName: "location.fill")
}
.buttonStyle(.glassProminent)
.buttonBorderShape(.circle)
.tint(Brand.green)
```

Grouped icon cluster (morphing):
```swift
GlassEffectContainer(spacing: 24) {
    HStack(spacing: 24) {
        Image(systemName: "scribble.variable").frame(width: 72, height: 72).glassEffect()
        Image(systemName: "eraser.fill").frame(width: 72, height: 72).glassEffect()
    }
}
```

Primary / secondary buttons:
```swift
Button("Confirm") { }.buttonStyle(.glassProminent)
Button("Cancel", role: .cancel) { }.buttonStyle(.glass)
```

## Fallback / Availability (SwiftUI)
Only pre-iOS-26 targets get an `.ultraThinMaterial` fallback, and only inside an `#available(iOS 26, *)` branch. If the deployment target is iOS 26+, delete the fallback — keep no legacy styling.

---

# Part B — React Native / Expo (iOS 26+)

React Native reaches the **same** native Liquid Glass, through native modules. **You still never custom-make glass.** On iOS you use the real native views; a custom `BlurView` dock is allowed **only** as a non-iOS (Android/Web) fallback, never as the iOS path.

## Libraries (the only sanctioned glass on iOS)

| Need | Library / API | Notes |
|---|---|---|
| Tab bar / nav | `NativeTabs` from `expo-router/unstable-native-tabs` | real native Liquid Glass tab bar. `blurEffect="systemChromeMaterial"`, SF Symbol icons via `icon: { sf: '...' }`, native haptics + scroll-to-top for free |
| Any custom glass surface | `GlassView` from `expo-glass-effect` | `glassEffectStyle="regular" | "clear"`, `tintColor`, `isInteractive` |
| Grouped/merging glass | `GlassContainer` from `expo-glass-effect` | RN equivalent of `GlassEffectContainer`; pass `spacing` |
| Availability gate | `isLiquidGlassAvailable()` + `isGlassEffectAPIAvailable()` from `expo-glass-effect` | true only on iOS 26+ capable devices |
| SF Symbols | `expo-symbols` (`SymbolView`) | monochrome system symbols, not flat icon assets |
| Haptics | `expo-haptics` | see [Mandatory Haptics](#mandatory-haptics) |

Do **not** use `expo-blur` `<BlurView>` as glass on iOS. It is a fallback for platforms without native Liquid Glass only.

## The required RN patterns (as used in the Akhi-AI `mobile` + Medhive `Frontend` reference apps)

**1. Platform-split layouts — native on iOS, custom fallback elsewhere.** Use Expo's platform file extensions so iOS gets the real native tab bar and other platforms get a custom dock:
```
app/(tabs)/_layout.ios.tsx   → NativeTabs (native Liquid Glass)  ✅ iOS
app/(tabs)/_layout.tsx       → custom GlassmorphicTabBar (BlurView) — Android/Web ONLY
```
```tsx
// _layout.ios.tsx
import { NativeTabs } from 'expo-router/unstable-native-tabs';

<NativeTabs blurEffect="systemChromeMaterial" tintColor={brand}>
  <NativeTabs.Trigger name="history"
    options={{ title: t('tabs.history'), icon: { sf: 'clock' }, selectedIcon: { sf: 'clock.fill' } }} />
</NativeTabs>
```

**2. Wrap `GlassView` once, gate on availability + Reduce Transparency, fall back to a plain `View`.** Never render fake glass when native glass is unavailable — degrade to a normal opaque view:
```tsx
// LiquidGlassSurface.tsx (thin wrapper over expo-glass-effect)
const liquidGlassEnabled = useLiquidGlassEnabled(); // canUseLiquidGlass() && !reduceTransparency
if (!liquidGlassEnabled) return <View style={style}>{children}</View>;
return (
  <GlassView glassEffectStyle={glassStyle} isInteractive={interactive} tintColor={tintColor} style={style}>
    {children}
  </GlassView>
);
```
```ts
// availability + accessibility gate
export function canUseLiquidGlass() {
  if (Platform.OS !== 'ios') return false;
  try { return isLiquidGlassAvailable() && isGlassEffectAPIAvailable(); } catch { return false; }
}
// useLiquidGlassEnabled() additionally subscribes to reduceTransparencyChanged and returns false when on
```

**3. Group with `GlassContainer`** (RN's `GlassEffectContainer`):
```tsx
<GlassContainer spacing={14} style={style}>{children}</GlassContainer>
```

**4. `glassStyle`/`glassEffectStyle`:** `"regular"` for cards/panels/modals, `"clear"` for control-like chrome (buttons, pills, segmented controls). Pass `tintColor` (rgba) only for semantic state/selection, matching the SwiftUI tint rule.

## RN mapping cheat-sheet (SwiftUI → RN)

| SwiftUI | React Native / Expo |
|---|---|
| `.glassEffect(.regular, in:)` | `<GlassView glassEffectStyle="regular">` |
| `.glassEffect(.clear, ...)` | `<GlassView glassEffectStyle="clear">` |
| `.glassEffect(.regular.interactive())` | `<GlassView isInteractive>` |
| `.glassEffect(.regular.tint(c)....)` | `<GlassView tintColor="rgba(...)">` |
| `GlassEffectContainer(spacing:)` | `<GlassContainer spacing={n}>` |
| `TabView` (auto glass) | `NativeTabs` (`expo-router/unstable-native-tabs`) |
| `#available(iOS 26,*)` fallback | `useLiquidGlassEnabled()` → plain `<View>` |

---

# Mandatory Haptics

**Every touch must produce a haptic.** This is non-negotiable and applies to both platforms. Buttons, tabs, chips, toggles, card taps, list rows, long-press, swipe actions, pull-to-refresh commit, sheet dismiss — all of them.

**Intensity guide (both platforms):**
- Light impact — most taps, secondary buttons, chips, list rows
- Medium impact — primary/CTA actions, tab switches, meaningful toggles
- Heavy / rigid — significant or destructive confirmations
- Selection — picker/segment scrubbing, incremental selection changes
- Success / warning / error notification — operation results (save done, validation fail)

## React Native / Expo
Use `expo-haptics` through a shared `useHaptics()` hook and call it in every `onPress`/gesture handler:
```ts
// hooks/useHaptics.ts
import * as Haptics from 'expo-haptics';
export const useHaptics = () => ({
  light:  () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light),
  medium: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium),
  heavy:  () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy),
  selection: () => Haptics.selectionAsync(),
  success: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success),
  warning: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning),
  error:   () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error),
});
```
```tsx
const { light, success } = useHaptics();
<Pressable onPress={() => { light(); onPress(); }} />
// notifications on outcomes: success() after a completed action, error() on failure
```
> `NativeTabs` fires native tab haptics automatically — don't double-fire on tab changes.

## SwiftUI / UIKit
Prefer a central manager + a `.hapticTap()` view modifier (as in the Halal-It reference app), or SwiftUI's `.sensoryFeedback`:
```swift
Button { HapticManager.shared.trigger(.lightImpact); action() } label: { ... }

// or attach to any tappable view:
someCard.hapticTap(.selection)

// or native modifier:
.sensoryFeedback(.impact(weight: .light), trigger: isPressed)
```

---

## Review Checklist (auditing existing code)

Liquid Glass:
- [ ] Any `.ultraThinMaterial`/opacity "glass" **on iOS** (SwiftUI or RN `<BlurView>`) outside a documented non-iOS/pre-26 fallback → replace with the native glass primitive
- [ ] Any hand-rolled nav/tab/search bar → `NavigationStack`/`TabView`/`.searchable` (SwiftUI) or `NativeTabs` (RN)
- [ ] RN app rendering glass on iOS via anything other than `expo-glass-effect` / `NativeTabs` → replace
- [ ] RN glass not gated by availability + Reduce Transparency (no plain-`View` fallback) → add the gate
- [ ] Manual `scaleEffect`/`opacity`/`Animated` press hack instead of native glass button behavior → replace
- [ ] Adjacent glass elements not grouped → `GlassEffectContainer` / `GlassContainer`
- [ ] Circular icon buttons (SwiftUI) not using `.buttonBorderShape(.circle)` → fix
- [ ] Decorative-only tint on glass → remove or justify semantically

Haptics:
- [ ] **Any tappable element with no haptic** → add one (light default; medium for primary; selection for scrubbing; success/error for outcomes)
- [ ] Haptics scattered inline instead of via a shared `useHaptics()` / `HapticManager` → centralize
- [ ] Double-firing haptics on `NativeTabs` tab changes (native already fires) → remove the manual one

Accessibility:
- [ ] Tested with Reduce Transparency / Increase Contrast / Reduce Motion → still legible; RN falls back to plain views

## Resources
- `references/liquid-glass-reference.md` — deeper snippets (concentricity, custom shapes, glassEffectID morphing, sheets, toolbar nuance, point-release quirks) and links to Apple's WWDC 2025 sessions (219, 323) + HIG "Materials".
