# Submitting to the App Store from the CLI

**The whole ship is commands now — building, screenshots, metadata, and the submit
itself. Nobody needs to open App Store Connect.**

This is new as of 2026-09-01. Before it, the build was automated but a human had to
create the version in Connect, attach the build, and press Submit. That is no longer
true, and the reason it used to be true is worth stating plainly: the obvious API
endpoint for submitting is deprecated and answers 403, which reads as "you can't do
this" rather than "use the other one".

---

## The four commands

```bash
# 1. Bump the version. MARKETING_VERSION moves on EVERY ship.
vim AppVersion.xcconfig                      # e.g. 1.7.0 / 123
python3 tools/stamp_msix_version.py          # keeps Windows in lockstep
git commit -am "1.7.0 (123) — ..." && git push

# 2. Build, sign, and upload the binary. ~12 min.
gh workflow run appstore-build.yml -f platform=ios     # or tvos / mac / all

# 3. Screenshots, if they changed. Writes into branding/store-screenshots/.
tools/capture-imessage-screenshots.sh all              # iMessage sets
tools/capture-screenshots.sh ios && tools/capture-screenshots.sh ipad   # app sets

# 4. Open the version, attach the build, set the notes, submit.
gh workflow run imessage-screenshots.yml \
  -f mode=upload \
  -f create_version=1.7.0 \
  -f attach_build=123 \
  -f release_notes="What's new..." \
  -f submit=true
```

Then confirm it actually landed — the tool's own success message is not evidence:

```bash
gh workflow run imessage-screenshots.yml -f mode=audit
```

`mode=audit` should end with `no blockers found` and a state of `WAITING_FOR_REVIEW`.

> The workflow is named for screenshots because that is what it started as. It now
> carries the whole submission; the name is the only misleading thing about it.

---

## Modes

| `-f mode=` | Does |
|---|---|
| `audit` | Full pre-submission check. Exits non-zero on a blocker. **Run this before and after submitting.** |
| `status` | Short readiness report: state, attached build, per-set screenshot delivery |
| `list` | The app's iOS versions and their states |
| `upload` | Uploads the iMessage screenshot sets (add `-f replace=true` to overwrite) |
| `dry-run` | Lists what would upload, changes nothing |

Any mode can also carry `-f create_version=`, `-f attach_build=`, `-f release_notes=`,
`-f release_type=`, `-f submit=true`.

---

## Release type: it auto-releases

New versions are created **`AFTER_APPROVAL`** — approval puts it on the store without
anyone pressing anything. That is deliberate: an approved build sitting unreleased is a
silent stall, and this project has already lost days to exactly that shape of problem
on the Microsoft Store (see `windows-store-two-silent-stalls`).

To change it, including on a version already in review:

```bash
gh workflow run imessage-screenshots.yml -f mode=status -f release_type=MANUAL
```

Release type is release logistics, not reviewable content, so Apple lets it change
while the version sits in `WAITING_FOR_REVIEW` — no withdrawal needed. Anything that
edits reviewable content (screenshots, notes, the attached build) still requires an
editable version.

---

## The four traps

Every one of these built and archived **green** and failed only at upload or submit.
That is the pattern worth remembering: for App Store work, a green build tells you
almost nothing.

**1. A TestFlight upload does not create an App Store version.**
They are separate records. 1.6.80 had builds uploaded for weeks and no version at all,
so the first submission attempt reported only a `READY_FOR_SALE` 1.6.73 and refused to
continue. `-f create_version=X.Y.Z` opens one.

**2. `POST /v1/appStoreVersionSubmissions` is deprecated.**

```
403  The resource 'appStoreVersionSubmissions' does not allow 'CREATE'.
     Allowed operation is: DELETE
```

Deprecated, not broken — and the message never says so. Submitting is now three calls:
create a `reviewSubmissions`, add the version as a `reviewSubmissionItems`, then PATCH
`submitted: true`. Apple's model is a submission carrying one or more items (the
version, IAPs, and so on), which is also why a version can no longer be sent alone.
`tools/asc_screenshots.py --submit` does all three.

**3. A new extension or app target needs its App ID registered.**
Signing dies with `bundle id not found in App Store Connect: ... (register it first)`.
`tools/asc_profiles.py` now registers it automatically. Note Apple rejects `.` and `_`
in a bundle id's **name** — the identifier itself is fine.

**4. An iMessage icon set needs `"platform": "ios"`.**
On its `universal` and `ios-marketing` entries. Without it actool silently drops them,
buries a `5 unassigned children` warning in the build log, and emits no
`MSMessagesExtensionStoreIconName` — then the upload rejects the build for missing
54x40 / 64x48 / 96x72 / 81x60 icons. `MessagesIconTests` pins this.

---

## Credentials

**They live in GitHub secrets and should stay there.** The submission runs in CI for
exactly that reason: the dev Mac has the `.p8` but not `ASC_ISSUER_ID`, and there is no
reason to put it there.

`ASC_KEY_ID` · `ASC_ISSUER_ID` · `ASC_KEY_P8` (**base64**, not raw PEM — passing it
through raw fails with `Unable to load PEM file ... MalformedFraming`).

---

## When something fails

`tools/asc_screenshots.py` prints Apple's error body verbatim rather than a summary.
Read it. Two of the four traps above were solved by reading the rejection and one by
reading Apple's format reference; none was solved by guessing.

A related warning, learned the hard way while building this: **be suspicious of a
probe that reports success.** While diagnosing the icon set, `--stickers-icon-role app`
appeared to pass because actool rejected the flag outright, so the warning being
grepped for never appeared — a broken command reading as a clean result. Check that a
check can actually fail before you trust it.
