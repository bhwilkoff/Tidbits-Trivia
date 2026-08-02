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

`gen_oddoneout.py` and `gen_enumerate.py` still do not read theirs — and no
longer need to. Every generator now writes through `genguard.merge`, which keeps
the shipped artifact and adds only what is new, and all 125 authored rows are
already in the shipped artifacts. The protection no longer depends on each
generator remembering to merge a particular file: it is a property of how the
artifact is written.

This directory is still the right home for authored rows. It is what a
FROM-SCRATCH rebuild would read, and it is the only place the authorship is
legible — `assets/oddoneout.json` cannot tell you which of its rows a human
wrote.
