# Create-Feature Question Generation Playbook

> How to build a robust, cross-platform "type a topic → get good questions"
> writer whose output is comparable to the pre-made corpus. Written after the
> on-device-AI-only attempt produced questions that were "either entirely
> obvious or entirely nonsensical."
>
> **Thesis (opinionated, up front): stop asking the on-device model to KNOW
> facts. It can't, and that is the whole bug. Make the bundled corpus the fact
> oracle (retrieve real, verified facts for the topic), and let the LLM do only
> what it is actually good at on-device — rephrasing a known fact into a natural
> stem and smoothing distractor wording — behind the SAME 9-gate validation
> funnel the offline pipeline already uses. That design ("grounded generation")
> is the only one that yields good questions on ANY device, because the
> load-bearing step (retrieval + typed-sibling distractors + gates) needs no LLM
> at all. The LLM is a garnish, not the kitchen.**

Companion docs: `docs/QUESTION-QUALITY.md` (the binding 9-gate rulebook this
must satisfy), `docs/CORPUS-SOURCE-PIPELINE.md`, and the vendored
`wikipedia-fact-extraction` skill (the offline fact-triple method). Skill
gate before any build: `learning-orientation-design` +
`feature-shipping-discipline`.

---

## 0. Why the naive approach failed (name the failure precisely)

The Create feature asked an on-device model to *generate trivia from its own
weights*. Two structural reasons this can only produce "obvious or nonsensical":

1. **The model has almost no reliable world knowledge.** Apple states its
   on-device model "is not designed for world knowledge or advanced reasoning"
   — it is tuned for *summarization, extraction, classification, and rewriting*
   over text you give it
   ([Apple ML Research — Introducing Apple's Foundation Models](https://machinelearning.apple.com/research/introducing-apple-foundation-models)).
   A ~3B, 2-bit-quantized model asked "give me a fact about Mongolia" either
   emits the single most common fact (obvious) or invents one (nonsense /
   hallucination). Same for Gemini Nano (~3-4B class).
2. **Guided generation guarantees STRUCTURE, not TRUTH.** `@Generable` /
   constrained decoding force valid JSON with four options and an index — so the
   output *looks* like a question and always parses — which masks that the
   *content* is unverified. A well-formed false question is worse than a parse
   error.

The offline corpus is good precisely because it *never lets the model author
facts*: facts come from Wikidata triples, infobox extraction, and article leads,
and 9 gates reject anything unverifiable (`QUESTION-QUALITY.md` §D). The Create
feature must inherit that discipline, not bypass it.

---

## 1. Apple on-device — Foundation Models framework (iOS 26 / iPadOS 26 / macOS 26; NOT tvOS)

Official API surface (verified against
[developer.apple.com/documentation/FoundationModels](https://developer.apple.com/documentation/FoundationModels)):

- **`SystemLanguageModel`** — the model handle + availability gate. Check
  `SystemLanguageModel.default.availability` before every use. Cases:
  `.available`; `.unavailable(.deviceNotEligible)` (permanent — hide the
  feature, don't nag); `.unavailable(.appleIntelligenceNotEnabled)` (user
  setting — a one-time prompt is fair); `.unavailable(.modelNotReady)`
  (downloading/temporary — retry silently)
  ([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)).
- **`LanguageModelSession`** — the conversation object. `respond(to:)` for
  text, `respond(to:generating:)` for a `@Generable` type, plus streaming
  variants. One request at a time per session; supports `instructions:` (system
  prompt) and multi-turn state.
- **`@Generable`** — macro on a struct/enum; compiles a `GenerationSchema` the
  runtime enforces via **constrained decoding** (guaranteed-parseable output).
- **`@Guide`** — per-property natural-language description + constraints
  (regex, ranges, `.anyOf`, counts) that further constrain decoding.
- **Tool calling** (`Tool` protocol) — the model can call *your* Swift function
  mid-generation. **This is the hook that makes grounded generation clean: a
  `CorpusLookupTool` returns real facts so the model rephrases instead of
  recalls.**
- **Model specs:** ~3B parameters, on-device, 2-bit QAT + KV-cache sharing
  ([Apple ML Research](https://machinelearning.apple.com/research/introducing-apple-foundation-models)).
  **Context window = 4096 tokens** total (instructions + prompts + responses);
  iOS 26.4 adds `SystemLanguageModel.contextSize` and `tokenCount(for:)`
  ([TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)).
  4096 is small — you cannot dump the corpus in; you retrieve a handful of facts
  and pass only those.
- **Availability reality:** requires an Apple-Intelligence-eligible device
  (A17 Pro / M-series class) with the feature enabled. **tvOS has no Foundation
  Models framework** — Apple TV must use the no-LLM baseline (§4/§6).

Verdict: excellent *rephraser and distractor-smoother* for the eligible iPhone/
iPad slice; useless (and dangerous) as a *fact source*.

---

## 2. Android on-device — narrow, high-end only

Two distinct stacks, both effectively unavailable on the min-spec fleet:

**A) ML Kit GenAI APIs / Gemini Nano via AICore** — the "blessed" path.
- Features: Prompt (freeform), Summarization, Proofreading, Rewriting, Image
  Description, Speech Recognition
  ([ML Kit GenAI overview](https://developers.google.com/ml-kit/genai)).
- Built on **AICore** system service; runs on optimized Tensor / Snapdragon /
  Dimensity SoCs
  ([Android Developers Blog, 2025-05](https://android-developers.googleblog.com/2025/05/on-device-gen-ai-apis-ml-kit-gemini-nano.html)).
- **Device coverage is narrow.** Prompt API: `nano-v2` on Pixel 9 series,
  Galaxy Z Fold7, select OnePlus/OPPO/Xiaomi/vivo; `nano-v3` on Pixel 10+ and
  newer Samsung/OPPO/OnePlus. Feature APIs cover a similar recent-flagship set
  ([Gemini Nano device support](https://developer.android.com/ai/gemini-nano),
  [ML Kit GenAI](https://developers.google.com/ml-kit/genai)). GenAI inference
  is also gated to the **foreground** app.

**B) MediaPipe / Google AI Edge LLM Inference** — bring-your-own small model.
- Runs Gemma-3 1B (4-bit), Gemma-2 2B, Phi-2, etc.
  ([LLM Inference for Android](https://developers.google.com/edge/mediapipe/solutions/genai/llm_inference/android)).
- **"The model is too large to be bundled in an APK"** — you host it and
  download at first run (hundreds of MB). Optimized for "high-end devices such
  as Pixel 8 and Samsung S23 or later"; "does not reliably support device
  emulators." No LoRA without GPU backend.

**Realistic story for `minSdk = 29` / `targetSdk = 36`:** the overwhelming
majority of the addressable fleet has **no usable on-device LLM.** Neither stack
degrades gracefully by itself — ML Kit simply reports unsupported; MediaPipe
demands a big download and a flagship. **Therefore Android's Create feature must
be fully functional with zero LLM (the corpus-grounded baseline, §4/§6), and
treat Gemini Nano / MediaPipe as an opportunistic enhancement on detected
flagships only** — same shape as iOS's availability gate. (Consistent with the
`android-production-gotchas` "assume the low-spec device" posture.)

---

## 3. Web — there is no reliable on-device LLM baseline

- **Chrome built-in Prompt API** (`LanguageModel` / `window.LanguageModel`,
  Gemini Nano): desktop Chrome/Edge only (Win10+, macOS 13+, Linux, ChromeOS on
  Chromebook Plus). **Chrome for Android and iOS are explicitly NOT supported**,
  and Safari/Firefox don't implement it
  ([The Prompt API — Chrome for Developers](https://developer.chrome.com/docs/ai/prompt-api)).
  `LanguageModel.availability()` returns `available|downloadable|downloading|unavailable`.
- **WebLLM (WebGPU)**: real, ~80% native throughput, but a multi-hundred-MB to
  multi-GB model download, ~8B quantized ceiling, and WebGPU coverage is
  "~65% of users," excluding many mobile browsers
  ([WebLLM](https://github.com/mlc-ai/web-llm),
  [WebGPU/WebLLM 2026 status](https://webllm.mlc.ai/)).

**Verdict:** the web has NO dependable on-device model, especially on mobile
Safari (a primary target). The web Create feature must run entirely on the
corpus-grounded, no-LLM path. If a shared-backend generation service ever
exists, the web can *optionally* call it — but the shippable web baseline is
retrieval + templates, identical to tvOS.

---

## 4. The key architectural question: generation vs. retrieval vs. hybrid

Three candidate designs:

| Design | Fact source | Works with no LLM? | Hallucination risk | Cross-platform |
|---|---|---|---|---|
| **A. Pure generation** | LLM weights | No | **High** (the current bug) | iPhone/Pixel-flagship only |
| **B. Retrieval / recombination** | Bundled corpus only | **Yes** | **~Zero** | **All 4 platforms** |
| **C. Grounded hybrid** | Corpus facts; LLM only rephrases | Yes (LLM optional) | Low (gated) | All 4, LLM as enhancement |

**Choose B as the universal baseline and C as the enhancement.** Rationale:

- The failure mode is hallucination, and the asset you already own is a
  high-quality, gated, structured fact store. Grounding *removes the failure
  mode by construction*, exactly as the Wikidata/fact paths do offline
  (`QUESTION-QUALITY.md` §D: "gates hold by construction").
- Retrieval + templating requires **no model**, so the feature works on every
  device on day one — tvOS, mobile Safari, a 2019 Android phone — which is the
  parity mandate.
- The on-device LLM's *actual* strength (rephrasing given text, per Apple's own
  positioning) is precisely the safe, optional layer on top.

### The corpus already contains everything retrieval needs

`tools/corpus/corpus_source.sqlite` holds the structured plane the shipped
`corpus.sqlite` currently flattens away:

```
subject(qid, title, va_class, qrank, category, sitelinks, p31, p106, image, aliases, gender)
fact(qid, prop, label, value, unit, kind)           -- typed numeric/date facts
relation(qid, prop, label, target_qid, target_label) -- director_of, capital_of, ...
prose(qid, title, lead, description)                 -- article lead + short desc
related(title, neighbour, n)                         -- co-occurrence neighbours
```

`p31`/`p106`/`va_class` give **typed-sibling distractor pools for free**;
`related` gives topic expansion; `fact`/`relation` give verifiable single-valued
triples. To ship Create, ship a **trimmed, indexed copy of this structured plane
in the app bundle** (or serve it as a data-plane the clients query), not just
the denormalized questions table. This is the single most important
infrastructure change — see `shared-data-plane-contract`.

### Grounded-generation flow (design C, LLM present)

```
topic string
  └─► RETRIEVE (no LLM): FTS/alias match topic → subject rows; expand via
       related[]; rank by qrank/sitelinks (fame floor). Pull their facts,
       relations, prose leads.
  └─► SELECT a single-valued, verifiable fact (a relation triple or a fact row)
       — the ANSWER is a corpus value, never model-authored.
  └─► DISTRACTORS (no LLM): typed siblings (same p31/p106/va_class), ranked by
       description-word overlap + length proximity; numeric/date via ratio/era
       bands (QUESTION-QUALITY §H/§I). Never model-authored.
  └─► PHRASE (LLM, optional): @Generable{stem:String} — "rewrite this KNOWN
       fact as a natural trivia stem; do not add facts; blank the answer." The
       model sees the fact; it does not supply it.
  └─► VALIDATION GATE (no LLM, ALWAYS runs — even on LLM output):
       answer-leak/redact check, distractor-correctness (no distractor also
       validates), single-answer, length band, no-nonsense/empty-slot filter.
       Reject → fall back to the template phrasing from design B.
```

The gate is the safety net that makes the optional LLM *safe*: if Foundation
Models emits garbage, the deterministic template output ships instead, and the
user never sees the difference in quality floor.

---

## 5. Distractor generation specifically

The literature converges on **same-type, same-category, plausible-but-wrong**,
and warns that generative models "are still susceptible to generating nonsense
distractors — duplicate correct answers, obviously incorrect options"
([Distractor Generation survey, arXiv 2402.01512](https://arxiv.org/html/2402.01512v2);
[KG-integrated DG, arXiv 2406.13578](https://arxiv.org/abs/2406.13578);
[DiVERT, arXiv 2406.19356](https://arxiv.org/pdf/2406.19356)). That warning is
exactly why distractors must come from the corpus, not the model.

On-device / corpus-sibling recipe (already half-built offline, see
`QUESTION-QUALITY.md` §H/§I — mirror it in the Create runtime):

- **Entities:** same `p31`/`p106` siblings from the retrieved topic
  neighbourhood, ranked by `sitelinks`/`qrank` (fame) and description-word
  overlap; prefer Wikidata **P1889 "different from"** / "not to be confused
  with" edges as the most diagnostic confusables. A different country's capital
  is *definitionally* wrong for this country — correctness by construction.
- **Numbers:** multiplicative ratio bands straddling the true value
  (e.g. 0.55/1.35/1.9×), consistent format, never all on one side, never the
  exact median.
- **Dates:** era-tiered offsets (modern ±1-5y, ancient ±10-100y), decade-consistent.
- **LLM's only role here (optional):** smooth grammatical agreement / surface
  form of already-chosen distractors — never *pick* them, never *invent* them.
  Then re-run the distractor-correctness gate on the smoothed text.

Difficulty knob = distractor **semantic-distance band**, not fact difficulty
(closer siblings = harder, below the "also-correct" ceiling).

---

## 6. Recommended architecture + phased plan

**Recommended architecture:** *corpus-grounded retrieval as the universal
baseline; on-device LLM as an availability-gated phrasing enhancement; a shared
validation gate that both paths pass through.* One `CreateEngine` protocol in
Core with a deterministic retrieval+template implementation everywhere, and a
Foundation Models decorator that only replaces the *phrasing* step where
`SystemLanguageModel` is `.available`. Android/Web mirror the same split.

### Phase 0 — Ship the structured plane (prerequisite, all platforms)
Bundle (or serve) the trimmed `subject/fact/relation/prose/related` tables with
an FTS index on titles/aliases. Author `docs/DATA-CONTRACT.md` per
`shared-data-plane-contract`. Nothing else works without retrievable facts.

### Phase 1 — No-LLM baseline everywhere (the real product)
Topic → FTS retrieve subjects → pick a verified single-valued triple → typed-
sibling distractors → template phrasing (reuse the two shapes `describe`/`cloze`
from `QUESTION-QUALITY.md` §G) → run the full gate → assemble a round. This alone
should already beat the current AI output, and it runs on **tvOS, mobile Safari,
minSdk-29 Android, and every iPhone** identically. Ship this first; it is the
baseline for devices without a capable model.

### Phase 2 — iOS grounded-phrasing enhancement
On Apple-Intelligence-eligible iPhone/iPad, add the Foundation Models decorator:
`CorpusLookupTool` + `@Generable` stem rewrite of the *retrieved* fact, gate-
validated with template fallback. Measure quality lift vs. Phase 1 (A/B in
`QUESTION-QUALITY` §D9 human-sampling style) before trusting it.

### Phase 3 — Android flagship enhancement (opportunistic)
Same decorator via ML Kit Prompt API where AICore reports Nano available; skip
MediaPipe's big-download path unless data shows demand. Everyone else stays on
Phase 1.

### Phase 4 — Optional web/server generation service
If a backend appears, expose a generation endpoint the web (and any client) can
call for richer phrasing — still corpus-grounded, still gated. Never a hard
dependency; the offline baseline always stands.

**Graceful degradation summary:** every platform runs Phase 1 with no model.
The LLM, where present and eligible, only upgrades *phrasing*; its output is
always gate-checked and always has a deterministic fallback. No device is ever
left without the feature, and no device ever ships an unverified fact.

---

## Cross-platform baseline (the one-line contract)

For any device **without** a capable on-device model — tvOS, mobile Safari,
the min-spec Android fleet, Apple-Intelligence-ineligible iPhones — the Create
feature is: **retrieve verified facts from the bundled corpus → typed-sibling
distractors → template phrasing → 9-gate validation.** No model required, no
hallucination possible, full parity. The LLM is a phrasing garnish layered on
top only where it is truly available.
