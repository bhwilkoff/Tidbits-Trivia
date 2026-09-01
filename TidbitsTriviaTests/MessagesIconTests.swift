import Foundation
import Testing

/// The iMessage app icon set must keep its `platform` keys.
///
/// Without `"platform": "ios"` on the `universal` and `ios-marketing` entries, actool
/// silently drops them: it compiled only the iphone/ipad sizes, warned about
/// "5 unassigned children" in a wall of build output nobody reads, and produced an
/// extension with no store icon and no `MSMessagesExtensionStoreIconName`. Everything
/// built and archived green. The failure surfaced only at upload:
///
///     Missing App Icon. iMessage app icons must be 54x40 pixels in .png format.
///     Missing Info.plist key ... must contain the MSMessagesExtensionStoreIconName key.
///
/// A silent drop that only a store upload can catch is worth a test.
struct MessagesIconTests {

    private func iconSet() throws -> [[String: Any]] {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("project.yml").path) { break }
        }
        let url = dir.appendingPathComponent(
            "TidbitsMessages/Assets.xcassets/iMessage App Icon.stickersiconset/Contents.json")
        let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        let images = (json as? [String: Any])?["images"] as? [[String: Any]]
        return try #require(images)
    }

    @Test func universalEntriesDeclareTheirPlatform() throws {
        let images = try iconSet()
        #expect(!images.isEmpty)
        for image in images {
            let idiom = image["idiom"] as? String ?? ""
            guard idiom == "universal" || idiom == "ios-marketing" else { continue }
            #expect(image["platform"] as? String == "ios",
                    "\(idiom) \(image["size"] as? String ?? "?") is missing platform:ios — actool drops it and the store icon never ships")
        }
    }

    /// The four sizes the App Store upload names explicitly, as their PIXEL dimensions:
    /// 54x40, 81x60, 64x48, 96x72.
    @Test func theDrawerSizesArePresent() throws {
        let images = try iconSet()
        let have = Set(images.compactMap { img -> String? in
            guard let s = img["size"] as? String, let sc = img["scale"] as? String else { return nil }
            return "\(s)@\(sc)"
        })
        for required in ["27x20@2x", "27x20@3x", "32x24@2x", "32x24@3x"] {
            #expect(have.contains(required), "missing \(required) — the upload rejects the build")
        }
    }

    @Test func theStoreIconIsPresent() throws {
        let images = try iconSet()
        let store = images.first { $0["idiom"] as? String == "ios-marketing" }
        let s = try #require(store, "no ios-marketing entry — MSMessagesExtensionStoreIconName is derived from it and the upload fails without it")
        #expect(s["size"] as? String == "1024x768")
    }

    /// Every declared filename must exist. A renamed PNG is the other way this set
    /// goes quietly wrong.
    @Test func everyDeclaredFileExists() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("project.yml").path) { break }
        }
        let setDir = dir.appendingPathComponent(
            "TidbitsMessages/Assets.xcassets/iMessage App Icon.stickersiconset")
        for image in try iconSet() {
            let name = try #require(image["filename"] as? String)
            #expect(FileManager.default.fileExists(atPath: setDir.appendingPathComponent(name).path),
                    "\(name) is declared but not on disk")
        }
    }
}
