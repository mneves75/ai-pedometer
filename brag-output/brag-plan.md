# AIPedometer — brag plan

## What it is
A step and workout tracker for iPhone and Apple Watch whose AI coach runs on the device
(Apple Foundation Models). One-time purchase, no subscription, no account, no ads.

- **For:** iPhone walkers who want coaching without shipping health data to a cloud.
- **Sets it apart:** the AI reads your HealthKit numbers and answers *on the phone*.
- **Most impressive true claim:** "Insights, coaching and plans from Apple Intelligence on
  supported devices, without a cloud AI service." (onboarding copy)
- **Visual hook:** the app's own mint→cyan→green progress ring counting to 7,500.
- **Real UI shown:** fresh Debug build 1.0.8 (68) on an iPhone 18 Pro simulator, demo HealthKit
  data, real on-device model output (checked against the demo data before use).
- **Tone:** `app-store` refined toward a keynote feel — dark stage, light phones, calm confidence.
- **Share line:** "A pedometer whose coach lives on your iPhone."

## Angle
"Your steps just got a coach — and it never leaves your phone." Lead with the ring (the thing
every user sees first), turn it into the product, then prove the coach with a real question and
a real on-device answer. Close on the business model, which is itself the punchline in a
subscription-fitness world: pay once.

## Identity
- Stage: near-black green-tinted `#07110C` with a soft accent glow. Light phone UI pops on it.
- Accent `#34C759` (AccentColor, light), ring gradient mint `#00C7BE` → cyan `#32ADE6` → accent.
- Type: SF Pro (system-ui), heavy weights for headlines, like the app's large titles.
- Phones: CSS iPhone frame around full-resolution simulator captures (1206×2622).

## Storyboard (21.0 s, 30 fps, 1920×1080, 120 BPM — cuts on the beat)

| # | Time | Scene | On screen | Motion | Sound |
|---|---|---|---|---|---|
| 1 | 0.0–3.0 | Hook | App ring rebuilt at stage centre fills to 75% while the count runs 0 → **7,500** / "of 10,000 steps". Headline: **"Your steps just got a coach."** | Ring draws with ease-out, number counts, headline rises in by 1.3 s | Soft pulse, pitched ticks rising with the count, riser into the cut |
| 2 | 3.0–6.5 | Reveal | Ring shrinks into the phone's own Dashboard ring (match cut). Right: app icon, **AI Pedometer**, "Steps, workouts and an AI coach that runs on your device." | Phone scales up from the ring, text staggers in | Drop: kick + chord, whoosh on the match cut |
| 3 | 6.5–12.0 | AI Coach | Phone zoomed on the chat: question typed → send → "Thinking…" → answer bubble revealed line by line. Left: **"Ask about your week."** then **"Answered on your iPhone. Not in a cloud."** Footnote: "AI features need a device with Apple Intelligence." | Push-in to the top of the screen, send tap pulse, bubble wipe | Send pop, soft shimmer while thinking, chime when the answer lands |
| 4 | 12.0–15.0 | Insights | Two phones fanned: History (Weekly Trend) and Workouts (Today's Plan). Headline: **"A weekly trend. A plan for today."** | Phones slide in from opposite sides with slight tilt | Whoosh, arpeggio |
| 5 | 15.0–18.0 | Privacy + price | Three lines, one per beat: **No account. / No ads. / No subscription.** with green check marks | Each line snaps in with a check | Three plucks rising, snare fill |
| 6 | 18.0–21.0 | Outro | Icon, **AI Pedometer**, "Pay once. Every feature included.", "iPhone · Apple Watch · Widgets", `mneves75.github.io/ai-pedometer` | Icon pops, lines settle, glow breathes | Final chord, tail |

Durations: 3.0 + 3.5 + 5.5 + 3.0 + 3.0 + 3.0 = 21.0 s.

## Truth checks
- Coach answer used: "65,500 steps… 9,357 steps per day… hitting the goal on 3 days" — matches the
  demo week (6,500+8,000+9,500+11,000+12,500+10,500+7,500; goal met Wed–Fri).
- Rejected answers: "How did I do this week?" (said 5% ≈ 4,700 steps; it is ≈ 470) and
  "What's my best day for walking?" (called Thursday Sep 24, 2026 a Saturday).
- No "Available on the App Store" claim: 1.0.8 is still in review. No price in a currency-neutral
  English cut; "pay once / no subscription" is the store listing's own claim.
- Active workout could not start in the simulator ("Unable to start workout"), so it is not shown.

## Vertical cut (1080×1920)
`brag-vertical.mp4` reuses the same timeline, captures, score and poster time (11.0 s); only the
layout changes (`work/index-v.html`): hook ring over a two-line headline, phones centred with copy
above or below, the coach phone pushed in under "Ask about your week.", and the privacy lines above
the Welcome screen. Render with `PAGE=index-v.html VW=1080 VH=1920 node render.mjs …`.

## Music cue guidance
No bundled track; score is synthesized to the cut: C major, 120 BPM, beat = 0.5 s. Downbeats at
3.0 (drop), 6.5, 12.0, 15.0, 18.0 (final chord). Timing guidance only; readability wins.
