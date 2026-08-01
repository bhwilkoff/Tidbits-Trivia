# Authored question rows

Hand-written rounds that the generators **cannot** produce, kept here as a
committed input so regenerating a type file does not delete them.

They used to live nowhere but the generated artifact in `assets/`. That is not a
place content can live: running `gen_match.py` on 2026-08-01 silently deleted all
22 authored Match-Up rounds, taking `matching x sports` from 11 rounds to 0 and
`matching x history` from 13 to 2. The loss was invisible — the file regenerated
cleanly, the app built, and every test passed.

| File | What is in it | Why the generator can't make it |
|---|---|---|
| `match.json` | 22 rounds — 11 sports, 11 history | The Wikidata relations are capital / currency / element-symbol / author / composer / director. There is no club-to-city or battle-to-war relation in the corpus. |
| `oddoneout.json` | 67 rows across history, science, arts, screen, music, sports | `gen_oddoneout.py` builds only continent-based **geography** rows. Every other category is authored. |
| `enumerate.json` | all 28 list puzzles | `gen_enumerate.py` builds continent-to-countries; the planets, elements, oceans and Great Lakes sets are curated. |

`gen_match.py` merges its file automatically (by id, so it is idempotent).

**`gen_oddoneout.py` and `gen_enumerate.py` do NOT yet merge theirs — do not run
them without wiring that up first, or you will drop the rows listed above.**
Regenerating `oddoneout.json` today would also replace 156 geography rows whose
ids have drifted since they were built, so it needs a deliberate pass rather than
a casual re-run.
