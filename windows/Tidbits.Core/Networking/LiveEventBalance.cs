using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

/// A balance readout for an event under construction (Wave A authoring aid) —
/// the question-type mix + a plain-language variety verdict, so a host doesn't
/// accidentally build an all-Classic night.
public static class LiveEventBalance
{
    public sealed record TypeShare(GameMode Kind, int Questions);

    /// Questions per type, most first.
    public static IReadOnlyList<TypeShare> ByType(IReadOnlyList<NightRound> rounds) =>
        rounds.GroupBy(r => r.Kind)
            .Select(g => new TypeShare(g.Key, g.Sum(r => r.Count)))
            .OrderByDescending(t => t.Questions)
            .ToList();

    public static int DistinctTypes(IReadOnlyList<NightRound> rounds) =>
        rounds.Select(r => r.Kind).Distinct().Count();

    /// Plain-language verdict on the night's variety.
    public static string Verdict(IReadOnlyList<NightRound> rounds)
    {
        var d = DistinctTypes(rounds);
        return d == 0 ? "" :
            d == 1 ? "One-note — add another question type" :
            d == 2 ? "A little variety" :
            d == 3 ? "Nicely balanced" :
            "Great variety";
    }
}
