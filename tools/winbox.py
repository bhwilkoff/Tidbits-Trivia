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
# HOME-RELATIVE, not "C:/tidbits". scp mangles a Windows drive letter in the
# destination — "C:/tidbits/" arrives as "/C:/tidbits/" and dest open fails — so
# the transfer target is relative to the ssh user's home and PowerShell resolves
# the absolute form itself.
REMOTE_REL = os.environ.get("TIDBITS_WIN_DIR", "tidbits")
_REMOTE_ABS = None


def remote_dir():
    """The absolute deploy path, resolved once and cached as a LITERAL.

    Every PowerShell string here is single-quoted so the script survives the trip
    through zsh/ssh intact — which also means "$env:USERPROFILE\tidbits" would
    never expand. Ask the box once, then interpolate the real path.
    """
    global _REMOTE_ABS
    if _REMOTE_ABS is None:
        r = ps('(Join-Path $env:USERPROFILE "' + REMOTE_REL + '")', timeout=45)
        got = r.stdout.strip()
        if not got:
            raise RuntimeError("could not resolve the remote dir: "
                               + _clean(r.stderr)[:200])
        _REMOTE_ABS = got.replace("\\", "/")
    return _REMOTE_ABS
APP = "Tidbits.App.exe"

SSH_OPTS = ["-o", "BatchMode=yes",            # never prompt for a password
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=8"]


def _clean(err):
    """OpenSSH prints a multi-line post-quantum advisory and a known-hosts notice
    on stderr that are not errors. They pushed the ACTUAL failure
    ("Permission denied (publickey)") out of a truncated view, which is exactly
    the kind of noise that makes a real message unreadable."""
    drop = ("post-quantum", "store now", "Permanently added", "This session may be")
    keep = [l for l in (err or "").splitlines()
            if l.strip() and not l.startswith("**") and not any(d in l for d in drop)]
    return "\n".join(keep).strip()


def _ssh(*args, timeout=120, check=False):
    if not HOST:
        raise RuntimeError("TIDBITS_WIN_HOST is not set (user@host)")
    cmd = ["ssh", "-i", KEY] + SSH_OPTS + [HOST] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"ssh failed ({r.returncode}): {_clean(r.stderr)[:300]}")
    return r


def ps(script, timeout=180, check=False):
    """Run PowerShell on the box. -EncodedCommand avoids every layer of quoting
    between zsh, ssh, cmd.exe and PowerShell, which is otherwise a reliable
    source of silent misbehaviour."""
    import base64
    # $ProgressPreference: PowerShell serialises its progress stream to stderr as
    # CLIXML over ssh ("Preparing modules for first use…"), which buries the
    # actual error under a wall of XML. Errors are caught and printed as plain
    # text for the same reason — a readable failure beats a serialised object.
    wrapped = ("$ProgressPreference='SilentlyContinue'\n"
               "try {\n" + script + "\n} catch { \"PSERROR: $($_.Exception.Message)\" }")
    enc = base64.b64encode(wrapped.encode("utf-16-le")).decode()
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
        err = _clean(r.stderr)
        if "Permission denied" in err:
            err += ("  — the key is not installed yet. For an ADMIN account it must go in "
                    "C:\\ProgramData\\ssh\\administrators_authorized_keys, not ~/.ssh/authorized_keys")
        return False, err[:280] or "ssh failed"
    return True, r.stdout.strip()


def dotnet_present():
    r = ps("(Get-Command dotnet -ErrorAction SilentlyContinue).Source", timeout=60)
    return r.stdout.strip()


def publish(local_out="windows/publish/win-x64"):
    """Build on the MAC. The csproj already cross-publishes win-x64 (that is how
    the CI-only pipeline ever worked), so the Windows box does not need the SDK
    just to run the app."""
    # cwd is already `windows`, so the output path is relative to THAT. An
    # earlier "../publish/win-x64" wrote a stray tree at the repo root while the
    # deploy kept shipping the old one — and `dotnet publish` reported success
    # the whole time, because it had genuinely published, just somewhere else.
    out_rel = local_out[len("windows/"):] if local_out.startswith("windows/") else local_out
    r = subprocess.run(
        ["dotnet", "publish", "Tidbits.App/Tidbits.App.csproj", "-c", "Release",
         "-r", "win-x64", "--self-contained", "-p:PublishSingleFile=true",
         "-o", out_rel],
        cwd="windows", capture_output=True, text=True, timeout=1800)
    ok = r.returncode == 0
    # "publish: ok" must mean the artifact MOVED. It did not, twice.
    if ok:
        exe = Path(local_out) / APP
        if not exe.exists():
            return False, f"publish reported success but {exe} does not exist"
    return ok, (r.stdout + r.stderr)[-1200:]


def deploy(local_out="windows/publish/win-x64"):
    """Copy the published app over. scp of a directory is one round trip and is
    far quicker than the obvious per-file loop."""
    src = Path(local_out)
    if not src.exists():
        return False, f"{src} does not exist — publish first"

    # Refuse to ship a build older than the source. Twice today a stale bundle
    # was deployed and the app was then blamed for "ignoring" a hook it had never
    # been compiled with — once on the Apple TV (a six-day-old Release bundle),
    # once here (a publish 40 minutes older than the edit). The timestamps knew;
    # nothing was checking them.
    exe = src / APP
    if exe.exists():
        newest, newest_f = 0.0, None
        for f in Path("windows").rglob("*"):
            if f.suffix in (".cs", ".axaml", ".csproj") and "/publish/" not in str(f) \
               and "/bin/" not in str(f) and "/obj/" not in str(f):
                m = f.stat().st_mtime
                if m > newest:
                    newest, newest_f = m, f
        if newest > exe.stat().st_mtime:
            import datetime as _dt
            fmt = lambda t: _dt.datetime.fromtimestamp(t).strftime("%H:%M:%S")
            return False, (f"STALE BUILD: {APP} is {fmt(exe.stat().st_mtime)} but "
                           f"{newest_f.name} changed at {fmt(newest)} — run --publish first")
    ps(f"New-Item -ItemType Directory -Force -Path '{remote_dir()}' | Out-Null", timeout=60)
    quit_app()          # a running app holds its own files open
    r = subprocess.run(["scp", "-i", KEY] + SSH_OPTS + ["-r", str(src) + "/.",
                        f"{HOST}:{REMOTE_REL}/"], capture_output=True, text=True, timeout=1800)
    return r.returncode == 0, r.stderr.strip()[:400]


def run_in_console(script, name="TidbitsHarness", timeout=240):
    """Run PowerShell in the INTERACTIVE console session, not the SSH session.

    This is the load-bearing piece of the whole Windows harness. An SSH session
    on Windows is **session 0** — the services session, with no visible desktop.
    Measured on this box: ssh lands in session 0 while the logged-in user is
    session 1, and `Screen.PrimaryScreen.Bounds` from session 0 reports a phantom
    1024x768 while the real display is 1920x1080. So a GUI app started over ssh
    launches where nobody can see it, and a screenshot taken over ssh photographs
    a blank virtual desktop. The first capture off this box was a pure white
    1024x768 frame for exactly that reason.

    A scheduled task with an Interactive principal runs in the user's real
    session. It needs nothing downloaded — no PsExec — and works on stock
    Windows 10.
    """
    remote_ps1 = f"{remote_dir()}/_task.ps1"
    # Write the script to the box, then run it as an interactive task.
    import base64
    b64 = base64.b64encode(script.encode("utf-8")).decode()
    setup = rf"""
New-Item -ItemType Directory -Force -Path '{remote_dir()}' | Out-Null
[IO.File]::WriteAllBytes('{remote_ps1}', [Convert]::FromBase64String('{b64}'))
Unregister-ScheduledTask -TaskName '{name}' -Confirm:$false -ErrorAction SilentlyContinue
$a = New-ScheduledTaskAction -Execute 'powershell.exe' `
     -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{remote_ps1}"'
# whoami, NOT $env:USERDOMAIN\$env:USERNAME. On a workgroup machine
# USERDOMAIN is literally "WORKGROUP", so that form yields WORKGROUP\benwi,
# which has no SID and fails with "No mapping between account names and
# security IDs was done" — an error that names the symptom, not the cause.
$p = New-ScheduledTaskPrincipal -UserId (whoami) -LogonType Interactive
Register-ScheduledTask -TaskName '{name}' -Action $a -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName '{name}'
$deadline = (Get-Date).AddSeconds({timeout - 20})
do {{
  Start-Sleep -Seconds 2
  $st = (Get-ScheduledTask -TaskName '{name}').State
}} while ($st -eq 'Running' -and (Get-Date) -lt $deadline)
$info = Get-ScheduledTaskInfo -TaskName '{name}'
Unregister-ScheduledTask -TaskName '{name}' -Confirm:$false -ErrorAction SilentlyContinue
"TASKRESULT:$($info.LastTaskResult)"
"""
    return ps(setup, timeout=timeout)


def session_locked():
    """Is the console session showing the lock screen?

    LogonUI.exe is present exactly while the workstation is locked. This matters
    because a locked session still runs interactive tasks — so a capture would
    quietly return a photograph of the LOCK SCREEN and every OCR assertion would
    be about that, not the app. Reported as a fact, never guessed at."""
    r = ps("if (Get-Process LogonUI -ErrorAction SilentlyContinue) { 'LOCKED' } "
           "else { 'UNLOCKED' }", timeout=60)
    return r.stdout.strip().startswith("LOCKED")


def keep_awake():
    """Reset the idle timer without changing any of the machine's settings.

    The box locks quickly. Rather than editing the owner's screensaver or power
    policy — which would outlive the test run — this presses a key Windows
    ignores (F15 has no effect on any app but does count as input) inside the
    console session."""
    return run_in_console(
        "$w = New-Object -ComObject WScript.Shell; $w.SendKeys('{F15}')",
        name="TidbitsAwake", timeout=90)


def launch(env=None, wait=10):
    """Start the app and return its pid, or None. Env vars are set INSIDE the
    same PowerShell process so the TIDBITS_* hooks reach the app the same way
    they do on every other platform."""
    sets = "\n".join(f"$env:{k}='{v}'" for k, v in (env or {}).items())
    run_in_console(f"""
{sets}
Get-Process Tidbits.App -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
$p = Start-Process -FilePath '{remote_dir()}/{APP}' -PassThru
Start-Sleep -Seconds {wait}
"$($p.Id)|$($p.HasExited)" | Out-File -Encoding ascii '{remote_dir()}/_launch.txt'
""", name="TidbitsLaunch", timeout=max(120, wait * 6))
    r = ps(f"Get-Content '{remote_dir()}/_launch.txt' -ErrorAction SilentlyContinue", timeout=60)
    out = r.stdout.strip()
    if "|" in out:
        pid, exited = out.split("|", 1)
        if exited.strip().lower().startswith("false"):
            return int(pid)
    return None


def window_rect():
    """The app window's bounds as normalised (x, y, w, h) of the screen, or None.

    MUST run in the interactive session. Asked over ssh, `MainWindowHandle` comes
    back as 0 — a session-0 process cannot see a session-1 window handle, the same
    root cause as the phantom 1024x768 desktop. It does not error; it reports zero,
    which reads as "the app has no window".

    Why scope to the window at all: the capture is deliberately the WHOLE desktop (a
    window-region grab on the Mac kept photographing whatever was in front, and what
    the machine is showing is the evidence). But grading the whole desktop means
    grading the owner's desktop — the first clean sweep failed `no_clipped_text` on
    "Roblox Player", a truncated ICON LABEL behind the app. A defect reported against
    someone's desktop shortcut is worse than no check at all. So: photograph
    everything, assert inside the window.

    Deliberately its OWN console task rather than folded into `screenshot_series`.
    Fusing them cost a round trip but broke the capture outright — frames stopped
    coming back — and a working rect is not worth an unreliable photograph. Callers
    read it once per sweep: the window opens at the same place every launch.
    """
    rd = remote_dir()
    run_in_console(f"""
Add-Type -AssemblyName System.Windows.Forms
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Add-Type @'
using System;using System.Runtime.InteropServices;
public struct TbR {{ public int L,T,Rr,B; }}
public class TbW {{
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out TbR r);
}}
'@
$proc = Get-Process Tidbits.App -ErrorAction SilentlyContinue |
        Where-Object {{ $_.MainWindowHandle -ne 0 }} | Select-Object -First 1
if ($proc) {{
  $wr = New-Object TbR
  [void][TbW]::GetWindowRect($proc.MainWindowHandle, [ref]$wr)
  "$($wr.L) $($wr.T) $($wr.Rr) $($wr.B) $($b.Width) $($b.Height)" |
    Out-File -Encoding ascii '{rd}/_rect.txt'
}} else {{
  Remove-Item '{rd}/_rect.txt' -ErrorAction SilentlyContinue
}}
""", name="TidbitsRect", timeout=110)
    r = ps(f"Get-Content '{rd}/_rect.txt' -ErrorAction SilentlyContinue", timeout=60)
    parts = _clean(r.stdout).split()
    if r.returncode != 0 or len(parts) != 6:
        return None
    try:
        l, t, rr, bb, sw, sh = (int(v) for v in parts)
    except ValueError:
        return None
    if sw <= 0 or sh <= 0 or rr <= l or bb <= t:
        return None
    return (l / sw, t / sh, (rr - l) / sw, (bb - t) / sh)


def screenshot_series(local_paths, gap=6, prefix="frame"):
    """Capture several frames over time in ONE console round trip.

    Each `run_in_console` costs ~35s of scheduled-task ceremony (register, start,
    poll at 2s granularity, unregister) while the capture itself is milliseconds. So
    N separate screenshots pay N x 35s of overhead to photograph something that took
    N x `gap` seconds to happen. Two frames per scenario is what made a six-scenario
    sweep take thirteen silent minutes and read as a hang — I killed it twice
    believing it was stuck.

    Batching also makes the frames mean more: the gaps are timed ON THE BOX by one
    script, rather than being whatever the network and the task scheduler added
    between separate calls.
    """
    keep_awake()
    if session_locked():
        return [], ("the console session is LOCKED — a capture here would be the "
                    "lock screen, not the app. Unlock the machine to see the UI.")
    n = len(local_paths)
    rd = remote_dir()
    # Clear last run's outputs FIRST. A script that dies early otherwise leaves the
    # previous run's files in place and the harness reads them as THIS run's result —
    # which is how a capture that produced no frames still reported a screen size.
    ps(f"Remove-Item '{rd}/_shot.txt' -ErrorAction SilentlyContinue; "
       f"Remove-Item '{rd}/{prefix}-*.png' -ErrorAction SilentlyContinue", timeout=45)
    run_in_console(f"""
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
for ($i = 0; $i -lt {n}; $i++) {{
  if ($i -gt 0) {{ Start-Sleep -Seconds {gap} }}
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bmp.Save("{rd}/{prefix}-$i.png")
  $g.Dispose(); $bmp.Dispose()
}}
"$($b.Width)x$($b.Height)" | Out-File -Encoding ascii '{rd}/_shot.txt'
""", name="TidbitsShots", timeout=120 + n * (gap + 4))
    r = ps(f"Get-Content '{rd}/_shot.txt' -ErrorAction SilentlyContinue", timeout=60)
    size = _clean(r.stdout).strip() or "?"
    got = []
    for i, lp in enumerate(local_paths):
        rc = subprocess.run(["scp", "-i", KEY] + SSH_OPTS +
                            [f"{HOST}:{rd}/{prefix}-{i}.png", str(lp)],
                            capture_output=True, text=True, timeout=120)
        if rc.returncode == 0 and Path(lp).exists():
            got.append(lp)
    return got, size


def screenshot(local_path, remote_name="tidbits-shot.png"):
    """Photograph the desktop and bring the PNG back.

    The whole screen, not the window: same reasoning as the Mac, where a
    window-region grab kept catching whatever was in front. What the machine is
    showing is the evidence."""
    # Nudge the idle timer first. This box locks quickly, and a sweep that spans
    # several scenarios would otherwise lock partway through and every capture
    # after that point would be refused.
    keep_awake()
    if session_locked():
        # Unlocking needs the account password, which this tooling must never
        # handle. So this is a hard limit, and it is reported as one instead of
        # returning a photograph of the lock screen for the grader to analyse.
        return False, ("the console session is LOCKED — a capture here would be the "
                       "lock screen, not the app. Unlock the machine to see the UI.")
    remote = f"{remote_dir()}/{remote_name}"
    # In the CONSOLE session — from ssh (session 0) this captures a phantom
    # 1024x768 desktop instead of the real 1920x1080 screen.
    # Clear last run's outputs FIRST. A script that dies early otherwise leaves the
    # previous run's files in place and the harness reads them as THIS run's result —
    # which is how a capture that produced no frames still reported a screen size.
    ps(f"Remove-Item '{rd}/_shot.txt' -ErrorAction SilentlyContinue; "
       f"Remove-Item '{rd}/{prefix}-*.png' -ErrorAction SilentlyContinue", timeout=45)
    run_in_console(f"""
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save('{remote}')
"$($b.Width)x$($b.Height)" | Out-File -Encoding ascii '{remote_dir()}/_shot.txt'
""", name="TidbitsShot", timeout=150)
    r = ps(f"Get-Content '{remote_dir()}/_shot.txt' -ErrorAction SilentlyContinue", timeout=60)
    if r.returncode != 0:
        return False, _clean(r.stderr)[:200]
    got = subprocess.run(["scp", "-i", KEY] + SSH_OPTS +
                         [f"{HOST}:{remote}", str(local_path)],
                         capture_output=True, text=True, timeout=300)
    return got.returncode == 0, r.stdout.strip()


def quit_app():
    run_in_console("Get-Process Tidbits.App -ErrorAction SilentlyContinue | "
                   "Stop-Process -Force", name="TidbitsQuit", timeout=90)


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
