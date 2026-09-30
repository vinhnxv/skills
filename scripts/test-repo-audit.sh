#!/bin/sh
# Check the standalone audit contract. Model-driven repository audits are
# exercised separately because their findings depend on the host and model.
# Every anchored clause must fail the check when it is removed from either
# host copy, and a check that always succeeds must miss every such case.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
claude="$root/skills/claude/repo-audit/SKILL.md"
codex="$root/skills/codex/repo-audit/SKILL.md"
prompts="$root/prompts/repo-audit.goal.md $root/prompts/repo-audit-readonly.goal.md"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/audit-contract.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() { echo "FAIL: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "$1 lacks $2"; }

# One whole clause per line; each must appear verbatim in the skill text.
skill_anchors() {
    cat <<'ANCHORS'
Never fetch or mutate refs; a read-only `git ls-remote` is allowed.
Record the remote default tip from `git ls-remote <remote> refs/heads/<default>`
record a failed probe as `unresolved`
Record linked-worktree status as `yes` when `git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`, otherwise `no`.
record `behind: unknown (tip <sha> not fetched)` and the exact command `git fetch <remote> refs/heads/<default>` for the reader to run
open the report with a `Warning:` block before section 1 that names the tip, `behind`, and the worktree status, and repeat it in the closing summary.
Exclude from the source scan only files that carry the `repo-audit-report/v1` marker
At finalize, rerun `git status --short` over the full set, excluding the report, and record every ignored path read as evidence.
Keep it at `<git-common-dir>/repo-audit-cache/`
discard any row older than 7 days
`RA-` plus the first 10 hex characters of the sha256 of these newline-joined inputs: `ra1`, `repo-id`, the primary criterion (first in roster order), the repo-relative path at the base commit, and the discriminator
Give a finding whose redaction state is not `none` a random `RA-` id instead
record `supersedes: RA-<old>`
`docs/audits/private/<run-id>-detail.md`
verify it with `git check-ignore -q` before writing
`.beads/` in the worktree or at `<git-common-dir>/../.beads`
`/source-to-beads <absolute-report-path> <IDs>`
`$source-to-beads <absolute-report-path> <IDs>`
`compound-engineering:ce-work`
ANCHORS
}

# Header fields the goal prompts must name so their success conditions match.
prompt_anchors() {
    cat <<'ANCHORS'
remote default tip
`behind`
linked-worktree status
ANCHORS
}

check() {
    file=$1
    [ -f "$file" ] || fail "missing $file"
    require "$file" 'repo-audit-report/v1'
    require "$file" 'docs/audits/'
    require "$file" '## Criterion roster'
    require "$file" 'all 32 criteria'
    require "$file" '## Candidate verification'
    require "$file" '## Portable report'
    require "$file" '## Cross-model review'
    require "$file" '## Recommendation and user choice'
    require "$file" 'Fix all confirmed, actionable findings'
    require "$file" 'Fix a subset'
    require "$file" 'Stop with the report'
    require "$file" 'source-to-beads'
    require "$file" 'withheld-no-ignored-path'
    while IFS= read -r clause; do
        require "$file" "$clause"
    done < "$tmp/skill-anchors"
    if grep -Eq '(^|[[:space:]`])bd[[:space:]]+(prime|ready|create|update|close|show|list|export)' "$file"; then
        fail "$file contains a Beads command"
    fi
    count=$(grep -Ec '^\| `([a-z]{2})-[a-z-]+` \|' "$file" || true)
    [ "$count" -eq 32 ] || fail "$file has $count criterion rows, expected 32"
}

check_prompt() {
    [ -f "$1" ] || fail "missing $1"
    while IFS= read -r clause; do
        require "$1" "$clause"
    done < "$tmp/prompt-anchors"
}

skill_anchors > "$tmp/skill-anchors"
prompt_anchors > "$tmp/prompt-anchors"

# A deliberately weakened check: it must miss every case below.
weak_check() { return 0; }

check "$claude"
check "$codex"
for p in $prompts; do check_prompt "$p"; done

# remove_clause <src> <dst> <clause>: copy src to dst without the clause.
remove_clause() {
    CLAUSE="$3" python3 - "$1" "$2" <<'PY'
import os, sys
clause = os.environ["CLAUSE"]
s = open(sys.argv[1]).read()
if clause not in s:
    sys.stderr.write("test bug: missing clause %r\n" % clause)
    sys.exit(2)
open(sys.argv[2], "w").write(s.replace(clause, ""))
PY
}

# run_cases <check-fn> <prompt-check-fn>: count the cases the function misses.
run_cases() {
    fn=$1; pfn=$2; misses=0
    cp "$claude" "$tmp/SKILL.md"
    sed '/repo-audit-report\/v1/d' "$claude" > "$tmp/no-schema.md"
    if ( "$fn" "$tmp/no-schema.md" ) >/dev/null 2>&1; then misses=$((misses + 1)); echo "  MISS: schema deletion" >&2; fi
    printf '\nbd create --title example\n' >> "$tmp/SKILL.md"
    if ( "$fn" "$tmp/SKILL.md" ) >/dev/null 2>&1; then misses=$((misses + 1)); echo "  MISS: Beads command" >&2; fi
    for host in claude codex; do
        src="$root/skills/$host/repo-audit/SKILL.md"
        while IFS= read -r clause; do
            remove_clause "$src" "$tmp/case.md" "$clause"
            if out=$("$fn" "$tmp/case.md" 2>&1); then
                misses=$((misses + 1)); echo "  MISS: $host drops: $clause" >&2
            elif [ "$fn" = check ] && ! printf '%s\n' "$out" | grep -Fq -- "lacks $clause"; then
                misses=$((misses + 1)); echo "  WRONG REASON: $host drops: $clause" >&2
            fi
        done < "$tmp/skill-anchors"
    done
    for p in $prompts; do
        while IFS= read -r clause; do
            remove_clause "$p" "$tmp/case.md" "$clause"
            if ( "$pfn" "$tmp/case.md" ) >/dev/null 2>&1; then
                misses=$((misses + 1)); echo "  MISS: $(basename "$p") drops: $clause" >&2
            fi
        done < "$tmp/prompt-anchors"
    done
    return "$misses"
}

run_cases check check_prompt || fail "$? case(s) escaped the contract check"
# Weakened pass: every case must be missed, so it must report a nonzero miss count.
if run_cases weak_check weak_check 2>/dev/null; then
    fail "weakened check missed no case; the cases prove nothing"
fi

echo 'OK: audit report contract is tracker-independent in both hosts'
