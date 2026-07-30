using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Pass G of docs/WINDOWS-PARITY-AUDIT.md: an icon-only control with no accessible name is
/// invisible to Narrator. The audit found seven (▲ ▼ ✕ reorder/delete buttons) with nothing.
///
/// A source scan rather than a render: these controls are built in code-behind inside loops,
/// so there is no single view to instantiate, and the rule is about the SOURCE anyway —
/// "if you write Content = an icon, write a name next to it".
public class AccessibleNamesTest
{
    private static readonly Regex IconContent =
        new(@"Content\s*=\s*""(?<icon>[^""A-Za-z0-9]{1,3})""", RegexOptions.Compiled);

    [Fact]
    public void Icon_only_buttons_declare_an_automation_name()
    {
        var root = RepoRoot();
        var offenders = new List<string>();
        var appDir = Path.Combine(root, "windows", "Tidbits.App");
        var sources = Directory.EnumerateFiles(appDir, "*.cs", SearchOption.AllDirectories)
            .Concat(Directory.EnumerateFiles(appDir, "*.axaml", SearchOption.AllDirectories));
        foreach (var file in sources)
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") ||
                file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")) continue;
            var lines = File.ReadAllLines(file);
            for (int i = 0; i < lines.Length; i++)
            {
                var m = IconContent.Match(lines[i]);
                if (!m.Success) continue;
                // "▶ " + pad.Label is a labelled button, not an icon-only one.
                if (Regex.IsMatch(lines[i], @"Content\s*=\s*""[^""]*""\s*\+")) continue;
                // The name may be set on any nearby line (the control is usually named right
                // before or after its Click handler is wired).
                var window = string.Join('\n', lines.Skip(System.Math.Max(0, i - 4)).Take(10));
                if (!window.Contains("AutomationProperties.SetName")
                    && !window.Contains("AutomationProperties.Name"))
                    offenders.Add($"{Path.GetFileName(file)}:{i + 1}  {lines[i].Trim()}");
            }
        }
        Assert.True(offenders.Count == 0,
            "Icon-only control(s) with no AutomationProperties.Name — Narrator reads nothing:\n  "
            + string.Join("\n  ", offenders));
    }

    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(Directory.GetCurrentDirectory());
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "windows"))) dir = dir.Parent;
        Assert.NotNull(dir);
        return dir!.FullName;
    }
}
