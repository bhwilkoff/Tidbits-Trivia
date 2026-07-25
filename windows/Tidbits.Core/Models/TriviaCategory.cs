namespace Tidbits.Core.Models;

/// A trivia category (port of Core/Models/TriviaCategory.swift). `Symbol` +
/// `ColorIndex` are semantic hints; the Avalonia layer maps them to Windows icons
/// and the shared palette. Keep the IDs in lockstep with the other platforms.
public sealed record TriviaCategory(string Id, string Name, string Symbol, int ColorIndex, string Blurb)
{
    public static readonly IReadOnlyList<TriviaCategory> All = new[]
    {
        new TriviaCategory("mixed",     "Mixed Bag",  "shuffle",     0, "A little of everything."),
        new TriviaCategory("history",   "History",    "scroll",      1, "People, places, and the past."),
        new TriviaCategory("science",   "Science",    "atom",        3, "How the universe works."),
        new TriviaCategory("geography", "Geography",  "globe",       4, "The whole wide world."),
        new TriviaCategory("arts",      "Arts & Lit", "theatermasks",5, "Books, art, and culture."),
        new TriviaCategory("screen",    "Film & TV",  "film",        0, "The big and small screen."),
        new TriviaCategory("music",     "Music",      "music",       2, "From Bach to beats."),
        new TriviaCategory("sports",    "Sports",     "sportscourt", 1, "Games and the greats."),
        new TriviaCategory("business",  "Business",   "building2",   3, "Companies and the brands behind them."),
    };

    public static TriviaCategory Named(string id) => All.FirstOrDefault(c => c.Id == id) ?? All[0];
}
