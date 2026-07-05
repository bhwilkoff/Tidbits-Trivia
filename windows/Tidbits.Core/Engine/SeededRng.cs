using System.Text;

namespace Tidbits.Core.Engine;

/// Deterministic splitmix64 RNG (port of Core/Engine/SeededRNG.swift). `unchecked`
/// + `ulong` mirrors Swift's wrapping `&+`/`&*` exactly, so distractor selection
/// and any seeded shuffle reproduce bit-for-bit across platforms.
public struct SeededRng
{
    private ulong _state;

    public SeededRng(ulong seed)
    {
        unchecked { _state = seed + 0x9E3779B97F4A7C15UL; }
    }

    public ulong Next()
    {
        unchecked
        {
            _state += 0x9E3779B97F4A7C15UL;
            var z = _state;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            return z ^ (z >> 31);
        }
    }
}

public static class StableSeed
{
    /// FNV-1a 64-bit over UTF-8 bytes — reproducible across launches/platforms
    /// (unlike a per-run-salted hash). Byte-exact with the Swift/Kotlin/JS twins.
    public static ulong Of(string s)
    {
        unchecked
        {
            ulong hash = 0xCBF29CE484222325UL;
            foreach (var b in Encoding.UTF8.GetBytes(s))
                hash = (hash ^ b) * 0x100000001B3UL;
            return hash;
        }
    }
}

/// Compares strings by their UTF-8 byte sequences (Swift's
/// `String.utf8.lexicographicallyPrecedes`) — NOT UTF-16 code units, so it stays
/// byte-exact for non-ASCII. Used for platform-agnostic tie-breaks.
public sealed class Utf8Ordinal : IComparer<string>
{
    public static readonly Utf8Ordinal Instance = new();

    public int Compare(string? x, string? y)
    {
        var bx = Encoding.UTF8.GetBytes(x ?? "");
        var by = Encoding.UTF8.GetBytes(y ?? "");
        int n = Math.Min(bx.Length, by.Length);
        for (int i = 0; i < n; i++)
            if (bx[i] != by[i]) return bx[i].CompareTo(by[i]); // byte = unsigned, matches Swift UInt8
        return bx.Length.CompareTo(by.Length);
    }
}
