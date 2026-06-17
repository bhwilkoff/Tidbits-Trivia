# Models/

Data models — `struct`s, `enum`s, `@Model` (SwiftData) classes.

The line between `/Models/` and `/Store/`:

| Lives here | Lives in `/Store/` |
|---|---|
| Persistent / serializable shapes (`Card`, `UserCard`, `Deck`) | App-wide reactive state (`@Observable AppStore`) |
| `@Model` SwiftData declarations | Navigation paths, selected-tab, signed-in-user cache |
| `Codable` API DTOs | Anything injected via `@Environment(_:.self)` |

Pure data lives here. Behavior that responds to data goes in
`/Store/`. UI that renders data lives in `/Views/`. Networking that
fetches data lives in `/Networking/`.

For SwiftData modeling patterns (`@Model`, `@Relationship`,
`@Attribute(.unique)`, `VersionedSchema`, `SchemaMigrationPlan`),
invoke `all-ios-skills:swiftdata`. For Codable shape decisions
(custom `CodingKeys`, nested decoding, heterogeneous arrays),
`all-ios-skills:swift-codable`.
