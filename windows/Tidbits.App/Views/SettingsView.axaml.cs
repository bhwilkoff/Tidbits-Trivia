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
        RefreshClub();
        _ = RefreshEntitlementThenClub();
    }

    private async System.Threading.Tasks.Task RefreshEntitlementThenClub()
    {
        await GameData.Shared.Value.Entitlement.RefreshAsync();
        RefreshClub();
    }

    // MARK: - Tidbits Club (Decision 047)

    private void RefreshClub()
    {
        ClubButton.Content = GameData.Shared.Value.Entitlement.IsClub
            ? "Tidbits Club — Member"
            : "Join Tidbits Club";
    }

    /// Opens the paywall as a FAContentDialog (the app's established modal idiom) — never a
    /// forced interstitial, always Settings-initiated. Sized comfortably for the pitch +
    /// pillars + plans without feeling like a squeezed phone sheet.
    private async void OnOpenClub(object? sender, RoutedEventArgs e)
    {
        var dialog = new FAContentDialog
        {
            Content = new ScrollViewer
            {
                Content = new ClubPaywallView(),
                MaxWidth = 520,
                MaxHeight = 640,
            },
            CloseButtonText = "Close",
        };
        await dialog.ShowAsync();
        RefreshClub();
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
            SignInAppleButton.IsVisible = false;
            SignOutButton.IsVisible = true;
        }
        else
        {
            AccountStatus.Text = "Playing on this device only.";
            SignInButton.IsVisible = true;
            SignInAppleButton.IsVisible = true;
            SignOutButton.IsVisible = false;
        }

        AccountErrorRow.IsVisible = a.AuthError is { Length: > 0 };
        AccountError.Message = a.AuthError ?? "";
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
            _ = GameData.Shared.Value.Entitlement.RefreshAsync();
        }
    }

    /// Apple rides an HTTPS bounce Worker rather than the loopback (Apple forbids
    /// localhost/IP redirects) — docs/APPLE-SIGNIN-WINDOWS.md. Same convergence: Apple and
    /// Google with the same verified email land on ONE profile.
    private async void OnSignInApple(object? sender, RoutedEventArgs e)
    {
        SignInAppleButton.IsEnabled = false;
        SignInAppleButton.Content = "Waiting for your browser…";
        try { await GameData.Shared.Value.Account.SignInWithApple(); }
        finally
        {
            SignInAppleButton.IsEnabled = true;
            SignInAppleButton.Content = "Sign in with Apple";
            RefreshAccount();
            _ = GameData.Shared.Value.Entitlement.RefreshAsync();
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
        GameData.Shared.Value.Entitlement.ClearOnSignOut();
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

    /// Account deletion (Decision 048) — the same in-app, irreversible delete the Apple
    /// platforms ship. Confirmed through an FAContentDialog with Cancel as the default, and
    /// it reports failure instead of silently leaving the account alive.
    private async void OnDeleteAccount(object? sender, RoutedEventArgs e)
    {
        var dialog = new FAContentDialog
        {
            Title = "Delete your account?",
            Content = "This cannot be undone. Your profile, rating, streak, Daily history, "
                    + "standings and friends are permanently deleted.",
            PrimaryButtonText = "Delete account",
            CloseButtonText = "Cancel",
            DefaultButton = FAContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != FAContentDialogResult.Primary) return;

        DeleteAccountButton.IsEnabled = false;
        DeleteAccountButton.Content = "Deleting…";
        var account = GameData.Shared.Value.Account;
        bool ok = await account.DeleteAccount();
        if (ok)
        {
            // Local records are part of "all of its data".
            GameData.Shared.Value.Records.ResetAll();
            GameData.Shared.Value.Provider.ResetSeen();
        }
        DeleteStatusRow.IsVisible = true;
        DeleteStatus.Severity = ok ? FAInfoBarSeverity.Success : FAInfoBarSeverity.Error;
        DeleteStatus.Message = ok
            ? "Your account was deleted. This PC is signed out and starting fresh."
            : account.DeleteError ?? "Couldn't delete your account.";
        DeleteAccountButton.IsEnabled = true;
        DeleteAccountButton.Content = "Delete account…";
        RefreshAccount();
        RefreshProfile();
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
        DataStatus.Message = text;
        DataStatusRow.IsVisible = true;
    }
}
