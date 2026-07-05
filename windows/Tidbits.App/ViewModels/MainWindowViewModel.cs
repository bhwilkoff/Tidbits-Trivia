using System.Collections.Generic;

namespace Tidbits.App.ViewModels;

public partial class MainWindowViewModel : ViewModelBase
{
    /// The five surfaces that mirror the Mac app's tabs (Play · Records · Create ·
    /// Tidbits Live) plus Settings. Keyed by the NavigationView item tag.
    public IReadOnlyDictionary<string, SectionViewModel> Sections { get; } =
        new Dictionary<string, SectionViewModel>
        {
            ["play"] = new(
                "Play",
                "Quick into a round, or the daily set — the consumer game.",
                new[]
                {
                    "Quick Play — jump straight into a round",
                    "Daily Tidbit — 7 shared questions, keep your streak",
                    "Customize — pick modes (mix + presets) and a category",
                    "Surprise me — a random round",
                    "Versus CPU + Online Multiplayer",
                }),
            ["records"] = new(
                "Records",
                "Compete against your past self — a dashboard, not a ledger (R-REC-1).",
                new[]
                {
                    "Streak + lifetime stats",
                    "Your 3 most recent games (See all…)",
                    "Your knowledge by domain",
                    "Calibration + personal bests",
                    "Facts to review",
                    "Sign in to sync across devices",
                }),
            ["create"] = new(
                "Create",
                "Generate a quiz on any topic from the whole of Wikipedia.",
                new[]
                {
                    "Topic entry → AI-generated quiz",
                    "Play the generated set",
                }),
            ["live"] = new(
                "Tidbits Live",
                "Host a pub/venue trivia night — the marquee, first-class on Windows.",
                new[]
                {
                    "Event builder (rounds, questions, timers, wagers, speed)",
                    "Host cockpit — reveal, score, answer distribution, hold/skip/jump",
                    "Big-screen projector on a second monitor (fullscreen, hot-plug safe)",
                    "Players join by code from phones (shared RTDB backend)",
                    "Standings, tie-break, CSV export, venue branding",
                    "Windows-first: taskbar-timer, global hotkeys, toasts",
                }),
            ["settings"] = new(
                "Settings",
                "Account, gameplay, and data.",
                new[]
                {
                    "Sign in with your account — sync records",
                    "Gameplay options (review questions, etc.)",
                    "Data — reset seen questions / records",
                    "About + version",
                }),
        };
}
