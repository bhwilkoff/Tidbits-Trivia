using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// The portable Tidbits player identity — the cross-platform profile wire contract on
/// the $0 RTDB data plane (port of Core/Networking/PlayerProfile.swift). Byte-identical
/// keys + determinism-critical helpers (accountKey, venueKey, currentSeason, avatarHue,
/// Elo, streak) so a cross-venue leaderboard spans iPhone + Android + web + Windows.
/// Additive-only.
public static class PlayerIdentity
{
    public const string PublicRoot = "players";
    public const string PrivateRoot = "playersPrivate";
    public static string PublicPath(string uid) => $"{PublicRoot}/{uid}";
    public static string PrivatePath(string uid) => $"{PrivateRoot}/{uid}";

    /// Stable, non-reversible profile key from the verified email — Apple + Google with
    /// the same email land on the SAME profile. Mirror of the JS/Kotlin sha256Hex(email).
    public static string AccountKey(string email)
    {
        var norm = email.Trim().ToLowerInvariant();
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(norm));
        var sb = new StringBuilder(hash.Length * 2);
        foreach (var b in hash) sb.Append(b.ToString("x2"));
        return sb.ToString();
    }

    public static string StandingPath(string season, string venue, string uid) =>
        $"standings/{season}/{venue}/{uid}";

    /// The current season id — calendar quarter, e.g. "2026-S3". Byte-identical everywhere.
    public static string CurrentSeason(DateTime? now = null)
    {
        var d = now ?? DateTime.Now;
        var quarter = ((d.Month - 1) / 3) + 1;
        return $"{d.Year}-S{quarter}";
    }

    /// "2026-S3" → "Q3 2026".
    public static string SeasonDisplay(string key)
    {
        var parts = key.Split('-');
        if (parts.Length == 2 && parts[1].StartsWith('S')) return $"Q{parts[1][1..]} {parts[0]}";
        return key;
    }

    /// Days until the current calendar-quarter season resets.
    public static int SeasonResetDays(DateTime? now = null)
    {
        var d = now ?? DateTime.Now;
        var quarter = ((d.Month - 1) / 3) + 1;
        var nextMonth = quarter * 3 + 1;
        var year = d.Year + (nextMonth > 12 ? 1 : 0);
        if (nextMonth > 12) nextMonth -= 12;
        var next = new DateTime(year, nextMonth, 1);
        return Math.Max(0, (int)(next.Date - d.Date).TotalDays);
    }

    /// A venue key safe for an RTDB path — ASCII a-z0-9 kept, every other run collapsed to a
    /// single "-", edges trimmed. Byte-identical to the JS/Kotlin `[^a-z0-9]+`→`-`.
    public static string VenueKey(string venue)
    {
        var lowered = venue.Trim().ToLowerInvariant();
        var sb = new StringBuilder();
        bool lastDash = false;
        foreach (var ch in lowered)
        {
            if (ch is >= 'a' and <= 'z' or >= '0' and <= '9') { sb.Append(ch); lastDash = false; }
            else if (!lastDash) { sb.Append('-'); lastDash = true; }
        }
        var s = sb.ToString();
        return s.Trim('-');
    }

    /// Up-to-two initials for the seeded avatar.
    public static string Initials(string name)
    {
        var parts = name.Split(' ', StringSplitOptions.RemoveEmptyEntries).Take(2);
        var s = string.Concat(parts.Select(p => p[0]));
        return string.IsNullOrEmpty(s) ? "?" : s.ToUpperInvariant();
    }

    /// Deterministic avatar hue (0–1) from the seed — djb2, matching iOS/Android/web.
    /// `long` + unchecked mirrors Swift Int's wrapping `&*`/`&+`.
    public static double AvatarHue(string seed)
    {
        long stable = 5381;
        unchecked
        {
            foreach (var b in Encoding.UTF8.GetBytes(seed)) stable = (stable * 33) + b;
        }
        return (double)(Math.Abs(stable) % 360) / 360.0;
    }

    /// Today in "yyyy-MM-dd" (the streak day key).
    public static string TodayString() => DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    /// Whole-day gap between two "yyyy-MM-dd" strings (empty `from` → 1 = fresh start).
    public static int DayGap(string from, string to)
    {
        if (string.IsNullOrEmpty(from)) return 1;
        if (!DateTime.TryParseExact(from, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var a)
            || !DateTime.TryParseExact(to, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var b))
            return 99;
        return (int)(b.Date - a.Date).TotalDays;
    }

    public static bool IsDefaultName(string n) => n.StartsWith("Player ", StringComparison.Ordinal);

    /// LOSSLESS merge of a local anon profile into an `account` profile (the survivor).
    public static Profile Merge(Profile a, Profile b)
    {
        var name = !IsDefaultName(b.Name) ? b.Name : (!IsDefaultName(a.Name) ? a.Name : b.Name);
        var rGames = a.Rating.Games + b.Rating.Games;
        var rating = new Rating
        {
            Value = Math.Max(a.Rating.Value, b.Rating.Value), Games = rGames,
            Provisional = rGames < Rating.EstablishedAt,
        };
        var streak = new Streak
        {
            Current = string.CompareOrdinal(a.Streak.LastPlayedDay, b.Streak.LastPlayedDay) >= 0 ? a.Streak.Current : b.Streak.Current,
            Longest = Math.Max(a.Streak.Longest, b.Streak.Longest),
            LastPlayedDay = string.CompareOrdinal(a.Streak.LastPlayedDay, b.Streak.LastPlayedDay) >= 0 ? a.Streak.LastPlayedDay : b.Streak.LastPlayedDay,
            Freezes = Math.Max(a.Streak.Freezes, b.Streak.Freezes),
        };
        var stats = new Stats
        {
            GamesPlayed = a.Stats.GamesPlayed + b.Stats.GamesPlayed,
            QuestionsAnswered = a.Stats.QuestionsAnswered + b.Stats.QuestionsAnswered,
            Correct = a.Stats.Correct + b.Stats.Correct,
            LiveNights = a.Stats.LiveNights + b.Stats.LiveNights,
            VenuesVisited = Math.Max(a.Stats.VenuesVisited, b.Stats.VenuesVisited),
        };
        return new Profile
        {
            Name = name, CreatedAt = Math.Min(a.CreatedAt, b.CreatedAt),
            AvatarSeed = b.AvatarSeed, Rating = rating, Streak = streak, Stats = stats,
        };
    }

    // MARK: wire types

    public sealed record Profile
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("createdAt")] public long CreatedAt { get; init; }
        [JsonPropertyName("avatarSeed")] public string AvatarSeed { get; init; } = "";
        [JsonPropertyName("rating")] public Rating Rating { get; init; } = new();
        [JsonPropertyName("streak")] public Streak Streak { get; init; } = new();
        [JsonPropertyName("stats")] public Stats Stats { get; init; } = new();
    }

    public sealed record Friend
    {
        [JsonPropertyName("uid")] public string Uid { get; init; } = "";
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("avatarSeed")] public string AvatarSeed { get; init; } = "";
        [JsonPropertyName("since")] public long Since { get; init; }
    }

    public sealed record Rating
    {
        [JsonPropertyName("value")] public double Value { get; init; } = Start;
        [JsonPropertyName("games")] public int Games { get; init; }
        [JsonPropertyName("provisional")] public bool Provisional { get; init; } = true;

        public const double Start = 1000.0;
        public const int EstablishedAt = 15;

        /// Elo-style update after a game (port). accuracy 0..1; provisional games move faster (K);
        /// weight boosts live games. Bounded ≥100.
        public Rating Updated(double accuracy, double field = 1200, double weight = 1)
        {
            var expected = 1.0 / (1.0 + Math.Pow(10, (field - Value) / 400));
            var k = (Provisional ? 64.0 : 24.0) * weight;
            var n = Games + 1;
            var newValue = Math.Max(100, Math.Round(Value + k * (accuracy - expected)));
            return new Rating { Value = newValue, Games = n, Provisional = n < EstablishedAt };
        }
    }

    public sealed record Streak
    {
        [JsonPropertyName("current")] public int Current { get; init; }
        [JsonPropertyName("longest")] public int Longest { get; init; }
        [JsonPropertyName("lastPlayedDay")] public string LastPlayedDay { get; init; } = "";
        [JsonPropertyName("freezes")] public int Freezes { get; init; }

        /// Register play on `today`. Same day = unchanged; consecutive = +1; a one-day gap
        /// consumes a freeze; a bigger gap resets to 1. A live night grants a freeze (cap 3).
        public Streak Played(string today, bool liveNight = false)
        {
            var current = Current; var longest = Longest; var last = LastPlayedDay; var freezes = Freezes;
            if (today != last)
            {
                var gap = DayGap(last, today);
                if (string.IsNullOrEmpty(last) || gap == 1) current += 1;
                else if (gap == 2 && freezes > 0) { freezes -= 1; current += 1; }
                else current = 1;
                longest = Math.Max(longest, current);
                last = today;
            }
            if (liveNight) freezes = Math.Min(freezes + 1, 3);
            return new Streak { Current = current, Longest = longest, LastPlayedDay = last, Freezes = freezes };
        }
    }

    public sealed record Stats
    {
        [JsonPropertyName("gamesPlayed")] public int GamesPlayed { get; init; }
        [JsonPropertyName("questionsAnswered")] public int QuestionsAnswered { get; init; }
        [JsonPropertyName("correct")] public int Correct { get; init; }
        [JsonPropertyName("liveNights")] public int LiveNights { get; init; }
        [JsonPropertyName("venuesVisited")] public int VenuesVisited { get; init; }
    }

    public sealed record Private
    {
        [JsonPropertyName("email")] public string? Email { get; init; }
        [JsonPropertyName("appleUserID")] public string? AppleUserId { get; init; }
        [JsonPropertyName("gameCenterID")] public string? GameCenterId { get; init; }
        [JsonPropertyName("playGamesID")] public string? PlayGamesId { get; init; }
        [JsonPropertyName("googleUserID")] public string? GoogleUserId { get; init; }
        [JsonPropertyName("venues")] public IReadOnlyList<string>? Venues { get; init; }
    }

    public sealed record Standing
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("score")] public int Score { get; init; }
        [JsonPropertyName("nights")] public int Nights { get; init; }
        [JsonPropertyName("updatedAt")] public long UpdatedAt { get; init; }
    }
}

/// One ranked row in a leaderboard (decoded from data/leaderboard/*.json).
public sealed record LeaderboardRow
{
    [JsonPropertyName("uid")] public string Uid { get; init; } = "";
    [JsonPropertyName("name")] public string Name { get; init; } = "";
    [JsonPropertyName("score")] public int Score { get; init; }
    [JsonPropertyName("nights")] public int Nights { get; init; }
    [JsonPropertyName("venues")] public int? Venues { get; init; }
}
