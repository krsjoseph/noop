# NOOP — Design Identity

The design fundamentals for NOOP (Strand). This is the source of truth for *how the app looks
and why*. It documents the locked component system in `Packages/StrandDesign`, the principles
that govern composition, and the rules every screen follows. When a screen and this doc disagree,
fix the screen.

> **One-line identity:** an instrument-grade health dashboard — calm, legible, and honest —
> rendered as **Liquid Glass over a living day-cycle scene**, set in **SF Rounded**, where colour
> belongs to the *data*, not the chrome.

---

## 1. Principles (the "why")

1. **Glance first, depth on demand.** Every screen answers its core question above the fold
   (Today → "how am I / should I push"; Sleep → "how did I sleep"; Trends → "which way am I
   heading"). Detail and controls disclose progressively below.
2. **Group by intent, not by data type.** Cards cluster around a question the user is asking
   (verdict → why → activity → metrics), not around where a number came from.
3. **One home per metric.** A value appears *once*, in its strongest context. Charge/Effort/Rest
   live as the hero rings; HRV/RHR/Respiratory live in the Readiness "why"; the metrics grid carries
   only what has no other home. Editors still expose everything — de-dupe changes *defaults*, never
   reachability.
4. **Honest empty states.** Never fabricate a number. A metric with no data shows `—` *with a
   caption that says why*, or the section hides entirely. "Calibrating" is stated once, not four
   times. Provenance is always truthful (`Whoop` vs `On-device` badges).
5. **Colour is data, chrome is neutral.** Card surfaces are uniform neutral glass. Identity and
   meaning come from the *content* — ring colours, sparklines, status words — never from tinting
   every card a different hue.
6. **Accessible by construction.** Severity is carried by glyph **and** colour (never colour
   alone). Type scales with Dynamic Type. Numeric values use tabular digits so they never reflow.
   VoiceOver reads one combined label per card.
7. **Performance is a feature.** Heavy screens never observe `LiveState` directly (a ~1 Hz strap
   tick would re-render the world). Live values live in small leaf subviews; derivations are
   memoized; long lists are lazy; glass composites once per cluster.

---

## 2. Surfaces — Liquid Glass

The signature surface. On **iOS 26+** every dashboard card is real Liquid Glass
(`.glassEffect(.regular, in:)`) floating over the day-cycle scene, refracting it.

- **The one surface API.** `NoopCard` and `StrandCard` are the only card containers; everything
  (`StatTile`, `ChartCard`, `InsightCard`, `SettingsSection`) is built on them. Do not invent
  ad-hoc card backgrounds.
- **How glass turns on.** A screen sets the scoped environment flag `\.noopGlassSurface` on its
  content (see `LiquidGlass.swift`); `NoopCard`/`StrandCard` read it and switch from the opaque
  `FrostedCardSurface` to `liquidGlassCard(...)`. Scoped per-subtree, so non-glass screens are
  untouched.
- **Uniform & neutral.** The glass path **ignores the per-domain `tint`** — every glass card is the
  same `.regular` glass, adapting light/dark to whatever's behind it. No rose/amber/green card
  washes. (The frosted fallback keeps its tint, since it isn't translucent.)
- **Glass needs something to refract.** Glass is enabled only when the day-cycle scene is on
  (`SceneBackgroundPrefs.enabledKey`). With the scene off, or below iOS 26, or on macOS, cards fall
  back to the opaque `FrostedCardSurface` — legibility is never sacrificed for the effect.
- **Group, don't scatter.** Use `GlassClusterContainer` (wraps `GlassEffectContainer`) for a tight
  visual unit; apply glass per-card for long scrolling lists. Never wrap a whole lazy column in one
  container (it would defeat laziness).
- **The scene** (`SceneScreenBackground`) is a full-bleed day-cycle backdrop confined to the
  header/hero band; it fades out above the cards, so lower cards sit on the canvas and read as
  neutral dark glass. Sleep is the exception — it keeps its own `.timeOfDayBackground(.night)` hero
  for a deliberate night mood and does not add the day-cycle scene.

`NoopMetrics.cardRadius = 20`, continuous corners, everywhere.

---

## 3. Typography — SF Rounded

The house face is **SF Rounded**, app-wide (`StrandFont` + `.fontDesign(.rounded)` at both app
roots). Friendly, legible, the same numerals Apple's fitness rings use. **SF Mono** is reserved for
raw/log/diagnostic views.

| Role | Size / Weight | Notes |
|------|---------------|-------|
| `display(_:)` | 64–80 / Bold | gauge score numerals, tight tracking, tabular |
| `rounded(_:)` / `number(_:)` | any / Bold·Semibold | score & tile values, tabular |
| `title1` | 28 / Bold | screen title |
| `title2` | 22 / Semibold | section title |
| `headline` | 17 / Semibold | card headline |
| `body` | 15 / Regular | prose |
| `subhead` | 13 | secondary prose |
| `caption` / `captionNumber` | 12 | captions, chips |
| `footnote` | 11 | tertiary detail |
| `overline` | 11 / Bold, +1.4 tracking | ALL-CAPS labels (`strandOverline()`) |
| `mono` | 13, monospaced | logs/raw only |

- **Tabular digits** on every numeric role (`.monospacedDigit()`) so live values don't reflow.
- **Dynamic Type:** prose/label roles scale (custom sizes scaled via `UIFontMetrics`); fixed-geometry
  numerals (`display`/`number`/`rounded`) don't, by design. The app caps at
  `DynamicTypeSize.accessibility1` so gauges/tiles stay legible.
- **Overline** is the one ALL-CAPS device — sparing, wide-tracked, secondary colour.

---

## 4. Colour — `StrandPalette`

Light + dark, with a "Titanium" (default) and "Classic" chart style. **Chrome is monochrome;
colour is reserved for data.**

**Surfaces & text**
- `surfaceBase` — canvas (`#121518` dark / `#F2F2F7` light)
- `surfaceRaised` — opaque card fill (frosted fallback)
- `textPrimary` / `textSecondary` / `textTertiary` — the only text tiers
- `hairline` / `hairlineStrong` — 1px borders/dividers

**Accent (chrome anchor)** — `accent` is the WHOOP-style action blue (`#60A0E0` dark). Links,
selection, focus, neutral CTAs. **No gold** (retired 2026-06-22).

**Domain "colour worlds" (data only)**
- **Charge / recovery** → green (`chargeColor`), value ramp red→orange→yellow→green
  (`recovery000…recovery100`)
- **Effort / strain** → blue (`effortColor`)
- **Rest / sleep** → blue-indigo (`restColor`), sleep stage colours
- **Vitals** → `metricPurple` (HRV), `metricRose` (RHR), `metricCyan` (SpO₂), `metricAmber` (temp)
- **Status** → `statusPositive` / `statusWarning` / `statusCritical`, always paired with a glyph

Use a domain colour for the *line, ring, sparkline, or status word* — never to wash a card.

---

## 5. Spacing & layout — `NoopMetrics`

One 4-pt scale is the single source of truth. Reach for tokens, not literals.

- `space1…space10` = 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40
- `gap = 12` (between cards) · `sectionGap`/`sectionSpacing` = 22–24 (between sections)
- `cardPadding = 16` · `cardRadius = 20` · `pillRadius = 999`
- `screenHPadding = 20` (`.screenPadding()`) · `tileHeight = 96` · `chartHeight = 220`
- `tabBarClearance = 76` — bottom scroll room so the last card clears the floating tab bar
- Screens compose through **`ScreenScaffold`** (title + scroll + optional `topBackground` scene +
  pull-to-refresh). iPad caps the readable column to ~700pt and centres it.

---

## 6. Components (the locked kit)

Compose screens from these only:

- **`SectionHeader(title, overline:, trailing:)`** — overline + title, optional trailing label.
- **`StatTile`** — fixed-height metric tile: label, big value, caption, sparkline, optional inline
  accessory (ⓘ). Grid via `GridItem(.adaptive(minimum: 150))`.
- **`ChartCard`** — header + fixed-height chart + optional `ChartFooter` (label/value columns).
- **`InsightCard`** — category overline + coloured status headline + detail prose.
- **`SegmentedPillControl`** — the *one* range/segmented control.
- **`SourceBadge`** — provenance pill (`Whoop` / `Apple Health` / `On-device`).
- **`ScoreStatePill`** — `.solid` / `.calibrating` status chip.
- **Gauges & charts** — `GlowRing` (Today rings), `BevelGauge` (Sleep hero), `PipBar`, `Sparkline`,
  `TrendChart`, `YearHeatStrip`, `OverviewHRChart`.
- **`NoopButton` / Noop button styles** — `.noopPrimary` / `.secondary` / `.ghost`.
- **Empty/pending** — `ComingSoon`, `DataPendingNote`, `SyncingHistoryNote`.

---

## 7. Motion

- **`staggeredAppear(index:)`** — sections fade + rise in sequence on first appear; Reduce-Motion
  safe.
- **`StrandMotion.interactive`** — the standard spring for state changes; `CountUpText` ticks
  numerals up.
- Gauges/rings animate their fill on appear and when the value changes; never on every body pass.
- Motion is purposeful — it explains a change or guides the eye, never decoration for its own sake.

---

## 8. Performance rules (non-negotiable)

- **Never observe `LiveState` in a heavy screen body.** A connected strap publishes ~1 Hz; an
  `@EnvironmentObject live` re-renders the whole screen on every tick. Put live values in small leaf
  subviews that own their own `live`.
- **Memoize expensive derivations** keyed on a cheap data fingerprint (see Today's `derived`,
  Sleep's `model`/`dataKey`, Trends' `resolve`).
- **Lazy columns** (`ScreenScaffold(lazy: true)`) for long trailing `ForEach`.
- **Flatten static backdrops** with `.drawingGroup()` (the scene composites once).
- **Glass composites once per cluster** — don't nest glass containers or apply glass per-glyph.

---

## 9. Cross-platform

- Shared SwiftUI across iOS + macOS; branch with `#if os(...)`.
- **Glass is iOS-26-only.** macOS and iOS < 26 use the opaque `FrostedCardSurface` (with macOS hover
  chrome). Same call sites, gated by `liquidGlassCard`'s internal availability check.
- iOS shell is `RootTabView` (Today / Trends / Sleep / More) with the **native iOS 26 Liquid Glass
  tab bar**; macOS is a `NavigationSplitView` (`RootView`). Don't restyle the native tab bar.
- Persisted identifiers (metric/card layout ids) are kept byte-identical to the Android app so
  backup/restore reads the same on either OS.

---

## 10. Voice

Plain, calm, second-person. Short verdict headlines ("Primed to push"), honest captions, never
hype. Explain the *why* and the *next step*; never a bare number without a state. Copy authored in
en-US; everything user-facing is a `LocalizedStringKey`.
