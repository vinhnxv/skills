#!/bin/sh
# Guard the source-to-Beads procedure's supported inputs and write boundaries.
# Every break case below deletes one whole clause from a copy of each host file
# and must make the contract check fail; an always-succeeding check must miss
# every case.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
claude="$root/skills/claude/source-to-beads/SKILL.md"
codex="$root/skills/codex/source-to-beads/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "$1 lacks $2"; }

# The one place a close is allowed: reconcile mode's confirmation clause.
close_clause='Close an issue only after the operator confirms the close-candidate list, and only an issue this skill created (its `source_to_beads_key` begins `s2b1|`); close each confirmed issue with `bd close <id> --reason-file <file>` only after a fresh `bd show <id> --json` still shows it open and unassigned.'

# Print the file with the anchored clause removed. Exactly one copy must exist,
# so a second clause appended elsewhere cannot smuggle a close past the guard.
outside_clause() {
    CLAUSE=$2 python3 - "$1" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
c = os.environ["CLAUSE"]
if s.count(c) != 1:
    sys.exit(3)
sys.stdout.write(s.replace(c, "", 1))
PY
}

check() {
    file=$1
    [ -f "$file" ] || fail "missing $file"
    require "$file" 'brainstorm or requirements'
    require "$file" 'implementation plan'
    require "$file" 'audit report'
    require "$file" 'cited research'
    require "$file" 'current session'
    require "$file" 'bd prime'
    require "$file" 'bd ready'
    require "$file" 'bd list --all --include-gates --limit 0 --json'
    require "$file" 'source_to_beads_key'
    require "$file" 'source_to_beads_source'
    require "$file" 'repo_audit_fingerprint'
    require "$file" 'both open and closed issues'
    require "$file" 'stable `RA-` finding ID'
    require "$file" 'bd show <id> --json'
    require "$file" '[HUMAN]'
    require "$file" 'human-gate'
    require "$file" 'no parent'
    require "$file" 'Do not run `backlog-loop`'
    require "$file" 'Revalidate every audit finding against the default-branch tip, never the checked-out branch.'
    require "$file" 'run `git fetch <remote> refs/heads/<default>`, which updates only the remote-tracking ref and touches no worktree or local branch'
    require "$file" 'Read the cited evidence with `git show <tip>:<path>`'
    require "$file" 'Defer a finding, and say so in the receipt, only when the fetch fails.'
    require "$file" 'Evidence that exists only on the checked-out branch defers unless the operator opted in to branch-only evidence'
    require "$file" 'Refuse a refuted finding: when the tip no longer shows the cited defect, file nothing'
    require "$file" 'File a finding that cannot be evaluated only as a `spike` with action kind `verify`.'
    require "$file" 'Record `revalidated-at: <tip sha>` in the body of every finding filed.'
    require "$file" 'A `disagree` or `correct` verdict in a companion `docs/audits/<run-id>-review-*.md` file defers the finding or turns it into a verification task.'
    require "$file" 's2b1|<repo-id>|<anchor>|<action-kind>[|<n>]'
    require "$file" '`git@GitHub.com:Org/Repo.git` and `https://github.com/Org/Repo` both give `github.com/org/repo`'
    require "$file" 'fall back to the root commit SHA when there is no origin'
    require "$file" 'Assert that each metadata key name matches `^[a-z_][a-z0-9_]*$` before create.'
    require "$file" 'Create each issue with `--id <prefix>-s<first 8 hex of sha256(key)>`'
    require "$file" 'a duplicate id is refused even with `--force`'
    require "$file" "--if-assignee '' --if-status open"
    require "$file" 'exit 13 means the issue was claimed or left `open`'
    require "$file" 'File every user-reserved question and every hard-blocker as a native gate with `bd create --type gate`'
    require "$file" 'Keep an agent-decidable technical choice a `decision` issue whose body says the loop may choose.'
    require "$file" 'An ambiguous match defers that candidate only'
    require "$file" 'stop tracker writes only when the listing itself is incomplete'
    require "$file" 'Pass `--no-inherit-labels` on a child that sets explicit labels.'
    require "$file" 'List every gate filed with how to resolve it: `bd gate resolve <id>`.'
    require "$file" 'Run reconcile mode only when the operator asks to reconcile issues already filed'
    require "$file" 'Never read an earlier result note as a verdict'
    require "$file" "--append-notes <note> --if-assignee '' --if-status open"
    require "$file" 'Never touch an issue whose `source_to_beads_key` does not begin `s2b1|`'
    require "$file" "$close_clause"
    rest=$(outside_clause "$file" "$close_clause") || fail "$file lacks exactly one reconcile close clause"
    if printf '%s\n' "$rest" | grep -Eq '(^|[[:space:]`])bd[[:space:]]+(close|reopen)'; then
        fail "$file closes or reopens an issue outside the reconcile confirmation clause"
    fi
}

# Control: a checker that accepts everything.
check_control() { :; }

check "$claude"
check "$codex"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/source-to-beads-contract.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

# Delete every line holding the literal; fail the case when none does, so a
# reworded anchor cannot leave a case silently testing nothing.
drop_line() {
    grep -Fq -- "$2" "$1" || fail "test bug: $1 has no line with $2"
    grep -Fv -- "$2" "$1" > "$1.new"
    mv "$1.new" "$1"
}
# Replace one literal with another inside a copy.
mutate() {
    OLD=$2 NEW=$3 python3 - "$1" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if old not in s:
    sys.stderr.write("test bug: missing literal %r in %s\n" % (old, p))
    sys.exit(2)
open(p, "w").write(s.replace(old, new))
PY
}

cases=0
misses=0
run_case() {
    # $1 checker, $2 case name, $3 mutation kind, $4 literal, $5 replacement
    for host in claude codex; do
        cases=$((cases + 1))
        src="$root/skills/$host/source-to-beads/SKILL.md"
        cp "$src" "$tmp/SKILL.md"
        case "$3" in
            drop) mutate "$tmp/SKILL.md" "$4" "" ;;
            replace) mutate "$tmp/SKILL.md" "$4" "$5" ;;
            append) printf '%s\n' "$4" >> "$tmp/SKILL.md" ;;
            delete-line) drop_line "$tmp/SKILL.md" "$4" ;;
        esac
        if ("$1" "$tmp/SKILL.md") >/dev/null 2>&1; then
            [ "$1" = check_control ] || echo "  MISS: $2 ($host)" >&2
            misses=$((misses + 1))
        fi
    done
}

run_cases() {
    checker=$1
    cases=0
    misses=0
    run_case "$checker" "metadata key deletion" delete-line 'source_to_beads_key'
    run_case "$checker" "issue closure outside the clause" append 'bd close example'
    run_case "$checker" "issue reopening" append 'bd reopen example'
    run_case "$checker" "close trailing the confirmation clause" replace "$close_clause" "$close_clause Then run \`bd close example\`."
    run_case "$checker" "second copy of the confirmation clause" append "$close_clause"
    run_case "$checker" "confirmation clause removed" drop "$close_clause"
    run_case "$checker" "confirmation requirement removed" replace 'only after the operator confirms the close-candidate list' 'without asking the operator'
    run_case "$checker" "close limited to issues this skill created" replace 'and only an issue this skill created (its `source_to_beads_key` begins `s2b1|`)' 'and any issue'
    run_case "$checker" "reconcile runs only on request" drop 'Run reconcile mode only when the operator asks to reconcile issues already filed'
    run_case "$checker" "result note is never a verdict" drop 'Never read an earlier result note as a verdict'
    run_case "$checker" "status-guarded result note" drop "--append-notes <note> --if-assignee '' --if-status open"
    run_case "$checker" "legacy and foreign issues untouched" drop 'Never touch an issue whose `source_to_beads_key` does not begin `s2b1|`'
    run_case "$checker" "default-tip revalidation sentence" drop 'Revalidate every audit finding against the default-branch tip, never the checked-out branch.'
    run_case "$checker" "fetch that touches only the remote-tracking ref" drop 'which updates only the remote-tracking ref and touches no worktree or local branch'
    run_case "$checker" "evidence read from the tip object" drop 'Read the cited evidence with `git show <tip>:<path>`'
    run_case "$checker" "fetch-failure-only deferral" drop 'Defer a finding, and say so in the receipt, only when the fetch fails.'
    run_case "$checker" "branch-only evidence deferral" drop 'Evidence that exists only on the checked-out branch defers unless the operator opted in to branch-only evidence'
    run_case "$checker" "refuted findings refused" drop 'Refuse a refuted finding: when the tip no longer shows the cited defect, file nothing'
    run_case "$checker" "unevaluable findings only as verification spikes" drop 'File a finding that cannot be evaluated only as a `spike` with action kind `verify`.'
    run_case "$checker" "revalidated-at record" drop 'Record `revalidated-at: <tip sha>` in the body of every finding filed.'
    run_case "$checker" "companion review verdicts" drop 'A `disagree` or `correct` verdict in a companion `docs/audits/<run-id>-review-*.md` file defers the finding or turns it into a verification task.'
    run_case "$checker" "key grammar" drop 's2b1|<repo-id>|<anchor>|<action-kind>[|<n>]'
    run_case "$checker" "ssh and https repo-id equivalence example" drop '`git@GitHub.com:Org/Repo.git` and `https://github.com/Org/Repo` both give `github.com/org/repo`'
    run_case "$checker" "root commit fallback" drop 'fall back to the root commit SHA when there is no origin'
    run_case "$checker" "metadata key name assertion" drop 'Assert that each metadata key name matches `^[a-z_][a-z0-9_]*$` before create.'
    run_case "$checker" "deterministic id create" drop 'Create each issue with `--id <prefix>-s<first 8 hex of sha256(key)>`'
    run_case "$checker" "duplicate id means reuse" drop 'a duplicate id is refused even with `--force`'
    run_case "$checker" "status-guarded update" drop "--if-assignee '' --if-status open"
    run_case "$checker" "exit 13 defers" drop 'exit 13 means the issue was claimed or left `open`'
    run_case "$checker" "native gate form" drop 'File every user-reserved question and every hard-blocker as a native gate with `bd create --type gate`'
    run_case "$checker" "agent-decidable decision issue" drop 'Keep an agent-decidable technical choice a `decision` issue whose body says the loop may choose.'
    run_case "$checker" "ambiguous match defers one candidate" drop 'An ambiguous match defers that candidate only'
    run_case "$checker" "global stop only for an incomplete listing" drop 'stop tracker writes only when the listing itself is incomplete'
    run_case "$checker" "no-inherit-labels" drop 'Pass `--no-inherit-labels` on a child that sets explicit labels.'
    run_case "$checker" "receipt gate resolution" drop 'List every gate filed with how to resolve it: `bd gate resolve <id>`.'
}

run_cases check
[ "$misses" -eq 0 ] || fail "$misses of $cases break cases escaped the contract check"
real_cases=$cases
run_cases check_control
[ "$misses" -eq "$cases" ] || fail "the always-succeeding control caught $((cases - misses)) of $cases cases"
[ "$cases" -eq "$real_cases" ] || fail "control ran a different number of cases"

echo "OK: source-to-Beads inputs and write boundaries hold in both hosts ($real_cases break cases, control misses all)"
