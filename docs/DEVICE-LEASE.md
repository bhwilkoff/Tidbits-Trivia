# Sharing the device bench between two agent sessions

Two Claude Code sessions were driving the **same physical devices** from different
repos — this one and an Archive Watch session. Neither knew the other existed.

What that looked like from inside each session:

- Each kept finding the other's app in the foreground and graded it as its own app
  failing to stay on screen.
- Each force-stopped the other's app, because "reset every device to a clean state
  before a test" is the correct thing to do when you are the only one on the bench.
- This harness spent four rounds of increasingly clever recovery logic — re-launch,
  re-foreground, rejoin, poll — getting better and better at fighting a peer it had
  no idea was there.

The devices were never the problem and neither app was broken. Two owners, no
protocol.

## The protocol

No shared memory is needed — only a shared filesystem and an agreed convention.

```
~/.device-lease/<device>.json
  {"owner": "...", "pid": 123, "task": "...", "acquired": ..., "expires": ...}
```

Four rules:

1. **Take a lease before touching a device; release it after.**
2. **A lease has a TTL** (default 15 min). A crashed session must not hold a device
   forever, and nobody should have to ask a human to break a lock.
3. **Never steal a live lease.** Wait, or skip the device and say the run did not
   cover it. A skipped device reported honestly beats a contended device reported
   as a product failure — which is exactly the mistake this replaces.
4. **Read a foreign lease to find out who holds it**, so a message can name the
   peer instead of blaming the app.

## Using it

`tools/devlease.py` is stdlib-only and has nothing in it specific to this repo.
Copy it, or point at it directly — it takes its identity from the environment:

```bash
export DEVICE_LEASE_OWNER=archive-watch      # defaults to "tidbits-trivia"
export DEVICE_LEASE_DIR=~/.device-lease      # the shared default
```

```python
import devlease

with devlease.lease("firetv", task="archive watch sweep", wait=60):
    ...                                      # the device is yours for the block

ok, holder = devlease.try_lease("androidtv", task="...")
if not ok:
    print(f"skipping androidtv — {holder}")  # names the peer, its pid and its task
```

Inspect or clear from a shell:

```bash
python3 tools/devlease.py                    # who holds what, and for how long
python3 tools/devlease.py release-all        # releases only leases THIS pid owns
```

## Device names

Shared across both sessions, so the two agree on what they are contending for:

`ipad` · `iphone` · `atv` · `pixel` · `firetv` · `androidtv` · `mac` · `windows` · `web`

## What it does not solve

A lease is cooperative. A tool that does not take one can still walk over a device
mid-run — the lease makes that *visible* (the run reports which device it could not
cover, and why) rather than preventing it. Both sides have to opt in, which is the
cost of not needing a daemon, a broker, or root.
