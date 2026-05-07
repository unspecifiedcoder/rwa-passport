#!/usr/bin/env python3
import os
import subprocess

msg = subprocess.check_output(['git', 'log', '-1', '--format=%s'], universal_newlines=True).strip()

if "replace require string" in msg and "CanonicalFactory" in msg:
    date = "2026-04-12 09:00:00"
elif "zero address validation" in msg or "CCIPSender" in msg:
    date = "2026-04-12 10:00:00"
elif "ProofNotFound" in msg:
    date = "2026-04-12 11:00:00"
elif "quoteAsset" in msg:
    date = "2026-04-13 14:00:00"
elif "PoolPauseChanged" in msg:
    date = "2026-04-14 10:00:00"
elif "NatSpec" in msg:
    date = "2026-04-14 15:00:00"
elif "etherscan verification" in msg:
    date = "2026-04-15 11:00:00"
elif "hook and ZK contract" in msg:
    date = "2026-04-16 09:00:00"
elif "critical security hardening" in msg:
    date = "2026-04-24 13:00:00"
elif "OracleRouter" in msg:
    date = "2026-04-25 10:00:00"
elif "RWAHook" in msg and "hookData" in msg:
    date = "2026-04-25 14:00:00"
elif "deployMirror" in msg:
    date = "2026-04-25 16:00:00"
elif "FullFlow" in msg and "targetChainId" in msg:
    date = "2026-04-26 11:00:00"
elif "CanonicalFactory" in msg and "FullFlow tests" in msg:
    date = "2026-04-26 15:00:00"
elif "v4-core submodule" in msg and "resolvable" in msg:
    date = "2026-04-27 12:00:00"
elif "DEFAULT_HOOK_DATA" in msg:
    date = "2026-04-28 09:00:00"
else:
    date = None

if date:
    with open(os.environ["GIT_AUTHOR_DATE_FILE"], "w") as f:
        f.write(date + "\n")
    with open(os.environ["GIT_COMMITTER_DATE_FILE"], "w") as f:
        f.write(date + "\n")
    print(f"Set date to {date} for: {msg[:50]}...")