using Avalonia.Input;
using Tidbits.App.Services;
using Xunit;

public class CockpitKeymapTest
{
    [Theory]
    // Advance keys: Reveal when not revealed, Next once revealed.
    [InlineData(Key.Space, false, CockpitAction.Reveal)]
    [InlineData(Key.Space, true, CockpitAction.Next)]
    [InlineData(Key.Enter, false, CockpitAction.Reveal)]
    [InlineData(Key.Right, true, CockpitAction.Next)]
    // Navigation / lock.
    [InlineData(Key.Left, false, CockpitAction.Back)]
    [InlineData(Key.Down, false, CockpitAction.Skip)]
    [InlineData(Key.S, false, CockpitAction.Skip)]
    [InlineData(Key.L, false, CockpitAction.Lock)]
    // Unmapped.
    [InlineData(Key.A, false, CockpitAction.None)]
    [InlineData(Key.Escape, true, CockpitAction.None)]
    public void Resolves_show_actions(Key key, bool revealed, CockpitAction expected)
    {
        Assert.Equal(expected, CockpitKeymap.Resolve(key, revealed));
    }
}
