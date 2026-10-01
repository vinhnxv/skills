#!/bin/sh
# Guard the source-to-Beads procedure's supported inputs and write boundaries.
# Every break case below deletes one whole clause from a copy of each host file
# and must make the contract check fail; an always-succeeding check must miss
# every case.
set -eu

# No arguments: a typo such as `--fixtures-only` must not pass for a flag.
[ "$#" -eq 0 ] || { echo "usage: test-source-to-beads.sh (takes no arguments)" >&2; exit 2; }

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
claude="$root/skills/claude/source-to-beads/SKILL.md"
codex="$root/skills/codex/source-to-beads/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "$1 lacks $2"; }

# The one place a close is allowed: reconcile mode's confirmation clause.
close_clause='Close an issue only after the operator confirms the close-candidate list, and only an issue this skill created (its `source_to_beads_key` begins `s2b1|`); close each confirmed issue with `bd close <id> --reason-file <file>` only after a fresh `bd show <id> --json` still shows it open and unassigned.'

# A close or reopen in any spelling: the subcommand behind global options
# (`bd -C <dir> close`), or a write of the `closed` status by flag
# (`--status closed`, `--status=closed`, `-s closed`). The bd command words match
# scripts/check-backlog-loop.sh's BD_WORDS.
bd_words='bd([[:space:]]+-[^[:space:]`]+([[:space:]]+[^-[:space:]`][^[:space:]`]*)?)*[[:space:]]+'
closure_pattern="(^|[^[:alnum:]_])${bd_words}(close|reopen)([^a-z-]|\$)|(--status[[:space:]=]+|-s[[:space:]=]+)[\"']?closed([^a-z-]|\$)"

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

requirements() {
    cat <<'REQUIREMENTS'
brainstorm or requirements
implementation plan
audit report
cited research
current session
bd prime
bd ready
bd list --all --include-gates --limit 0 --json
source_to_beads_key
source_to_beads_source
repo_audit_fingerprint
both open and closed issues
stable `RA-` finding ID
bd show <id> --json
[HUMAN]
human-gate
no parent
Do not run `backlog-loop`
Revalidate every audit finding against the default-branch tip, never the checked-out branch.
run `git fetch <remote> refs/heads/<default>`, which updates only the remote-tracking ref and touches no worktree or local branch
Read the cited evidence with `git show <tip>:<path>`
Defer a finding, and say so in the receipt, only when the fetch fails.
Evidence that exists only on the checked-out branch defers unless the operator opted in to branch-only evidence
Refuse a refuted finding: when the tip no longer shows the cited defect, file nothing
File a finding that cannot be evaluated only as a `spike` with action kind `verify`.
Record `revalidated-at: <tip sha>` in the body of every finding filed.
A `disagree` or `correct` verdict in a companion `docs/audits/<run-id>-review-*.md` file defers the finding or turns it into a verification task.
s2b1|<repo-id>|<anchor>|<action-kind>[|<n>]
`git@GitHub.com:Org/Repo.git` and `https://github.com/Org/Repo` both give `github.com/org/repo`
fall back to the root commit SHA when there is no origin
Assert that each metadata key name matches `^[a-z_][a-z0-9_]*$` before create.
Create each issue with `--id <prefix>-s<first 8 hex of sha256(key)>`
a duplicate id is refused even with `--force`
--if-assignee '' --if-status open
exit 13 means the issue was claimed or left `open`
File every user-reserved question and every hard-blocker as a native gate with `bd create --type gate`
Keep an agent-decidable technical choice a `decision` issue whose body says the loop may choose.
An ambiguous match defers that candidate only
stop tracker writes only when the listing itself is incomplete
Pass `--no-inherit-labels` on a child that sets explicit labels.
List every gate filed with how to resolve it: `bd gate resolve <id>`.
Run reconcile mode only when the operator asks to reconcile issues already filed
Never read an earlier result note as a verdict
--append-notes <note> --if-assignee '' --if-status open
Never touch an issue whose `source_to_beads_key` does not begin `s2b1|`
Resolve `<remote>` in this order: the remote of the current branch's upstream, else `origin`, else the only remote. When there is no remote, or several remotes with no upstream and none named `origin`, record `Remote: unresolved` and record the tip probes as `unresolved`.
Read `<remote>` from the audit report's `Remote` header when the source is an audit report whose header names a remote; otherwise use the following resolution rule.
A legacy `repo-audit-report/v1` report with no `Remote` header, or a header that reads `unresolved`, uses that rule too, and the receipt says the remote was derived during revalidation.
REQUIREMENTS
    printf '%s\n' "$close_clause"
}

check() {
    file=$1
    [ -f "$file" ] || fail "missing $file"
    while IFS= read -r clause; do
        require "$file" "$clause"
    done <<REQUIREMENTS
$(requirements)
REQUIREMENTS
    rest=$(outside_clause "$file" "$close_clause") || fail "$file lacks exactly one reconcile close clause"
    if printf '%s\n' "$rest" | grep -Eq "$closure_pattern"; then
        fail "$file closes or reopens an issue outside the reconcile confirmation clause"
    fi
}

# Control: a checker that accepts everything.
check_control() { :; }

check "$claude"
check "$codex"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/source-to-beads-contract.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT HUP TERM

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
    # $1 checker, $2 case name, $3 mutation kind, $4 literal, $5 replacement, $6 expected reason
    for host in claude codex; do
        cases=$((cases + 1))
        src="$root/skills/$host/source-to-beads/SKILL.md"
        cp "$src" "$tmp/SKILL.md"
        case "$3" in
            drop) mutate "$tmp/SKILL.md" "$4" "" ;;
            replace) mutate "$tmp/SKILL.md" "$4" "$5" ;;
            append) printf '%s\n' "$4" >> "$tmp/SKILL.md" ;;
        esac
        if out=$("$1" "$tmp/SKILL.md" 2>&1); then
            [ "$1" = check_control ] || echo "  MISS: $2 ($host)" >&2
            misses=$((misses + 1))
        elif ! printf '%s\n' "$out" | grep -Fq -- "$6"; then
            echo "  WRONG REASON: $2 ($host)" >&2
            misses=$((misses + 1))
        fi
    done
}

run_cases() {
    checker=$1
    cases=0
    misses=0
    while IFS= read -r clause; do
        run_case "$checker" "requirement deletion: $clause" drop "$clause" '' "lacks $clause"
    done <<REQUIREMENTS
$(requirements)
REQUIREMENTS
    run_case "$checker" "issue closure outside the clause" append 'bd close example' '' 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "issue reopening" append 'bd reopen example' '' 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "issue closure behind a directory option" append 'bd -C . close example' '' 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "issue reopening behind a directory option" append 'bd -C /tmp/example reopen example' '' 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "issue closure behind a quiet option" append 'bd -q close example' '' 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "closed status written by long flag" append 'bd update example --status closed' '' 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "closed status written by long flag with equals" append 'bd update example --status=closed' '' 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "closed status written by short flag" append 'bd update example -s closed' '' 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "closed status written by quoted flag value" append 'bd update example --status "closed"' '' 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "directory-option close trailing the confirmation clause" replace "$close_clause" "$close_clause Then run \`bd -C . close example\`." 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "close trailing the confirmation clause" replace "$close_clause" "$close_clause Then run \`bd close example\`." 'closes or reopens an issue outside the reconcile confirmation clause'
    run_case "$checker" "second copy of the confirmation clause" append "$close_clause" '' 'lacks exactly one reconcile close clause'
    run_case "$checker" "confirmation clause removed" drop "$close_clause" '' "lacks $close_clause"
    run_case "$checker" "confirmation requirement removed" replace 'only after the operator confirms the close-candidate list' 'without asking the operator' "lacks $close_clause"
    run_case "$checker" "close limited to issues this skill created" replace 'and only an issue this skill created (its `source_to_beads_key` begins `s2b1|`)' 'and any issue' "lacks $close_clause"
    run_case "$checker" "status-guarded result note" drop "--append-notes <note> --if-assignee '' --if-status open" '' 'lacks --append-notes <note> --if-assignee '"'"''"'"' --if-status open'
    run_case "$checker" "fetch that touches only the remote-tracking ref" drop 'which updates only the remote-tracking ref and touches no worktree or local branch' '' 'lacks run `git fetch <remote> refs/heads/<default>`, which updates only the remote-tracking ref and touches no worktree or local branch'
    run_case "$checker" "status-guarded update" drop "--if-assignee '' --if-status open" '' 'lacks --if-assignee '"'"''"'"' --if-status open'
}

check_unrelated() { echo 'FAIL: deliberately unrelated reason' >&2; return 1; }
run_case check_unrelated 'unrelated-reason probe' append 'bd close example' '' 'closes or reopens an issue outside the reconcile confirmation clause'
[ "$misses" -eq 2 ] || fail 'the unrelated-reason probe did not miss both hosts'

run_cases check
[ "$misses" -eq 0 ] || fail "$misses of $cases break cases escaped the contract check"
real_cases=$cases
run_cases check_control
[ "$misses" -eq "$cases" ] || fail "the always-succeeding control caught $((cases - misses)) of $cases cases"
[ "$cases" -eq "$real_cases" ] || fail "control ran a different number of cases"

# A checkout path with a space must not split into two paths: rerun the whole
# suite from a copy under one.
if [ -z "${S2B_SPACE_RERUN:-}" ]; then
    spaced="$tmp/checkout with space"
    mkdir "$spaced"
    cp -R "$root/scripts" "$root/skills" "$spaced/"
    S2B_SPACE_RERUN=1 sh "$spaced/scripts/test-source-to-beads.sh" >/dev/null 2>&1 || fail "the suite fails from a checkout path that contains a space"
fi

echo "OK: source-to-Beads inputs and write boundaries hold in both hosts ($real_cases break cases, control misses all)"
