namespace Tidbits.Core.Networking;

/// Persists the anonymous refresh token so the uid (hence the portable profile)
/// survives relaunches. (Windows DPAPI/Credential-Manager encryption is a tracked
/// hardening follow-up — parity item 1.22; the default here is a plain file.)
public interface ITokenStore
{
    string? Get(string key);
    void Set(string key, string value);
    void Delete(string key);
}

public sealed class FileTokenStore : ITokenStore
{
    private readonly string _dir;

    public FileTokenStore(string? dir = null) =>
        _dir = dir ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TidbitsTrivia", "tokens");

    private string PathFor(string key) => Path.Combine(_dir, key + ".txt");

    public string? Get(string key)
    {
        try { var p = PathFor(key); return File.Exists(p) ? File.ReadAllText(p) : null; }
        catch { return null; }
    }

    public void Set(string key, string value)
    {
        try { Directory.CreateDirectory(_dir); File.WriteAllText(PathFor(key), value); } catch { }
    }

    public void Delete(string key)
    {
        try { var p = PathFor(key); if (File.Exists(p)) File.Delete(p); } catch { }
    }
}

/// A no-op token store (tests / ephemeral sessions).
public sealed class MemoryTokenStore : ITokenStore
{
    private readonly Dictionary<string, string> _m = new();
    public string? Get(string key) => _m.GetValueOrDefault(key);
    public void Set(string key, string value) => _m[key] = value;
    public void Delete(string key) => _m.Remove(key);
}
