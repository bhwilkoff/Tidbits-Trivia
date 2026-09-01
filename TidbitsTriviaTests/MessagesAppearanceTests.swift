import Foundation
import Testing

/// The iMessage extension must force light appearance.
///
/// Tidbits is a fixed cream-and-ink design with no dark variants. An app extension
/// does NOT inherit its host app's appearance, so on a dark-mode device the extension
/// ran dark: the default label colour became white, on top of the white field
/// background the design hardcodes. The name field looked empty while you typed into
/// it — reported from an iPad, not caught here.
///
/// The setting was originally written as the build setting
/// `INFOPLIST_KEY_UIUserInterfaceStyle`, which Xcode only merges when it GENERATES an
/// Info.plist. This target supplies an explicit `info.path`, so the setting was
/// silently ignored and nothing warned. That silence is why this is asserted against
/// the project file rather than trusted to review.
struct MessagesAppearanceTests {

    private func projectYML() throws -> String {
        // The test bundle runs from DerivedData, so walk up to the repo root by
        // looking for the file rather than guessing a relative depth.
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent("project.yml")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    @Test func extensionInfoPlistForcesLightAppearance() throws {
        let yml = try projectYML()
        let ext = try #require(yml.range(of: "  TidbitsMessages:"))
        let tail = String(yml[ext.lowerBound...])
        // Everything up to the next top-level target.
        let block = tail.components(separatedBy: "\n  TidbitsTriviaTests:").first ?? tail

        // COMMENTS STRIPPED FIRST. The first version of this check was a plain
        // substring match and failed on the comment that explains why the build-setting
        // form must not be used — a gate that cannot tell a warning from the thing it
        // warns about.
        let settings = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.hasPrefix("#") ? "" : String(line)
            }
            .joined(separator: "\n")

        #expect(settings.contains("UIUserInterfaceStyle: Light"),
                "the Messages extension must force light appearance in its Info.plist")
        // The form that does nothing. If it comes back, the plist stops carrying the
        // key and a dark-mode device gets white-on-white again with no warning.
        #expect(!settings.contains("INFOPLIST_KEY_UIUserInterfaceStyle"),
                "INFOPLIST_KEY_* is ignored when the target supplies an explicit info.path")
    }

    @Test func everyTextFieldPinsItsForegroundColour() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("project.yml").path) { break }
        }
        let views = try String(
            contentsOf: dir.appendingPathComponent("TidbitsMessages/RoundViews.swift"),
            encoding: .utf8)

        // A fixed-palette design must never inherit a text colour: one appearance
        // change away from invisible. Every TextField declares its own.
        let fields = views.components(separatedBy: "TextField(").dropFirst()
        #expect(!fields.isEmpty, "expected TextFields to exist — has the view been renamed?")
        for field in fields {
            // Look only at the modifier chain, which ends at the next blank line.
            let chain = field.components(separatedBy: "\n\n").first ?? field
            #expect(chain.contains(".foregroundStyle("),
                    "a TextField relies on the inherited text colour")
        }
    }
}
