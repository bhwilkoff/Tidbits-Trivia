#!/usr/bin/env python3
"""Prove the deployed `live/{code}` security rules against the REAL database.

The rules are the only thing standing between one pub table and another's answers,
and a rules file in the repo is not a rules file in production — this opens a
throwaway room with three anonymous identities (a host and two tables) and checks
each read and write from the outside, then tears the room down.

    python3 tools/rules_probe.py        # exits non-zero if any rule misbehaves

Run it after every `firebase deploy --only database`, and whenever a client starts
reading a new path.
"""
import random
import sys
import time
import urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import multiplayer_run as mr  # noqa: E402


def anon():
    d = mr.http('POST', f'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={mr.API_KEY}',
                {'returnSecureToken': True})
    return d['idToken'], d['localId']


def main() -> int:
    code = ''.join(random.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(4))
    host_tok, host_uid = anon()
    a_tok, a_uid = anon()
    b_tok, b_uid = anon()

    def allowed(method, path, tok, body=None):
        """True when the rules PERMIT it, False on a 401/403. Anything else is a real error."""
        try:
            mr.http(method, f'{mr.DB}/live/{code}{path}.json?auth={tok}', body)
            return True
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                return False
            raise

    now = int(time.time() * 1000)
    mr.http('PUT', f'{mr.DB}/live/{code}/meta.json?auth={host_tok}',
            {'host': host_uid, 'createdAt': now, 'name': 'Rules probe', 'venue': '', 'state': 'live'})
    mr.http('PUT', f'{mr.DB}/live/{code}/pub.json?auth={host_tok}',
            {'qid': 'r0q0', 'phase': 'question', 'prompt': 'Q?'})
    for tok, uid, name in ((a_tok, a_uid, 'Table A'), (b_tok, b_uid, 'Table B')):
        mr.http('PUT', f'{mr.DB}/live/{code}/teams/{uid}.json?auth={tok}', {'name': name, 'joinedAt': now})
    mr.http('PUT', f'{mr.DB}/live/{code}/answers/r0q0/{a_uid}.json?auth={a_tok}', {'text': 'A secret guess', 'ts': 1})
    mr.http('PUT', f'{mr.DB}/live/{code}/control.json?auth={a_tok}', {'id': 3, 'verb': 'reveal', 'pin': '246810'})

    checks = [
        # No table may learn what another table said…
        ("a table reads ANOTHER table's answer",      False, allowed('GET', f'/answers/r0q0/{a_uid}', b_tok)),
        ("a table reads the whole answers node",      False, allowed('GET', '/answers/r0q0', b_tok)),
        ("a table reads its OWN answer",              True,  allowed('GET', f'/answers/r0q0/{a_uid}', a_tok)),
        ("the HOST reads every answer",               True,  allowed('GET', '/answers/r0q0', host_tok)),
        # …nor pick up the keys to the show (the remote PIN lives in `control`)…
        ("a table reads the remote PIN in control",   False, allowed('GET', '/control', b_tok)),
        ("a remote reads just the command id",        True,  allowed('GET', '/control/id', b_tok)),
        ("the HOST reads control",                    True,  allowed('GET', '/control', host_tok)),
        # …and a blanket room read would hand over both at once.
        ("a table reads the whole room",              False, allowed('GET', '', b_tok)),
        # What the room IS still has to reach every player.
        ("a table reads meta",                        True,  allowed('GET', '/meta', b_tok)),
        ("a table reads pub",                         True,  allowed('GET', '/pub', b_tok)),
        ("a table reads teams",                       True,  allowed('GET', '/teams', b_tok)),
        ("a table reads scores",                      True,  allowed('GET', '/scores', b_tok)),
        ("a table reads media",                       True,  allowed('GET', '/media', b_tok)),
        # Writes stay where they were.
        ("a table writes its OWN answer",             True,  allowed('PUT', f'/answers/r0q0/{b_uid}', b_tok, {'text': 'B', 'ts': 2})),
        ("a table overwrites ANOTHER table's answer", False, allowed('PUT', f'/answers/r0q0/{a_uid}', b_tok, {'text': 'x', 'ts': 3})),
        ("a table writes control (the remote path)",  True,  allowed('PUT', '/control', b_tok, {'id': 4, 'verb': 'next', 'pin': '000000'})),
        ("a table overwrites pub",                    False, allowed('PUT', '/pub', b_tok, {'qid': 'x', 'phase': 'reveal'})),
        ("a table overwrites scores",                 False, allowed('PUT', '/scores', b_tok, {'x': 99})),
    ]

    bad = []
    for what, expected, actual in checks:
        ok = expected == actual
        if not ok:
            bad.append(what)
        print(f"{'PASS' if ok else 'FAIL'}  {what:44s} expected={'allow' if expected else 'DENY':5s} got={'allow' if actual else 'DENY'}")

    mr.http('DELETE', f'{mr.DB}/live/{code}.json?auth={host_tok}')

    # --- duels: the node carries the question set WITH its answers, so only the two
    # named players may read it. (Both of them legitimately hold the answers — an async
    # duel is scored on the device; there is no server to hold them back.)
    did = 'probe' + ''.join(random.choice('abcdef0123456789') for _ in range(12))
    c_tok, c_uid = anon()          # challenger
    t_tok, t_uid = anon()          # the friend they challenged
    s_tok, _ = anon()              # a signed-in stranger
    mr.http('PUT', f'{mr.DB}/duels/{did}.json?auth={c_tok}', {
        'createdBy': c_uid, 'challenged': t_uid, 'createdAt': now,
        'questions': [{'p': 'Q?', 'o': ['a', 'b', 'c', 'd'], 'c': 2, 'e': ''}],
        'players': {c_uid: {'name': 'Challenger', 'done': False, 'score': 0}},
    })

    def duel_allowed(method, path, tok, body=None):
        try:
            mr.http(method, f'{mr.DB}/duels/{did}{path}.json?auth={tok}', body)
            return True
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                return False
            raise

    duel_checks = [
        ("a stranger reads someone else's duel",   False, duel_allowed('GET', '', s_tok)),
        ("the challenger reads their duel",        True,  duel_allowed('GET', '', c_tok)),
        ("the challenged friend reads it",         True,  duel_allowed('GET', '', t_tok)),
        ("the friend writes their own result",     True,  duel_allowed('PUT', f'/players/{t_uid}', t_tok, {'name': 'Friend', 'done': True, 'score': 3})),
        ("a stranger writes into the duel",        False, duel_allowed('PUT', f'/players/{s_tok[:8]}', s_tok, {'name': 'X', 'done': True, 'score': 9})),
    ]
    for what, expected, actual in duel_checks:
        ok = expected == actual
        if not ok:
            bad.append(what)
        print(f"{'PASS' if ok else 'FAIL'}  {what:44s} expected={'allow' if expected else 'DENY':5s} got={'allow' if actual else 'DENY'}")

    print('\nRESULT:', 'ALL RULES BEHAVE' if not bad else f'{len(bad)} MISBEHAVING: ' + '; '.join(bad))
    return 1 if bad else 0


if __name__ == '__main__':
    raise SystemExit(main())
