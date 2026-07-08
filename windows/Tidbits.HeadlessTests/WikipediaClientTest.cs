using Tidbits.Core.Networking;
using Xunit;

public class WikipediaClientTest
{
    [Fact]
    public void Parses_a_rest_summary()
    {
        // A trimmed real /page/summary/{title} shape.
        const string json = """
        {
          "type": "standard",
          "title": "Ada Lovelace",
          "description": "English mathematician (1815–1852)",
          "extract": "Augusta Ada King, Countess of Lovelace, was an English mathematician and writer, chiefly known for her work on Charles Babbage's Analytical Engine.",
          "thumbnail": { "source": "https://upload.wikimedia.org/ada.jpg" },
          "content_urls": { "desktop": { "page": "https://en.wikipedia.org/wiki/Ada_Lovelace" } }
        }
        """;
        var s = WikipediaClient.Parse(json);
        Assert.NotNull(s);
        Assert.Equal("Ada Lovelace", s!.Title);
        Assert.Equal("standard", s.Type);
        Assert.Equal("English mathematician (1815–1852)", s.Description);
        Assert.Contains("Analytical Engine", s.Extract);
        Assert.Equal("https://en.wikipedia.org/wiki/Ada_Lovelace", s.PageUrl);
        Assert.Equal("https://upload.wikimedia.org/ada.jpg", s.ImageUrl);
    }

    [Fact]
    public void Parses_action_search_titles()
    {
        const string json = """
        { "query": { "search": [ { "title": "Renaissance" }, { "title": "Italian Renaissance" } ] } }
        """;
        var titles = WikipediaClient.ParseSearch(json);
        Assert.Equal(new[] { "Renaissance", "Italian Renaissance" }, titles);
    }

    [Fact]
    public void Malformed_bodies_degrade_to_empty()
    {
        Assert.Null(WikipediaClient.Parse("not json"));
        Assert.Empty(WikipediaClient.ParseSearch("{ oops"));
    }
}
