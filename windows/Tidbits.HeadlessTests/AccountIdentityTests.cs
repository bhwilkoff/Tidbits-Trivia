using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// The account layer decides which key a profile — and therefore an ENTITLEMENT
/// (Decision 047) — lands on. The rules only accept an email-keyed write when
/// `email_verified === true`, so the "verified or stay uid-keyed" invariant is pinned here.
public class AccountIdentityTests
{
    [Fact]
    public void A_fresh_profile_is_named_and_seeded()
    {
        var p = PlayerIdentity.Profile.New("Player 1234", createdAt: 1_700_000_000_000);
        Assert.Equal("Player 1234", p.Name);
        Assert.Equal(1_700_000_000_000, p.CreatedAt);
        Assert.Equal(12, p.AvatarSeed.Length);
        Assert.Equal(PlayerIdentity.Rating.Start, p.Rating.Value);
        Assert.True(p.Rating.Provisional);
    }

    [Fact]
    public void Fresh_profiles_get_distinct_avatar_seeds()
    {
        Assert.NotEqual(PlayerIdentity.Profile.New("a").AvatarSeed,
                        PlayerIdentity.Profile.New("a").AvatarSeed);
    }

    [Fact]
    public void Merging_an_anon_profile_into_an_account_keeps_the_real_name_and_sums_play()
    {
        // The sign-in path: local anon play merges INTO the existing account record.
        var local = PlayerIdentity.Profile.New("Player 4242") with
        {
            Stats = new PlayerIdentity.Stats { GamesPlayed = 3, QuestionsAnswered = 30, Correct = 20 },
        };
        var account = PlayerIdentity.Profile.New("Quiz Khalifa") with
        {
            Stats = new PlayerIdentity.Stats { GamesPlayed = 10, QuestionsAnswered = 100, Correct = 70 },
        };

        var merged = PlayerIdentity.Merge(local, account);

        Assert.Equal("Quiz Khalifa", merged.Name);          // a real name beats a default one
        Assert.Equal(13, merged.Stats.GamesPlayed);          // play is additive, never lost
        Assert.Equal(130, merged.Stats.QuestionsAnswered);
        Assert.Equal(90, merged.Stats.Correct);
    }

    [Fact]
    public void Merging_is_lossless_for_the_longest_streak()
    {
        var a = PlayerIdentity.Profile.New("a") with
        { Streak = new PlayerIdentity.Streak { Current = 2, Longest = 21, LastPlayedDay = "2026-07-01" } };
        var b = PlayerIdentity.Profile.New("b") with
        { Streak = new PlayerIdentity.Streak { Current = 9, Longest = 9, LastPlayedDay = "2026-07-19" } };

        var merged = PlayerIdentity.Merge(a, b);

        Assert.Equal(21, merged.Streak.Longest);             // best-ever survives
        Assert.Equal(9, merged.Streak.Current);              // the more RECENT day wins current
        Assert.Equal("2026-07-19", merged.Streak.LastPlayedDay);
    }

    [Fact]
    public void An_unverified_email_token_must_not_produce_an_email_key()
    {
        // The RTDB rules reject players/{key} writes unless email_verified is true. If the
        // client keyed by email anyway it would promise sync and then silently fail.
        static string Jwt(string payload)
        {
            string B64(byte[] b) => Convert.ToBase64String(b).TrimEnd('=').Replace('+', '-').Replace('/', '_');
            return $"{B64("{}"u8.ToArray())}.{B64(System.Text.Encoding.UTF8.GetBytes(payload))}.sig";
        }

        var unverified = Jwt("""{"email":"a@b.com","email_verified":false}""");
        Assert.Equal("a@b.com", FirebaseRtdb.EmailFromJwt(unverified));
        Assert.False(FirebaseRtdb.EmailVerifiedFromJwt(unverified));   // → stay uid-keyed
    }

    [Fact]
    public void The_account_key_is_provider_independent()
    {
        // Apple on an iPhone and Google on Windows must converge on ONE profile.
        Assert.Equal(PlayerIdentity.AccountKey("ben@learningischange.com"),
                     PlayerIdentity.AccountKey("BEN@LearningIsChange.com "));
    }

    /// Build an account with an EXPLICIT oauth config so these tests don't depend on
    /// whether TIDBITS_GOOGLE_CLIENT_ID happens to be set in the environment.
    private static AccountIdentity Account(string clientId = "")
    {
        var db = new FirebaseRtdb();
        return new AccountIdentity(db, new MemoryTokenStore(),
            new WindowsSignIn(db, new GoogleOAuth.Config(clientId), new FakeBrowserLauncher()));
    }

    [Fact]
    public void SignIn_is_unavailable_until_the_oauth_client_is_configured()
    {
        Assert.False(Account().CanSignIn);          // UI hides the button rather than failing on tap
        Assert.True(Account("x.apps.googleusercontent.com").CanSignIn);
    }

    [Fact]
    public void A_new_account_starts_signed_out_and_unkeyed()
    {
        var account = Account();
        Assert.False(account.SignedIn);
        Assert.Null(account.ProfileId);
        Assert.Null(account.AccountEmail);
    }
}
