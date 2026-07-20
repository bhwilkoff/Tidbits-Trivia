using System.Security.Cryptography;
using System.Text;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// The desktop OAuth flow is security-shaped, so the pure parts are pinned here. These
/// run on the Mac head; only the loopback socket + browser launch need Windows.
public class GoogleOAuthTests
{
    private static readonly GoogleOAuth.Config Cfg = new("test-client.apps.googleusercontent.com");

    // MARK: - PKCE

    [Fact]
    public void Pkce_challenge_is_s256_of_verifier()
    {
        var pkce = GoogleOAuth.CreatePkce(new byte[32]); // fixed entropy → deterministic
        var expected = GoogleOAuth.Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(pkce.Verifier)));
        Assert.Equal(expected, pkce.Challenge);
    }

    [Fact]
    public void Pkce_verifier_is_url_safe_and_rfc_length()
    {
        var pkce = GoogleOAuth.CreatePkce();
        Assert.InRange(pkce.Verifier.Length, 43, 128);
        Assert.DoesNotContain('+', pkce.Verifier);
        Assert.DoesNotContain('/', pkce.Verifier);
        Assert.DoesNotContain('=', pkce.Verifier);
    }

    [Fact]
    public void Pkce_is_random_per_call()
    {
        Assert.NotEqual(GoogleOAuth.CreatePkce().Verifier, GoogleOAuth.CreatePkce().Verifier);
    }

    // MARK: - Auth URL

    [Fact]
    public void Auth_url_carries_pkce_and_loopback_redirect()
    {
        var url = GoogleOAuth.BuildAuthUrl(Cfg, "http://127.0.0.1:53219/", "CHAL", "STATE");
        Assert.StartsWith(GoogleOAuth.AuthEndpoint + "?", url);
        Assert.Contains("code_challenge=CHAL", url);
        Assert.Contains("code_challenge_method=S256", url);
        Assert.Contains("response_type=code", url);
        Assert.Contains("state=STATE", url);
        Assert.Contains(Uri.EscapeDataString("http://127.0.0.1:53219/"), url);
    }

    [Fact]
    public void Auth_url_requests_openid_email_so_the_token_carries_a_verified_email()
    {
        // The whole identity spine keys on sha256(verified email) — losing this scope
        // silently produces an unkeyable token.
        var url = GoogleOAuth.BuildAuthUrl(Cfg, "http://127.0.0.1:1/", "c", "s");
        Assert.Contains(Uri.EscapeDataString("openid email profile"), url);
    }

    [Fact]
    public void Auth_url_forces_the_account_chooser()
    {
        Assert.Contains("prompt=select_account", GoogleOAuth.BuildAuthUrl(Cfg, "http://127.0.0.1:1/", "c", "s"));
    }

    // MARK: - Callback parsing

    [Fact]
    public void Parses_code_and_state_from_a_bare_query()
    {
        var cb = GoogleOAuth.ParseCallback("?code=abc123&state=xyz");
        Assert.Equal("abc123", cb.Code);
        Assert.Equal("xyz", cb.State);
        Assert.Null(cb.Error);
    }

    [Fact]
    public void Parses_a_full_url_and_ignores_the_fragment()
    {
        var cb = GoogleOAuth.ParseCallback("http://127.0.0.1:5/?code=a&state=b#frag");
        Assert.Equal("a", cb.Code);
        Assert.Equal("b", cb.State);
    }

    [Fact]
    public void Parses_an_error_callback()
    {
        var cb = GoogleOAuth.ParseCallback("?error=access_denied&state=xyz");
        Assert.Equal("access_denied", cb.Error);
        Assert.Null(cb.Code);
    }

    [Fact]
    public void Percent_decodes_values()
    {
        Assert.Equal("a b/c", GoogleOAuth.ParseCallback("?code=a%20b%2Fc").Code);
    }

    [Fact]
    public void Empty_callback_yields_nothing_rather_than_throwing()
    {
        var cb = GoogleOAuth.ParseCallback("");
        Assert.Null(cb.Code);
        Assert.Null(cb.State);
        Assert.Null(cb.Error);
    }

    // MARK: - State (CSRF)

    [Fact]
    public void State_must_match_exactly()
    {
        Assert.True(GoogleOAuth.StateMatches("abc", "abc"));
        Assert.False(GoogleOAuth.StateMatches("abc", "abd"));
        Assert.False(GoogleOAuth.StateMatches("abc", "ab"));
    }

    [Fact]
    public void Missing_state_never_matches()
    {
        // A forged callback that simply omits state must not be accepted.
        Assert.False(GoogleOAuth.StateMatches("abc", null));
        Assert.False(GoogleOAuth.StateMatches("abc", ""));
        Assert.False(GoogleOAuth.StateMatches(null, null));
    }

    // MARK: - Configuration gate

    [Fact]
    public void Default_ships_the_desktop_client_id_so_sign_in_is_available()
    {
        // The "Tidbits Windows (desktop)" client id ships in the code (not a secret — PKCE
        // is the proof). So sign-in is configured out of the box; the env var can override.
        Assert.True(GoogleOAuth.Config.Default.IsConfigured);
        Assert.EndsWith(".apps.googleusercontent.com", GoogleOAuth.Config.Default.ClientId);
        Assert.StartsWith("842242746909-", GoogleOAuth.Config.Default.ClientId);
    }

    [Fact]
    public void An_empty_or_whitespace_client_id_is_not_configured()
    {
        Assert.False(new GoogleOAuth.Config("").IsConfigured);
        Assert.False(new GoogleOAuth.Config("   ").IsConfigured);
        Assert.True(new GoogleOAuth.Config("x.apps.googleusercontent.com").IsConfigured);
    }

    [Fact]
    public async Task SignIn_throws_NotConfigured_rather_than_opening_a_browser()
    {
        // Pass an EXPLICITLY empty config, never Config.Default: Default reads the
        // environment, so on a machine where TIDBITS_GOOGLE_CLIENT_ID is set this test
        // would sail past the guard, bind a real loopback socket, and block forever
        // waiting for a browser callback that never comes. Tests must not depend on
        // ambient environment.
        var browser = new FakeBrowserLauncher();
        var flow = new WindowsSignIn(new FirebaseRtdb(), new GoogleOAuth.Config(""), browser);
        await Assert.ThrowsAsync<OAuthNotConfiguredException>(
            () => flow.SignInWithGoogle(TestContext.Current.CancellationToken));
        Assert.Null(browser.LastUrl); // no stray browser window
    }

    [Fact]
    public async Task An_abandoned_sign_in_times_out_instead_of_hanging_forever()
    {
        // Regression: a user who closes the consent tab produces no callback. Without a
        // bound, the socket stays open and the UI's sign-in button is dead permanently.
        var flow = new WindowsSignIn(
            new FirebaseRtdb(), new GoogleOAuth.Config("x.apps.googleusercontent.com"),
            new FakeBrowserLauncher())
        { Timeout = TimeSpan.FromMilliseconds(250) };

        var ex = await Assert.ThrowsAsync<OAuthDeniedException>(
            () => flow.SignInWithGoogle(TestContext.Current.CancellationToken));
        Assert.Equal("timeout", ex.Reason);
    }

    // MARK: - Cancellation classification

    [Fact]
    public void User_cancellation_is_distinguished_from_a_real_failure()
    {
        Assert.True(new OAuthDeniedException("access_denied").IsUserCancellation);
        Assert.True(new OAuthDeniedException("no_code").IsUserCancellation);
        Assert.False(new OAuthDeniedException("state_mismatch").IsUserCancellation);
    }
}
