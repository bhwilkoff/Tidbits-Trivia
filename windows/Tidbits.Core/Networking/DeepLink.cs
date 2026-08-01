using System;
using System.Linq;

namespace Tidbits.Core.Networking;

public enum DeepLinkKind { None, Play, Daily, Records, Create, Leaderboard, Live, Quiz }

/// A parsed deep link — the nav destination + an optional live room code.
public sealed record DeepLinkTarget(DeepLinkKind Kind, string? Code = null)
{
    /// The FANavigationView item tag this routes to.
    public string NavTag => Kind switch
    {
        DeepLinkKind.Records => "records",
        DeepLinkKind.Create => "create",
        DeepLinkKind.Quiz => "create",   // a shared quiz lands where the shelf lives
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
            // The web canonical for a quiz puts the route in the FRAGMENT
            // (tidbitstrivia.com/#/quiz/<id>), so the path is empty and the id would
            // be lost if only AbsolutePath were read.
            var frag = uri.Fragment.TrimStart('#').Trim('/');
            var source = frag.Length > 0 ? frag : uri.AbsolutePath.Trim('/');
            var segs = source.Split('/', StringSplitOptions.RemoveEmptyEntries);
            head = segs.Length > 0 ? segs[0] : "";
            tail = segs.Length > 1 ? segs[1] : "";
        }

        return head.ToLowerInvariant() switch
        {
            "live" => new(DeepLinkKind.Live, RoomCode(tail)),
            // Carries an id, so unlike the other routes it can't collapse to a token.
            "quiz" => tail.Length > 0 ? new(DeepLinkKind.Quiz, tail) : new(DeepLinkKind.None),
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
