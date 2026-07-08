using Avalonia.Input;

namespace Tidbits.App.Services;

/// Host cockpit action a key maps to (the "keyboard cockpit" — run the show
/// without the mouse). Pure so the mapping is unit-testable.
public enum CockpitAction { None, Reveal, Next, Back, Skip, Lock }

public static class CockpitKeymap
{
    /// Space/Enter/→ advances the show (Reveal, then Next once revealed); ← steps
    /// back; ↓ / S skips; L locks.
    public static CockpitAction Resolve(Key key, bool revealed) => key switch
    {
        Key.Space or Key.Enter or Key.Right => revealed ? CockpitAction.Next : CockpitAction.Reveal,
        Key.Left => CockpitAction.Back,
        Key.Down or Key.S => CockpitAction.Skip,
        Key.L => CockpitAction.Lock,
        _ => CockpitAction.None,
    };
}
