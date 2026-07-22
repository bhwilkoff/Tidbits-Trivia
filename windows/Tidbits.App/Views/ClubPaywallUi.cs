using System;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

/// The Tidbits Club paywall content (docs/CLUB-MARKETING.md §2/§3, Decision 047 / R-MON).
/// Sells the tier without ever gating the free game — reachable from Settings, never an
/// interstitial. Static builder so the panel renders from injected state in a headless test
/// (mirrors AudioPanelUi/DuelsUi); `ClubPaywallView` wires it to `GameData.Shared` (the
/// `IStoreGateway` seam, shared with the entitlement gate) and rebuilds on purchase/restore.
///
/// R-MON-2: Club unlocks by account sign-in only — there is no code/key/coupon field
/// anywhere in this panel, ever.
public static class ClubPaywallUi
{
    public const string PitchHeadline = "Get better, not just play more";
    public const string PitchBody =
        "Ranked seasons, a map of everything you know, and a library of every fact you've learned.";
    public const string EmptyStateNote =
        "Tidbits Club is available in the Microsoft Store edition of this app.";
    public const string WebNote =
        "Already a member from the web or another device? Just sign in — your Club unlocks everywhere.";
    public const string MemberHeadline = "You're a Club member";

    /// CLUB-MARKETING §2 — the four pillars, verbatim (order deliberate: two play, two keep).
    public static readonly IReadOnlyList<(string Emoji, string Title, string Subtitle)> Pillars = new[]
    {
        ("🏆", "Ranked Seasons", "A calendar-driven climb — and your live pub nights count too."),
        ("🗺️", "Knowledge Atlas", "A map of what you actually know, by domain, over time."),
        ("📚", "Story Archive", "Every fact you've learned, kept forever and searchable."),
        ("🧭", "Expeditions", "Multi-week campaigns that turn a session game into a pursuit."),
    };

    /// `onPurchase(productId)` / `onRestore()` fire the actions; `busyProductId` disables the
    /// row mid-purchase; `message` is an optional status line (pending / restore result).
    public static Control BuildPanel(
        bool isClub,
        IReadOnlyList<StoreProductInfo> products,
        string? busyProductId,
        string? message,
        Action<string> onPurchase,
        Action onRestore)
    {
        var root = new StackPanel { Spacing = 18, MinWidth = 380, MaxWidth = 460 };
        root.Children.Add(Hero());

        if (isClub)
        {
            root.Children.Add(MemberBanner());
        }
        else
        {
            root.Children.Add(PillarList());
            root.Children.Add(Plans(products, busyProductId, onPurchase));
            root.Children.Add(RestoreRow(onRestore));
            root.Children.Add(new TextBlock
            {
                Text = WebNote, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center,
            });
        }

        if (!string.IsNullOrEmpty(message))
            root.Children.Add(new TextBlock
            {
                Text = message, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center,
            });

        return root;
    }

    private static Control Hero() => new Border
    {
        Classes = { "card" },
        Child = new StackPanel
        {
            Spacing = 6, HorizontalAlignment = HorizontalAlignment.Center,
            Children =
            {
                new TextBlock { Text = "Tidbits Club", Classes = { "view-heading" }, HorizontalAlignment = HorizontalAlignment.Center },
                new TextBlock { Text = PitchHeadline, Classes = { "body-strong" }, HorizontalAlignment = HorizontalAlignment.Center, TextAlignment = TextAlignment.Center },
                new TextBlock
                {
                    Text = PitchBody, Classes = { "body" }, Opacity = 0.85, TextWrapping = TextWrapping.Wrap,
                    TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center,
                },
                new TextBlock
                {
                    Text = "The whole game stays free. Club is the layer on top.",
                    Classes = { "caption" }, TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center,
                },
            },
        },
    };

    private static Control MemberBanner() => new Border
    {
        Classes = { "card" },
        Child = new StackPanel
        {
            Spacing = 4, HorizontalAlignment = HorizontalAlignment.Center,
            Children =
            {
                new TextBlock { Text = MemberHeadline, Classes = { "section-header" }, HorizontalAlignment = HorizontalAlignment.Center },
                new TextBlock { Text = "Thanks for backing Tidbits.", Classes = { "body" }, Opacity = 0.8, HorizontalAlignment = HorizontalAlignment.Center },
            },
        },
    };

    private static Control PillarList()
    {
        var list = new StackPanel { Spacing = 14 };
        foreach (var (emoji, title, subtitle) in Pillars)
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*") };
            row.Children.Add(new TextBlock
            {
                Text = emoji, FontSize = 22, VerticalAlignment = VerticalAlignment.Top,
                Margin = new Avalonia.Thickness(0, 0, 12, 0),
            });
            var text = new StackPanel { Spacing = 2 };
            text.Children.Add(new TextBlock { Text = title, Classes = { "body-strong" } });
            text.Children.Add(new TextBlock { Text = subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            list.Children.Add(row);
        }
        return new Border { Classes = { "card" }, Child = list };
    }

    private static Control Plans(IReadOnlyList<StoreProductInfo> products, string? busyProductId, Action<string> onPurchase)
    {
        var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(new TextBlock { Text = "Choose a plan", Classes = { "section-header" } });

        // NoStoreGateway (Mac head / unpackaged .exe) reports no products — a calm note,
        // never an empty/blank plan list (universal-feature-states).
        if (products.Count == 0)
        {
            panel.Children.Add(new TextBlock
            {
                Text = EmptyStateNote, Classes = { "body" }, Opacity = 0.75, TextWrapping = TextWrapping.Wrap,
            });
            return panel;
        }

        foreach (var p in products)
        {
            var id = p.Id;
            var isLifetime = id == ClubProducts.Lifetime;
            var isAnnual = id == ClubProducts.Annual;
            var tag = isLifetime ? "Founding Member · limited time" : (isAnnual ? "Best value" : null);

            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            var left = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
            left.Children.Add(new TextBlock { Text = p.Title, Classes = { "body-strong" } });
            if (tag is not null) left.Children.Add(new TextBlock { Text = tag, Classes = { "caption" } });
            grid.Children.Add(left);

            var busy = busyProductId == id;
            var btn = new Button
            {
                Content = busy ? "…" : p.FormattedPrice, Classes = { "accent", "compact" }, IsEnabled = !busy,
                VerticalAlignment = VerticalAlignment.Center,
            };
            btn.Click += (_, _) => onPurchase(id);
            Grid.SetColumn(btn, 1);
            grid.Children.Add(btn);

            panel.Children.Add(new Border { Classes = { "card" }, Padding = new Avalonia.Thickness(14, 12), Child = grid });
        }
        return panel;
    }

    private static Control RestoreRow(Action onRestore)
    {
        var btn = new Button { Content = "Restore purchases", Classes = { "compact" }, HorizontalAlignment = HorizontalAlignment.Center };
        btn.Click += (_, _) => onRestore();
        return btn;
    }
}
