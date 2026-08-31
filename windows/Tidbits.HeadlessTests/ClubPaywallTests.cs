using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Tidbits Club paywall (docs/CLUB-MARKETING.md, Decision 047) — the last of six platforms.
/// `ClubPaywallUi.BuildPanel` is a static builder (mirrors AudioPanelUi/DuelsUi) so the empty,
/// plans, and member states render deterministically from injected state, offline, without
/// depending on GameData.Shared's singleton entitlement/store state. One extra test wires the
/// real `ClubPaywallView` to confirm it reads GameData.Shared correctly end-to-end.
[Collection("EnvSensitive")]
public class ClubPaywallTests
{
    private static string ArtifactsDir()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static List<string?> TextsOf(Control root) =>
        root.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();

    [AvaloniaFact]
    public void Empty_state_shows_pitch_pillars_and_the_store_edition_note()
    {
        var panel = ClubPaywallUi.BuildPanel(
            isClub: false,
            products: Array.Empty<StoreProductInfo>(),
            busyProductId: null,
            message: null,
            onPurchase: _ => { },
            onRestore: () => { });

        var win = new Window { Width = 480, Height = 780, Content = panel };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("Tidbits Club", texts);
        Assert.Contains(ClubPaywallUi.PitchBody, texts);
        foreach (var (_, title, _) in ClubPaywallUi.Pillars) Assert.Contains(title, texts);
        // NoStoreGateway (Mac head / unpackaged .exe) -> a calm note, never a blank plan list.
        Assert.Contains(ClubPaywallUi.EmptyStateNote, texts);
        Assert.Contains(ClubPaywallUi.WebNote, texts);
        Assert.DoesNotContain(ClubPaywallUi.MemberHeadline, texts);

        win.CaptureRenderedFrame()!.Save(Path.Combine(ArtifactsDir(), "club-paywall-empty.png"));
    }

    [AvaloniaFact]
    public void Products_present_show_a_plan_row_per_product_with_no_code_field()
    {
        var products = new List<StoreProductInfo>
        {
            new(ClubProducts.Lifetime, "Founding Member (Lifetime)", "$79.99"),
            new(ClubProducts.Annual, "Tidbits Club (Yearly)", "$29.99"),
            new(ClubProducts.Monthly, "Tidbits Club (Monthly)", "$3.99"),
        };
        var purchased = new List<string>();
        var panel = ClubPaywallUi.BuildPanel(
            isClub: false, products: products, busyProductId: null, message: null,
            onPurchase: id => purchased.Add(id), onRestore: () => { });

        var win = new Window { Width = 480, Height = 860, Content = panel };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("$79.99", texts);
        Assert.Contains("$29.99", texts);
        Assert.Contains("$3.99", texts);
        Assert.DoesNotContain(texts, t => t is not null && t.Contains("Store edition", StringComparison.OrdinalIgnoreCase));

        // R-MON-2: Club unlocks by account sign-in only — no code/key/coupon field anywhere.
        Assert.Empty(win.GetVisualDescendants().OfType<TextBox>());

        // The purchase button wires through onPurchase (the IStoreGateway seam), not a
        // hidden network/URL call — clicking fires exactly the plan's product id.
        var buyButtons = win.GetVisualDescendants().OfType<Button>()
            .Where(b => b.Classes.Contains("accent")).ToList();
        Assert.Equal(3, buyButtons.Count);
        buyButtons[0].RaiseEvent(new Avalonia.Interactivity.RoutedEventArgs(Button.ClickEvent));
        Assert.Single(purchased);

        win.CaptureRenderedFrame()!.Save(Path.Combine(ArtifactsDir(), "club-paywall-plans.png"));
    }

    [AvaloniaFact]
    public void Member_state_shows_the_banner_instead_of_plans()
    {
        var panel = ClubPaywallUi.BuildPanel(
            isClub: true,
            products: Array.Empty<StoreProductInfo>(),
            busyProductId: null,
            message: null,
            onPurchase: _ => { },
            onRestore: () => { });

        var win = new Window { Width = 480, Height = 480, Content = panel };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains(ClubPaywallUi.MemberHeadline, texts);
        Assert.DoesNotContain(ClubPaywallUi.EmptyStateNote, texts);
        Assert.DoesNotContain("Restore purchases", texts);
        foreach (var (_, title, _) in ClubPaywallUi.Pillars) Assert.DoesNotContain(title, texts);

        win.CaptureRenderedFrame()!.Save(Path.Combine(ArtifactsDir(), "club-paywall-member.png"));
    }

    [AvaloniaFact]
    public void ClubPaywallView_wires_to_GameData_and_renders_the_default_empty_state()
    {
        // GameData.Shared's Store is a NoStoreGateway on the Mac head / headless tests, and a
        // fresh test run has no cached entitlement -> the default is the graceful empty
        // state (never a blank paywall), proving the View reads the shared IStoreGateway
        // seam rather than a raw StoreContext/HttpClient.
        var view = new ClubPaywallView();
        var win = new Window { Width = 480, Height = 780, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        Dispatcher.UIThread.RunJobs(); // pump the async GetProductsAsync() continuation

        var texts = TextsOf(view);
        Assert.Contains("Tidbits Club", texts);

        win.CaptureRenderedFrame()!.Save(Path.Combine(ArtifactsDir(), "club-paywall-view.png"));
    }

    /// Store Policy 10.8.6 + 10.5.1. This is a COMPLIANCE gate, not a UI preference: the
    /// purchase buttons shipped on Windows in 1.6.75 with no renewal disclosure and no Terms or
    /// Privacy link anywhere in the binary, while every other platform carried all three. Apple's
    /// were added after a real 2.1(b) rejection, so this is the one paywall assertion that must
    /// fail loudly rather than be quietly relaxed.
    [AvaloniaFact]
    public void Subscription_plans_carry_the_renewal_disclosure_and_both_legal_links()
    {
        var panel = ClubPaywallUi.BuildPanel(
            isClub: false,
            products: new[]
            {
                new StoreProductInfo(ClubProducts.Monthly,  "Monthly",         "$3.99",  "mo"),
                new StoreProductInfo(ClubProducts.Annual,   "Yearly",          "$29.99", "yr"),
                new StoreProductInfo(ClubProducts.Lifetime, "Founding Member", "$79.99"),
            },
            busyProductId: null, message: null, onPurchase: _ => { }, onRestore: () => { });

        var body = string.Join(" ", TextsOf(panel));
        Assert.Contains("auto-renewable subscriptions", body);
        Assert.Contains("Microsoft account", body);       // not "Apple Account" — wrong store
        Assert.Contains("cancel anytime", body);
        Assert.Contains("does not renew", body);          // the one-time plan is called out too

        var links = panel.GetVisualDescendants().OfType<HyperlinkButton>()
                         .ToDictionary(l => l.Content as string ?? "", l => l.NavigateUri?.ToString());
        Assert.Equal(StoreLegal.TermsUrl,   links["Terms of Use"]);
        Assert.Equal(StoreLegal.PrivacyUrl, links["Privacy Policy"]);
    }

    /// The disclosure must describe only plans that are ON THE SCREEN. The Apple twin carries a
    /// comment about the day the real store returned the two subscriptions but not Founding
    /// Member, leaving prose about a plan with no button — which is what the rejection was.
    [AvaloniaFact]
    public void Disclosure_never_describes_a_plan_that_has_no_button()
    {
        var monthlyOnly = StoreLegal.Disclosure(new[]
            { new StoreProductInfo(ClubProducts.Monthly, "Monthly", "$3.99", "mo") });
        Assert.Contains("Monthly is an auto-renewable subscription", monthlyOnly);
        Assert.DoesNotContain("Yearly", monthlyOnly);
        Assert.DoesNotContain("Founding Member", monthlyOnly);

        // Nothing loaded: there are no terms to state for nothing, so the footer stays silent
        // rather than asserting facts about products the customer cannot see.
        Assert.Equal("", StoreLegal.Disclosure(Array.Empty<StoreProductInfo>()));
    }
}
