import Foundation
import Testing

/// The on-screen diagnostic strip must never reach a store build.
///
/// The strip earns its place: three device-only bugs in this extension (dark mode,
/// a stripped `MSMessage.url`, answers that staged instead of sending) were mutually
/// indistinguishable from the outside, and it is what told them apart. Messages
/// launches the extension, so there is no console, no debugger and no env var — an
/// on-screen readout is the only instrument available.
///
/// That is exactly why it is dangerous to keep. It is gated on the build
/// configuration, which is invisible at the call site: nothing about reading
/// `RoundViews.swift` tells you whether the gate still holds, and a strip that shipped
/// would look like a normal part of the UI rather than a mistake. So it is asserted
/// here instead of trusted to review.
struct MessagesDiagnosticTests {

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("project.yml").path) { return dir }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func source(_ rel: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(rel), encoding: .utf8)
    }

    /// Walk the file tracking `#if DEBUG` nesting, and report any line mentioning the
    /// diagnostic that sits outside it.
    private func diagnosticLinesOutsideDebug(_ src: String) -> [String] {
        var depth = 0                 // nesting inside #if DEBUG
        var otherIf = 0               // nesting inside any other #if, to match #endif correctly
        var offenders: [String] = []

        for raw in src.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("#if") {
                if line.contains("DEBUG"), otherIf == 0 { depth += 1 } else { otherIf += 1 }
                continue
            }
            if line.hasPrefix("#endif") {
                if otherIf > 0 { otherIf -= 1 } else if depth > 0 { depth -= 1 }
                continue
            }
            // #else inside the DEBUG block is the RELEASE side — treat it as outside.
            if line.hasPrefix("#else"), depth > 0, otherIf == 0 {
                depth -= 1
                otherIf += 1
                continue
            }
            if line.hasPrefix("//") { continue }   // comments discuss it by name; that is fine

            if line.contains("MsgDiag"), depth == 0 {
                offenders.append(String(raw))
            }
        }
        return offenders
    }

    @Test func diagnosticStateIsDebugOnly() throws {
        for file in ["TidbitsMessages/RoundViews.swift",
                     "TidbitsMessages/MessagesViewController.swift"] {
            let src = try source(file)
            let offenders = diagnosticLinesOutsideDebug(src)
            #expect(offenders.isEmpty,
                    "\(file): MsgDiag referenced outside #if DEBUG — the strip would ship:\n\(offenders.joined(separator: "\n"))")
        }
    }

    /// Guards the scanner itself. A checker that cannot distinguish gated from ungated
    /// code would pass this suite while the strip shipped — the failure mode this repo
    /// has hit more than once, where the gate is the thing that is broken.
    @Test func theScannerCanActuallyFail() {
        let gated = """
        #if DEBUG
        MsgDiag.text = "x"
        #endif
        """
        let ungated = """
        MsgDiag.text = "x"
        """
        let releaseSide = """
        #if DEBUG
        Text(MsgDiag.text)
        #else
        MsgDiag.text = "x"
        #endif
        """
        #expect(diagnosticLinesOutsideDebug(gated).isEmpty)
        #expect(diagnosticLinesOutsideDebug(ungated).count == 1)
        #expect(diagnosticLinesOutsideDebug(releaseSide).count == 1,
                "the #else branch is the Release side and must count as outside")
    }

    /// The strip's gate is only as good as the configurations either side of it. If a
    /// Release build ever gained DEBUG, everything above would still pass and the strip
    /// would ship anyway.
    @Test func releaseDoesNotDefineDebug() throws {
        let pbx = try source("TidbitsTrivia.xcodeproj/project.pbxproj")
        let defines = pbx.components(separatedBy: "SWIFT_ACTIVE_COMPILATION_CONDITIONS").count - 1
        #expect(defines == 1,
                "expected exactly one SWIFT_ACTIVE_COMPILATION_CONDITIONS (the Debug config); found \(defines) — a Release configuration may now define DEBUG")
    }
}
