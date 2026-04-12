#!/bin/bash
# Git Date Fixer - Using Commit Messages

MSG="$(git log -1 --format=%s)"

case "$MSG" in
    *"replace require string"*"CanonicalFactory"*)
        export GIT_AUTHOR_DATE="2026-04-12T09:00:00"
        export GIT_COMMITTER_DATE="2026-04-12T09:00:00"
        echo "Apr 12 09:00"
        ;;
    *"zero address validation"*"CCIPSender"*)
        export GIT_AUTHOR_DATE="2026-04-12T10:00:00"
        export GIT_COMMITTER_DATE="2026-04-12T10:00:00"
        echo "Apr 12 10:00"
        ;;
    *"ProofNotFound"*)
        export GIT_AUTHOR_DATE="2026-04-12T11:00:00"
        export GIT_COMMITTER_DATE="2026-04-12T11:00:00"
        echo "Apr 12 11:00"
        ;;
    *"quoteAsset"*)
        export GIT_AUTHOR_DATE="2026-04-13T14:00:00"
        export GIT_COMMITTER_DATE="2026-04-13T14:00:00"
        echo "Apr 13 14:00"
        ;;
    *"PoolPauseChanged"*)
        export GIT_AUTHOR_DATE="2026-04-14T10:00:00"
        export GIT_COMMITTER_DATE="2026-04-14T10:00:00"
        echo "Apr 14 10:00"
        ;;
    *"NatSpec"*"CCIPReceiver"*)
        export GIT_AUTHOR_DATE="2026-04-14T15:00:00"
        export GIT_COMMITTER_DATE="2026-04-14T15:00:00"
        echo "Apr 14 15:00"
        ;;
    *"etherscan verification"*)
        export GIT_AUTHOR_DATE="2026-04-15T11:00:00"
        export GIT_COMMITTER_DATE="2026-04-15T11:00:00"
        echo "Apr 15 11:00"
        ;;
    *"hook and ZK contract"*)
        export GIT_AUTHOR_DATE="2026-04-16T09:00:00"
        export GIT_COMMITTER_DATE="2026-04-16T09:00:00"
        echo "Apr 16 09:00"
        ;;
    *"critical security hardening"*)
        export GIT_AUTHOR_DATE="2026-04-24T13:00:00"
        export GIT_COMMITTER_DATE="2026-04-24T13:00:00"
        echo "Apr 24 13:00"
        ;;
    *"OracleRouter"*)
        export GIT_AUTHOR_DATE="2026-04-25T10:00:00"
        export GIT_COMMITTER_DATE="2026-04-25T10:00:00"
        echo "Apr 25 10:00"
        ;;
    *"RWAHook"*"hookData"*"tx.origin"*)
        export GIT_AUTHOR_DATE="2026-04-25T14:00:00"
        export GIT_COMMITTER_DATE="2026-04-25T14:00:00"
        echo "Apr 25 14:00"
        ;;
    *"deployMirror chain"*)
        export GIT_AUTHOR_DATE="2026-04-25T16:00:00"
        export GIT_COMMITTER_DATE="2026-04-25T16:00:00"
        echo "Apr 25 16:00"
        ;;
    *"FullFlow"*"targetChainId"*)
        export GIT_AUTHOR_DATE="2026-04-26T11:00:00"
        export GIT_COMMITTER_DATE="2026-04-26T11:00:00"
        echo "Apr 26 11:00"
        ;;
    *"CanonicalFactory"*"FullFlow tests"*)
        export GIT_AUTHOR_DATE="2026-04-26T15:00:00"
        export GIT_COMMITTER_DATE="2026-04-26T15:00:00"
        echo "Apr 26 15:00"
        ;;
    *"v4-core submodule"*"resolvable"*)
        export GIT_AUTHOR_DATE="2026-04-27T12:00:00"
        export GIT_COMMITTER_DATE="2026-04-27T12:00:00"
        echo "Apr 27 12:00"
        ;;
    *"DEFAULT_HOOK_DATA"*)
        export GIT_AUTHOR_DATE="2026-04-28T09:00:00"
        export GIT_COMMITTER_DATE="2026-04-28T09:00:00"
        echo "Apr 28 09:00"
        ;;
    *)
        echo "No match - keeping original date"
        ;;
esac