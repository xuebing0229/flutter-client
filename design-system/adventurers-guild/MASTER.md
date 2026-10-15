# Adventurer's Guild UI Design System

> Source of truth for UI work in 冒险者公会.
> Derived from verified rules in nextlevelbuilder/ui-ux-pro-max-skill.
> Do not replace these choices with ad-hoc visual experiments.

## Product fit

- Product type: Productivity Tool / freelancer workflow tool.
- Primary style: Flat Design + Micro-interactions.
- Secondary style: Minimalism & Swiss Style + Soft UI Evolution.
- Goal: fast scanning, clear hierarchy, functional color, low visual noise.
- Existing guild/fantasy identity may remain as restrained accents, but must not reduce task readability.

## Texture modes

### Classic

- Preserve the established app surfaces and layout.
- No glass treatment.

### Frosted Glass

- Glassmorphism is allowed only where there is a real layer behind the surface:
  - mobile bottom navigation
  - mobile drawer
  - overlay / floating chrome where background content genuinely exists behind it
- Do not apply translucency to order cards, product cards, settings cards, dense reading surfaces, or data-heavy content.
- Backdrop blur target: 10–20px equivalent.
- Translucent surface opacity: roughly 70–85% in Flutter Material terms, tuned for 4.5:1 text contrast.
- Border: thin, low-contrast, semantic; no decorative diagonal shine.
- Never add fake glow, fake refraction, or decorative gradients just to make glass visible.

### Liquid Glass

- True Liquid Glass is an Apple platform material for system-aligned navigation and controls.
- Android and Windows must not fake Apple refraction/lensing.
- Android fallback: Material 3 Expressive principles — tonal elevation, semantic color, clear state layers, rounded controls, no harsh box shadows.
- Windows fallback: Fluent 2 principles — calm hierarchy, standardized corners, semantic tokens, subtle depth.
- Content surfaces remain opaque and readable.
- If Apple platform support is added later, use native platform Liquid Glass for navigation/controls only, with reduced-transparency and reduced-motion fallbacks.

## Content surfaces

- Order/product cards: opaque content layer in all texture modes.
- Settings cards: opaque content layer in all texture modes.
- Dialogs and sheets: prioritize legibility; do not simulate glass unless a real blurred backdrop is provided.
- Avoid mixing flat, skeuomorphic, and glass treatments within the same hierarchy level.

## Layout and spacing

- Use the existing 4/8dp rhythm.
- Keep section spacing in consistent tiers such as 8 / 16 / 24 / 32.
- Preserve safe-area clearance and existing bottom-navigation clearance.
- Do not change existing app information architecture as part of texture work.

## Interaction

- Touch targets: at least 48dp on Android.
- Press feedback should be visible within 80–150ms.
- State changes should not shift layout.
- Prefer Material/Flutter state layers and implicit animations for simple feedback.
- Respect reduced-motion behavior where applicable.

## Color and contrast

- Continue using the existing ColorScheme and user-selected UI theme color.
- Do not hardcode a new visual palette for texture modes.
- Normal text must remain >= 4.5:1 contrast in both light and dark mode.
- Meaningful icons / control boundaries should remain >= 3:1 against adjacent surfaces.
- Glass tint should be semantic and subtle, never the dominant content color.

## Flutter implementation

- Use ThemeData + ColorScheme + ThemeExtension for design tokens.
- Use BackdropFilter only where a meaningful backdrop exists.
- Avoid rebuilding full trees for local visual state changes.
- Use const widgets where possible.
- Use RepaintBoundary for costly animated/blurred regions if profiling shows repaint pressure.
- Do not introduce a third-party glass/refraction library unless a verified native/platform requirement cannot be met.

## Forbidden patterns

- No glass on every card.
- No fake Apple-style refraction on Android/Windows.
- No diagonal highlight gradients pretending to be optical glass.
- No low-contrast translucent content surfaces.
- No arbitrary icon-size changes, random spacing, or mixed filled/outline icon styles at the same hierarchy.
- No visual change that hides content under fixed navigation.
