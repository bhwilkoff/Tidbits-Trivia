using System;
using System.Linq;

namespace Tidbits.Core.Networking;

public enum DeepLinkKind { None, Play, Daily, Records, Create, Leaderboard, Live }

/// A parsed deep link — the nav destination + an optional live room code.
public sealed record DeepLinkTarget(DeepLinkKind Kind, string? Code = null)
{
    /// The FANavigationView item tag this routes to.
    public string NavTag => Kind switch
    {
        DeepLinkKind.Records => "records",
        DeepLinkKind.Create => "create",
        DeepLinkKind.Leaderboard => "leaderboard",
        DeepLinkKind.Live => "live",
        _ => "play", // Play + Daily land on the Play tab
    };
}

/// Parse a Tidbits deep link — the custom scheme (tidbitstrivia://live/2NRE) or
/// the https twin (https://tidbitstrivia.com/live/2NRE) — into a nav target.
/// The scheme registration (needs package identity) is separate; this is the
/// routing the inbox consumes.
public static class DeepLink
{
    public static DeepLinkTarget Parse(string? url)
    {
        if (string.IsNullOrWhiteSpace(url) || !Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri))
            return new(DeepLinkKind.None);

        // tidbitstrivia://live/2NRE → host="live", path="2NRE".
        // https://tidbitstrivia.com/live/2NRE → path segments ["live","2NRE"].
        string head, tail;
        if (uri.Scheme.Equals("tidbitstrivia", StringComparison.OrdinalIgnoreCase))
        {
            head = uri.Host;
            tail = uri.AbsolutePath.Trim('/');
        }
        else
        {
            var segs = uri.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
            head = segs.Length > 0 ? segs[0] : "";
            tail = segs.Length > 1 ? segs[1] : "";
        }

        return head.ToLowerInvariant() switch
        {
            "live" => new(DeepLinkKind.Live, RoomCode(tail)),
            "daily" => new(DeepLinkKind.Daily),
            "records" => new(DeepLinkKind.Records),
            "create" => new(DeepLinkKind.Create),
            "leaderboard" => new(DeepLinkKind.Leaderboard),
            "play" or "" => new(DeepLinkKind.Play),
            _ => new(DeepLinkKind.None),
        };
    }

    private static string? RoomCode(string raw)
    {
        var code = new string(raw.ToUpperInvariant().Where(char.IsLetterOrDigit).Take(4).ToArray());
        return code.Length == 4 ? code : null;
    }
}
