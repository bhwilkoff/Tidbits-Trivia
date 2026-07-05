using System.IO;
using Avalonia.Media.Imaging;
using QRCoder;

namespace Tidbits.App.Services;

/// Generates a QR code as an Avalonia Bitmap (QRCoder's PngByteQRCode — pure C#, no
/// System.Drawing / native deps, so it cross-builds clean).
public static class QrHelper
{
    public static Bitmap Generate(string text, int pixelsPerModule = 8)
    {
        using var generator = new QRCodeGenerator();
        using var data = generator.CreateQrCode(text, QRCodeGenerator.ECCLevel.M);
        var png = new PngByteQRCode(data).GetGraphic(pixelsPerModule);
        return new Bitmap(new MemoryStream(png));
    }

    /// The canonical join URL — the web app's live target (every code has an https twin).
    public static string JoinUrl(string code) => $"https://tidbitstrivia.com/live/{code}";
}
