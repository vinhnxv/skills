#!/bin/sh
# Cross-skill boundary: audit has no Beads commands; the independent writer
# owns Beads metadata and remains consumable by backlog-loop.
set -eu
root="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
fail() { echo "FAIL: $*" >&2; exit 1; }
copies_of() {
    for host in claude codex; do
        f="$root/skills/$host/$1/SKILL.md"
        [ -f "$f" ] && printf '%s\n' "$f"
    done
    return 0
}
[ -d "$root/skills/claude" ] || fail "no Claude skills tree"
skills=$(for host in claude codex; do
    [ -d "$root/skills/$host" ] || continue
    for d in "$root/skills/$host"/*; do [ -d "$d" ] && basename "$d"; done
done | LC_ALL=C sort -u)
[ -n "$skills" ] || fail "no skills found"
audit_copies=$(copies_of repo-audit)
writer_copies=$(copies_of source-to-beads)
consumer_copies=$(copies_of backlog-loop)
[ -n "$audit_copies" ] || fail "repo-audit skill missing"
[ -n "$writer_copies" ] || fail "source-to-beads skill missing"
[ -n "$consumer_copies" ] || fail "backlog-loop skill missing"

# Audit may name the writer as a next action but may not invoke bd itself.
for f in $audit_copies; do
    calls=$(grep -nE '(^|[^[:alnum:]_])bd[[:space:]]+(--[a-z-]+|[a-z][a-z-]*)([[:space:]`]|$)' "$f" || true)
    [ -z "$calls" ] || fail "repo-audit: $f contains a Beads command: $(printf '%s\n' "$calls" | head -n 1)"
done

bd_set_lines() { grep -nE 'bd [a-z]' "$1" | grep -E -- '--(set-)?metadata[ =]|--(add-|set-|remove-)?labels?[ =]' || true; }
declared_metadata_keys() {
    awk -F'|' '
        /^\| *key *\|/ { if ($NF ~ /^ *$/ && $(NF-1) ~ /^ *value *$/) { intable = 1; next } }
        intable && /^\|[ -]*-[ -|]*\|$/ { next }
        intable && !/^\|/ { intable = 0 }
        intable { gsub(/[` ]/, "", $2); if ($2 != "") print $2 }
    ' "$1"
}
written_metadata_keys() {
    sites=$(bd_set_lines "$1")
    {
        printf '%s\n' "$sites" | sed -E 's/.*--(set-)?metadata[ =]+/\n/g' | sed -E 's/[ `].*//; s/=.*//'
        printf '%s\n' "$sites" | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*:' | sed -E 's/^"//; s/"[[:space:]]*:$//' || true
        declared_metadata_keys "$1"
        case "$1" in
            */source-to-beads/SKILL.md)
                for key in source_to_beads_key source_to_beads_source; do
                    grep -qF -- "$key" "$1" && printf '%s\n' "$key"
                done ;;
        esac
    } | grep -E '^[a-z][a-z0-9_]*$' | LC_ALL=C sort -u || true
}
for f in $writer_copies; do
    for key in source_to_beads_key source_to_beads_source; do
        grep -qF -- "$key" "$f" || fail "source-to-beads: $f missing metadata key '$key'"
    done
    grep -qF 'bd list --all --include-gates --limit 0 --json' "$f" || fail "source-to-beads: $f missing full Beads dedup scan"
    grep -qF 'repo_audit_fingerprint' "$f" || fail "source-to-beads: $f missing legacy audit deduplication"
    grep -qF 'legacy issue' "$f" || fail "source-to-beads: $f missing legacy evidence comparison"
    grep -qF 'both open and closed issues' "$f" || fail "source-to-beads: $f missing closed-issue semantic deduplication"
    grep -qF 'stable `RA-` finding ID' "$f" || fail "source-to-beads: $f missing cross-report audit identity"
    grep -qF '[HUMAN]' "$f" || fail "source-to-beads: $f missing human-gate title contract"
    grep -qF 'human-gate' "$f" || fail "source-to-beads: $f missing human-gate label contract"
    grep -qF 'with no parent and no dependency on agent work' "$f" || fail "source-to-beads: $f missing standalone human-gate contract"
    grep -qF 'unless no agent work can run' "$f" || fail "source-to-beads: $f missing hard-blocker exception"
    grep -qi 'read.back' "$f" || fail "source-to-beads: $f missing tracker read-back contract"
done

scratch=$(mktemp -d "${TMPDIR:-/tmp}/check-cross-skill.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
total_keys=0
for skill in $skills; do
    : > "$scratch/keys.$skill"
    for f in $(copies_of "$skill"); do written_metadata_keys "$f" >> "$scratch/keys.$skill"; done
    LC_ALL=C sort -u "$scratch/keys.$skill" -o "$scratch/keys.$skill"
    n=$(grep -c . "$scratch/keys.$skill" || true)
    total_keys=$((total_keys + n))
done
[ "$total_keys" -gt 0 ] || fail "no metadata key was harvested from any skill"
for skill in backlog-loop source-to-beads; do
    prefix=$(printf '%s' "$skill" | tr '-' '_')_
    grep -q "^$prefix" "$scratch/keys.$skill" || fail "$skill yields no metadata key under its own reserved prefix"
done
for skill in $skills; do
    while IFS= read -r key; do
        case "$key" in
            backlog_loop_*) [ "$skill" = backlog-loop ] || fail "$skill writes metadata key '$key', reserved to 'backlog-loop'" ;;
            source_to_beads_*) [ "$skill" = source-to-beads ] || fail "$skill writes metadata key '$key', reserved to 'source-to-beads'" ;;
            repo_audit_*) fail "$skill writes legacy audit metadata key '$key'" ;;
        esac
    done < "$scratch/keys.$skill"
done
for a in $skills; do
    for b in $skills; do
        [ "$a" = "$b" ] && continue
        [ "$(printf '%s\n%s\n' "$a" "$b" | LC_ALL=C sort | head -n 1)" = "$a" ] || continue
        shared=$(LC_ALL=C comm -12 "$scratch/keys.$a" "$scratch/keys.$b" | tr '\n' ' ')
        [ -z "$shared" ] || fail "$a and $b both write metadata key(s): $shared"
    done
done
for skill in $skills; do
    for f in $(copies_of "$skill"); do
        for label in hard-blocker audit-suppressed; do
            sites=$(bd_set_lines "$f" | grep -F -- "$label" || true)
            [ -z "$sites" ] || fail "$skill: $f has a write site for author-only label '$label'"
            claims=$(grep -nF -- "$label" "$f" | grep -E '\b(writes?|adds?|applies|apply|sets?|attaches|attach|marks?|labels)\b' | grep -Evi '\b(never|no|not|nothing|neither|none|refuses?)\b|author.only' || true)
            [ -z "$claims" ] || fail "$skill: $f claims in prose to write author-only label '$label'"
        done
    done
done
for f in $consumer_copies; do
    grep -qE '^\|.*\| `deferred` \|.*status=deferred' "$f" || fail "backlog-loop: $f no longer classifies deferred issues"
    responsible=$(grep -n 'LOOP-RESPONSIBLE SET' "$f" | head -n 1 | cut -d: -f1)
    [ -n "$responsible" ] || fail "backlog-loop: $f missing LOOP-RESPONSIBLE SET"
    sed -n "${responsible}p" "$f" | grep -q '`deferred`' && fail "backlog-loop: $f includes deferred in LOOP-RESPONSIBLE SET"
    grep -q 'issue_type` is `gate`' "$f" || fail "backlog-loop: $f no longer recognizes native gate issues"
    grep -qF 'backlog_loop_run' "$f" || fail "backlog-loop: $f missing claim marker"
    grep -qF 'hard-blocker' "$f" || fail "backlog-loop: $f missing author-only adoption signal"
done
echo "OK: audit is Beads-free; writer metadata, dedup, and human gates hold; backlog-loop contract holds"
