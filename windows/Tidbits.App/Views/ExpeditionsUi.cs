using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using FluentAvalonia.UI.Controls;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// The Club Expedition's pure rendering (docs/CLUB-FEATURES-BUILD.md "Feature 5").
/// Static builders so the hub / map / stage-result states render deterministically
/// from injected state in a headless test (mirrors KnowledgeAtlasUi/MarathonUi) —
/// `ExpeditionsDialog` wires these to a live `RecordsStore` + the FAContentDialog
/// shell. The hub + map are a REAL preview reachable by everyone (never gated at
/// this layer) — only the Play action itself is Club-gated by the caller.
public static class ExpeditionsUi
{
    private static readonly IBrush Teal = new SolidColorBrush(Color.Parse("#13B6C9"));
    private static readonly IBrush Green = new SolidColorBrush(Color.Parse("#2FCB8A"));
    private static readonly IBrush Gold = new SolidColorBrush(Color.Parse("#FFC531"));
    private static readonly IBrush Muted = new SolidColorBrush(Color.Parse("#22808080"));
    // A solid (opaque) gray for the locked-stage icon — `Muted` above is a very
    // low-alpha overlay tint meant for background fills, not a legible icon stroke.
    private static readonly IBrush LockedIcon = new SolidColorBrush(Color.Parse("#808080"));

    public enum StageState { Locked, Current, Done }

    // MARK: - Hub (campaign list + certificates shelf)

    /// The hub: every catalog campaign with its progress ("Stage N of M" / "Not
    /// started" / "Completed"), plus a Completed/certificates shelf. Reachable by
    /// everyone — a real preview, never gated (only Play, inside the map, is).
    public static Control BuildHub(
        IReadOnlyList<(Expedition Expedition, ExpeditionProgress? Progress)> available,
        IReadOnlyList<ExpeditionCertificate> certificates,
        Action<Expedition> onSelect)
    {
        var root = new StackPanel { Spacing = 14, MinWidth = 420, MaxWidth = 460 };
        root.Children.Add(new TextBlock
        {
            Text = Expeditions.PreviewLine(), Classes = { "caption" }, TextWrapping = TextWrapping.Wrap,
        });

        foreach (var (exp, progress) in available)
        {
            var e = exp; var p = progress;
            root.Children.Add(BuildCampaignRow(e, p, () => onSelect(e)));
        }

        if (certificates.Count > 0)
        {
            root.Children.Add(new TextBlock { Text = "Completed", Classes = { "section-header" }, Margin = new Avalonia.Thickness(0, 6, 0, 0) });
            foreach (var c in certificates)
                root.Children.Add(BuildCertificateRow(c));
        }

        return new ScrollViewer { Content = root, MaxHeight = 520 };
    }

    /// One campaign row on the hub — title/subtitle + a progress line, the whole
    /// card a tap-to-open-map button.
    public static Control BuildCampaignRow(Expedition expedition, ExpeditionProgress? progress, Action onSelect)
    {
        var certLine = progress is null ? "Not started" : ProgressLine(expedition, progress);

        var body = new StackPanel { Spacing = 4 };
        body.Children.Add(new TextBlock { Text = expedition.Title, Classes = { "body-strong" } });
        body.Children.Add(new TextBlock { Text = expedition.Subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(new TextBlock { Text = certLine, Classes = { "caption" }, FontWeight = FontWeight.SemiBold, Foreground = Teal });

        var btn = new Button
        {
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Avalonia.Thickness(14, 12), Content = body,
        };
        btn.Click += (_, _) => onSelect();
        return new Border { Classes = { "card" }, Padding = new Avalonia.Thickness(0), Child = btn };
    }

    private static string ProgressLine(Expedition expedition, ExpeditionProgress progress) =>
        progress.CurrentStageIndex >= expedition.Stages.Count
            ? "Completed"
            : $"Stage {progress.CurrentStageIndex + 1} of {expedition.Stages.Count}";

    private static Control BuildCertificateRow(ExpeditionCertificate cert) => new Border
    {
        Classes = { "card" }, Padding = new Avalonia.Thickness(14, 12),
        Child = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto"),
            Children =
            {
                new FASymbolIcon { Symbol = FASymbol.StarFilled, FontSize = 20, Foreground = Gold, VerticalAlignment = VerticalAlignment.Center, Margin = new Avalonia.Thickness(0, 0, 10, 0) },
                CertBody(cert),
                CertScore(cert),
            },
        },
    };

    private static Control CertBody(ExpeditionCertificate cert)
    {
        var stack = new StackPanel { Spacing = 2 };
        stack.Children.Add(new TextBlock { Text = cert.Title, Classes = { "body-strong" } });
        stack.Children.Add(new TextBlock
        {
            Text = $"{cert.StagesCompleted} stages · {cert.CompletedAt.ToLocalTime():MMM d, yyyy}",
            Classes = { "caption" },
        });
        Grid.SetColumn(stack, 1);
        return stack;
    }

    private static Control CertScore(ExpeditionCertificate cert)
    {
        var t = new TextBlock
        {
            Text = cert.TotalScore.ToString(), FontSize = 18, FontWeight = FontWeight.Black,
            Foreground = Gold, VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(t, 2);
        return t;
    }

    // MARK: - Map (locked / current / done stage path)

    /// One campaign's stage path — locked/current/done, tap the current stage to
    /// play. `isClub` only affects the Play button's label (the map itself is a
    /// real preview reachable by everyone); the caller gates the actual launch.
    public static Control BuildMap(Expedition expedition, ExpeditionProgress? progress, bool isClub, Action onPlayCurrent, Action onBack)
    {
        var currentIndex = progress?.CurrentStageIndex ?? 0;
        var root = new StackPanel { Spacing = 12, MinWidth = 420, MaxWidth = 460 };

        var back = new Button { Content = "‹ All expeditions", Background = Brushes.Transparent, Padding = new Avalonia.Thickness(0) };
        back.Click += (_, _) => onBack();
        root.Children.Add(back);

        root.Children.Add(new TextBlock { Text = expedition.Title, Classes = { "view-heading" } });
        root.Children.Add(new TextBlock { Text = expedition.Subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });

        if (currentIndex >= expedition.Stages.Count)
        {
            root.Children.Add(new Border
            {
                Classes = { "card" },
                Child = new TextBlock
                {
                    Text = "Expedition complete — see your certificate on the hub.", Classes = { "body" },
                    TextWrapping = TextWrapping.Wrap,
                },
            });
            return new ScrollViewer { Content = root, MaxHeight = 520 };
        }

        foreach (var stage in expedition.Stages)
        {
            var state = stage.Index < currentIndex ? StageState.Done
                : stage.Index == currentIndex ? StageState.Current
                : StageState.Locked;
            var lastAttempt = progress?.StageResults.FirstOrDefault(r => r.StageIndex == stage.Index);
            root.Children.Add(BuildStageNode(stage, state, lastAttempt,
                isClub, state == StageState.Current ? onPlayCurrent : null));
        }

        return new ScrollViewer { Content = root, MaxHeight = 520 };
    }

    /// One stage on the map path — Done (green check), Current (playable, tap to
    /// start), or Locked (dim, no action). `lastAttempt` (when set and failed)
    /// shows an honest "Needed X of Y, got Z" line on the Current node.
    public static Control BuildStageNode(ExpeditionStage stage, StageState state, ExpeditionStageResult? lastAttempt,
        bool isClub, Action? onPlay)
    {
        var body = new StackPanel { Spacing = 4 };
        var top = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        top.Children.Add(new FASymbolIcon
        {
            Symbol = state switch { StageState.Done => FASymbol.Checkmark, StageState.Current => FASymbol.Play, _ => FASymbol.ProtectedDocument },
            FontSize = 16, VerticalAlignment = VerticalAlignment.Center,
            Foreground = state switch { StageState.Done => Green, StageState.Current => Teal, _ => LockedIcon },
            Opacity = state == StageState.Locked ? 0.5 : 1,
        });
        top.Children.Add(new TextBlock
        {
            Text = $"Stage {stage.Index + 1}: {stage.Title}", Classes = { "body-strong" },
            Opacity = state == StageState.Locked ? 0.5 : 1,
        });
        body.Children.Add(top);
        body.Children.Add(new TextBlock
        {
            Text = stage.Blurb, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap,
            Opacity = state == StageState.Locked ? 0.5 : 0.85,
        });

        if (state == StageState.Current && lastAttempt is { Passed: false })
        {
            body.Children.Add(new TextBlock
            {
                Text = $"Last try: needed {stage.PassBar} of {stage.QuestionCount}, got {lastAttempt.Correct}",
                Classes = { "caption" }, Foreground = new SolidColorBrush(Color.Parse("#FF5C5C")),
            });
        }

        if (state == StageState.Current && onPlay is not null)
        {
            var play = new Button
            {
                Content = isClub ? "Play" : "Join Club", Classes = { "accent", "compact" },
                HorizontalAlignment = HorizontalAlignment.Left, Margin = new Avalonia.Thickness(0, 4, 0, 0),
            };
            play.Click += (_, _) => onPlay();
            body.Children.Add(play);
        }

        return new Border
        {
            Classes = { "card" }, Opacity = state == StageState.Locked ? 0.7 : 1,
            Child = body,
        };
    }

    // MARK: - Stage result (pass / fail / certificate)

    /// The just-played stage's outcome — pass (unlocks the next stage), fail ("Try
    /// again", no advance), or the final stage passing (a certificate beat).
    /// Replaces the generic session recap for an Expedition session (mirrors
    /// Marathon's dedicated scorecard).
    public static Control BuildStageResult(ExpeditionPlayResult result, Action onContinue, Action onRetry, Action onDone)
    {
        var stack = new StackPanel { Spacing = 16, MaxWidth = 480 };

        if (result.Certificate is { } cert)
        {
            stack.Children.Add(new Border
            {
                Classes = { "card" }, Padding = new Avalonia.Thickness(24, 20),
                Child = new StackPanel
                {
                    Spacing = 4, HorizontalAlignment = HorizontalAlignment.Center,
                    Children =
                    {
                        new FASymbolIcon { Symbol = FASymbol.StarFilled, FontSize = 40, Foreground = Gold, HorizontalAlignment = HorizontalAlignment.Center },
                        new TextBlock { Text = "EXPEDITION COMPLETE", Classes = { "section-header" }, HorizontalAlignment = HorizontalAlignment.Center },
                        new TextBlock { Text = cert.Title, Classes = { "body-strong" }, HorizontalAlignment = HorizontalAlignment.Center },
                        new TextBlock
                        {
                            Text = $"{cert.StagesCompleted} stages · score {cert.TotalScore}", Classes = { "caption" },
                            HorizontalAlignment = HorizontalAlignment.Center,
                        },
                    },
                },
            });
            var done = new Button
            {
                Content = "Done", Classes = { "accent" }, FontWeight = FontWeight.Bold,
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Center,
                Padding = new Avalonia.Thickness(0, 13),
            };
            done.Click += (_, _) => onDone();
            stack.Children.Add(done);
            return stack;
        }

        if (result.Passed)
        {
            stack.Children.Add(new Border
            {
                Classes = { "card" }, Padding = new Avalonia.Thickness(24, 20),
                Child = new StackPanel
                {
                    Spacing = 4, HorizontalAlignment = HorizontalAlignment.Center,
                    Children =
                    {
                        new TextBlock { Text = "STAGE PASSED", Classes = { "section-header" }, Foreground = Green, HorizontalAlignment = HorizontalAlignment.Center },
                        new TextBlock { Text = result.Stage.Title, Classes = { "body-strong" }, HorizontalAlignment = HorizontalAlignment.Center },
                        new TextBlock
                        {
                            Text = $"{result.Correct} of {result.Total} correct — next stage unlocked", Classes = { "caption" },
                            HorizontalAlignment = HorizontalAlignment.Center,
                        },
                    },
                },
            });
            var next = new Button
            {
                Content = "Continue", Classes = { "accent" }, FontWeight = FontWeight.Bold,
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Center,
                Padding = new Avalonia.Thickness(0, 13),
            };
            next.Click += (_, _) => onContinue();
            stack.Children.Add(next);
            return stack;
        }

        // Fail — "Try again", never advance.
        stack.Children.Add(new Border
        {
            Classes = { "card" }, Padding = new Avalonia.Thickness(24, 20),
            Child = new StackPanel
            {
                Spacing = 4, HorizontalAlignment = HorizontalAlignment.Center,
                Children =
                {
                    new TextBlock { Text = "NOT QUITE", Classes = { "section-header" }, Foreground = new SolidColorBrush(Color.Parse("#FF5C5C")), HorizontalAlignment = HorizontalAlignment.Center },
                    new TextBlock { Text = result.Stage.Title, Classes = { "body-strong" }, HorizontalAlignment = HorizontalAlignment.Center },
                    new TextBlock
                    {
                        Text = $"Needed {result.Stage.PassBar} of {result.Stage.QuestionCount} — you got {result.Correct}", Classes = { "caption" },
                        HorizontalAlignment = HorizontalAlignment.Center,
                    },
                },
            },
        });
        var retry = new Button
        {
            Content = "Try Again", Classes = { "accent" }, FontWeight = FontWeight.Bold,
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Center,
            Padding = new Avalonia.Thickness(0, 13),
        };
        retry.Click += (_, _) => onRetry();
        stack.Children.Add(retry);
        var backToMap = new Button { Content = "Back to map", HorizontalAlignment = HorizontalAlignment.Center, Background = Brushes.Transparent, Padding = new Avalonia.Thickness(26, 10) };
        backToMap.Click += (_, _) => onDone();
        stack.Children.Add(backToMap);
        return stack;
    }
}
