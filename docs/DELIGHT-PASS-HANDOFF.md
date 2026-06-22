# Delight Pass — Status & Economic Strategy (handoff)

> Survives compaction. Where the LLM "make every question delightful" pass stands,
> and how to finish it WITHOUT burning Opus 4.8 tokens. Part of Decision 032/033.

## What "delight" is

Rewrite each robotic auto-generated corpus clue ("Who is this — 'American actress
(born 1958)'?") into a hand-written-feeling trivia question, GROUNDED strictly in
that article's Wikipedia summary (no invented facts), never naming the answer,
answerable with the existing type-matched options. Pipeline:
`build_corpus.py` (robotic) → `score_questions.py --apply` (cut mundane) →
batch files of {id, answer, options, summary} → LLM rewrites → `apply_delight.py`
(leak-guarded merge) → regenerate `gen_*.py` → build → ship.

## Current state (2026-06-22, ~9am MT)

- **Subjects:** 19,921 kept (`corpus_source.sqlite` `subject`): 11,906 Vital-Articles
  (`va_class='B/GA/FA/A'`) + 8,015 top-Qrank expansion (`va_class='qrank'`). Enriched
  (facts/relations/gender/P31/aliases/image), prose fetched (~19,887 rows),
  relations resolved.
- **corpus.json (working tree) = ROBOTIC, 21,005 rows** (after `build_corpus.py` over
  all subjects + `score_questions.py --apply` cut 2,589). NOT yet committed — the
  shipped version (`d949a14`, v1.3.0) is the OLD 11,054-row corpus with 6,861
  delightful + the Foundation Models Create feature.
- **Delight rewrites done (out files persist in /tmp):**
  - `/tmp/delight/out_*.json` — wave 1, describe originals (125 batches) ✅
  - `/tmp/delight2/out_*.json` — wave 2, cloze+holdout originals (132) ✅
  - `/tmp/delight3/out_*.json` — wave 3, **expansion** describe/cloze (207 batches,
    **186 done / 21 failed** at b186–b206 — session limit). ~9,769 original + ~7,440
    expansion ids rewritten.
- The 21 missing wave-3 batches are `/tmp/delight3/in_186.json`–`in_206.json`.

## IMMEDIATE finish (LOCAL, no LLM — do this first)

```
cd tools/corpus/sources
python3 apply_delight.py          # merges /tmp/delight{,2,3}/out_*.json, leak-guarded
cd .. && for g in gen_typeanswer gen_picture gen_closest gen_thisorthat gen_order \
         gen_match gen_oddoneout gen_enumerate; do python3 $g.py; done
# then build all 4 platforms + commit + ship  (corpus ~2x, ~17k delightful)
```
This bakes the delight into corpus.json (durable) and ships the doubled corpus.
Only the 21 expansion batches remain robotic until the cheap pass below.

## THE ECONOMIC STRATEGY (the ask: stop burning Opus)

The rewrite is **grounded paraphrasing, not hard reasoning** — it does NOT need
Opus 4.8. Levers, biggest first:

1. **Switch the model to Haiku 4.5** (`agent(prompt, {model:'haiku', effort:'low'})`
   in the workflow). ~10–20× cheaper than Opus; quality is ample for grounded
   rewriting. **Validate a 1-batch Haiku sample vs the Opus output before the full
   run.** This alone fixes the economics.
2. **Bigger batches** (80–100 items/agent, not 40) → fewer agents → less repeated
   instruction/system overhead.
3. **Even cheaper (no agent framework):** a standalone Python script calling the
   Anthropic API directly with Haiku (needs `ANTHROPIC_API_KEY` on the build box).
   No per-agent system-prompt/tool overhead; pure Haiku completion per batch. Most
   economical if a key is available; the user pays Haiku rates directly.
4. **Do less work:** delight ONE question per subject (describe) and leave cloze as
   the natural lead-sentence (already decent) — halves volume. And/or **tier by
   Qrank**: delight the top-N most-played subjects first; long tail later/cheaper.
5. **Runtime on-device (Apple only):** Foundation Models can delight bundled
   questions on-device at runtime for FREE on Apple-Intelligence devices (cache the
   result) — zero build-time cost, but only iOS (now) covers it, so it complements
   (doesn't replace) the cheap pre-bake for cross-platform consistency.

**Recommendation:** finish the 21 batches + all FUTURE expansion delight with
**Haiku at batch-80** (lever 1+2), after a quick sample validation. Reserve Opus
for genuinely hard work. Keep grounding + leak-guard unchanged.

## Resume the remaining 21 (when chosen): edit the workflow script's agent() call to
add `{model:'haiku', effort:'low'}`, rebuild in-files at batch-80 for the 21, run.
Script: `workflows/scripts/delight-rewrite-3-wf_d2a5f44f-874.js` (resumeFromRunId
`wf_d2a5f44f-874` reuses the 186 cached).
