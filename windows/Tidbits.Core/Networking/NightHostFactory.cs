using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.Core.Networking;

/// Builds a configured LiveNightHost from explicit options.
///
/// This was inline in LiveView, reading its controls directly (CategoryPicker,
/// SpeedBonusCheck, HostNameBox...). That is what tied hosting to the Tidbits
/// Live page: Play could not host a night without duplicating the whole body,
/// and a duplicate would drift. Taking the options as arguments makes hosting a
/// pure function of them, so both products call ONE implementation.
public static class NightHostFactory
{
    public static LiveNightHost Create(
        NightPlan plan,
        TriviaCategory category,
        QuestionProvider provider,
        string title,
        bool speedBonus,
        bool hostPlays,
        string? hostName,
        LiveEvent? branding = null)
    {
        var host = new LiveNightHost(plan, category, provider, title)
        {
            SpeedBonus = speedBonus,
            HostPlays = hostPlays,
            HostName = string.IsNullOrWhiteSpace(hostName) ? "Host" : hostName!.Trim(),
            // Without this the editor is theatre: the host edits a question, hits
            // Host, and the night pulls a fresh corpus round over their work.
            AuthoredQuestions = branding is null
                ? new List<IReadOnlyList<Question>>()
                : Enumerable.Range(0, branding.Rounds.Count).Select(branding.QuestionsFor).ToList(),
            AuthoredClips = branding is null
                ? new List<IReadOnlyList<string>>()
                : Enumerable.Range(0, branding.Rounds.Count)
                    .Select(i => (IReadOnlyList<string>)
                        Enumerable.Range(0, branding.QuestionsFor(i).Count)
                                  .Select(q => branding.ClipFor(i, q) ?? "").ToList())
                    .ToList(),
            Sponsor = branding?.Sponsor,
            BrandHex = branding?.BrandHex,
            LeadCaptureUrl = branding?.LeadCaptureUrl,
            WagerRoundIndex = branding?.WagerFinalRound == true ? System.Math.Max(0, plan.Rounds.Count - 1) : null,
            RoundNotes = branding?.RoundNotes ?? new List<string>(),
            RoundTimers = branding?.RoundTimers ?? new List<int>(),
        };
        return host;
    }
}
