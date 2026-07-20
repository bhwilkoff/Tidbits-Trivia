namespace Tidbits.Core.Networking;

/// The account-aware identity layer for Windows — the port of the Swift
/// `PlayerIdentityStore.bootstrap()/linkApple()` re-keying logic (1.6.22 portable-identity
/// spine). This is what lets a Windows player share ONE profile with their phone, and
/// what an entitlement can key on (Decision 047).
///
/// Deliberately additive: the existing `PlayerIdentityStore` stays exactly as-is as the
/// local-first name/avatar store. This class owns the *account* — anon uid vs verified
/// email — and never blocks the app from running signed-out.
///
/// The invariant that matters: the RTDB rules only accept a write to `players/{key}` when
/// `auth.token.email_verified === true` AND `emailOwners/{key}` matches the token email.
/// So we re-key by email ONLY when the token says the email is verified; otherwise we stay
/// uid-keyed and the UI must not promise cross-device sync.
public sealed class AccountIdentity(FirebaseRtdb db, ITokenStore tokens, WindowsSignIn? signIn = null)
{
    private const string EmailKey = "account_email";

    private readonly WindowsSignIn _signIn = signIn ?? new WindowsSignIn(db);

    /// The profile key currently in force — an email accountKey when signed in, else the
    /// anonymous uid. This is the value an entitlement lookup uses.
    public string? ProfileId { get; private set; }

    public PlayerIdentity.Profile? Profile { get; private set; }
    public bool SignedIn { get; private set; }
    public string? AccountEmail { get; private set; }
    public string? AuthError { get; private set; }

    public bool CanSignIn => _signIn.IsConfigured;

    /// Idempotent; safe at launch and again after a sign-in.
    ///
    /// Prefers the token's email, falling back to the persisted one so a refreshed token
    /// that omits the claim still re-keys to the shared profile (the same trap the Swift
    /// side hit with Apple).
    public async Task Bootstrap()
    {
        try
        {
            var uid = await db.EnsureAuth();
            var email = db.CurrentEmail() ?? tokens.Get(EmailKey);

            if (email is { Length: > 0 } && db.CurrentEmailVerified())
            {
                SignedIn = true;
                AccountEmail = email;
                tokens.Set(EmailKey, email);
                var key = PlayerIdentity.AccountKey(email);
                ProfileId = key;
                Profile = await db.Get<PlayerIdentity.Profile>(PlayerIdentity.PublicPath(key))
                          ?? await AdoptUidProfile(uid, key, email);
            }
            else
            {
                SignedIn = false;
                ProfileId = uid;
                Profile = await db.Get<PlayerIdentity.Profile>(PlayerIdentity.PublicPath(uid))
                          ?? PlayerIdentity.Profile.New(SuggestedName());
            }
        }
        catch (Exception e)
        {
            // Local-first: never block the app on a network failure. Stay signed-out.
            AuthError = e.Message;
        }
    }

    /// Google sign-in, then re-key the profile onto the verified email and merge whatever
    /// was played anonymously into the account record.
    public async Task<bool> SignInWithGoogle(CancellationToken ct = default)
    {
        if (SignedIn) return true;      // already durable — never re-merge the same records
        AuthError = null;
        try
        {
            var local = Profile ?? PlayerIdentity.Profile.New(SuggestedName());
            var res = await _signIn.SignInWithGoogle(ct);
            return await AdoptFederated(local, res.Email, res.DisplayName);
        }
        catch (OAuthDeniedException e) when (e.IsUserCancellation)
        {
            return false;                                   // a closed tab is not an error
        }
        catch (OAuthNotConfiguredException)
        {
            AuthError = "Google sign-in isn't available in this build yet.";
            return false;
        }
        catch (Exception e)
        {
            AuthError = $"Sign-in couldn't complete. {e.Message}";
            return false;
        }
    }

    /// Sign in with Apple (docs/APPLE-SIGNIN-WINDOWS.md) — same re-keying as Google, so
    /// Apple and Google with the same verified email converge on ONE profile.
    public async Task<bool> SignInWithApple(CancellationToken ct = default)
    {
        if (SignedIn) return true;
        AuthError = null;
        try
        {
            var local = Profile ?? PlayerIdentity.Profile.New(SuggestedName());
            var res = await _signIn.SignInWithApple(ct);
            return await AdoptFederated(local, res.Email, res.DisplayName);
        }
        catch (OAuthDeniedException e) when (e.IsUserCancellation) { return false; }
        catch (OAuthNotConfiguredException)
        {
            AuthError = "Apple sign-in isn't available in this build yet.";
            return false;
        }
        catch (Exception e)
        {
            AuthError = $"Sign-in couldn't complete. {e.Message}";
            return false;
        }
    }

    /// Sign out → a fresh anonymous identity. Local play continues untouched.
    public async Task SignOut()
    {
        tokens.Delete(EmailKey);
        SignedIn = false;
        AccountEmail = null;
        AuthError = null;
        var uid = await db.SignOut();
        ProfileId = uid;
        Profile = await db.Get<PlayerIdentity.Profile>(PlayerIdentity.PublicPath(uid))
                  ?? PlayerIdentity.Profile.New(SuggestedName());
    }

    /// The shared tail of ANY federated sign-in (Google or Apple): re-key the profile onto
    /// the verified email and merge this device's anonymous play into the account record.
    /// Kept in one place so the two providers can never drift — that convergence is the
    /// whole point of the email-keyed spine.
    private async Task<bool> AdoptFederated(PlayerIdentity.Profile local, string? providerEmail, string? displayName)
    {
        var email = FirstNonEmpty(providerEmail, db.CurrentEmail());
        if (email is null || !db.CurrentEmailVerified())
        {
            // Signed in, but not with a verified email — the RTDB rules would reject every
            // email-keyed write, so stay uid-keyed and say so honestly rather than
            // promising a sync that would silently fail.
            AuthError = "Signed in, but that account has no verified email — "
                      + "your records will stay on this device.";
            return false;
        }

        var key = PlayerIdentity.AccountKey(email);
        await db.Put($"emailOwners/{key}", email);
        var existing = await db.Get<PlayerIdentity.Profile>(PlayerIdentity.PublicPath(key));
        var merged = existing is null ? local : PlayerIdentity.Merge(local, existing);

        if (PlayerIdentity.IsDefaultName(merged.Name) && FirstNonEmpty(displayName) is { } n)
            merged = merged with { Name = n.Length > 24 ? n[..24] : n };

        Profile = merged;
        ProfileId = key;
        AccountEmail = email;
        await db.Put(PlayerIdentity.PublicPath(key), merged);
        tokens.Set(EmailKey, email);
        SignedIn = true;
        return true;
    }

    /// Migrate an anonymous uid-keyed profile onto the email key the first time we see it.
    private async Task<PlayerIdentity.Profile> AdoptUidProfile(string uid, string key, string email)
    {
        var baseProfile = await db.Get<PlayerIdentity.Profile>(PlayerIdentity.PublicPath(uid))
                          ?? PlayerIdentity.Profile.New(SuggestedName());
        await db.Put($"emailOwners/{key}", email);
        await db.Put(PlayerIdentity.PublicPath(key), baseProfile);
        return baseProfile;
    }

    private static string? FirstNonEmpty(params string?[] xs) =>
        xs.Select(x => x?.Trim()).FirstOrDefault(x => !string.IsNullOrEmpty(x));

    private static string SuggestedName() =>
        $"Player {Random.Shared.Next(1000, 9999)}";
}
