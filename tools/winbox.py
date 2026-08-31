"""Drive a real Windows 10/11 machine over SSH — the sixth device in the fleet.

Decision 045 said there is no Windows box, so `windows-latest` IS the box and
everything is observed through CI artifacts. That constraint is now lifted for
ITERATION: a real machine on the LAN can be deployed to, launched, and
photographed in the same loop as the Apple TV or the Pixel. CI stays the GATE —
"it works on the machine in the den" is not "it works on a clean runner" — but
the edit/see cycle no longer costs a push and a four-minute workflow.

The transport is OpenSSH with PUBLIC-KEY auth, deliberately:
  * it is the only Windows remote channel that gives a shell, file copy and
    PowerShell in one thing, from macOS, without extra software;
  * key auth means no password is ever typed, stored, or seen by this tooling.

Everything here mirrors the shape of macapp.py / adb_run.py so the harnesses
stay legible side by side: connect, deploy, launch, capture, quit.

    python3 tools/winbox.py --check          # is the box reachable?
    python3 tools/winbox.py --deploy         # publish + copy the app over
    python3 tools/winbox.py --shot out.png   # launch and photograph it
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

# Set TIDBITS_WIN_HOST=user@10.0.0.x to point at the machine. Kept in the
# environment rather than committed: it is a personal address, not a fact about
# the project, and it changes with DHCP.
HOST = os.environ.get("TIDBITS_WIN_HOST", "")
KEY = os.path.expanduser(os.environ.get("TIDBITS_WIN_KEY", "~/.ssh/tidbits_win"))
REMOTE = os.environ.get("TIDBITS_WIN_DIR", "C:/tidbits")
APP = "Tidbits.App.exe"

SSH_OPTS = ["-o", "BatchMode=yes",            # never prompt for a password
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=8"]


def _ssh(*args, timeout=120, check=False):
    if not HOST:
        raise RuntimeError("TIDBITS_WIN_HOST is not set (user@host)")
    cmd = ["ssh", "-i", KEY] + SSH_OPTS + [HOST] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"ssh failed ({r.returncode}): {r.stderr.strip()[:300]}")
    return r


def ps(script, timeout=180, check=False):
    """Run PowerShell on the box. -EncodedCommand avoids every layer of quoting
    between zsh, ssh, cmd.exe and PowerShell, which is otherwise a reliable
    source of silent misbehaviour."""
    import base64
    enc = base64.b64encode(script.encode("utf-16-le")).decode()
    return _ssh("powershell", "-NoProfile", "-NonInteractive",
                "-EncodedCommand", enc, timeout=timeout, check=check)


def check():
    """Prove the channel works and report what the box actually is."""
    if not HOST:
        return False, "TIDBITS_WIN_HOST is not set"
    if not Path(KEY).exists():
        return False, f"no private key at {KEY} — run --keygen first"
    r = ps("$o=Get-CimInstance Win32_OperatingSystem;"
           "\"$($o.Caption)|$($o.Version)|$env:COMPUTERNAME|"
           "$([Environment]::Is64BitOperatingSystem)\"", timeout=45)
    if r.returncode != 0:
        return False, r.stderr.strip()[:200] or "ssh failed"
    return True, r.stdout.strip()


def dotnet_present():
    r = ps("(Get-Command dotnet -ErrorAction SilentlyContinue).Source", timeout=60)
    return r.stdout.strip()


def publish(local_out="windows/publish/win-x64"):
    """Build on the MAC. The csproj already cross-publishes win-x64 (that is how
    the CI-only pipeline ever worked), so the Windows box does not need the SDK
    just to run the app."""
    r = subprocess.run(
        ["dotnet", "publish", "Tidbits.App/Tidbits.App.csproj", "-c", "Release",
         "-r", "win-x64", "--self-contained", "-p:PublishSingleFile=true",
         "-o", f"../{local_out.split('/', 1)[1]}" if local_out.startswith("windows/") else local_out],
        cwd="windows", capture_output=True, text=True, timeout=1800)
    return r.returncode == 0, (r.stdout + r.stderr)[-1200:]


def deploy(local_out="windows/publish/win-x64"):
    """Copy the published app over. scp of a directory is one round trip and is
    far quicker than the obvious per-file loop."""
    src = Path(local_out)
    if not src.exists():
        return False, f"{src} does not exist — publish first"
    ps(f"New-Item -ItemType Directory -Force -Path '{REMOTE}' | Out-Null", timeout=60)
    r = subprocess.run(["scp", "-i", KEY] + SSH_OPTS + ["-r", str(src) + "/.",
                        f"{HOST}:{REMOTE}/"], capture_output=True, text=True, timeout=1800)
    return r.returncode == 0, r.stderr.strip()[:400]


def launch(env=None, wait=10):
    """Start the app and return its pid, or None. Env vars are set INSIDE the
    same PowerShell process so the TIDBITS_* hooks reach the app the same way
    they do on every other platform."""
    sets = "\n".join(f"$env:{k}='{v}'" for k, v in (env or {}).items())
    r = ps(f"""
{sets}
Get-Process Tidbits.App -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$p = Start-Process -FilePath '{REMOTE}/{APP}' -PassThru
Start-Sleep -Seconds {wait}
if ($p.HasExited) {{ "EXITED:$($p.ExitCode)" }} else {{ "PID:$($p.Id)" }}
""", timeout=180)
    out = r.stdout.strip()
    if out.startswith("PID:"):
        return int(out.split(":", 1)[1])
    return None


def screenshot(local_path, remote_name="tidbits-shot.png"):
    """Photograph the desktop and bring the PNG back.

    The whole screen, not the window: same reasoning as the Mac, where a
    window-region grab kept catching whatever was in front. What the machine is
    showing is the evidence."""
    remote = f"{REMOTE}/{remote_name}"
    r = ps(f"""
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save('{remote}')
"$($b.Width)x$($b.Height)"
""", timeout=120)
    if r.returncode != 0:
        return False, r.stderr.strip()[:200]
    got = subprocess.run(["scp", "-i", KEY] + SSH_OPTS +
                         [f"{HOST}:{remote}", str(local_path)],
                         capture_output=True, text=True, timeout=300)
    return got.returncode == 0, r.stdout.strip()


def quit_app():
    ps("Get-Process Tidbits.App -ErrorAction SilentlyContinue | Stop-Process -Force",
       timeout=60)


def keygen():
    """A dedicated keypair for this box. Never reuses a personal key, and the
    private half never leaves this machine."""
    k = Path(KEY)
    if k.exists():
        return k.with_suffix(".pub").read_text().strip()
    k.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ssh-keygen", "-t", "ed25519", "-f", str(k), "-N", "",
                    "-C", "tidbits-win-harness"], capture_output=True, timeout=60)
    return k.with_suffix(".pub").read_text().strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--keygen", action="store_true")
    ap.add_argument("--publish", action="store_true")
    ap.add_argument("--deploy", action="store_true")
    ap.add_argument("--shot")
    a = ap.parse_args()

    if a.keygen:
        print(keygen())
        return 0
    if a.check:
        ok, why = check()
        print(("  OK    " if ok else "  FAIL  ") + why)
        if ok:
            d = dotnet_present()
            print(f"  dotnet on the box: {d or '(absent — fine, the app is self-contained)'}")
        return 0 if ok else 1
    if a.publish:
        ok, log = publish()
        print("  publish:", "ok" if ok else "FAILED")
        if not ok:
            print(log)
        return 0 if ok else 1
    if a.deploy:
        ok, err = deploy()
        print("  deploy:", "ok" if ok else f"FAILED — {err}")
        return 0 if ok else 1
    if a.shot:
        pid = launch()
        print("  launched pid:", pid)
        ok, size = screenshot(a.shot)
        print("  screenshot:", f"{a.shot} ({size})" if ok else f"FAILED — {size}")
        quit_app()
        return 0 if ok else 1
    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
