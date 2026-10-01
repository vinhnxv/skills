#!/bin/sh
# Check the standalone audit contract. Model-driven repository audits are
# exercised separately because their findings depend on the host and model.
# Every anchored clause must fail the check when it is removed from either
# host copy, and a check that always succeeds must miss every such case. The
# model-neutral fixture scripts/fixtures/audit-report-v1.md is validated
# structurally against the skill's own section, dimension, and criterion names,
# and each mutation of it must fail the report check for its stated reason.
set -eu

# No arguments: a typo such as `--fixtures-only` must not pass for a flag.
[ "$#" -eq 0 ] || { echo "usage: test-repo-audit.sh (takes no arguments)" >&2; exit 2; }

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
claude="$root/skills/claude/repo-audit/SKILL.md"
codex="$root/skills/codex/repo-audit/SKILL.md"
fixture="$root/scripts/fixtures/audit-report-v1.md"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/audit-contract.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT HUP TERM

fail() { echo "FAIL: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "$1 lacks $2"; }

# One goal prompt per line, so a checkout path with a space stays whole.
printf '%s\n' "$root/prompts/repo-audit.goal.md" "$root/prompts/repo-audit-readonly.goal.md" > "$tmp/prompts"

# What counts as a Beads command: scripts/check-cross-skill.sh's definition,
# restated here and required to match it.
bd_command='(^|[^[:alnum:]_])bd[[:space:]]+(-[^[:space:]`]+|[a-z][a-z-]*)([[:space:]`]|$)'
grep -qF -- "BD_COMMAND='$bd_command'" "$root/scripts/check-cross-skill.sh" || fail "the Beads command pattern differs from scripts/check-cross-skill.sh"

# One whole clause per line; each must appear verbatim in the skill text.
skill_anchors() {
    cat <<'ANCHORS'
Resolve `<remote>` in this order: the remote of the current branch's upstream, else `origin`, else the only remote. When there is no remote, or several remotes with no upstream and none named `origin`, record `Remote: unresolved` and record the tip probes as `unresolved`.
1. **Run and source snapshot:** schema, run ID, UTC times, host/model if known, repo identity, base SHA and branch, `Remote`, remote default tip, `behind` (or its unknown form with the fetch command), off-default state, linked-worktree status, audited scope, per-path dirty status and local snapshot marker, visibility, restriction level, and report VCS status.
status (`confirmed`, `refuted`, `unevaluable`)
repo-audit-report/v1
docs/audits/
## Criterion roster
all 32 criteria
## Candidate verification
## Portable report
## Cross-model review
## Recommendation and user choice
Fix all confirmed, actionable findings
Fix a subset
Stop with the report
source-to-beads
withheld-no-ignored-path
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
    while IFS= read -r clause; do
        require "$file" "$clause"
    done < "$tmp/skill-anchors"
    if grep -Eq -- "$bd_command" "$file"; then
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

# Header fields a report must carry in section 1.
header_fields() {
    cat <<'FIELDS'
Schema
Run ID
Started (UTC)
Finished (UTC)
Host/model
Repository
Base SHA
Branch
Remote
Remote default tip
Behind
Off default branch
Linked worktree
Audited scope
Dirty paths
Visibility
Restriction level
Report VCS status
FIELDS
}

# Skill text the header fields and statuses above are derived from; a rename in
# the skill must fail here rather than leave the fixture silently stale.
header_anchors() {
    cat <<'ANCHORS'
1. **Run and source snapshot:** schema, run ID, UTC times, host/model if known, repo identity, base SHA and branch, `Remote`, remote default tip, `behind` (or its unknown form with the fetch command), off-default state, linked-worktree status, audited scope, per-path dirty status and local snapshot marker, visibility, restriction level, and report VCS status.
status (`confirmed`, `refuted`, `unevaluable`)
ANCHORS
}

# section <file> <n>: print the body of numbered "## <n>." section.
section() {
    awk -v n="$2" '/^## [0-9]+\./ { s = $2 + 0; next } s == n' "$1"
}

# roster <skill> <heading>: print the body of a "## <heading>" section.
roster() {
    awk -v h="## $2" '$0 == h { p = 1; next } /^## / { p = 0 } p' "$1"
}

# Derive the report vocabulary from the current skill, never from memory.
report_vocab() {
    roster "$claude" 'Portable report' | sed -n 's/^\([0-9]\)\. \*\*\([^*]*\):\*\*.*/\1 \2/p' > "$tmp/sections"
    roster "$claude" 'Dimension roster' | sed -n 's/^| [a-z ]* | \(.*\) |$/\1/p' > "$tmp/dimensions"
    roster "$claude" 'Criterion roster' | sed -n 's/^| `\([a-z][a-z]-[a-z-]*\)` |.*/\1/p' > "$tmp/criteria"
    [ "$(wc -l < "$tmp/sections")" -eq 6 ] || fail "skill names $(wc -l < "$tmp/sections") report sections, expected 6"
    [ "$(wc -l < "$tmp/dimensions")" -eq 9 ] || fail "skill names $(wc -l < "$tmp/dimensions") dimensions, expected 9"
    [ "$(wc -l < "$tmp/criteria")" -eq 32 ] || fail "skill names $(wc -l < "$tmp/criteria") criteria, expected 32"
    header_fields > "$tmp/fields"
    header_anchors > "$tmp/header-anchors"
    while IFS= read -r clause; do
        require "$claude" "$clause"
    done < "$tmp/header-anchors"
}

# check_report <file>: structural validation of a repo-audit-report/v1 report.
check_report() {
    f=$1
    [ -f "$f" ] || fail "missing $f"
    while read -r n name; do
        grep -Fxq -- "## $n. $name" "$f" || fail "$f lacks section heading: ## $n. $name"
    done < "$tmp/sections"
    [ "$(grep -c '^## [0-9]\. ' "$f")" -eq 6 ] || fail "$f does not have exactly six sections"
    if grep -Eq -- "$bd_command" "$f"; then
        fail "$f contains a Beads command"
    fi
    section "$f" 1 > "$tmp/s1"
    while IFS= read -r field; do
        grep -q -- "^- $field: ." "$tmp/s1" || fail "$f lacks header field: $field"
    done < "$tmp/fields"
    value() { sed -n "s/^- $1: //p" "$tmp/s1" | head -n 1; }
    [ "$(value Schema)" = 'repo-audit-report/v1' ] || fail "$f lacks the repo-audit-report/v1 marker"
    value 'Base SHA' | grep -Eq '^[0-9a-f]{40}$' || fail "$f has a malformed base SHA"
    tip=$(value 'Remote default tip')
    printf '%s\n' "$tip" | grep -Eq '^([0-9a-f]{40}|unresolved)$' || fail "$f has a malformed remote default tip"
    if [ "$(value Remote)" = unresolved ]; then
        [ "$tip" = unresolved ] || fail "$f unresolved remote must have an unresolved tip probe"
    fi
    behind=$(value Behind)
    printf '%s\n' "$behind" | grep -Eq '^([0-9]+|unknown \(tip [0-9a-f]+ not fetched\))$' || fail "$f has a malformed behind value"
    off=$(value 'Off default branch')
    printf '%s\n' "$off" | grep -Eq '^(yes|no|unknown)$' || fail "$f has a malformed off-default state"
    value 'Linked worktree' | grep -Eq '^(yes|no)$' || fail "$f has a malformed linked-worktree status"
    value Visibility | grep -Eq '^(public|private|unresolved)$' || fail "$f has a malformed visibility"
    case $behind in
    unknown*) grep -Eq 'git fetch [^ ]+ refs/heads/[^ ]+' "$tmp/s1" || fail "$f lacks the fetch command for an unknown behind" ;;
    esac
    # A stale or off-default checkout must open and close with a Warning: block.
    if [ "$behind" != 0 ] || [ "$off" != no ]; then
        awk '/^## 1\./ { exit } { print }' "$f" > "$tmp/preamble"
        section "$f" 6 > "$tmp/s6"
        grep -q '^Warning:' "$tmp/preamble" || fail "$f lacks the top-of-report Warning: block"
        grep -q 'behind' "$tmp/preamble" || fail "$f Warning: block does not name behind"
        grep -q 'worktree' "$tmp/preamble" || fail "$f Warning: block does not name the worktree status"
        [ "$tip" = unresolved ] || grep -Fq -- "$tip" "$tmp/preamble" || fail "$f Warning: block does not name the tip"
        grep -q '^Warning:' "$tmp/s6" || fail "$f closing summary does not repeat the Warning: block"
    fi
    # Coverage: one row per criterion and per dimension, each with a known status.
    section "$f" 3 > "$tmp/s3"
    [ "$(grep -Ec '^\| `([a-z]{2})-[a-z-]+` \|' "$tmp/s3" || true)" -eq 32 ] || fail "$f does not have 32 criterion rows"
    while IFS= read -r id; do
        [ "$(grep -c "^| \`$id\` |" "$tmp/s3" || true)" -eq 1 ] || fail "$f lacks exactly one criterion row: $id"
    done < "$tmp/criteria"
    while IFS= read -r dim; do
        awk -v d="$dim" 'index($0, "| " d " |") == 1' "$tmp/s3" > "$tmp/dimrow"
        [ "$(wc -l < "$tmp/dimrow")" -eq 1 ] || fail "$f lacks exactly one dimension row: $dim"
        v=$(awk -F'|' '{ gsub(/^ +| +$/, "", $8); print $8 }' "$tmp/dimrow")
        case $v in clean|uncovered|skipped) ;; *) fail "$f dimension row $dim has status $v" ;; esac
    done < "$tmp/dimensions"
    grep '^| `' "$tmp/s3" | awk -F'|' '{ gsub(/^ +| +$/, "", $10); print $10 }' > "$tmp/verdicts"
    if grep -Evq '^(clean|uncovered|skipped)$' "$tmp/verdicts"; then fail "$f has a criterion row with an unknown status"; fi
    grep -q 'not defect-free' "$tmp/s3" || fail "$f does not say that clean means covered search, not defect-free code"
    # Findings: stable ids, known statuses, and counts that section 5 reconciles.
    if grep -Eo 'RA-[0-9A-Za-z_]*' "$f" | grep -Evq '^RA-[0-9a-f]{10}$'; then fail "$f has a malformed RA- id"; fi
    section "$f" 4 > "$tmp/s4"
    grep '^### ' "$tmp/s4" > "$tmp/headings" || true
    n=$(wc -l < "$tmp/headings")
    if grep -Evq '^### RA-[0-9a-f]{10}$' "$tmp/headings"; then fail "$f has a malformed finding heading"; fi
    [ "$(sort "$tmp/headings" | uniq -d | wc -l)" -eq 0 ] || fail "$f repeats a finding id"
    for key in Status Severity Criterion Redaction; do
        [ "$(grep -c "^- $key: ." "$tmp/s4")" -eq "$n" ] || fail "$f does not give every finding a $key"
    done
    if grep '^- Status: ' "$tmp/s4" | grep -Evq '^- Status: (confirmed|refuted|unevaluable)$'; then fail "$f has an unknown finding status"; fi
    if grep '^- Severity: ' "$tmp/s4" | grep -Evq '^- Severity: P[0-4] - .'; then fail "$f has a malformed severity"; fi
    sed -n 's/^- Criterion: `\([^`]*\)`.*/\1/p' "$tmp/s4" > "$tmp/cited"
    while IFS= read -r id; do
        grep -Fxq -- "$id" "$tmp/criteria" || fail "$f finding cites unknown criterion $id"
    done < "$tmp/cited"
    section "$f" 5 > "$tmp/s5"
    for st in confirmed refuted unevaluable; do
        c=$(grep -c "^- Status: $st\$" "$tmp/s4" || true)
        grep -Fxq -- "- $st: $c" "$tmp/s5" || fail "$f section 5 does not count $c $st findings"
    done
    grep -Fq 'No source fix or tracker write was made' "$tmp/s5" || fail "$f section 5 lacks the no-write statement"
}

skill_anchors > "$tmp/skill-anchors"
prompt_anchors > "$tmp/prompt-anchors"
report_vocab

# A deliberately weakened check: it must miss every case below.
check_control() { return 0; }

check "$claude"
check "$codex"
while IFS= read -r p; do check_prompt "$p"; done < "$tmp/prompts"
check_report "$fixture"

# An unresolved remote is explicit provenance, and an unresolved probe is valid.
sed -e 's/^- Remote: origin$/- Remote: unresolved/' -e 's/^- Remote default tip: .*$/- Remote default tip: unresolved/' "$fixture" > "$tmp/unresolved-report.md"
check_report "$tmp/unresolved-report.md"

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

# replace_first <src> <dst> <old> <new>: copy src to dst with one substitution.
replace_first() {
    OLD="$3" NEW="$4" python3 - "$1" "$2" <<'PY'
import os, sys
old = os.environ["OLD"]
s = open(sys.argv[1]).read()
if old not in s:
    sys.stderr.write("test bug: missing text %r\n" % old)
    sys.exit(2)
open(sys.argv[2], "w").write(s.replace(old, os.environ["NEW"], 1))
PY
}

# expect_rejected <label> <reason> <fn> <file>: run the check on one mutated
# file and count a miss when it passes, or when it fails for another reason.
# The always-passing control never reaches the reason test.
expect_rejected() {
    if out=$("$3" "$4" 2>&1); then
        misses=$((misses + 1)); echo "  MISS: $1" >&2
    elif ! printf '%s\n' "$out" | grep -Fq -- "$2"; then
        misses=$((misses + 1)); echo "  WRONG REASON: $1" >&2
    fi
}

# report_case <fn> <name> <reason> <old> <new>: mutate the fixture, then require
# the report check to fail for that reason; an empty <new> deletes the text.
report_case() {
    cases=$((cases + 1))
    replace_first "$fixture" "$tmp/report.md" "$4" "$5"
    expect_rejected "report $2" "$3" "$1" "$tmp/report.md"
}

# run_cases <check-fn> <prompt-check-fn> <report-check-fn>: run every case,
# leaving the number run in `cases` and the number the function missed in `misses`.
run_cases() {
    fn=$1; pfn=$2; rfn=$3; misses=0; cases=0
    for host in claude codex; do
        src="$root/skills/$host/repo-audit/SKILL.md"
        cases=$((cases + 1))
        sed '/repo-audit-report\/v1/d' "$src" > "$tmp/no-schema.md"
        expect_rejected "$host schema deletion" "lacks repo-audit-report/v1" "$fn" "$tmp/no-schema.md"
        # Every spelling of a Beads command must fail, behind global options too.
        for cmd in 'bd create --title example' 'bd -C . create example' 'bd dep add a b' 'bd label add a b' 'bd q example' 'bd -q list' 'bd --version'; do
            cases=$((cases + 1))
            { cat "$src"; printf '\n%s\n' "$cmd"; } > "$tmp/SKILL.md"
            expect_rejected "$host Beads command: $cmd" 'contains a Beads command' "$fn" "$tmp/SKILL.md"
        done
        while IFS= read -r clause; do
            cases=$((cases + 1))
            remove_clause "$src" "$tmp/case.md" "$clause"
            expect_rejected "$host drops: $clause" "lacks $clause" "$fn" "$tmp/case.md"
        done < "$tmp/skill-anchors"
    done
    while IFS= read -r p; do
        while IFS= read -r clause; do
            cases=$((cases + 1))
            remove_clause "$p" "$tmp/case.md" "$clause"
            expect_rejected "$(basename "$p") drops: $clause" "lacks $clause" "$pfn" "$tmp/case.md"
        done < "$tmp/prompt-anchors"
    done < "$tmp/prompts"
    while IFS= read -r field; do
        line=$(awk -v prefix="- $field: " 'index($0, prefix) == 1 { print }' "$fixture")
        report_case "$rfn" "header deletion: $field" "lacks header field: $field" "$line
" ''
    done < "$tmp/fields"
    report_case "$rfn" 'unresolved remote with resolved tip' 'unresolved remote must have an unresolved tip probe' '- Remote: origin' '- Remote: unresolved'
    report_case "$rfn" 'malformed base SHA' 'malformed base SHA' '- Base SHA: 4be07a19c3d8f5e2a61b9047cd3e8f12a5b6c7d0' '- Base SHA: invalid'
    report_case "$rfn" 'malformed remote default tip' 'malformed remote default tip' '- Remote default tip: 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21' '- Remote default tip: invalid'
    report_case "$rfn" 'malformed behind' 'malformed behind value' '- Behind: 3' '- Behind: stale'
    report_case "$rfn" 'malformed off-default state' 'malformed off-default state' '- Off default branch: no' '- Off default branch: maybe'
    report_case "$rfn" 'malformed visibility' 'malformed visibility' '- Visibility: private' '- Visibility: invalid'
    report_case "$rfn" 'duplicate finding IDs' 'repeats a finding id' '### RA-dce059c6b5' '### RA-166172a2cc'
    report_case "$rfn" 'severity vocabulary' 'malformed severity' '- Severity: P2 - a zero quantity reaches the price division; likely on any empty order line.' '- Severity: invalid'
    report_case "$rfn" 'warning missing behind' 'Warning: block does not name behind' 'Warning: the remote default tip is 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 and this checkout is behind it by 3 commits; it is a linked worktree. Findings may already be fixed on the default branch, or exist only on this branch.' 'Warning: the remote default tip is 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 and this checkout is stale it by 3 commits; it is a linked worktree. Findings may already be fixed on the default branch, or exist only on this branch.'
    report_case "$rfn" 'warning missing worktree status' 'Warning: block does not name the worktree status' 'Warning: the remote default tip is 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 and this checkout is behind it by 3 commits; it is a linked worktree. Findings may already be fixed on the default branch, or exist only on this branch.' 'Warning: the remote default tip is 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 and this checkout is behind it by 3 commits; it is a linked checkout. Findings may already be fixed on the default branch, or exist only on this branch.'
    report_case "$rfn" 'warning missing tip' 'Warning: block does not name the tip' 'Warning: the remote default tip is 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 and this checkout is behind it by 3 commits; it is a linked worktree. Findings may already be fixed on the default branch, or exist only on this branch.' 'Warning: the remote default tip is unresolved and this checkout is behind it by 3 commits; it is a linked worktree. Findings may already be fixed on the default branch, or exist only on this branch.'
    report_case "$rfn" 'extra numbered section' 'does not have exactly six sections' '## 6. Closing summary' '## 7. Extra

## 6. Closing summary'
    report_case "$rfn" 'malformed finding heading' 'has a malformed finding heading' '### RA-166172a2cc' '### RA-166172a2cc extra'
    report_case "$rfn" 'missing clean caveat' 'does not say that clean means covered search' 'not defect-free' healthy
    report_case "$rfn" 'missing finding Status' 'does not give every finding a Status' '- Status: confirmed
' ''
    report_case "$rfn" 'missing finding Severity' 'does not give every finding a Severity' '- Severity: P2 - a zero quantity reaches the price division; likely on any empty order line.
' ''
    report_case "$rfn" 'missing finding Criterion' 'does not give every finding a Criterion' '- Criterion: `cc-existing`
' ''
    report_case "$rfn" 'missing finding Redaction' 'does not give every finding a Redaction' '- Redaction: none
' ''
    report_case "$rfn" 'schema field deletion' 'lacks header field: Schema' '- Schema: repo-audit-report/v1
' ''
    report_case "$rfn" 'wrong schema marker' 'lacks the repo-audit-report/v1 marker' '- Schema: repo-audit-report/v1' '- Schema: repo-audit-report/v2'
    report_case "$rfn" 'missing criterion row' 'does not have 32 criterion rows' '| `ti-skipped` | test integrity and vacuous passes | skip markers | 3 | 1 | 3 | 1.00 | 0.33 | clean | none |
' ''
    report_case "$rfn" 'renamed criterion row' 'lacks exactly one criterion row: ti-skipped' '| `ti-skipped` |' '| `ti-skipp` |'
    report_case "$rfn" 'extra criterion row' 'does not have 32 criterion rows' '| `dc-dead-script` |' '| `dc-dead-script` | x | x | 1 | 0 | 0 | 0.00 | 0.00 | clean | none |
| `dc-dead-script` |'
    report_case "$rfn" 'missing dimension row' 'lacks exactly one dimension row: dead and duplicated code' '| dead and duplicated code | 18 |' '| removed | 18 |'
    report_case "$rfn" 'unknown criterion status' 'has a criterion row with an unknown status' '| 0.80 | 0.20 | clean |' '| 0.80 | 0.20 | healthy |'
    report_case "$rfn" 'unknown dimension status' 'dimension row correctness and control flow has status healthy' '| 0.85 | 0.15 | clean |' '| 0.85 | 0.15 | healthy |'
    report_case "$rfn" 'missing section' 'lacks section heading: ## 4. Findings' '## 4. Findings' '## Findings'
    report_case "$rfn" 'short RA- id' 'has a malformed RA- id' '### RA-166172a2cc' '### RA-166172a2c'
    report_case "$rfn" 'uppercase RA- id' 'has a malformed RA- id' '### RA-dce059c6b5' '### RA-DCE059C6B5'
    report_case "$rfn" 'long RA- id' 'has a malformed RA- id' '### RA-026cce4b06' '### RA-026cce4b06f'
    report_case "$rfn" 'unknown finding status' 'has an unknown finding status' '- Status: refuted' '- Status: dismissed'
    report_case "$rfn" 'finding count drift' 'section 5 does not count 3 confirmed findings' '- confirmed: 3' '- confirmed: 2'
    report_case "$rfn" 'unknown criterion in finding' 'finding cites unknown criterion' '- Criterion: `cc-existing`' '- Criterion: `cc-nonexistent`'
    report_case "$rfn" 'missing remote default tip' 'lacks header field: Remote default tip' '- Remote default tip: 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21
' ''
    report_case "$rfn" 'missing behind' 'lacks header field: Behind' '- Behind: 3
' ''
    report_case "$rfn" 'missing linked-worktree status' 'lacks header field: Linked worktree' '- Linked worktree: yes
' ''
    report_case "$rfn" 'missing off-default state' 'lacks header field: Off default branch' '- Off default branch: no
' ''
    report_case "$rfn" 'invalid linked-worktree value' 'malformed linked-worktree status' '- Linked worktree: yes' '- Linked worktree: maybe'
    report_case "$rfn" 'missing top warning' 'lacks the top-of-report Warning: block' 'Warning: the remote default tip is 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 and this checkout is behind it by 3 commits; it is a linked worktree. Findings may already be fixed on the default branch, or exist only on this branch.

## 1.' '## 1.'
    report_case "$rfn" 'closing warning dropped' 'closing summary does not repeat the Warning: block' '
Warning: the remote default tip is 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 and this checkout is behind it by 3 commits; it is a linked worktree. Findings may already be fixed on the default branch, or exist only on this branch.

Coverage:' '
Coverage:'
    report_case "$rfn" 'unknown behind without fetch command' 'lacks the fetch command for an unknown behind' '- Behind: 3' '- Behind: unknown (tip 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 not fetched)'
    report_case "$rfn" 'no-write statement dropped' 'lacks the no-write statement' '- No source fix or tracker write was made during this audit.
' ''
    report_case "$rfn" 'Beads command in report' 'contains a Beads command' '## 6. Closing summary' '## 6. Closing summary

bd create --title example'
    report_case "$rfn" 'Beads command behind a directory option in report' 'contains a Beads command' '## 6. Closing summary' '## 6. Closing summary

bd -C . create example'
}

run_cases check check_prompt check_report
[ "$misses" -eq 0 ] || fail "$misses of $cases case(s) escaped the contract check"
real_cases=$cases
# Weakened pass: it must miss every case, not merely one, so a crashed run
# cannot pass for a discriminating one.
run_cases check_control check_control check_control 2>/dev/null
[ "$misses" -eq "$cases" ] || fail "weakened check missed only $misses of $cases cases; the cases prove nothing"
[ "$cases" -eq "$real_cases" ] || fail "the weakened pass ran a different number of cases"

# A checkout path with a space must not split into two paths: rerun the whole
# suite from a copy under one.
if [ -z "${AUDIT_SPACE_RERUN:-}" ]; then
    spaced="$tmp/checkout with space"
    mkdir "$spaced"
    cp -R "$root/scripts" "$root/skills" "$root/prompts" "$spaced/"
    AUDIT_SPACE_RERUN=1 sh "$spaced/scripts/test-repo-audit.sh" >/dev/null 2>&1 || fail "the suite fails from a checkout path that contains a space"
fi

echo "OK: audit report contract is tracker-independent in both hosts ($real_cases cases, control misses all)"
