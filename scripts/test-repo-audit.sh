#!/bin/sh
# Check the standalone audit contract. Model-driven repository audits are
# exercised separately because their findings depend on the host and model.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
claude="$root/skills/claude/repo-audit/SKILL.md"
codex="$root/skills/codex/repo-audit/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "$1 lacks $2"; }

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
    if grep -Eq '(^|[[:space:]`])bd[[:space:]]+(prime|ready|create|update|close|show|list|export)' "$file"; then
        fail "$file contains a Beads command"
    fi
    count=$(grep -Ec '^\| `([a-z]{2})-[a-z-]+` \|' "$file" || true)
    [ "$count" -eq 32 ] || fail "$file has $count criterion rows, expected 32"
}

check "$claude"
check "$codex"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/audit-contract.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cp "$claude" "$tmp/SKILL.md"
sed '/repo-audit-report\/v1/d' "$claude" > "$tmp/no-schema.md"
if (check "$tmp/no-schema.md") >/dev/null 2>&1; then
    fail "schema deletion escaped the contract check"
fi
printf '\nbd create --title example\n' >> "$tmp/SKILL.md"
if (check "$tmp/SKILL.md") >/dev/null 2>&1; then
    fail "Beads command escaped the contract check"
fi

echo 'OK: audit report contract is tracker-independent in both hosts'
