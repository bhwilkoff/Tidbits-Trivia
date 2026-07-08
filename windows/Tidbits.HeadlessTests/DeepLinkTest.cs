using Tidbits.Core.Networking;
using Xunit;

public class DeepLinkTest
{
    [Theory]
    [InlineData("tidbitstrivia://live/2nre", DeepLinkKind.Live, "2NRE")]           // custom scheme, lowercased code
    [InlineData("https://tidbitstrivia.com/live/2NRE", DeepLinkKind.Live, "2NRE")] // https twin
    [InlineData("tidbitstrivia://daily", DeepLinkKind.Daily, null)]
    [InlineData("https://tidbitstrivia.com/leaderboard", DeepLinkKind.Leaderboard, null)]
    [InlineData("tidbitstrivia://records", DeepLinkKind.Records, null)]
    [InlineData("tidbitstrivia://create", DeepLinkKind.Create, null)]
    [InlineData("tidbitstrivia://play", DeepLinkKind.Play, null)]
    [InlineData("https://tidbitstrivia.com/", DeepLinkKind.Play, null)]
    [InlineData("tidbitstrivia://live/bad", DeepLinkKind.Live, null)]              // <4 chars → no code
    [InlineData("tidbitstrivia://nonsense", DeepLinkKind.None, null)]
    [InlineData("", DeepLinkKind.None, null)]
    [InlineData("not a url", DeepLinkKind.None, null)]
    public void Parses_scheme_and_https(string url, DeepLinkKind kind, string? code)
    {
        var t = DeepLink.Parse(url);
        Assert.Equal(kind, t.Kind);
        Assert.Equal(code, t.Code);
    }

    [Theory]
    [InlineData(DeepLinkKind.Live, "live")]
    [InlineData(DeepLinkKind.Records, "records")]
    [InlineData(DeepLinkKind.Leaderboard, "leaderboard")]
    [InlineData(DeepLinkKind.Create, "create")]
    [InlineData(DeepLinkKind.Daily, "play")]   // Daily lands on Play
    [InlineData(DeepLinkKind.Play, "play")]
    public void Maps_to_the_nav_tag(DeepLinkKind kind, string tag)
    {
        Assert.Equal(tag, new DeepLinkTarget(kind).NavTag);
    }
}
