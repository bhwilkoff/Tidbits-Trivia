"""Prove the Mac app cannot demand a password at game start.

A trivia game asking for the login keychain password is the defect. This runs the
SAME launch-and-host flow against two builds and watches the screen for a
SecurityAgent window the whole time, because the only evidence that counts is
whether a dialog appears in front of a player.

Why an A/B and not a single run: the dialog is a ONE-TIME decision per signing
identity and its window is owned by SecurityAgent, so it outlives the app that
raised it. A single clean run proves nothing — it may only mean the machine
already answered. Running the known-bad build first re-establishes that the
detector works on this machine, and only then does a clean run mean something.

    python3 tools/mac_keychain_ab.py
"""
import subprocess
import sys
import time
from pathlib import Path

SHIPPED = "/Applications/TidbitsTrivia.app/Contents/MacOS/TidbitsTrivia"
FIXED = "build/dd-mac/Build/Products/Debug/TidbitsTrivia.app/Contents/MacOS/TidbitsTrivia"
WATCH_SECONDS = 45


def osa(script, timeout=20):
    return subprocess.run(["osascript", "-e", script], capture_output=True,
                          text=True, timeout=timeout)


def dialogs():
    r = osa('tell application "System Events" to count (every window of '
            '(every process whose name contains "SecurityAgent"))')
    try:
        return int(r.stdout.strip())
    except ValueError:
        return 0


def dismiss():
    osa('tell application "System Events"\n'
        '  repeat with p in (every process whose name contains "SecurityAgent")\n'
        '    repeat with w in windows of p\n'
        '      click button "Deny" of w\n'
        '    end repeat\n'
        '  end repeat\n'
        'end tell')


def quit_app():
    subprocess.run(["pkill", "-x", "TidbitsTrivia"], capture_output=True)
    time.sleep(2)


def trial(label, binary):
    quit_app()
    dismiss()
    time.sleep(2)
    if dialogs() != 0:
        print(f"  [{label}] could not clear the screen first — result would be meaningless")
        return None
    if not Path(binary).exists():
        print(f"  [{label}] {binary} missing — SKIP")
        return None

    # The exact thing a player does: open the app and start a game.
    subprocess.Popen(f"TIDBITS_LIVE_HOST=1 TIDBITS_LIVE_CODE=KCAB '{binary}' "
                     ">/dev/null 2>&1 &", shell=True)
    first = None
    for i in range(WATCH_SECONDS // 3):
        time.sleep(3)
        if dialogs() > 0 and first is None:
            first = (i + 1) * 3
    quit_app()
    dismiss()
    print(f"  [{label}] " + (f"PASSWORD DIALOG at t+{first}s" if first
                             else f"no dialog in {WATCH_SECONDS}s"))
    return first


def main():
    print("Launch + host a game, watching for a SecurityAgent password dialog.\n")
    # Known-bad first: if this does not raise a dialog, the detector is not
    # working on this machine and the clean run below proves nothing.
    bad = trial("shipped  (legacy keychain)", SHIPPED)
    good = trial("fixed    (data-protection)", FIXED)

    print()
    if good is not None:
        print(f"RESULT: STILL BROKEN — the fixed build prompted at t+{good}s")
        return 1
    if bad is not None:
        print(f"RESULT: FIXED — the shipped build prompts at t+{bad}s under this")
        print("        exact flow; the fixed build never does.")
        return 0
    # Neither prompted. That is NOT a pass: once the ACL question has been
    # answered on a machine (allowed or denied), the dialog never returns, so the
    # detector is disarmed and a quiet fixed build proves nothing on its own.
    print("RESULT: INCONCLUSIVE — the known-bad build did not prompt either, so")
    print("        this machine has already answered the ACL question and the")
    print("        detector is disarmed. A quiet run here is not evidence.")
    print("        The standing proof is the in-app measurement instead:")
    print("          TIDBITS_KEYCHAIN_DIAG=1 <app binary>")
    print("        Every query carries an LAContext with interactionNotAllowed, so")
    print("        any call that WOULD prompt reports -25308 rather than prompting.")
    return 2


if __name__ == "__main__":
    sys.exit(main())
