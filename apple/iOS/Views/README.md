# Views/

SwiftUI views — one folder per feature. The structural rule is:

- **One root `View` per feature**, named for the feature (e.g.
  `FindView.swift`, `ProfileView.swift`).
- Decompose into private `View` types in the same file until a
  type crosses ~100 lines OR is reused elsewhere — at which point
  it moves to `/Components/`.
- **No business logic in views.** Read state via `@Environment(...)`
  or `@Bindable`; emit intents back through the store.

Recommended starting decomposition:

```
Views/
├── Find/
│   ├── FindView.swift          ← root
│   └── FindSearchToolbar.swift ← collaborates with FindView
├── Profile/
│   └── ProfileView.swift
└── Collection/
    └── CollectionView.swift
```

Cross-cutting reusable pieces (card cells, section headers,
empty-state primitives) graduate to `/Components/`.

For navigation patterns (NavigationStack, NavigationSplitView,
sheet detents, hero zooms), invoke
`all-ios-skills:swiftui-navigation`. For state ownership
(`@Observable`, `@Bindable`, `@State`, `@Environment`),
`all-ios-skills:swiftui-patterns`.
