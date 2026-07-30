using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using FluentAvalonia.UI.Controls;
using Tidbits.App.Services;

namespace Tidbits.App.Views;

/// First-run walkthrough (audit A.2) — the Windows twin of macOS's
/// `OnboardingSheet_macOS`: one compact pass over what the app is, then straight into
/// playing. Deliberately NOT a multi-page carousel; the Mac shows all three points at once
/// and a desktop window has the room for it.
///
/// Gated on `GameSettings.HasOnboarded`, which is written as soon as the dialog is
/// dismissed BY ANY MEANS (button, Esc, close) — a walkthrough that reappears because the
/// player pressed Escape is worse than one they never saw.
public static class OnboardingDialog
{
    private static readonly (string Title, string Body)[] Points =
    {
        ("All of Wikipedia, as trivia",
            "Thousands of questions built from real Wikipedia facts — and you can spin up a quiz on any topic."),
        ("Play your way",
            "Classic, Time Attack, Survival, Stake, and more — pick a mode and category, or hit Quick Play."),
        ("Compete with your past self",
            "Records tracks your streak, accuracy, and the domains you've mastered. Every miss comes back to help it stick."),
    };

    /// The walkthrough body, separate from the dialog so a test can render it.
    public static StackPanel BuildBody()
    {
        var stack = new StackPanel { Spacing = 18, MaxWidth = 460 };
        BuildPoints(stack);
        return stack;
    }

    /// One numbered row per point.
    private static void BuildPoints(StackPanel stack)
    {
        for (int i = 0; i < Points.Length; i++)
        {
            var (title, body) = Points[i];
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*") };
            // A numbered brand badge rather than an icon-font glyph: Windows 10 ships Segoe
            // MDL2 Assets and Windows 11 Segoe Fluent Icons, and the codepoints do not all
            // agree, so a glyph that looks right here can render as tofu on the other.
            row.Children.Add(new Border
            {
                Width = 28, Height = 28, CornerRadius = new Avalonia.CornerRadius(14),
                Background = new SolidColorBrush(Color.Parse("#FF5C35")),
                Margin = new Avalonia.Thickness(0, 2, 14, 0),
                VerticalAlignment = VerticalAlignment.Top,
                Child = new TextBlock
                {
                    Text = (i + 1).ToString(), Foreground = Brushes.White, FontWeight = FontWeight.Bold,
                    FontSize = 14, HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
            });
            var text = new StackPanel { Spacing = 3 };
            text.Children.Add(new TextBlock { Text = title, FontWeight = FontWeight.SemiBold, FontSize = 15 });
            text.Children.Add(new TextBlock { Text = body, TextWrapping = TextWrapping.Wrap, Opacity = 0.75, FontSize = 13 });
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            stack.Children.Add(row);
        }
    }

    /// Show once per install. No-ops when already seen, so callers can fire it unconditionally.
    public static async Task ShowIfFirstRunAsync()
    {
        var settings = GameData.Shared.Value.Settings;
        if (settings.HasOnboarded) return;

        var stack = BuildBody();


        var dialog = new FAContentDialog
        {
            Title = "Welcome to Tidbits",
            Content = stack,
            PrimaryButtonText = "Get started",
            DefaultButton = FAContentDialogButton.Primary,
        };
        await dialog.ShowAsync();

        settings.HasOnboarded = true;
        settings.Save();
    }
}
