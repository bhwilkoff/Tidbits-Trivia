using System;
using System.Collections.Generic;
using System.Linq;
using LibVLCSharp.Shared;

namespace Tidbits.App.Services;

/// The Wave B audio/video engine (owner-chose LibVLCSharp — cross-platform, so
/// this is verifiable on the Mac). One shared LibVLC; separate MediaPlayers for
/// one-shot stingers (SFX board 3.30) vs a looping music bed (3.33) vs the
/// question clip (audio round 3.32 / video 3.34), so a stinger never cuts the bed.
public sealed class AvPlayer : IDisposable
{
    private static readonly Lazy<bool> Initialized = new(() =>
    {
        try { LibVLCSharp.Shared.Core.Initialize(); return true; } catch { return false; }
    });

    private readonly LibVLC? _vlc;
    private MediaPlayer? _sfx;   // one-shot effects
    private MediaPlayer? _bed;   // looping background bed
    private MediaPlayer? _clip;  // question audio/video

    public bool Available => _vlc is not null;

    public AvPlayer()
    {
        if (!Initialized.Value) return;
        try
        {
            _vlc = new LibVLC();
            _sfx = new MediaPlayer(_vlc);
            _bed = new MediaPlayer(_vlc);
            _clip = new MediaPlayer(_vlc);
        }
        catch { _vlc = null; }
    }

    /// Fire a one-shot effect (stops any previous stinger first).
    public void PlaySfx(string path) => PlayOn(_sfx, path, loop: false);

    /// Start/replace the looping music bed.
    public void PlayBed(string path) => PlayOn(_bed, path, loop: true);
    public void StopBed() => _bed?.Stop();
    public void SetBedVolume(int percent) { if (_bed is not null) _bed.Volume = Math.Clamp(percent, 0, 100); }

    /// Play the current question's audio or video clip.
    public void PlayClip(string path) => PlayOn(_clip, path, loop: false);
    public void StopClip() => _clip?.Stop();
    public void PauseClip() => _clip?.Pause();

    /// The video sink (bind to an Avalonia VideoView for video questions, 3.34).
    public MediaPlayer? ClipPlayer => _clip;

    private void PlayOn(MediaPlayer? mp, string path, bool loop)
    {
        if (_vlc is null || mp is null || string.IsNullOrEmpty(path)) return;
        try
        {
            var opts = loop ? new[] { "input-repeat=65535" } : Array.Empty<string>();
            var media = new Media(_vlc, new Uri(path), opts);
            mp.Play(media);
            media.Dispose();
        }
        catch { /* bad file / no device — never crash the show */ }
    }

    /// Output devices for PA routing (3.31) — id + human name. Empty if unavailable.
    public IReadOnlyList<(string Id, string Name)> OutputDevices()
    {
        if (_clip is null) return Array.Empty<(string, string)>();
        try { return _clip.AudioOutputDeviceEnum.Select(d => (d.DeviceIdentifier, d.Description)).ToList(); }
        catch { return Array.Empty<(string, string)>(); }
    }

    /// Route all channels to a specific output device (PA routing, 3.31).
    public void SetOutputDevice(string deviceId)
    {
        foreach (var mp in new[] { _sfx, _bed, _clip })
            try { mp?.SetOutputDevice(deviceId); } catch { }
    }

    public void Dispose()
    {
        _sfx?.Dispose(); _bed?.Dispose(); _clip?.Dispose(); _vlc?.Dispose();
    }
}
