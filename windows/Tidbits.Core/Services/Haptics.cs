namespace Tidbits.Core.Services;

/// Tactile feedback — a no-op on Windows desktop (no haptics engine). Kept as the
/// exact call surface the GameEngine uses so the engine ports unchanged. (Could
/// later map to subtle system sounds; not parity-critical.)
public static class Haptics
{
    public static void Correct() { }
    public static void Wrong() { }
    public static void Success() { }
    public static void Tap() { }
}
