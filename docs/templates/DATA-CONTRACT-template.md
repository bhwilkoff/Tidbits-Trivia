# [APP NAME] — Shared Data Contract

<!-- Author this as docs/DATA-CONTRACT.md the moment a SECOND client
     consumes the same content/data. See the
     `shared-data-plane-contract` skill for the full pattern. -->

The shared data plane all clients ([list: tvOS, iOS, Web, Android])
implement against. Source of truth for everything below: [the
pipeline scripts / CI workflows / the reference client's query
layer]. **When this doc and the code disagree, the code wins — then
fix this doc in the same change.**

---

## 1. Overview + the one rule

[One paragraph: what the pipeline compiles, from what sources, into
what published artifacts, with what policy flags baked in.]

**The one rule:** no client re-implements or re-hosts any part of
the pipeline. No client re-derives flags, re-audits policy, or
publishes its own copy. Every client consumes the published
artifacts below and reproduces the query verbs in §5 natively.
User state (favorites/progress/preferences) is per-ecosystem
(`per-ecosystem-sync-islands`) and is **out of scope** here.

---

## 2. Published assets

| Asset | URL | Host | CORS | Range | Refresh |
|---|---|---|---|---|---|
| <!-- main DB / feed --> | | GitHub Release (rolling tag) | none | 206, no CORS | daily cron + on push |
| <!-- browser-facing index / config JSON --> | | GitHub Pages | `*` | 206 + CORS on GET | on push |
| <!-- bundled seed --> | | app bundle | n/a | n/a | per release |

Notes to keep verified (re-measure with GET, not HEAD):
- Release assets send **no CORS** and 302-redirect — native clients
  only; the browser plane lives on Pages.
- Use **ETag-conditional GET** on the main artifact; 304 = keep
  cache.
- [Compression format + on-device decompression path, if any —
  raw DEFLATE for Apple Compression / Android Inflater(nowrap).]
- [Validation before swap: size floor + integrity check + atomic
  rename.]

---

## 3. Schema

<!-- Tables/columns (or JSON shape) with types. Mark policy flag
     columns (visibility/maturity/rights) and which are COMPUTED at
     build time. Note FTS tables. Schema evolution is ADDITIVE ONLY:
     new columns/keys; clients ignore unknowns; bump schemaVersion. -->

---

## 4. Editorial / config JSON shapes

<!-- Each hand-authored file clients read (featured/config/etc.):
     shape, where served, which clients consume it. -->

---

## 5. Query verbs (every client reproduces these natively)

<!-- The canonical queries — name, semantics, SQL/filter sketch.
     e.g. browse(filters, sort, page) · search(text) · related(item)
     · home shelves. State the universal WHERE clauses (excluded=0,
     maturity gate) that EVERY query applies. -->

---

## 6. Refresh protocol

<!-- Cadence, manifest shape, client behavior on failure (keep
     serving the cached artifact), and the mutation safety rules:
     writers serialized, rebuilds merge-guarded (abort on shrink),
     removals are reversible flags. -->
