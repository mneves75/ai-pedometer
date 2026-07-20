# 014 — Repair adaptive navigation and accessibility semantics

**Written against commit** `cff33ec`. Category: SwiftUI / accessibility / UX.
Confidence: HIGH. Impact: MED. Effort: L. Fix risk: MED.

**Status:** DONE* for 0.94 (50).

## Goal

Keep navigation selection valid across compact/regular layouts and make primary metrics, weekly
history, chat scrolling, freshness copy, and actionable badge feedback behave correctly.

## Constraints

- Preserve the current phone tab and iPad sidebar information architecture.
- Respect Reduce Motion, Dynamic Type, VoiceOver, pt-BR localization, and existing Liquid Glass
  conventions.
- Do not introduce a custom navigation framework or broad design-system rewrite.

## Implementation plan

1. Add transition tests for every selection when changing compact ↔ regular size class. Map `.more`
   and nested tablet-only destinations explicitly to valid selections.
2. Replace gesture-derived chat pinning with bottom-position visibility and thresholded updates;
   verify manual return to bottom resumes streamed-token following.
3. Preserve per-day VoiceOver semantics in the weekly chart.
4. Convert primary numeric readouts to bounded Dynamic Type scaling and verify representative
   normal and AX sizes without clipping.
5. Add a minute-level heart-rate freshness invalidation limited to the affected readout.
6. Mark all actionable badge glass cards interactive, including locked badge detail buttons.
7. Add/update localized copy and accessibility identifiers only where the behavior requires them.

## Done when

- Navigation transition and chat-pinning regressions pass.
- VoiceOver can inspect each weekly bar, primary values scale at accessibility sizes, and the
  heart-rate stale state changes without unrelated model updates.
- All actionable badges have consistent iOS 26 interaction feedback.
- Targeted tests pass and simulator evidence covers phone/iPad layout plus normal/AX text sizes.

`DONE*`: navigation state, chat pinning, chart semantics, freshness, badge interaction, and bounded
scaling are implemented and covered. The reusable QA matrix still tracks nested More routes,
pt-BR, iPad, VoiceOver, and representative AX sizes as observational release checks.
