# QA sweep log — every game mode and feature screen, per platform

Driven by `tools/qa-sweep.sh <ios|ipad|tvos> [outdir]`, which launches the app once per
case with the `DebugHooks` env family, screenshots it, and reports a crash when the pid
simctl handed back is gone. ~47 captures per platform.

This is a **playability + completeness** pass, not the store capture
(`tools/capture-screenshots.sh`) — it draws real questions rather than the screened set,
because the point is to catch a mode that renders or plays wrong.

---

## Round 1 — iPhone 17 Pro (iOS 26 sim), 2026-07-30, build 1.6.69

**Swept:** 15 modes mid-question · 9 modes at reveal · 3 end-of-game · 20 feature screens.

### Findings

| # | Severity | Finding | Status |
|---|---|---|---|
| Q1 | **Bug** | **Match-Up gave away 2 of 4 pairs.** The parenthetical added to disambiguate a WORK title also names its composer — the value being matched to. "Magnificat (Bach)" → Johann Sebastian Bach; "Symphony No. 3 (Górecki)" → Henryk Górecki. 18 pairs across the set. | **Fixed** — `tools/corpus/fix_match_giveaways.py`, all 3 shipping mirrors |
| Q2 | Judgement | 44 matching pairs where key and value are the **same name** (San Marino → San Marino, Monaco → Monaco). Factually true, and knowing city-states share the name IS knowledge — but in a 4-pair grid it is a free point *and* removes a distractor. | **Owner call** — not changed |
| Q3 | None | 25 pairs with partial overlap (Tunisia → Tunis, El Salvador → San Salvador, Saudi Arabia → Saudi riyal). Still require real knowledge. | No action |
| Q4 | Content | "In what year did William Penn die?" is filed **ARTS & LIT**; Penn was a colonial administrator. Corpus categorisation, not a rendering fault. | Noted |
| Q5 | Cosmetic | Enumerate prompts have no terminal punctuation ("…as you can"). | Noted |
| Q6 | Cosmetic | "Which of these is the most populous?" omits the noun (city). Inferable but loose. | Noted |

| Q7 | **Bug** | **Ordering and Matching gave NO reveal feedback.** Both are partial-credit modes, yet the reveal re-rendered the player's own grid unmarked — the only way to learn what you got wrong was to read the explanation and diff it by eye. Every MCQ mode colours correct/incorrect. Verified the scoring itself was right (ordering is inversion-based: 3 of 6 inversions → 40×0.5 = +20). | **Fixed (iOS)** — each row now marks ✓ / the position it should have had, mint/coral tinted |
| Q8 | Regression I caused | Tinting the Matching rows turned them muddy brown with grey text: they are `Button`s with `.disabled(!live)`, and SwiftUI's disabled dimming compounds any fill. Now rendered as a plain view at reveal. | Fixed |
| Q9 | **Bug** | macOS and tvOS had the **same missing ordering/matching reveal feedback** (separate game views). | **Fixed** — tvOS verified on the Apple TV sim (green ✓ / dark-red "→ N", legible at ten feet); macOS code-mirrored + builds, **not visually verified this round** |
| Q10 | Harness | The tvOS sim showed the **Game Center sign-in overlay** across the first capture attempt. `TIDBITS_NO_GAMECENTER=1` suppresses it — needed for every tvOS run. | Fixed in the run recipe |

### Harness defects found in the harness itself
- `launchctl list` does **not** reliably list simulator apps — it reported all 6 of
  home/profile/ladder/daily/multiplayer/weakspot as dead when every one rendered
  correctly. Now checks the pid `simctl launch` returns.
- A 12s settle was too short for a 10-question autopilot run, so `results-*` captured
  mid-game instead of the results screen. Raised to 30s.

### Verified working (rendered correctly, no crash)
Classic · Time Attack · Survival · Stake · Sweep · Picture Round (image loads, aspect-fit)
· This or That · Closest Call (slider + range + Lock In) · Ordering · Match-Up · Type
Answer · Odd One Out · Ladder · Enumerate (0/8 + Done) · Daily · Home · Records · Create ·
Settings · Profile · Customize · Daily archive · Night setup · Pass & Play · Versus ·
Multiplayer · Paywall · Club hub · Story archive · Atlas · Link Wall · Expedition map ·
Marathon · Weak Spot · Mix

---

## Still to do

- [ ] Round 1 review is **partial**: ~12 of 47 captures examined in depth; the rest are
      captured and awaiting review.
- [x] Re-ran `results-*` at 30s — Classic (FLAWLESS, 2,825, 10/10, spoiler-free grid,
      streak, "Tough ones you nailed" + the reflection prompt) and Stake (15 on chips)
      both correct. Score SCALES differ hugely between modes (2,825 vs 15) and are
      presented identically; Records separates by mode, so noted not filed.
- [x] Mirrored the Q7 reveal-feedback fix to macOS + tvOS (Q9).
- [ ] **Visually verify the macOS reveal** — code-mirrored and building, but this round only
      confirmed iOS and tvOS on simulators. macOS needs a real run.
- [ ] iPad sweep (`tools/qa-sweep.sh ipad`) — layout at a different size class.
- [ ] Full tvOS sweep (`tools/qa-sweep.sh tvos`, with TIDBITS_NO_GAMECENTER=1) — focus
      engine, the 10-foot ramp, self-marking modes. Only ordering/matching seen so far.
- [ ] Android + Windows equivalents.
