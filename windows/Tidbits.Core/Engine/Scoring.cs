namespace Tidbits.Core.Engine;

/// Speed-aware scoring (port of Core/Engine/Scoring.swift). Base points + a speed
/// bonus that rewards but never requires quickness + a bounded streak multiplier
/// (a hot run feels hot, capped so it stays a thrill not a runaway). Int casts
/// truncate toward zero, matching Swift's `Int(...)`.
public static class Scoring
{
    public const int Base = 100;
    public const int MaxSpeedBonus = 100;
    public const double StreakStep = 0.1;        // +10% per consecutive correct
    public const double MaxStreakMultiplier = 2.0;

    public static int Points(bool correct, double secondsTaken, double budget, int streak)
    {
        if (!correct) return 0;
        var speedFraction = Math.Max(0, Math.Min(1, 1 - secondsTaken / Math.Max(budget, 0.001)));
        var speed = (int)(MaxSpeedBonus * speedFraction);
        var mult = Math.Min(MaxStreakMultiplier, 1 + Math.Max(0, streak - 1) * StreakStep);
        return (int)((Base + speed) * mult);
    }
}
