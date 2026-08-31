using System;
using Tidbits.App.Services;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The launch hooks are how this app is DRIVEN on a real machine. Nine capabilities the
/// app has could not be reached by anything before they existed — not failing, unasked,
/// which reads identically to a pass in a green report and is strictly worse.
///
/// `tools/hook_coverage.py` prints the cross-platform matrix. This file is the half that
/// runs in CI: a hook whose name is quietly changed here becomes a harness that silently
/// grades whatever screen happened to be showing, which is exactly how the first Windows
/// sweep reported "records" while photographing the Play screen.
[Collection("EnvSensitive")]
public class LaunchHooksTest
{
    private static void With(string key, string? value, Action body)
    {
        var prior = Environment.GetEnvironmentVariable(key);
        try { Environment.SetEnvironmentVariable(key, value); body(); }
        finally { Environment.SetEnvironmentVariable(key, prior); }
    }

    [Theory]
    [InlineData("TIDBITS_SETTINGS")]
    [InlineData("TIDBITS_PAYWALL")]
    [InlineData("TIDBITS_PARTY")]
    [InlineData("TIDBITS_NIGHT_HOST")]
    [InlineData("TIDBITS_AUTOPILOT")]
    [InlineData("TIDBITS_SKIP_ONBOARD")]
    public void Flags_are_off_by_default_and_on_for_1(string key)
    {
        Func<bool> read = key switch
        {
            "TIDBITS_SETTINGS"      => () => LaunchHooks.Settings,
            "TIDBITS_PAYWALL"       => () => LaunchHooks.Paywall,
            "TIDBITS_PARTY"         => () => LaunchHooks.Party,
            "TIDBITS_NIGHT_HOST"    => () => LaunchHooks.NightHost,
            "TIDBITS_AUTOPILOT"     => () => LaunchHooks.Autopilot,
            _                       => () => LaunchHooks.SkipOnboarding,
        };

        // Unset must be OFF: a hook that defaults on changes what a real person sees.
        With(key, null, () => Assert.False(read()));
        With(key, "1", () => Assert.True(read()));
        // Whitespace is not "set" — an exported-but-empty variable is a common shell
        // accident, and treating it as true would silently redirect a real launch.
        With(key, "  ", () => Assert.False(read()));
    }

    [Fact]
    public void Live_join_carries_a_code_and_a_capped_name()
    {
        With("TIDBITS_LIVE_JOIN", null, () => Assert.Null(LaunchHooks.LiveJoin));
        With("TIDBITS_LIVE_JOIN", " win1 ", () => Assert.Equal("win1", LaunchHooks.LiveJoin));

        // 24 chars is the join field's own cap. Without it a long name is accepted here
        // and rejected by the form, so the join fails at the last step with no hint why.
        With("TIDBITS_LIVE_NAME", new string('x', 40),
             () => Assert.Equal(24, LaunchHooks.LiveName!.Length));
        With("TIDBITS_LIVE_NAME", null, () => Assert.Null(LaunchHooks.LiveName));
    }

    [Fact]
    public void Autoplay_parses_mode_and_category_and_defaults_the_missing_half()
    {
        With("TIDBITS_AUTOPLAY", null, () => Assert.Null(LaunchHooks.Autoplay));
        With("TIDBITS_AUTOPLAY", "timeAttack:history", () =>
        {
            Assert.Equal("timeAttack", LaunchHooks.Autoplay!.Value.Mode);
            Assert.Equal("history", LaunchHooks.Autoplay!.Value.Category);
        });
        // Mode alone is the common form; the category defaults rather than erroring.
        With("TIDBITS_AUTOPLAY", "survival", () =>
        {
            Assert.Equal("survival", LaunchHooks.Autoplay!.Value.Mode);
            Assert.Equal("mixed", LaunchHooks.Autoplay!.Value.Category);
        });
    }

    [Fact]
    public void Seed_records_only_accepts_a_positive_count()
    {
        With("TIDBITS_SEED_RECORDS", "12", () => Assert.Equal(12, LaunchHooks.SeedRecords));
        With("TIDBITS_SEED_RECORDS", "0", () => Assert.Null(LaunchHooks.SeedRecords));
        With("TIDBITS_SEED_RECORDS", "-3", () => Assert.Null(LaunchHooks.SeedRecords));
        With("TIDBITS_SEED_RECORDS", "lots", () => Assert.Null(LaunchHooks.SeedRecords));
    }
}
