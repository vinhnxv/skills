#!/bin/sh
# Prove the safety properties every script under scripts/ shares: unknown
# arguments exit 2, an interrupt stops a suite with exit 130 and removes its
# work directory, a failed host CLI is reported rather than aborting, a suite's
# failure count never travels through a `return` status, and a failed `bd init`
# shows its reason.
#
# Usage: test-harness.sh
#
# This is its own suite because no other one owns these properties: each is
# about how a script behaves, not about the skill text it checks. It reuses the
# other scripts as the things under test and stubs the host CLIs and `bd` with
# throwaway executables on PATH, so no model and no real tracker is driven by
# the failure cases. The two census runs need a real `bd` for the contract half
# that precedes the classification half; they SKIP without one.
set -eu

[ "$#" -eq 0 ] || { echo "usage: test-harness.sh (takes no arguments)" >&2; exit 2; }

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scripts="$repo_root/scripts"

work=$(mktemp -d "${TMPDIR:-/tmp}/test-harness.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT HUP TERM

failures=0
checks=0
pass() { checks=$((checks + 1)); printf '  ok: %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL: %s\n' "$1"; }

# A script's exit status without tripping `set -e`.
status_of() {
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}

# ---------------------------------------------------------------------------
echo "unknown arguments exit 2 in every script"

for f in "$scripts"/*.sh; do
    name=$(basename "$f")
    [ "$(status_of sh "$f" --bogus)" -eq 2 ] \
        && pass "$name rejects --bogus" \
        || fail "$name does not exit 2 on --bogus"
done

# The scripts that take one optional path reject a second argument too.
for name in check-parity.sh check-cross-skill.sh check-backlog-loop.sh \
    test-check-parity.sh test-check-cross-skill.sh test-check-backlog-loop.sh; do
    [ "$(status_of sh "$scripts/$name" one two)" -eq 2 ] \
        && pass "$name rejects a second argument" \
        || fail "$name does not exit 2 on two arguments"
done

# `--fixtures-only` once looked like a mode. The two suites CI passed it to
# have no model-driven half and no fixture-only half to select, so it is as
# unknown as any other flag.
for name in test-repo-audit.sh test-source-to-beads.sh; do
    [ "$(status_of sh "$scripts/$name" --fixtures-only)" -eq 2 ] \
        && pass "$name rejects --fixtures-only" \
        || fail "$name accepts --fixtures-only"
done

[ "$(status_of sh "$scripts/test-census.sh" --full --contract-only)" -eq 2 ] \
    && pass "test-census.sh rejects --full together with --contract-only" \
    || fail "test-census.sh accepts --full together with --contract-only"

# ---------------------------------------------------------------------------
echo "an interrupt stops a suite with exit 130 and removes its work directory"

# Launch a suite with a private TMPDIR, wait until it has made its work
# directory, send the signal, and read the status and what is left behind. An
# asynchronous command ignores SIGINT in a non-interactive shell, and a signal
# ignored on entry cannot be trapped, so TERM and HUP stand in for INT here; the
# static check below pins that all three share one trap.
interrupt_case() { # script signal
    name=$1; sig=$2
    tmp="$work/interrupt-$name-$sig"
    mkdir "$tmp"
    TMPDIR="$tmp" sh "$scripts/$name" >/dev/null 2>&1 &
    pid=$!
    waited=0
    while [ -z "$(ls "$tmp")" ] && [ "$waited" -lt 300 ]; do
        sleep 0.1
        waited=$((waited + 1))
    done
    kill "-$sig" "$pid"
    rc=0
    wait "$pid" || rc=$?
    [ "$rc" -eq 130 ] \
        && pass "$name exits 130 on $sig" \
        || fail "$name exited $rc on $sig, not 130"
    [ -z "$(ls "$tmp")" ] \
        && pass "$name removes its work directory on $sig" \
        || fail "$name left $(ls "$tmp" | tr '\n' ' ') behind on $sig"
}

interrupt_case test-check-cross-skill.sh TERM
interrupt_case test-check-cross-skill.sh HUP
interrupt_case test-check-parity.sh TERM

# Every script cleans up on EXIT alone and turns the three signals into exit
# 130, which runs that cleanup. A cleanup trap on the signals themselves lets a
# suite carry on after its work directory is gone.
for f in "$scripts"/*.sh; do
    name=$(basename "$f")
    if grep -E '^[[:space:]]*trap[^#]* EXIT[^#]*(HUP|INT|TERM)' "$f" >/dev/null; then
        fail "$name traps a signal and EXIT in one trap, so the signal handler no longer exits"
    elif grep -E '^[[:space:]]*trap [^#]*EXIT' "$f" >/dev/null &&
        ! grep -F "trap 'exit 130' INT HUP TERM" "$f" >/dev/null; then
        fail "$name cleans up on EXIT but does not exit 130 on INT, HUP and TERM"
    else
        pass "$name: cleanup on EXIT only, signals exit 130"
    fi
done

# ---------------------------------------------------------------------------
echo "a suite's failure count never travels through a return status"

# A shell status wraps at 256: 256 failures read as success and 272 as 16.
if grep -nE '^[^#]*(return "\$|run_suite[^#]*\|\|)' "$scripts"/*.sh >/dev/null; then
    fail "a script returns a failure count or reads one from run_suite's status: $(grep -nE '^[^#]*(return "\$|run_suite[^#]*\|\|)' "$scripts"/*.sh | head -n 1)"
else
    pass "no script returns a count or reads a count from run_suite's status"
fi

# Behavior: a parity suite over more skills than one status can count. The
# checker under test never fails, so every break case is missed and the suite
# must report the whole count, not the count modulo 256. The tree holds copies
# of the smallest real skill, because every case copies the whole tree.
big="$work/big"
mkdir -p "$big/scripts"
cp "$scripts/test-check-parity.sh" "$big/scripts/"
smallest=$(cd "$repo_root/skills/claude" && du -sk -- * | sort -n | head -n 1 | cut -f2)
for host in claude codex; do
    mkdir -p "$big/skills/$host"
    cp -R "$repo_root/skills/$host/$smallest" "$big/skills/$host/$smallest"
    for n in 1 2 3 4 5 6 7; do
        cp -R "$repo_root/skills/$host/$smallest" "$big/skills/$host/clone-$n"
    done
done
printf '#!/bin/sh\nexit 0\n' > "$work/never-fails.sh"
rc=0
sh "$big/scripts/test-check-parity.sh" "$work/never-fails.sh" > "$work/big.out" 2>&1 || rc=$?
missed=$(sed -n 's/^FAIL: check-parity.sh missed or mis-reported \([0-9][0-9]*\) case.*/\1/p' "$work/big.out")
if [ "$rc" -ne 0 ] && [ -n "$missed" ] && [ "$missed" -gt 255 ]; then
    pass "a parity suite with $missed missed cases exits $rc and reports all of them"
else
    fail "a parity suite with more than 255 missed cases exited $rc and reported '${missed:-no count}'"
fi

# ---------------------------------------------------------------------------
echo "test-check-parity.sh builds its base tree once"

# `fresh_tree` runs once per case, so planting the synthetic skill there is the
# per-case rebuild this step removed.
fresh_body=$(sed -n '/^fresh_tree() {/,/^}/p' "$scripts/test-check-parity.sh")
case "$fresh_body" in
    *plant_synthetic_skill*) fail "fresh_tree plants the synthetic skill for every case" ;;
    "") fail "fresh_tree not found in test-check-parity.sh" ;;
    *) pass "fresh_tree only copies the base tree" ;;
esac

# ---------------------------------------------------------------------------
echo "a failed bd init shows bd's own message"

stub="$work/stub"
mkdir "$stub"
printf '#!/bin/sh\necho "stub bd: init exploded" >&2\nexit 4\n' > "$stub/bd"
chmod +x "$stub/bd"
rc=0
PATH="$stub:$PATH" sh "$scripts/test-census.sh" > "$work/init.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && grep -F 'bd init --prefix cx failed' "$work/init.out" >/dev/null &&
    grep -F 'stub bd: init exploded' "$work/init.out" >/dev/null; then
    pass "the suite stops non-zero and prints bd's stderr"
else
    fail "a failing bd init exited $rc without showing its stderr: $(head -n 3 "$work/init.out" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
echo "test-census.sh runs the contract half by default and reports a failed host CLI"

if ! command -v bd >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "  SKIP: needs bd and python3; the census runs below drive a real tracker."
else
    # `timeout` is absent from a stock macOS; the suite probes for it and skips
    # without one, so a stub keeps these runs independent of the machine.
    printf '#!/bin/sh\nshift\nexec "$@"\n' > "$stub/timeout"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/claude.calls"\necho "stub claude: refused" >&2\nexit 3\n' "$work" > "$stub/claude"
    chmod +x "$stub/timeout" "$stub/claude"
    # The default-mode run gets its own claude stub so the other run's calls
    # cannot be mistaken for it.
    default_stub="$work/default-stub"
    mkdir "$default_stub"
    cp "$stub/timeout" "$default_stub/timeout"
    printf '#!/bin/sh\necho called >> "%s/default.calls"\nexit 3\n' "$work" > "$default_stub/claude"
    chmod +x "$default_stub/claude"
    rm -f "$stub/bd"

    # PATH minus every directory that holds a real host CLI, then the Codex stub:
    # the census prefers `claude`, so Codex is only reached when `claude` is gone.
    clean_path=""
    old_ifs=$IFS
    IFS=:
    for dir in $PATH; do
        [ -x "$dir/claude" ] || [ -x "$dir/codex" ] || clean_path="$clean_path${clean_path:+:}$dir"
    done
    IFS=$old_ifs
    codex_stub="$work/codex-stub"
    mkdir "$codex_stub"
    cp "$stub/timeout" "$codex_stub/timeout"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/codex.calls"\necho "stub codex: refused" >&2\nexit 3\n' "$work" > "$codex_stub/codex"
    chmod +x "$codex_stub/codex"

    # The three runs touch separate stores, so they run side by side.
    PATH="$default_stub:$PATH" sh "$scripts/test-census.sh" > "$work/default.out" 2>&1 &
    default_pid=$!
    PATH="$stub:$PATH" sh "$scripts/test-census.sh" --full > "$work/full.out" 2>&1 &
    full_pid=$!
    codex_rc=0
    if PATH="$codex_stub:$clean_path" sh -c 'command -v bd python3 git >/dev/null' 2>/dev/null; then
        PATH="$codex_stub:$clean_path" sh "$scripts/test-census.sh" --full > "$work/codex.out" 2>&1 &
        codex_pid=$!
    else
        codex_pid=""
    fi
    default_rc=0; wait "$default_pid" || default_rc=$?
    full_rc=0; wait "$full_pid" || full_rc=$?
    [ -z "$codex_pid" ] || wait "$codex_pid" || codex_rc=$?

    if [ "$default_rc" -eq 0 ] && grep -F '[contract only]' "$work/default.out" >/dev/null &&
        ! grep -F 'PART 2' "$work/default.out" >/dev/null && [ ! -s "$work/default.calls" ]; then
        pass "no argument runs the contract half only and never calls the host CLI"
    else
        fail "no argument exited $default_rc: $(tail -n 3 "$work/default.out" | tr '\n' ' ')"
    fi

    if [ "$full_rc" -ne 0 ] && grep -F 'FAIL: census runner failed: claude exited 3' "$work/full.out" >/dev/null &&
        grep -E '^[0-9]+ check\(s\), [0-9]+ failure\(s\)$' "$work/full.out" >/dev/null &&
        ! grep -F '[contract only]' "$work/full.out" >/dev/null; then
        pass "--full with a host CLI that exits 3 reports 'runner failed' and still prints the summary"
    else
        fail "--full with a failing host CLI exited $full_rc: $(tail -n 3 "$work/full.out" | tr '\n' ' ')"
    fi

    if [ -z "$codex_pid" ]; then
        echo "  SKIP: the Codex invocation check needs a PATH without the real claude and codex that still has bd, python3 and git."
    elif [ "$codex_rc" -ne 0 ] && grep -F 'FAIL: census runner failed: codex exited 3' "$work/codex.out" >/dev/null &&
        [ "$(head -n 1 "$work/codex.calls" 2>/dev/null | cut -c1-5)" = "exec " ]; then
        pass "the Codex path runs 'codex exec <prompt>' and its failure is reported"
    else
        fail "the Codex path exited $codex_rc; calls: $(head -n 1 "$work/codex.calls" 2>/dev/null | cut -c1-40)"
    fi
fi

printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
[ "$failures" -eq 0 ] || exit 1
