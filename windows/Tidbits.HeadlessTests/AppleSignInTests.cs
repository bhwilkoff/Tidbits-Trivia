using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// Apple sign-in on Windows rides an HTTPS bounce Worker (docs/APPLE-SIGNIN-WINDOWS.md).
/// The pure parts — nonce derivation, the state contract the Worker parses, the authorize
/// URL, and callback parsing — are pinned here; they must agree with
/// workers/tidbits-auth/src/state.js or sign-in breaks in a way no local test would catch.
public class AppleSignInTests
{
    private static readonly AppleSignIn.Config Cfg = new("com.example.svc", "https://example.workers.dev/apple/callback");

    // MARK: - Nonce

    [Fact]
    public void Raw_nonce_is_url_safe_and_long_enough()
    {
        var n = AppleSignIn.NewRawNonce();
        Assert.InRange(n.Length, 32, 128);
        Assert.DoesNotContain('+', n);
        Assert.DoesNotContain('/', n);
        Assert.DoesNotContain('=', n);
        Assert.NotEqual(n, AppleSignIn.NewRawNonce());   // random per call
    }

    [Fact]
    public void Sha256Hex_is_the_known_digest()
    {
        // shasum -a 256 of "abc"
        Assert.Equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                     AppleSignIn.Sha256Hex("abc"));
    }

    // MARK: - The state contract (must match the Worker's parser)

    [Fact]
    public void State_is_nonce_dot_port_and_round_trips()
    {
        var state = AppleSignIn.BuildState("Zm9vYmFyYmF6cXV4MTIz", 53219);
        Assert.Equal("Zm9vYmFyYmF6cXV4MTIz.53219", state);
        Assert.Equal(53219, AppleSignIn.PortFromState(state));
    }

    [Fact]
    public void PortFromState_rejects_out_of_range_and_junk()
    {
        foreach (var bad in new[] { "nonce.80", "nonce.443", "nonce.1023", "nonce.65536",
                                    "nonce.abc", "nonce.", ".53219", "nonce", "" })
            Assert.Null(AppleSignIn.PortFromState(bad));
    }

    // MARK: - Authorize URL

    [Fact]
    public void Auth_url_requests_form_post_and_the_id_token_directly()
    {
        var url = AppleSignIn.BuildAuthUrl(Cfg, "HASHEDNONCE", "csrf.53219");
        Assert.StartsWith(AppleSignIn.AuthEndpoint + "?", url);
        // `code id_token` is what lets us skip the code exchange (and Apple's .p8 secret).
        Assert.Contains(Uri.EscapeDataString("code id_token"), url);
        // Requesting scopes REQUIRES form_post — Apple's rule.
        Assert.Contains("response_mode=form_post", url);
        Assert.Contains(Uri.EscapeDataString("name email"), url);
        Assert.Contains("nonce=HASHEDNONCE", url);
        Assert.Contains(Uri.EscapeDataString("csrf.53219"), url);
    }

    [Fact]
    public void Auth_url_uses_the_services_id_not_a_bundle_id()
    {
        // Apple's web flow authenticates a Services ID; passing a bundle id silently fails.
        Assert.Contains(Uri.EscapeDataString("com.example.svc"), AppleSignIn.BuildAuthUrl(Cfg, "h", "s"));
    }

    // MARK: - Callback parsing (what the Worker forwards to loopback)

    [Fact]
    public void Parses_the_id_token_and_nonce_half_of_state()
    {
        var cb = AppleSignIn.ParseCallback("?id_token=HEAD.PAY.SIG&code=abc&state=csrfonly");
        Assert.Equal("HEAD.PAY.SIG", cb.IdToken);
        Assert.Equal("abc", cb.Code);
        Assert.Equal("csrfonly", cb.State);   // the Worker strips the port half
        Assert.Null(cb.Error);
    }

    [Fact]
    public void Parses_the_first_authorization_user_payload()
    {
        // Apple sends the NAME only on first authorization; the email is in the id_token.
        var cb = AppleSignIn.ParseCallback("?id_token=x&state=s&user=" + Uri.EscapeDataString("""{"name":{"firstName":"Ben"}}"""));
        Assert.Contains("firstName", cb.User);
    }

    [Fact]
    public void Parses_an_error_callback_and_empty_input_fails_closed()
    {
        Assert.Equal("user_cancelled_authorize", AppleSignIn.ParseCallback("?error=user_cancelled_authorize").Error);
        var empty = AppleSignIn.ParseCallback("");
        Assert.Null(empty.IdToken);
        Assert.Null(empty.State);
    }

    // MARK: - CSRF

    [Fact]
    public void State_comparison_is_exact_and_missing_never_matches()
    {
        Assert.True(AppleSignIn.StateMatches("abc", "abc"));
        Assert.False(AppleSignIn.StateMatches("abc", "abd"));
        Assert.False(AppleSignIn.StateMatches("abc", null));
        Assert.False(AppleSignIn.StateMatches(null, "abc"));
        // The FULL state must NOT match — the Worker returns only the nonce half.
        Assert.False(AppleSignIn.StateMatches("abc", "abc.53219"));
    }

    [Fact]
    public void Default_config_ships_the_services_id_and_the_deployed_bounce()
    {
        Assert.True(AppleSignIn.Config.Default.IsConfigured);
        Assert.StartsWith("https://", AppleSignIn.Config.Default.RedirectUri);
        // Apple forbids loopback/IP redirects — the default must never be one.
        Assert.DoesNotContain("localhost", AppleSignIn.Config.Default.RedirectUri);
        Assert.DoesNotContain("127.0.0.1", AppleSignIn.Config.Default.RedirectUri);
    }
}
