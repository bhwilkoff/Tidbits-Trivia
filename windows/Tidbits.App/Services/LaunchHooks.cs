using System;
using System.Linq;

namespace Tidbits.App.Services;

/// The Windows twin of Apple's `DebugHooks` and Android's `ScreenshotHooks`.
///
/// Why this file exists at all: Windows was driven only by the headless Avalonia
/// tests, which construct a view in-process and never launch the real shell. So no
/// hook that exists to drive a REAL launch was ever needed, and when the app went
/// onto a real machine it turned out that nine capabilities the app has could not be
/// reached by anything — not failing, unasked, which reads identically to a pass in a
/// green report and is strictly worse.
///
/// `tools/hook_coverage.py` prints the per-platform matrix these close.
///
/// Every one of these is inert unless the variable is set, so they cost a shipped
/// build nothing. They deliberately do NOT write persistent state (see
/// `OnboardingDialog.ShouldShow`): driving a surface for a test must never consume a
/// real person's first run or change what they would see next launch.
public static class LaunchHooks
{
    private static string? Env(string k)
    {
        var v = Environment.GetEnvironmentVariable(k);
        return string.IsNullOrWhiteSpace(v) ? null : v.Trim();
    }

    private static bool Flag(string k) => Env(k) is "1" or "true" or "True";

    /// TIDBITS_TAB=play|records|leaderboard|create|live — the section to open on launch.
    public static string? Tab => Env("TIDBITS_TAB");

    /// TIDBITS_LIVE_HOST=<preset name> — host that night straight from launch.
    public static string? LiveHost => Env("TIDBITS_LIVE_HOST");

    /// TIDBITS_NIGHT_HOST=1 — host the default Trivia Night. Apple and Android both
    /// had this; Windows could host only via a Click, so "Windows hosts a night" was
    /// untestable.
    public static bool NightHost => Flag("TIDBITS_NIGHT_HOST");

    /// TIDBITS_LIVE_JOIN=<code> — JOIN a room someone else is hosting.
    ///
    /// The most consequential gap of the set: every other platform could be told to
    /// join, so "every platform joins every other platform's game" had been proven in
    /// every direction except one — nothing could ask Windows to join at all.
    public static string? LiveJoin => Env("TIDBITS_LIVE_JOIN");

    /// TIDBITS_LIVE_NAME=<name> — the display name to join under. Without it several
    /// devices join under one default name and the host cannot tell them apart, which
    /// made a wire check report "3 of 4 landed" when all four had.
    public static string? LiveName
    {
        get
        {
            var n = Env("TIDBITS_LIVE_NAME");
            return n is null ? null : n[..Math.Min(24, n.Length)];   // the field's own cap
        }
    }

    /// TIDBITS_LIVE_DIAG=1 — append what the launch hooks saw to
    /// %LOCALAPPDATA%/TidbitsTrivia/launch-hooks.log, the only way to read it on a
    /// box driven over ssh. No-op otherwise.
    public static void Diag(string line)
    {
        if (!Flag("TIDBITS_LIVE_DIAG")) return;
        try
        {
            var dir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TidbitsTrivia");
            System.IO.Directory.CreateDirectory(dir);
            System.IO.File.AppendAllText(System.IO.Path.Combine(dir, "launch-hooks.log"), $"{DateTime.Now:HH:mm:ss.fff} {line}\n");
        }
        catch { }
    }

    /// TIDBITS_LIVE_HOST_FILE=<path.tidbits|.json> — import that night and host it
    /// straight from launch (the Mac's hook of the same name).
    public static string? LiveHostFile => Env("TIDBITS_LIVE_HOST_FILE");
    /// TIDBITS_LIVE_IMPORT_FILE=<path.tidbits|.json> — import that night into the
    /// BUILDER (rounds open) without hosting it, so the builder can be photographed.
    public static string? LiveImportFile => Env("TIDBITS_LIVE_IMPORT_FILE");
    /// TIDBITS_LIVE_REFRESH=1 — 20 s in, swap every question the room has heard
    /// for a fresh one, through the same call as the round menu (3.56).
    public static bool LiveRefresh => Flag("TIDBITS_LIVE_REFRESH");
    /// TIDBITS_LIVE_TAPCLIP=1 — a joiner takes up a clip offer without a click.
    public static bool LiveTapClip => Flag("TIDBITS_LIVE_TAPCLIP");

    /// TIDBITS_LIVE_EDIT=<prompt> (at TIDBITS_LIVE_EDIT_AT s, default 8) — rewrite
    /// the question on screen mid-night, the way the cockpit's Edit does (3.55).
    public static string? LiveEdit => Env("TIDBITS_LIVE_EDIT");
    public static double LiveEditAt => double.TryParse(Env("TIDBITS_LIVE_EDIT_AT"), out var v) ? v : 8;
    /// TIDBITS_LIVE_ACCEPT_ALL=<text> (at TIDBITS_LIVE_ACCEPT_AT s, default 30) —
    /// reveal if needed, then rule that typed answer correct for everyone (3.21).
    public static string? LiveAcceptAll => Env("TIDBITS_LIVE_ACCEPT_ALL");
    public static double LiveAcceptAt => double.TryParse(Env("TIDBITS_LIVE_ACCEPT_AT"), out var v) ? v : 30;

    /// TIDBITS_LIVE_EXPORT_ANSWERS=<path> — write the answer sheet (3.62) there 5 s after the ACCEPT_ALL ruling.
    public static string? LiveExportAnswers => Env("TIDBITS_LIVE_EXPORT_ANSWERS");
    /// TIDBITS_LIVE_BED=<path> — start the music bed 1 s after the cockpit is up (A9.2).
    public static string? LiveBed => Env("TIDBITS_LIVE_BED");
    /// TIDBITS_LIVE_PLAYCLIP_AT=<secs> — press Play on the question's clip.
    public static double? LivePlayClipAt => double.TryParse(Env("TIDBITS_LIVE_PLAYCLIP_AT"), out var v) ? v : null;
    /// TIDBITS_LIVE_NEXT_AT=<secs> — reveal if needed, then Next (A3.9's standings hold).
    public static double? LiveNextAt => double.TryParse(Env("TIDBITS_LIVE_NEXT_AT"), out var v) ? v : null;
    /// TIDBITS_LIVE_REPORT_AT=<secs> — open the Night report dialog (3.68) that many seconds after the ACCEPT_ALL ruling.
    public static double? LiveReportAt => double.TryParse(Env("TIDBITS_LIVE_REPORT_AT"), out var v) ? v : null;
    /// TIDBITS_LIVE_RENAME=<name> at TIDBITS_LIVE_RENAME_AT=<secs> — rename the alphabetically first joined team (A3.12).
    public static string? LiveRename => Env("TIDBITS_LIVE_RENAME");
    public static double? LiveRenameAt => double.TryParse(Env("TIDBITS_LIVE_RENAME_AT"), out var v) ? v : null;
    /// TIDBITS_LIVE_FIX_KEY=<answer> at TIDBITS_LIVE_FIX_AT=<secs> — reveal if needed, then replace the current
    /// question's accepted list with that answer, which re-scores the room (A3.13).
    public static string? LiveFixKey => Env("TIDBITS_LIVE_FIX_KEY");
    public static double? LiveFixAt => double.TryParse(Env("TIDBITS_LIVE_FIX_AT"), out var v) ? v : null;
    /// TIDBITS_DUELS=1 — open the Duels dialog on launch. Duels shipped with NO hook and no
    /// fleet coverage, so the surface could never be photographed and a rules change to
    /// `duels/$id` could not be re-verified in-app (DATA-SECURITY-AUDIT "known coverage gap").
    public static bool Duels => Flag("TIDBITS_DUELS");
    /// TIDBITS_DUEL_CHALLENGE=<uid> — challenge that uid to a fresh set on launch; the duel id
    /// is written to the Diag log so a harness can play the other side from the wire.
    public static string? DuelChallenge => Env("TIDBITS_DUEL_CHALLENGE");
    /// TIDBITS_LIVE_BREAK=<minutes> at TIDBITS_LIVE_BREAK_AT=<secs> — hold the show on a break
    /// with a promised return, the way the cockpit's Break command does (A3.14).
    public static int? LiveBreak => int.TryParse(Env("TIDBITS_LIVE_BREAK"), out var v) ? v : null;
    public static double LiveBreakAt => double.TryParse(Env("TIDBITS_LIVE_BREAK_AT"), out var v) ? v : 15;
    /// TIDBITS_LIVE_FINISH_AT=<secs> — reveal if needed, then END the night the way the host does
    /// (macOS parity). Without it a two-question night on the box could never be driven to its wrap.
    public static double? LiveFinishAt => double.TryParse(Env("TIDBITS_LIVE_FINISH_AT"), out var v) ? v : null;
    /// TIDBITS_LIVE_NIGHTS=1 — open the newest archived night on launch (A2.12); nothing else
    /// reaches that dialog without a click, so without this the surface is untestable on the glass.
    public static bool LiveNights => Flag("TIDBITS_LIVE_NIGHTS");
    /// TIDBITS_LIVE_ANSWER=<text> at TIDBITS_LIVE_ANSWER_AT=<secs> (default 75) — the JOINER types and submits (3.75).
    public static string? LiveAnswer => Env("TIDBITS_LIVE_ANSWER");
    public static double LiveAnswerAt => double.TryParse(Env("TIDBITS_LIVE_ANSWER_AT"), out var v) ? v : 75;
    /// TIDBITS_PROFILE_NAME=<name> — rename the portable profile at launch through the Settings path (3.71).
    public static string? ProfileName => Env("TIDBITS_PROFILE_NAME");
    /// TIDBITS_DEEPLINK=<url> — route a link on launch exactly as a registered-protocol launch would (3.37).
    public static string? DeepLink => Env("TIDBITS_DEEPLINK");
    /// TIDBITS_LIVE_TIEBREAK=1 — 3 s after the ACCEPT_ALL ruling, open the
    /// tie-break dialog (3.58) so it can be photographed with real tied teams.
    public static bool LiveTieBreak => Flag("TIDBITS_LIVE_TIEBREAK");
    /// TIDBITS_LIVE_PROJECTOR=1 — open the projector window as soon as the cockpit
    /// is up, so the big screen can be photographed without a click.
    public static bool LiveProjector => Flag("TIDBITS_LIVE_PROJECTOR");
    /// TIDBITS_LIVE_FULLSCREEN=1 — the projector goes full screen even on a
    /// single display (6.3a's automatic placement would keep it windowed there).
    public static bool LiveFullScreen => Flag("TIDBITS_LIVE_FULLSCREEN");

    /// TIDBITS_SETTINGS=1 — open Settings.
    public static bool Settings => Flag("TIDBITS_SETTINGS");

    /// TIDBITS_PAYWALL=1 — open the Club paywall. This is the surface carrying the
    /// renewal disclosure and the Terms/Privacy links, so it is the one most worth
    /// being able to photograph on a real machine.
    public static bool Paywall => Flag("TIDBITS_PAYWALL");

    /// TIDBITS_PARTY=1 — open Pass & Play.
    public static bool Party => Flag("TIDBITS_PARTY");

    /// TIDBITS_AUTOPLAY=<mode>[:<category>] — start a round on launch.
    public static (string Mode, string Category)? Autoplay
    {
        get
        {
            var raw = Env("TIDBITS_AUTOPLAY");
            if (raw is null) return null;
            var parts = raw.Split(':');
            return (parts.ElementAtOrDefault(0) ?? "classic",
                    parts.ElementAtOrDefault(1) ?? "mixed");
        }
    }

    /// TIDBITS_AUTOPILOT=1 — answer automatically, so a reveal or a scorecard can be
    /// photographed without a click. TIDBITS_AUTOPILOT_CORRECT=1 answers correctly
    /// rather than picking option 0, which otherwise advertises a bad score in a shot.
    public static bool Autopilot => Flag("TIDBITS_AUTOPILOT");
    public static bool AutopilotCorrect => Flag("TIDBITS_AUTOPILOT_CORRECT");

    /// TIDBITS_SEED_RECORDS=<n> — insert n synthetic games so Records is not an empty
    /// state. Never written to the real store; see the caller.
    public static int? SeedRecords =>
        int.TryParse(Env("TIDBITS_SEED_RECORDS"), out var n) && n > 0 ? n : null;

    /// TIDBITS_QA_LABEL=<text> — draw a small banner naming what this device is
    /// testing. Six devices on a desk all running Tidbits look identical, so a bench
    /// photograph said nothing about which one was under test and a device left over
    /// from an earlier run was indistinguishable from one in the current one.
    public static string? QaLabel
    {
        get
        {
            var v = Env("TIDBITS_QA_LABEL");
            return v is null ? null : v[..Math.Min(60, v.Length)];
        }
    }

    /// TIDBITS_SKIP_ONBOARD=1 — suppress the first-run walkthrough. It is a MODAL
    /// dialog, so while it is up it blocks input to the surface under test.
    public static bool SkipOnboarding => Flag("TIDBITS_SKIP_ONBOARD");
}
