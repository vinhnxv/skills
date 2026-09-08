#!/bin/sh
# Prove that check-backlog-loop.sh actually detects a broken tree.
#
# Usage: test-check-backlog-loop.sh [path-to-check-backlog-loop.sh]
#
# Copies the real skills tree into a fresh temporary directory per case,
# applies a single break, and requires the checker to exit non-zero AND to say
# why in a way that matches the case. Asserting the message matters: without it
# a case passes whenever the checker fails for any reason at all, including a
# reason unrelated to the break the case is named after -- and this checker has
# nine independent assertions, so "it failed" carries almost no information.
#
# The cases come in three kinds.
#
#   DELETION cases remove a rule the procedure rests on -- the RECOVERY default
#   arm, the sentence closing the phase enum, `hooked` from `abandoned-claim`'s
#   exclusion list. Each of these is a real edit somebody could make while
#   tidying, and each one wedges a run rather than degrading it.
#
#   DRIFT cases leave every rule present and move one out from under another --
#   a phase renamed in the ledger with no arm added, a parked row renumbered
#   back below `abandoned-claim`, a `<cause>` row for a category CLASSIFY does
#   not carry. This is the failure mode parity cannot see, because both copies
#   drift together.
#
#   VACUITY cases break an extraction rather than a rule. Every assertion in
#   the checker is a loop over a table matched on its exact header line, so a
#   reformatting edit that touches no rule can empty the loop and leave a green
#   run asserting nothing. "Found nothing" and "found nothing wrong" have to be
#   distinguishable.
#
# One case runs the other way round: the UNMODIFIED tree must PASS. That is the
# only proof that the ` / ` split over the `<cause>` table's three multi-
# category cells works on the real file -- a checker that could not split them
# would report twelve categories against fifteen and fail here, and the fix
# would be to weaken the two-way census rather than the parser.
#
# Finally the whole break suite runs again against a deliberately weakened
# checker and requires *every* break to go undetected. Requiring all of them,
# rather than merely one, is what separates a suite that discriminates from a
# suite that crashed: an environmental failure would not miss exactly the full
# set.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
checker="${1:-$repo_root/scripts/check-backlog-loop.sh}"

work=$(mktemp -d "${TMPDIR:-/tmp}/test-check-backlog-loop.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# A fresh copy of the real tree, one per case, so no case can see another's
# break. Only `skills/` is copied: the checker is invoked by path and reads
# nothing else under the root it is given.
#
# The directory name comes from `mktemp` and NOT from a counter this function
# increments. Every call site is `t=$(fresh_tree)`, which runs the function in
# a subshell, so an incremented counter would die with it and every case after
# the first would silently reuse -- and then overwrite -- case one's tree.
fresh_tree() {
    tree=$(mktemp -d "$work/case-XXXXXX")
    cp -R "$repo_root/skills" "$tree/skills"
    echo "$tree"
}

LOOP_MD_CLAUDE="skills/claude/backlog-loop/SKILL.md"
LOOP_MD_CODEX="skills/codex/backlog-loop/SKILL.md"

# Append a line to a file in a case tree.
append_line() { # tree, relative-path, text
    printf '%s\n' "$3" >> "$1/$2"
}

# Replace the first occurrence of a literal string in a file in a case tree.
# `sed` is avoided here: every string below carries backticks, pipes, or both.
# Exits 2 rather than 0 when the target text is absent, because a break case
# that silently applied nothing would run the checker against a correct tree
# and report a MISS against the checker for the test's own defect.
replace_first() { # tree, relative-path, old, new
    OLD="$3" NEW="$4" python3 - "$1/$2" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if old not in s:
    sys.stderr.write("test bug: literal not present in %s: %r\n" % (p, old))
    sys.exit(2)
open(p, "w").write(s.replace(old, new, 1))
PY
}

# ---------------------------------------------------------------------------
# One case: run the checker under test against a broken tree and require both
# a non-zero exit and a message matching this case's expectation.
#
# Increments `break_cases` and, on a miss, `case_failures`. Never exits: the
# suite has to reach the end so the weakened-checker comparison below compares
# two runs of the same set.
# ---------------------------------------------------------------------------
break_cases=0
case_failures=0

expect_fail() { # name, expected-message-ERE, tree
    name="$1"
    expected="$2"
    tree="$3"
    break_cases=$((break_cases + 1))

    out=$(sh "$checker_under_test" "$tree" 2>&1) && rc=0 || rc=$?

    if [ "$rc" -eq 0 ]; then
        echo "  MISS: $name -- checker exited 0 on a broken tree" >&2
        case_failures=$((case_failures + 1))
        return 0
    fi
    if ! printf '%s\n' "$out" | grep -qE -- "$expected"; then
        echo "  WRONG REASON: $name" >&2
        echo "    expected message matching: $expected" >&2
        echo "    got: $(printf '%s\n' "$out" | head -n 1)" >&2
        case_failures=$((case_failures + 1))
        return 0
    fi
    echo "  ok: $name"
}

# ---------------------------------------------------------------------------
# The suite. Every case builds its own tree, applies exactly one break, and
# states the message it expects.
# ---------------------------------------------------------------------------
run_suite() { # checker path
    checker_under_test="$1"
    break_cases=0
    case_failures=0

    # -- DELETION: a rule removed -------------------------------------------

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '- Absent, or any value the `backlog_loop_phase` row above does not list:' \
        '- Never reached, kept for history:'
    expect_fail "the RECOVERY default arm is deleted" \
        "RECOVERY carries no arm for an absent or unrecognized" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '. These seven are the only phase values this procedure writes.' \
        '.'
    expect_fail "the sentence closing the backlog_loop_phase value set is deleted, every arm left in place" \
        "no longer states that its values are the only phase values" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'and `status` is not `blocked`, `hooked`, `pinned` or `deferred` |' \
        'and `status` is not `blocked`, `pinned` or `deferred` |'
    expect_fail "hooked is dropped from abandoned-claim's exclusion list" \
        'does not exclude .hooked.' "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'This procedure writes exactly four statuses: `open`, `in_progress`, `blocked`, and `closed`. It never writes `hooked`, `pinned`, or `deferred`.' \
        'This procedure writes the statuses the tracker accepts.'
    expect_fail "the ## CONSTRAINTS status sentence is removed" \
        "states no status this procedure never writes" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'RESIDUE PASS. For each issue this census classified' \
        'RESIDUE REPAIR. For each issue this census classified'
    expect_fail "the RESIDUE PASS opener is renamed out of ## CENSUS" \
        "carries no 'RESIDUE PASS.' opener" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '(REOPEN PASS, RESIDUE PASS, and GATE REPAIR PASS)' \
        '(REOPEN PASS and GATE REPAIR PASS)'
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        ', or RESIDUE PASS, which writes at most once per issue and then never again' \
        ''
    expect_fail "the WRITE GATE paragraph stops naming RESIDUE PASS" \
        "does not name RESIDUE PASS among the writes it covers" "$t"

    # A substring test for `claimed` stays green here: the replacement leaves
    # "reclaimed" in the block. Only a whole-token match sees the arm go.
    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '- `pr-open`, `built`, or `claimed`: nothing shipped. Reclaim, retiring the PR first' \
        '- `pr-open` or `built`: nothing shipped. An issue reclaimed here is reclaimed whole. Reclaim, retiring the PR first'
    expect_fail "the RECOVERY claimed arm is deleted while 'reclaimed' still appears in the block" \
        'declares phase .claimed. but no RECOVERY arm' "$t"

    # -- DRIFT: every rule present, one moved out from under another ---------

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| `backlog_loop_phase` | each transition | `claimed`, `built`, `shipping-requested`, `pr-open`,' \
        '| `backlog_loop_phase` | each transition | `claimed`, `built`, `shipping-requested`, `pr-opened`,'
    expect_fail "a phase value is renamed in the ledger with no arm added" \
        'declares phase .pr-opened. but no RECOVERY arm' "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| 11 | `deferred` | `status=deferred` |' \
        '| 13 | `deferred` | `status=deferred` |'
    expect_fail "deferred is renumbered back below abandoned-claim" \
        'CLASSIFY row 13 .deferred. does not outrank row 12 .abandoned-claim.' "$t"

    t=$(fresh_tree)
    append_line "$t" "$LOOP_MD_CLAUDE" \
        'Park it with `bd update <id> --status=deferred` and move on.'
    expect_fail "a --status=deferred write is added" \
        'writes .--status=deferred., which is outside' "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| `ready` | `none` |' \
        '| `ready` | `none` |
| `stalled` | `none` |'
    expect_fail "a <cause> row names a category CLASSIFY does not carry" \
        "name no CLASSIFY row" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| `ready` | `none` |
' \
        ''
    expect_fail "a CLASSIFY category loses its <cause> row" \
        "have no row in the EMIT <cause> table" "$t"

    # -- The Codex copy is read too -----------------------------------------
    #
    # Same break as the first case, applied to the other host only. A checker
    # that read one copy would report this tree clean, and every operator on
    # that host would run the wedged procedure.

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CODEX" \
        '- Absent, or any value the `backlog_loop_phase` row above does not list:' \
        '- Never reached, kept for history:'
    expect_fail "the RECOVERY default arm is deleted from the Codex copy alone" \
        "skills/codex/backlog-loop/SKILL.md: RECOVERY carries no arm" "$t"

    # -- VACUITY: an extraction broken rather than a rule --------------------

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| # | category | test |' \
        '| # | category | test-name |'
    expect_fail "the CLASSIFY table header changes shape and no row parses" \
        "the CLASSIFY table did not parse" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'RECOVERY, by the recorded phase.' \
        'RECOVERY BY PHASE.'
    expect_fail "the RECOVERY opener changes shape and no arm parses" \
        "extracted no '- ' arm" "$t"

    return "$case_failures"
}

# ---------------------------------------------------------------------------
# The one case that runs the other way round. It is deliberately outside
# `run_suite`: a weakened checker exits 0 and would "pass" it, so it carries
# information against the real checker only and must not count as a break.
# ---------------------------------------------------------------------------
echo "Running suite against $checker"
t=$(fresh_tree)
if sh "$checker" "$t" >/dev/null 2>&1; then
    echo "  ok: the unmodified tree passes, so the ' / ' split reconciles the real <cause> table's multi-category cells"
else
    echo "FAIL: the checker rejects an unmodified copy of the real tree:" >&2
    sh "$checker" "$t" >&2 || true
    exit 1
fi

suite_failures=0
run_suite "$checker" || suite_failures=$?
real_breaks="$break_cases"

if [ "$suite_failures" -ne 0 ]; then
    echo "FAIL: check-backlog-loop.sh missed or mis-reported $suite_failures case(s)" >&2
    exit 1
fi

# The guard on the guard. A checker that always succeeds must miss every break,
# not merely some: an environmental abort would produce a partial count, so
# requiring the full set is what proves the suite is actually discriminating.
weak="$work/weakened-check-backlog-loop.sh"
printf '#!/bin/sh\nexit 0\n' > "$weak"
echo "Running suite against a deliberately weakened checker (every break must go undetected)"
weak_failures=0
run_suite "$weak" || weak_failures=$?

if [ "$weak_failures" -ne "$real_breaks" ]; then
    echo "FAIL: the weakened checker went undetected in only $weak_failures of $real_breaks break cases;" >&2
    echo "      the suite is not discriminating (or it aborted partway)." >&2
    exit 1
fi

echo "OK: check-backlog-loop.sh caught all $real_breaks breaks with the right reason, and the suite rejects a weakened checker"
