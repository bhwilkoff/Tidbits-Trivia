using System.Text;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// The RTDB rules gate the email-keyed profile on `auth.token.email_verified === true`.
/// If the client misreads that claim it will promise a synced identity and then silently
/// fail every write — so the decode is pinned here.
public class JwtClaimTests
{
    private static string Jwt(string payloadJson)
    {
        string B64(byte[] b) => Convert.ToBase64String(b).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        return $"{B64("{}"u8.ToArray())}.{B64(Encoding.UTF8.GetBytes(payloadJson))}.sig";
    }

    [Fact]
    public void Reads_email_claim()
    {
        Assert.Equal("a@b.com", FirebaseRtdb.EmailFromJwt(Jwt("""{"email":"a@b.com"}""")));
    }

    [Fact]
    public void Missing_or_empty_email_is_null()
    {
        Assert.Null(FirebaseRtdb.EmailFromJwt(Jwt("""{"sub":"x"}""")));
        Assert.Null(FirebaseRtdb.EmailFromJwt(Jwt("""{"email":""}""")));
    }

    [Fact]
    public void Reads_email_verified_boolean()
    {
        Assert.True(FirebaseRtdb.EmailVerifiedFromJwt(Jwt("""{"email_verified":true}""")));
        Assert.False(FirebaseRtdb.EmailVerifiedFromJwt(Jwt("""{"email_verified":false}""")));
    }

    [Fact]
    public void Accepts_the_string_form_some_providers_emit()
    {
        Assert.True(FirebaseRtdb.EmailVerifiedFromJwt(Jwt("""{"email_verified":"true"}""")));
        Assert.False(FirebaseRtdb.EmailVerifiedFromJwt(Jwt("""{"email_verified":"false"}""")));
    }

    [Fact]
    public void Absent_claim_is_NOT_verified()
    {
        // Fail closed: no claim means no email-keyed write.
        Assert.False(FirebaseRtdb.EmailVerifiedFromJwt(Jwt("""{"email":"a@b.com"}""")));
    }

    [Fact]
    public void Malformed_tokens_fail_closed_rather_than_throwing()
    {
        foreach (var bad in new[] { "", "notajwt", "a.b", "a.!!!.c" })
        {
            Assert.Null(FirebaseRtdb.EmailFromJwt(bad));
            Assert.False(FirebaseRtdb.EmailVerifiedFromJwt(bad));
        }
    }

    [Fact]
    public void A_verified_google_token_produces_the_same_account_key_as_every_other_platform()
    {
        // The whole point of the spine: Apple on iPhone and Google on Windows must land
        // on ONE profile. Pinned to the cross-platform golden value.
        var token = Jwt("""{"email":"  Test@Example.COM  ","email_verified":true}""");
        var email = FirebaseRtdb.EmailFromJwt(token)!;
        Assert.True(FirebaseRtdb.EmailVerifiedFromJwt(token));
        Assert.Equal("973dfe463ec85785f5f95af5ba3906eedb2d931c24e69824a89ea65dba4e813b",
                     PlayerIdentity.AccountKey(email));
    }
}
