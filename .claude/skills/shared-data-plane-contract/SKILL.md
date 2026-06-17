---
name: shared-data-plane-contract
description: Use when multiple clients consume the same content/data (a catalog, feed, corpus, or library), when designing how published data reaches the apps, when a browser client needs the shared data (CORS/Range realities), or when changing the published schema. Carries the consumers-only rule, the contract doc, hosting trade-offs (GitHub Releases vs Pages vs git), verified CORS/Range matrix, ETag refresh, raw-DEFLATE on-device decompression, additive schema evolution, and merge-guarded mutations. Triggers on data plane, shared catalog, published database, sqlite over http, data contract, CORS, range requests, ETag, schema version, "where should the data live".
---

# Shared Data Plane Contract

When several clients (iOS, tvOS, Android, web) consume the same
content, build the data ONCE as a published plane and make every
client a consumer. Distilled from shipping a ~40k-item catalog to
four clients with zero per-client data logic.

## The one rule

**No client re-implements or re-hosts any part of the pipeline.**
No client re-derives content flags, re-audits policy, re-matches
external metadata, or publishes its own copy. The pipeline (CI /
build-time) compiles everything — including policy flags like
visibility, maturity, rights — into the published artifacts; clients
filter with a `WHERE` clause and inherit every policy fix for free.

The moment a second client exists, author `docs/DATA-CONTRACT.md`
(seed: `docs/templates/DATA-CONTRACT-template.md`). It specifies:
the published assets (URL, host, CORS, Range), the schema, the
editorial JSON shapes, the **query verbs** every client reproduces
natively, and the refresh protocol. When doc and code disagree, the
code wins — then fix the doc in the same change.

## Architecture that scales

For content beyond a few MB, publish a **prebuilt SQLite database**
(with FTS if you need search) and have clients query ON DISK — not a
JSON blob decoded into memory. The binding constraint on a TV/phone
is resident memory, not download: a 95 MB JSON decodes into 150–250
MB of live objects; query-on-disk keeps residency at the visible
rows and scales to 1M+ items.

- Ship a small **bundled seed** DB for first paint; swap in the full
  downloaded DB when ready.
- Compress as **raw DEFLATE** (`zlib.compressobj(wbits=-15)`), not
  gzip: Apple's Compression framework (`COMPRESSION_ZLIB`) and
  Android's `Inflater(nowrap=true)` both decode raw DEFLATE
  natively, streaming file-to-file in small chunks (peak memory
  ~64 KB instead of the whole DB).
- **Validate before swap**: size floor + `PRAGMA integrity_check`
  (or an open-probe) on the staged file, then atomic rename. A
  half-downloaded DB must never become the live one.
- **ETag-conditional GET** (`If-None-Match` → 304 = keep cache) for
  refresh — don't re-download an unchanged 30 MB asset daily.

## Hosting: the verified matrix

Where an asset lives determines who can read it. Measured, not
assumed (re-verify with **GET**, not HEAD — HEAD lies about Range
support):

| Host | CORS on fetch() | Byte-range (206) | Native clients |
|---|---|---|---|
| GitHub **Release** assets | **none** (302 to objects.githubusercontent.com) | 206 but no CORS | fine (URLSession/OkHttp) |
| GitHub **Pages** | yes (`*`) | **206 + CORS on GET** | fine |
| Third-party media hosts (e.g. archive.org download nodes) | usually none | varies | fine; `<img>`/`<video>` elements are CORS-exempt |

Consequences:
- **Big rolling artifacts → GitHub Releases** (a rolling tag,
  clobbered per publish). Native apps consume them directly.
- **Anything the BROWSER must fetch() → Pages** (or another
  CORS-enabled host). If the browser needs the big DB, deploy it to
  Pages via an Actions artifact — never committed to git — and query
  in place over range requests (sql.js-httpvfs class tooling), or
  publish a slim index JSON as the browser plane.
- Never `fetch()` a Release asset or a no-CORS media host from
  browser JS. Media elements (`<img>`, `<video>`) are exempt — use
  them.

## Git hygiene

**Generated accumulators do not live in git.** A multi-MB
machine-generated file committed per rebuild bloats `.git`
unboundedly (a real repo hit 624 MB and GitHub's 100 MB push limit
before the purge + history rewrite). Hand-authored editorial JSON,
tools, and the small bundled seed stay in git; the full artifact
lives on the Release. Gitignore the artifact path so it can't come
back.

## Mutation safety (the expensive lessons)

- **Additive, merge-guarded builds.** Once the artifact lives
  outside git, there is no diff review to catch a clobber. Any
  workflow that REBUILDS (rather than incrementally enriches) must
  merge its output INTO the fetched current artifact and **abort if
  the result would shrink**. A from-scratch rebuild once silently
  replaced a 30k-item catalog with 1.1k — the merge guard is the
  permanent fix.
- **Serialize writers.** Multiple CI jobs mutating the published
  artifact share one concurrency group (fetch → mutate → publish is
  stateful).
- **Policy removals are reversible flags, not deletes.** Hiding
  content (rights, maturity, quality) sets `excluded: true` in the
  source; the publish step filters it. Restorable, reviewable,
  auditable — and a wrong hide is a one-line fix.
- **Schema evolution is additive.** New columns/keys only; clients
  ignore unknown keys (decode leniently). Bump a `schemaVersion`
  for readers that care. Never rename/repurpose a field — add a new
  one and let the old age out with old clients.

## Refresh cadence + manifest

Publish on a schedule (daily cron) + on relevant pushes. Alongside
the artifact, publish a small `manifest.json` (schemaVersion,
generatedAt, counts, bytes) — a cheap version probe for tooling and
future clients, even if today's clients go straight to the asset
with ETag.
