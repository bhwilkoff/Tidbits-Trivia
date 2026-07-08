using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace Tidbits.Core.Networking;

/// The private "people you played with" friend list (L5 social graph). Local-only
/// (mirrors the owner-only playersPrivate bucket on the other platforms), JSON-backed,
/// deduped by uid.
public sealed class FriendStore
{
    private readonly string _path;
    private List<PlayerIdentity.Friend> _friends = new();

    public FriendStore(string path)
    {
        _path = path;
        try
        {
            if (System.IO.File.Exists(path))
                _friends = JsonSerializer.Deserialize<List<PlayerIdentity.Friend>>(System.IO.File.ReadAllText(path)) ?? new();
        }
        catch { _friends = new(); }
    }

    public IReadOnlyList<PlayerIdentity.Friend> All => _friends;
    public bool Contains(string uid) => _friends.Any(f => f.Uid == uid);

    /// Add a friend (no-op if already present or self/empty uid).
    public void Add(PlayerIdentity.Friend friend)
    {
        if (string.IsNullOrEmpty(friend.Uid) || Contains(friend.Uid)) return;
        _friends.Add(friend);
        Persist();
    }

    public void Remove(string uid)
    {
        _friends.RemoveAll(f => f.Uid == uid);
        Persist();
    }

    private void Persist()
    {
        try
        {
            var dir = System.IO.Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) System.IO.Directory.CreateDirectory(dir);
            System.IO.File.WriteAllText(_path, JsonSerializer.Serialize(_friends));
        }
        catch { /* best-effort */ }
    }
}
