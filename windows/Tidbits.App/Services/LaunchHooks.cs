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

    /// TIDBITS_SKIP_ONBOARD=1 — suppress the first-run walkthrough. It is a MODAL
    /// dialog, so while it is up it blocks input to the surface under test.
    public static bool SkipOnboarding => Flag("TIDBITS_SKIP_ONBOARD");
}
