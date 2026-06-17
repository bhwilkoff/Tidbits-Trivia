# Components/

Reusable UI primitives — the iOS equivalent of Android's
`core/ui/` or web's component classes in `styles.css`.

A view graduates from `/Views/` to `/Components/` when:

1. It's used by two or more feature views, OR
2. It's the canonical render for a domain concept (a card cell,
   a section header, a wordmark).

Naming follows the `<AppPrefix><Role>` pattern (`BOBACardCell`,
`BOBASectionRow`, `BOBASignInPrompt`, `BOBAWordmark`). One root
component per file.

The discipline (from BOBA's binding design doc): every grid uses
the SAME card cell. Every section header uses the SAME row.
Decoration removed = primitives reused = density without chrome.
See `mobile-first-density-design` skill.
