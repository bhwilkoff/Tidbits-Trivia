# "The App Store didn't send the plans back"

What the Tidbits Club paywall shows when `Product.products(for:)` comes back with
nothing. Diagnosed 2026-08-02 from a device screenshot.

## The one distinction that matters

`products(for:)` fails in two completely different ways and the paywall used to
show the same sentence for both:

| what happened | `lastError` | means |
|---|---|---|
| the call **threw** | set | StoreKit could not reach the store — network, sandbox, entitlement |
| the call **succeeded with `[]`** | **nil** | the store answered, and had nothing to return for these ids |

The screenshot showed the fallback sentence, not a StoreKit error, so `lastError`
was nil: **the App Store answered successfully and returned zero products.** That
rules out connectivity entirely and puts every remaining cause on the App Store
Connect side.

The paywall now says "hasn't published the plans for this build yet" for the
empty case and prints an ordered checklist to the console.

## Verified NOT the cause

- **Product ids match.** Code and `Tidbits.storekit` agree exactly:
  `…club.lifetime`, `…club.annual`, `…club.monthly`.
- **The local StoreKit config is well-formed** — lifetime as a non-consumable,
  monthly/annual in the `Tidbits Club` group at P1M/P1Y.
- **The client retries.** Three attempts with backoff; a cold-launch empty is
  already handled (that was the App Review fix in `appreview-2026-07-28`).
- **The bundle id matches** `com.learningischange.tidbitstrivia`.

## The remaining causes, in order of likelihood

1. **Agreements, Tax, and Banking — the Paid Applications agreement is not
   Active.** Until it is, App Store Connect returns NOTHING for every product of
   every app on the account. This is the most common cause by a wide margin and
   it looks exactly like a broken client. Owner-only; it needs banking and tax
   forms completed.
2. **Product state.** A product in *Missing Metadata* is not returned. Each needs
   its localization, screenshot and review notes to reach *Ready to Submit*.
3. **First approval.** A subscription group's products are returned in sandbox
   once *Ready to Submit*, but the group itself needs a localized display name.

## The trap that makes this hard to test

**Xcode's StoreKit configuration file only applies when Xcode launches the app.**
It is set on the scheme's run action (`project.yml` → `scheme.storeKitConfiguration`),
so:

- Run from Xcode → local config, three products, always works.
- TestFlight, or any device build launched from the home screen → App Store
  Connect, real state.

That is why the paywall can look perfect on a development run and empty on the
same device via TestFlight. `xcrun simctl launch` also bypasses it, which is how
this was reproduced locally.

## What to check first, next time

Read the console. The empty case now prints the four checks above with the exact
product ids. If `lastError` is set instead, it is a different problem and the
message on screen is StoreKit's own words.
