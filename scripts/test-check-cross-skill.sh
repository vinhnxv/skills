#!/bin/sh
# Prove that check-cross-skill.sh actually detects a broken tree.
#
# Usage: test-check-cross-skill.sh [path-to-check-cross-skill.sh]
#
# Copies the real skills tree into a fresh temporary directory per case,
# applies a single break, and requires the checker to exit non-zero AND to say
# why in a way that matches the case. Asserting the message matters: without it
# a case passes whenever the checker fails for any reason at all, including a
# reason unrelated to the break the case is named after.
#
# This suite exists because the checker it guards shipped blind. Its write-site
# definition required a literal `bd ... --set-metadata` command line, which
# `repo-audit` -- the skill the file was written to constrain -- does not
# contain anywhere: it states every tracker write as prose and as a declared
# namespace table. Measured on that tree, the detector found six write sites in
# `backlog-loop` and zero in `repo-audit`, so three of the four checks iterated
# over an empty key set and passed for reasons unrelated to the invariant. A
# planted namespace collision shipped green.
#
# So the cases below come in three kinds:
#
#   COLLISION cases break the invariant through a `bd` command line -- the form
#   the original detector could already see.
#
#   PROSE cases break the same invariant through a table row or a sentence --
#   the form it could not see at all. These are the regression tests for the
#   defect above; each one must be caught for the same reason its command-line
#   twin is.
#
#   VACUITY cases leave every invariant intact and instead make the harvest go
#   silent. A checker whose loops have nothing to iterate over reports success,
#   so "found nothing" and "found nothing wrong" have to be distinguishable.
#
# Finally the whole suite runs again against a deliberately weakened checker and
# requires *every* break to go undetected. Requiring all of them, rather than
# merely one, is what separates a suite that discriminates from a suite that
# crashed: an environmental failure would not miss exactly the full set.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
checker="${1:-$repo_root/scripts/check-cross-skill.sh}"

work=$(mktemp -d "${TMPDIR:-/tmp}/test-check-cross-skill.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# A fresh copy of the real tree, one per case, so no case can see another's
# break. Only `skills/` is copied: the checker is invoked by path and reads
# nothing else under the root it is given.
#
# The directory name comes from `mktemp` and NOT from a counter this function
# increments. Every call site is `t=$(fresh_tree)`, which runs the function in
# a subshell, so an incremented counter would die with it and every case after
# the first would silently reuse -- and then overwrite -- case one's tree. That
# is the same subshell-assignment defect the repository's own audit suite was
# carrying, found by review on the same day this file was written; it is worth
# a comment here because the shape is invisible until the second case fails for
# the first case's reason.
fresh_tree() {
    tree=$(mktemp -d "$work/case-XXXXXX")
    cp -R "$repo_root/skills" "$tree/skills"
    echo "$tree"
}

AUDIT_MD_CLAUDE="skills/claude/repo-audit/SKILL.md"
CONSUMER_MD_CLAUDE="skills/claude/backlog-loop/SKILL.md"

# Append a line to a file in a case tree.
append_line() { # tree, relative-path, text
    printf '%s\n' "$3" >> "$1/$2"
}

# Replace the first occurrence of a literal string in a file in a case tree.
# `sed` is avoided here: the strings carry backticks, pipes and slashes.
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

# Replace every occurrence, for the rename cases.
replace_all() { # tree, relative-path, old, new
    OLD="$3" NEW="$4" python3 - "$1/$2" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if old not in s:
    sys.stderr.write("test bug: literal not present in %s: %r\n" % (p, old))
    sys.exit(2)
open(p, "w").write(s.replace(old, new))
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

expect_fail() { # name, expected-message-substring (ERE), tree
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

    # -- COLLISION: the form the original detector could already see -----------

    t=$(fresh_tree)
    append_line "$t" "$AUDIT_MD_CLAUDE" \
        'Then run `bd update <id> --set-metadata backlog_loop_run=1` to record it.'
    expect_fail "command-line write of another skill's reserved key" \
        "reserved to 'backlog-loop'" "$t"

    t=$(fresh_tree)
    append_line "$t" "$CONSUMER_MD_CLAUDE" \
        'Then run `bd update <id> --set-metadata repo_audit_sha=abc` to record it.'
    expect_fail "consumer writes the audit's reserved key" \
        "reserved to 'repo-audit'" "$t"

    t=$(fresh_tree)
    append_line "$t" "$AUDIT_MD_CLAUDE" \
        'Then run `bd update <id> --set-metadata shared_probe_key=1` to record it.'
    append_line "$t" "$CONSUMER_MD_CLAUDE" \
        'Then run `bd update <id> --set-metadata shared_probe_key=1` to record it.'
    expect_fail "two skills write the same unreserved key" \
        "both write metadata key" "$t"

    t=$(fresh_tree)
    append_line "$t" "$AUDIT_MD_CLAUDE" \
        'Then run `bd update <id> --add-label hard-blocker` on the gate.'
    expect_fail "command-line write of the consumer's author-only label" \
        "write site for the author-only label 'hard-blocker'" "$t"

    t=$(fresh_tree)
    append_line "$t" "$CONSUMER_MD_CLAUDE" \
        'Then run `bd update <id> --add-label audit-suppressed` on the issue.'
    expect_fail "command-line write of the audit's suppression label" \
        "write site for the author-only label 'audit-suppressed'" "$t"

    # -- PROSE: the form the original detector was blind to --------------------
    #
    # Each of these is a real regression test. Every one of them shipped green
    # before this suite existed.

    t=$(fresh_tree)
    replace_first "$t" "$AUDIT_MD_CLAUDE" \
        '| `repo_audit_heartbeat` | the index issue | `<run-token>` and an ISO timestamp |' \
        '| `repo_audit_heartbeat` | the index issue | `<run-token>` and an ISO timestamp |
| `backlog_loop_run` | a colliding key, in the same style the real table uses | `1` |'
    expect_fail "namespace collision planted as a declared-table row" \
        "reserved to 'backlog-loop'" "$t"

    t=$(fresh_tree)
    append_line "$t" "$AUDIT_MD_CLAUDE" \
        'The audit adds the label `hard-blocker` when it files a rotation gate.'
    expect_fail "prose claim to write the consumer's author-only label" \
        "claims in prose to write the author-only label 'hard-blocker'" "$t"

    t=$(fresh_tree)
    append_line "$t" "$CONSUMER_MD_CLAUDE" \
        'The loop applies `audit-suppressed` to every issue it retires.'
    expect_fail "prose claim to write the audit's suppression label" \
        "claims in prose to write the author-only label 'audit-suppressed'" "$t"

    # -- VACUITY: the invariants hold and the harvest goes silent --------------

    t=$(fresh_tree)
    replace_first "$t" "$AUDIT_MD_CLAUDE" '| key | on | value |' '| name | on | value |'
    expect_fail "declared-metadata table header drifts out of shape" \
        "yields no metadata key under its own reserved prefix" "$t"

    t=$(fresh_tree)
    rm -rf "$t/skills"
    mkdir -p "$t/skills/claude/toy" "$t/skills/codex/toy"
    printf '# toy\nA skill that declares nothing.\n' > "$t/skills/claude/toy/SKILL.md"
    printf '# toy\nA skill that declares nothing.\n' > "$t/skills/codex/toy/SKILL.md"
    expect_fail "no metadata key harvested anywhere in the tree" \
        "no metadata key was harvested from any skill" "$t"

    # -- CONSUMER FACTS: true in the other skill's text, and relied on here ----

    t=$(fresh_tree)
    replace_all "$t" "$CONSUMER_MD_CLAUDE" 'status=deferred' 'status=parked'
    expect_fail "consumer stops classifying a deferred issue (R28)" \
        "repo-audit R28" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$CONSUMER_MD_CLAUDE" 'LOOP-RESPONSIBLE SET' 'LOOP SET'
    expect_fail "consumer drops its LOOP-RESPONSIBLE SET (R28)" \
        "repo-audit R28" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$CONSUMER_MD_CLAUDE" 'issue_type` is `gate`' 'issue_type` is `blocker`'
    expect_fail "consumer stops recognizing the native gate type (R30)" \
        "repo-audit R30" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$CONSUMER_MD_CLAUDE" 'backlog_loop_run' 'backlog_loop_claim'
    expect_fail "consumer renames its claim marker (R77)" \
        "repo-audit R77" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$CONSUMER_MD_CLAUDE" 'backlog_loop_cause' 'backlog_loop_reason'
    expect_fail "consumer renames its cause key (R77)" \
        "repo-audit R77" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$CONSUMER_MD_CLAUDE" 'needs-person' 'needs-human'
    expect_fail "consumer renames the needs-person cause value (R77)" \
        "'needs-person' cause vocabulary" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$CONSUMER_MD_CLAUDE" 'hard-blocker' 'hard-block'
    expect_fail "consumer renames the author-only label" \
        "no longer names the 'hard-blocker' label" "$t"

    return "$case_failures"
}

# ---------------------------------------------------------------------------
# Run it, then run it again against a checker that cannot fail.
# ---------------------------------------------------------------------------
echo "Running suite against $checker"
suite_failures=0
run_suite "$checker" || suite_failures=$?
real_breaks="$break_cases"

if [ "$suite_failures" -ne 0 ]; then
    echo "FAIL: check-cross-skill.sh missed or mis-reported $suite_failures case(s)" >&2
    exit 1
fi

# The guard on the guard. A checker that always succeeds must miss every break,
# not merely some: an environmental abort would produce a partial count, so
# requiring the full set is what proves the suite is actually discriminating.
weak="$work/weakened-check-cross-skill.sh"
printf '#!/bin/sh\nexit 0\n' > "$weak"
echo "Running suite against a deliberately weakened checker (every break must go undetected)"
weak_failures=0
run_suite "$weak" || weak_failures=$?

if [ "$weak_failures" -ne "$real_breaks" ]; then
    echo "FAIL: the weakened checker went undetected in only $weak_failures of $real_breaks break cases;" >&2
    echo "      the suite is not discriminating (or it aborted partway)." >&2
    exit 1
fi

echo "OK: check-cross-skill.sh caught all $real_breaks breaks with the right reason, and the suite rejects a weakened checker"
