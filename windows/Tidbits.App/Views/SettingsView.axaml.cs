using System.Reflection;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;
using FluentAvalonia.UI.Controls;
using Tidbits.App.Services;

namespace Tidbits.App.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
        ReviewToggle.IsChecked = GameData.Shared.Value.Settings.ReviewEnabled;
        var v = Assembly.GetExecutingAssembly().GetName().Version;
        VersionText.Text = $"Tidbits Trivia for Windows — version {v?.ToString(3) ?? "1.0.0"}";
        RefreshProfile();
        RefreshAccount();
    }

    // MARK: - Account (portable identity)

    /// Reflect the account state. Sign-in is hidden entirely when the OAuth client isn't
    /// configured — a button that always fails is worse than no button.
    private void RefreshAccount()
    {
        var a = GameData.Shared.Value.Account;
        AccountSection.IsVisible = a.CanSignIn || a.SignedIn;

        if (a.SignedIn)
        {
            AccountStatus.Text = a.AccountEmail is { Length: > 0 } e
                ? $"Signed in as {e}. Your records sync across your devices."
                : "Signed in. Your records sync across your devices.";
            SignInButton.IsVisible = false;
            SignOutButton.IsVisible = true;
        }
        else
        {
            AccountStatus.Text = "Playing on this device only.";
            SignInButton.IsVisible = true;
            SignOutButton.IsVisible = false;
        }

        AccountError.IsVisible = a.AuthError is { Length: > 0 };
        AccountError.Text = a.AuthError ?? "";
    }

    private async void OnSignIn(object? sender, RoutedEventArgs e)
    {
        SignInButton.IsEnabled = false;
        SignInButton.Content = "Waiting for your browser…";
        try { await GameData.Shared.Value.Account.SignInWithGoogle(); }
        finally
        {
            SignInButton.IsEnabled = true;
            SignInButton.Content = "Sign in with Google";
            RefreshAccount();
        }
    }

    private async void OnSignOut(object? sender, RoutedEventArgs e)
    {
        var confirm = new FAContentDialog
        {
            Title = "Sign out?",
            Content = "Your records stay safe on your account. This device will go back to "
                    + "playing on its own until you sign in again.",
            PrimaryButtonText = "Sign out",
            CloseButtonText = "Cancel",
            DefaultButton = FAContentDialogButton.Close,
        };
        if (await confirm.ShowAsync() != FAContentDialogResult.Primary) return;
        await GameData.Shared.Value.Account.SignOut();
        RefreshAccount();
    }

    /// Show the current name + a deterministic hue-colored avatar.
    private void RefreshProfile()
    {
        var p = GameData.Shared.Value.Identity.Current;
        NameBox.Text = p.Name;
        AvatarCircle.Background = new SolidColorBrush(
            new HslColor(1.0, p.AvatarHue * 360.0, 0.62, 0.55).ToRgb());
    }

    private void OnNameCommitted(object? sender, RoutedEventArgs e)
    {
        GameData.Shared.Value.Identity.Rename(NameBox.Text ?? "");
        RefreshProfile();
    }

    private void OnShuffleAvatar(object? sender, RoutedEventArgs e)
    {
        GameData.Shared.Value.Identity.RerollAvatar();
        RefreshProfile();
    }

    private void OnReviewToggled(object? sender, RoutedEventArgs e)
    {
        var s = GameData.Shared.Value.Settings;
        s.ReviewEnabled = ReviewToggle.IsChecked ?? true;
        s.Save();
    }

    private void OnResetSeen(object? sender, RoutedEventArgs e)
    {
        GameData.Shared.Value.Provider.ResetSeen();
        ShowStatus("Seen-questions history cleared.");
    }

    /// Reset-all is destructive + irreversible, so confirm first (iOS/web parity —
    /// and basic data safety: an accidental click must not wipe scores/streaks).
    private async void OnResetRecords(object? sender, RoutedEventArgs e)
    {
        var dialog = new FAContentDialog
        {
            Title = "Reset all records?",
            Content = "This permanently deletes your scores, streaks, and review list. This can't be undone.",
            PrimaryButtonText = "Reset everything",
            CloseButtonText = "Cancel",
            DefaultButton = FAContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == FAContentDialogResult.Primary)
        {
            GameData.Shared.Value.Records.ResetAll();
            ShowStatus("All records reset.");
        }
    }

    private void ShowStatus(string text)
    {
        DataStatus.Text = text;
        DataStatus.IsVisible = true;
    }
}
