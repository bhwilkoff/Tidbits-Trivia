using System.Collections.Generic;

namespace Tidbits.App.ViewModels;

/// A tab's frame. In this scaffold build every section is a placeholder that
/// names the features it will hold (drawn from the Mac app) — the "frame of
/// every feature" the bootstrap loop targets. Feature parity comes in later loops.
public sealed class SectionViewModel(string title, string subtitle, IReadOnlyList<string> features)
    : ViewModelBase
{
    public string Title { get; } = title;
    public string Subtitle { get; } = subtitle;
    public IReadOnlyList<string> Features { get; } = features;
}
