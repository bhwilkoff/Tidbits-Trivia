using System;
using System.IO;
using System.Threading;
using Tidbits.App.Services;
using Xunit;

public class AvPlayerTest
{
    private readonly ITestOutputHelper _o;
    public AvPlayerTest(ITestOutputHelper o) => _o = o;

    /// Write a short 440Hz mono PCM WAV so we have a real clip to play.
    private static string WriteBeepWav()
    {
        int sampleRate = 8000, seconds = 1, n = sampleRate * seconds;
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-beep-{Guid.NewGuid():N}.wav");
        using var fs = new FileStream(path, FileMode.Create);
        using var w = new BinaryWriter(fs);
        int dataLen = n * 2;
        w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));
        w.Write(36 + dataLen);
        w.Write(System.Text.Encoding.ASCII.GetBytes("WAVE"));
        w.Write(System.Text.Encoding.ASCII.GetBytes("fmt "));
        w.Write(16); w.Write((short)1); w.Write((short)1);
        w.Write(sampleRate); w.Write(sampleRate * 2); w.Write((short)2); w.Write((short)16);
        w.Write(System.Text.Encoding.ASCII.GetBytes("data"));
        w.Write(dataLen);
        for (int i = 0; i < n; i++)
            w.Write((short)(Math.Sin(2 * Math.PI * 440 * i / sampleRate) * 12000));
        return path;
    }

    [Fact]
    public void LibVlc_initializes_and_accepts_a_clip()
    {
        using var av = new AvPlayer();
        _o.WriteLine($"AvPlayer.Available = {av.Available}");
        // VideoLAN.LibVLC.Mac ships x64-only, so LibVLC can't load on an arm64 Mac —
        // skip there. The win-x64 native IS bundled, so Windows CI (the ship target,
        // x64) exercises the real playback pipeline below.
        Assert.SkipUnless(av.Available, "LibVLC native not loadable on this arch (arm64 macOS is x64-only) — verified on Windows CI instead.");

        var wav = WriteBeepWav();
        try
        {
            // Play must not throw; give it a moment to spin up the pipeline.
            av.PlaySfx(wav);
            av.PlayBed(wav);
            av.SetBedVolume(50);
            Thread.Sleep(300);
            av.StopBed();

            // Output-device enumeration is available (empty is OK in a headless env).
            var devices = av.OutputDevices();
            _o.WriteLine($"output devices: {devices.Count}");
            Assert.NotNull(devices);
        }
        finally { if (File.Exists(wav)) File.Delete(wav); }
    }
}
