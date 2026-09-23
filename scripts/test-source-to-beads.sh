#!/bin/sh
# Guard the source-to-Beads procedure's supported inputs and write boundaries.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
claude="$root/skills/claude/source-to-beads/SKILL.md"
codex="$root/skills/codex/source-to-beads/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "$1 lacks $2"; }

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
    if grep -Eq '(^|[[:space:]`])bd[[:space:]]+(close|reopen)' "$file"; then
        fail "$file claims issue closure or reopening"
    fi
}

check "$claude"
check "$codex"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/source-to-beads-contract.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
sed '/source_to_beads_key/d' "$claude" > "$tmp/no-key.md"
if (check "$tmp/no-key.md") >/dev/null 2>&1; then
    fail "metadata key deletion escaped the contract check"
fi
cp "$claude" "$tmp/SKILL.md"
printf '\nbd close example\n' >> "$tmp/SKILL.md"
if (check "$tmp/SKILL.md") >/dev/null 2>&1; then
    fail "issue closure escaped the contract check"
fi

echo 'OK: source-to-Beads inputs and write boundaries hold in both hosts'
