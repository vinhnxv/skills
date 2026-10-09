#!/bin/sh
# Cross-skill boundary: audit has no Beads commands; the independent writer
# owns Beads metadata and remains consumable by backlog-loop.
set -eu
# Path lists below are newline-separated, so a checkout path with a space
# survives every `for f in $list`; nothing here relies on splitting at a space.
IFS='
'
# At most one argument, and never an option: anything else is a typo to reject.
case "${1:-}" in -*) echo "usage: check-cross-skill.sh [tree-root]" >&2; exit 2 ;; esac
[ "$#" -le 1 ] || { echo "usage: check-cross-skill.sh [tree-root]" >&2; exit 2; }
root="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
fail() { echo "FAIL: $*" >&2; exit 1; }
copies_of() {
    for host in claude codex; do
        f="$root/skills/$host/$1/SKILL.md"
        [ -f "$f" ] && printf '%s\n' "$f"
    done
    return 0
}
# SKILL.md of each copy, then every Markdown file directly in that copy's
# `references/` directory. Scan-type checks (the metadata harvest and the
# author-only label check) read these, so a write moved out of SKILL.md into a
# reference file is still seen and still names its own path. Every contract
# anchor below keeps reading copies_of, SKILL.md only, so a clause moved into
# `references/` fails loudly. A skill with no `references/` yields SKILL.md alone.
scan_copies_of() {
    for f in $(copies_of "$1"); do
        printf '%s\n' "$f"
        for r in "$(dirname -- "$f")"/references/*.md; do
            [ -f "$r" ] && printf '%s\n' "$r"
        done
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

# What counts as a Beads command. scripts/test-repo-audit.sh restates this
# pattern and fails when the two differ.
BD_COMMAND='(^|[^[:alnum:]_])bd[[:space:]]+(-[^[:space:]`]+|[a-z][a-z-]*)([[:space:]`]|$)'
bd_lines() { grep -nE "$BD_COMMAND" "$1" || true; }
# Audit may name the writer as a next action but may not invoke bd itself.
for f in $audit_copies; do
    calls=$(bd_lines "$f")
    [ -z "$calls" ] || fail "repo-audit: $f contains a Beads command: $(printf '%s\n' "$calls" | head -n 1)"
done

bd_set_lines() { bd_lines "$1" | grep -E -- '--(set-)?metadata[ =]|--(add-|set-|remove-)?labels?[ =]|(^|[[:space:]])-l([[:space:]=]|$)' || true; }
# Lines that claim to write <label>: a write verb within six words of the label
# that no negation governs. A negation governs a verb only when it stands within
# four words before it, so one elsewhere on the line, or after the verb, exempts
# nothing. A line that declares the label author-only is the invariant itself
# and is skipped.
prose_claims() {
    grep -nF -- "$2" "$1" | awk -v label="$2" '
        BEGIN {
            nv = split("write writes add adds apply applies set sets attach attaches mark marks labels", v, " ")
            for (i = 1; i <= nv; i++) verb[v[i]] = 1
            nn = split("never no not nothing neither none refuse refuses", n, " ")
            for (i = 1; i <= nn; i++) neg[n[i]] = 1
            label = tolower(label)
        }
        tolower($0) ~ /author.only/ { next }
        {
            line = tolower($0)
            sub(/^[0-9]+:/, "", line)
            while ((p = index(line, label)) > 0) line = substr(line, 1, p - 1) " labeltoken " substr(line, p + length(label))
            gsub(/[^a-z0-9_]+/, " ", line)
            nw = split(line, w, " ")
            for (i = 1; i <= nw; i++) {
                if (!(w[i] in verb)) continue
                near = 0
                for (j = i - 6; j <= i + 6; j++) if (j >= 1 && j <= nw && w[j] == "labeltoken") near = 1
                governed = 0
                for (j = i - 4; j < i; j++) if (j >= 1 && (w[j] in neg)) governed = 1
                if (near && !governed) { print; break }
            }
        }' || true
}
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
        # Every `--metadata <key>` on a line counts, not only the last one.
        printf '%s\n' "$sites" | grep -oE -- '--(set-)?metadata[ =]+[^ `]*' | sed -E 's/^--(set-)?metadata[ =]+//; s/=.*//' || true
        printf '%s\n' "$sites" | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*:' | sed -E 's/^"//; s/"[[:space:]]*:$//' || true
        declared_metadata_keys "$1"
        # The writer's metadata contract lives in prose, with no `bd` write line
        # of its own, so a reserved key it names in backticks is a key it writes.
        case "$1" in
            */source-to-beads/SKILL.md|*/source-to-beads/references/*.md)
                grep -oE '`(backlog_loop|source_to_beads)_[a-z0-9_]+`' "$1" | tr -d '`' || true ;;
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
    grep -qF 'File every user-reserved question and every hard-blocker as a native gate with `bd create --type gate`: `backlog-loop` declares a native gate'"'"'s edges by construction, so no `hard-blocker` label is needed.' "$f" || fail "source-to-beads: $f missing native gate form for hard-blockers"
    grep -qF 'Keep an agent-decidable technical choice a `decision` issue whose body says the loop may choose.' "$f" || fail "source-to-beads: $f missing agent-decidable decision form"
    grep -qF 'a choice only a person can make is a native gate, never a `decision`' "$f" || fail "source-to-beads: $f missing the rule that a person-only choice is a native gate"
    grep -qF 'with the options, a recommended option, and the decision criterion; otherwise create a `spike`' "$f" || fail "source-to-beads: $f missing recommended-option decision form"
done

# Worktree handoff: both skills carry one procedure, print the remove command
# only behind the safety verdict, and never run a worktree removal themselves.
remote_resolution='Resolve `<remote>` in this order: the remote of the current branch'"'"'s upstream, else `origin`, else the only remote. When there is no remote, or several remotes with no upstream and none named `origin`, record `Remote: unresolved` and record the tip probes as `unresolved`.'
handoff_main='In a main checkout print the verdict `not applicable (main checkout)`, with the copy marked not needed and no remove command, because the root checkout is not a removable worktree.'
handoff_root='Resolve `<root>` as the first `worktree` entry of `git worktree list --porcelain`'
handoff_copy='compare the sha256 of each copy with its source'
handoff_sidecar='makes the verdict `not safe to delete`, names the worktree path of the sidecar, and suppresses the remove command'
handoff_print='Only when the checkout is a linked worktree and the verdict is `safe to delete`, print the literal `git worktree remove <worktree>` command for the operator to run.'
handoff_never='Never run `git worktree remove` or `git worktree prune`; removal belongs to the operator.'
without_allowed_worktree_commands() {
    awk -v a="$handoff_print" -v b="$handoff_never" '
        {
            line = $0
            while ((p = index(line, a)) > 0) line = substr(line, 1, p - 1) substr(line, p + length(a))
            while ((p = index(line, b)) > 0) line = substr(line, 1, p - 1) substr(line, p + length(b))
            print line
        }' "$1"
}
for pair in "repo-audit:$audit_copies" "source-to-beads:$writer_copies"; do
    skill=${pair%%:*}
    for f in ${pair#*:}; do
        grep -qE '^## .*Worktree handoff$' "$f" || fail "$skill: $f missing worktree handoff section"
        grep -qF -- "$remote_resolution" "$f" || fail "$skill: $f missing shared remote resolution"
        grep -qF -- "$handoff_main" "$f" || fail "$skill: $f missing main-checkout verdict"
        grep -qF -- "$handoff_root" "$f" || fail "$skill: $f missing handoff root resolution"
        grep -qF -- "$handoff_copy" "$f" || fail "$skill: $f missing handoff copy verification"
        grep -qF -- "$handoff_sidecar" "$f" || fail "$skill: $f missing handoff sidecar safety"
        grep -qF -- "$handoff_print" "$f" || fail "$skill: $f missing printed remove command gated on the verdict"
        grep -qF -- "$handoff_never" "$f" || fail "$skill: $f missing no-remove rule"
        strays=$(without_allowed_worktree_commands "$f" | grep -nE 'worktree[[:space:]]+(remove|prune)' || true)
        [ -z "$strays" ] || fail "$skill: $f instructs running a worktree removal: $(printf '%s\n' "$strays" | head -n 1)"
    done
done
for f in $audit_copies; do
    grep -qF 'Run the handoff once when the report is finalized, before presenting any choice, so every exit, an abandoned session included, already holds the root copy.' "$f" || fail "repo-audit: $f missing finalize-time handoff"
    grep -qF 'Rerun it on every exit, idempotently: on Stop with report, and on Beads and Fix before printing the command.' "$f" || fail "repo-audit: $f missing handoff rerun on every exit"
done
for f in $writer_copies; do
    grep -qF 'Run the handoff after the receipt, reading every receipt issue id back with `bd -C <root> show <id> --json` first.' "$f" || fail "source-to-beads: $f missing post-receipt handoff"
    grep -qF 'compare `bd where` in the current directory with `bd -C <root> where`' "$f" || fail "source-to-beads: $f missing bd where comparison"
done

scratch=$(mktemp -d "${TMPDIR:-/tmp}/check-cross-skill.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
trap 'exit 130' INT HUP TERM
tab=$(printf '\t')
total_keys=0
for skill in $skills; do
    : > "$scratch/keyed.$skill"
    for f in $(scan_copies_of "$skill"); do
        written_metadata_keys "$f" | while IFS= read -r key; do printf '%s\t%s\n' "$key" "$f"; done >> "$scratch/keyed.$skill"
    done
    cut -f1 "$scratch/keyed.$skill" | LC_ALL=C sort -u > "$scratch/keys.$skill"
    n=$(grep -c . "$scratch/keys.$skill" || true)
    total_keys=$((total_keys + n))
done
[ "$total_keys" -gt 0 ] || fail "no metadata key was harvested from any skill"
for skill in backlog-loop source-to-beads; do
    prefix=$(printf '%s' "$skill" | tr '-' '_')_
    for f in $(copies_of "$skill"); do
        awk -F"$tab" -v f="$f" -v p="$prefix" '$2 == f && index($1, p) == 1 { found = 1 } END { exit !found }' "$scratch/keyed.$skill" || fail "$skill: $f yields no metadata key under its own reserved prefix"
    done
done
for skill in $skills; do
    while IFS="$tab" read -r key f; do
        case "$key" in
            backlog_loop_*) [ "$skill" = backlog-loop ] || fail "$skill: $f writes metadata key '$key', reserved to 'backlog-loop'" ;;
            source_to_beads_*) [ "$skill" = source-to-beads ] || fail "$skill: $f writes metadata key '$key', reserved to 'source-to-beads'" ;;
            repo_audit_*) fail "$skill: $f writes legacy audit metadata key '$key'" ;;
        esac
    done < "$scratch/keyed.$skill"
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
    for f in $(scan_copies_of "$skill"); do
        for label in hard-blocker audit-suppressed; do
            sites=$(bd_set_lines "$f" | grep -F -- "$label" || true)
            [ -z "$sites" ] || fail "$skill: $f has a write site for author-only label '$label'"
            claims=$(prose_claims "$f" "$label")
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
    grep -qF 'carries the `human-gate` label, or' "$f" || fail "backlog-loop: $f no longer recognizes the human-gate label"
    grep -qF 'A native gate (`issue_type=gate`) is NEVER repaired or quarantined: its blocking edge is declared by construction, so every edge a producer such as `source-to-beads` writes on one stands.' "$f" || fail "backlog-loop: $f no longer exempts native gate edges from gate repair"
    grep -qF 'an issue is one when its `issue_type` is `decision` and CENSUS classified it as neither `human-gate` nor `label-defect`' "$f" || fail "backlog-loop: $f no longer treats every non-gate decision issue as owner-decision"
    grep -qF 'Three classes stay with a person, and they are told apart by structure and never by reading the body:' "$f" || fail "backlog-loop: $f no longer reserves exactly the structural classes of decision for a person"
    grep -qF 'a decision that changes a contract, permission, or security stance or contradicts a `user-approved` decision' "$f" || fail "backlog-loop: $f no longer reserves a contract, permission, or security decision for a person"
    grep -qF 'backlog_loop_run' "$f" || fail "backlog-loop: $f missing claim marker"
    grep -qF 'hard-blocker' "$f" || fail "backlog-loop: $f missing author-only adoption signal"
done
echo "OK: audit is Beads-free; writer metadata, dedup, and human gates hold; worktree handoff holds; backlog-loop contract holds"
