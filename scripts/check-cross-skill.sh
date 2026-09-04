#!/bin/sh
# Assert the invariants two skills depend on EACH OTHER for.
#
# Usage: check-cross-skill.sh [tree-root]
#
# tree-root defaults to the repository root (this script's parent directory).
#
# check-parity.sh compares a skill against its own other host copy, so nothing
# in it can assert that two DIFFERENT skills keep their metadata namespaces
# apart, that neither writes a label the other reserves, or that a fact one
# skill's safety rests on still holds in the other skill's text. Those are the
# only invariants this file owns, and it is the only place they are checked.
#
# Exits 0 with a one-line summary, or non-zero naming the specific invariant.

set -eu

# Metadata key prefixes reserved to one skill. A skill absent from this table
# reserves nothing, which is what lets a third skill land without editing it.
RESERVED_PREFIXES="backlog-loop:backlog_loop_ repo-audit:repo_audit_"

# The label `backlog-loop` declares author-only: NO step of either procedure
# may write it, on any issue, in any mode.
AUTHOR_ONLY_LABEL="hard-blocker"

# The label `repo-audit` uses to mark a finding suppressed. `backlog-loop` must
# never write it: a suppression the consumer authored would be a suppression
# the audit cannot account for and would re-derive against.
SUPPRESSION_LABEL="audit-suppressed"

root="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -d "$root/skills/claude" ] || fail "no Claude skills tree at $root/skills/claude"

# Every SKILL.md copy of one skill, both hosts, whichever exist.
copies_of() {
    for host in claude codex; do
        f="$root/skills/$host/$1/SKILL.md"
        [ -f "$f" ] && echo "$f"
    done
    return 0
}

skills=$(
    for host in claude codex; do
        [ -d "$root/skills/$host" ] || continue
        for d in "$root/skills/$host"/*; do
            [ -d "$d" ] || continue
            basename "$d"
        done
    done | LC_ALL=C sort -u
)

[ -n "$skills" ] || fail "no skills found under $root/skills"

# ---------------------------------------------------------------------------
# A WRITE SITE, defined once, before any check below uses it.
#
# An occurrence of the name on a line that is a `bd` command form AND carries a
# label-setting or metadata-setting flag. The definition has to be this narrow
# because BOTH procedures must talk about the names they promise not to write:
# `backlog-loop` names the author-only label in its own author-only declaration
# and again in its adoption gate, and `repo-audit` carries the same prohibition.
# A naive grep for the name fails on the current tree, and an implementer left
# to invent the rule narrows it until it matches nothing at all.
#
# `--metadata-field` and `--has-metadata-key` are READ flags and are excluded:
# filtering on a key is not writing one. The trailing character class is what
# keeps `--metadata-field` from matching the `--metadata` alternative.
# ---------------------------------------------------------------------------
SET_FLAGS='--metadata[ =]|--set-metadata[ =]|--labels[ =]|--set-labels[ =]|--add-label[ =]|--remove-label[ =]'

write_sites() { # file, name
    grep -nF -- "$2" "$1" | grep -E 'bd [a-z]' | grep -E -- "$SET_FLAGS" || true
}

# Metadata keys a file actually WRITES: the token after a metadata-setting
# flag, on a line that is a write site, with any `=value` stripped. Tokens that
# are placeholders rather than literals -- `<key>` and friends -- do not match
# the key charset and drop out here.
written_metadata_keys() { # file
    grep -nE 'bd [a-z]' "$1" | grep -E -- "$SET_FLAGS" |
        sed -E 's/.*--(set-)?metadata[ =]+/\n/g' |
        sed -E 's/[ `].*//; s/=.*//' |
        grep -E '^[a-z][a-z0-9_]*$' | LC_ALL=C sort -u || true
}

reserved_prefix_of() { # skill
    for pair in $RESERVED_PREFIXES; do
        case "$pair" in
            "$1":*) echo "${pair#*:}"; return 0 ;;
        esac
    done
    return 0
}

owner_of_prefix() { # prefix
    for pair in $RESERVED_PREFIXES; do
        case "$pair" in
            *:"$1") echo "${pair%%:*}"; return 0 ;;
        esac
    done
    return 0
}

# ---------------------------------------------------------------------------
# 1. No skill writes a metadata key reserved to another skill.
#
#    Checked over WRITE SITES and not over mentions, because `repo-audit` must
#    name the consumer's claim marker in order to defer to it, and a check that
#    read mentions would forbid the very sentence that makes the deference
#    work.
# ---------------------------------------------------------------------------
for skill in $skills; do
    for f in $(copies_of "$skill"); do
        for key in $(written_metadata_keys "$f"); do
            for pair in $RESERVED_PREFIXES; do
                prefix="${pair#*:}"
                owner="${pair%%:*}"
                [ "$owner" = "$skill" ] && continue
                case "$key" in
                    "$prefix"*)
                        fail "$skill: $f writes metadata key '$key', which is reserved to '$owner'" ;;
                esac
            done
        done
    done
done

# ---------------------------------------------------------------------------
# 2. Two skills never write the same metadata key, whether or not either owns
#    a reserved prefix. Check 1 covers the declared namespaces; this covers a
#    key neither skill declared, which is how a collision actually arrives.
# ---------------------------------------------------------------------------
scratch=$(mktemp -d "${TMPDIR:-/tmp}/check-cross-skill.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

for skill in $skills; do
    : > "$scratch/keys.$skill"
    for f in $(copies_of "$skill"); do
        written_metadata_keys "$f" >> "$scratch/keys.$skill"
    done
    LC_ALL=C sort -u "$scratch/keys.$skill" -o "$scratch/keys.$skill"
done

for a in $skills; do
    for b in $skills; do
        [ "$a" = "$b" ] && continue
        # Each unordered pair once. `test` has no string-ordering operator in
        # POSIX -- the one bash offers is absent from the shell that runs this
        # on a stock Linux runner -- so the order is decided by sort.
        [ "$(printf '%s\n%s\n' "$a" "$b" | LC_ALL=C sort | head -n 1)" = "$a" ] || continue
        shared=$(LC_ALL=C comm -12 "$scratch/keys.$a" "$scratch/keys.$b" | tr '\n' ' ')
        [ -z "$shared" ] ||
            fail "$a and $b both write metadata key(s): $shared"
    done
done

# ---------------------------------------------------------------------------
# 3. Neither skill has a write site for the author-only label.
# ---------------------------------------------------------------------------
for skill in $skills; do
    for f in $(copies_of "$skill"); do
        sites=$(write_sites "$f" "$AUTHOR_ONLY_LABEL")
        [ -z "$sites" ] ||
            fail "$skill: $f has a write site for the author-only label '$AUTHOR_ONLY_LABEL': $(echo "$sites" | head -n 1)"
    done
done

# ---------------------------------------------------------------------------
# 4. The suppression label has a write site in exactly one skill, and it is
#    never `backlog-loop`.
# ---------------------------------------------------------------------------
for f in $(copies_of backlog-loop); do
    sites=$(write_sites "$f" "$SUPPRESSION_LABEL")
    [ -z "$sites" ] ||
        fail "backlog-loop: $f has a write site for the suppression label '$SUPPRESSION_LABEL': $(echo "$sites" | head -n 1)"
done

# ---------------------------------------------------------------------------
# 5. Facts in the consumer's text that `repo-audit`'s own protections rest on.
#    Each failure names the audit requirement it breaks, because the failure is
#    otherwise unreadable: the consumer's text is correct on its own terms and
#    only wrong with respect to an assumption made in another file.
#
#    Skipped when the consumer is absent, so a tree with one skill still passes.
# ---------------------------------------------------------------------------
consumer_checked=0
for f in $(copies_of backlog-loop); do
    consumer_checked=1

    # R28: the audit's index issue is parked as `deferred` so the consumer
    # never claims it. That needs the category to exist AND to sit outside the
    # set the loop clears. Without both, the index is claimed, implemented and
    # closed, and every run's cross-run state is destroyed.
    grep -qE '^\|.*\| `deferred` \|.*status=deferred' "$f" ||
        fail "backlog-loop: $f no longer classifies a 'deferred' issue (breaks repo-audit R28: the index issue would be claimed)"

    responsible=$(grep -n 'LOOP-RESPONSIBLE SET' "$f" | head -n 1 | cut -d: -f1)
    [ -n "$responsible" ] ||
        fail "backlog-loop: $f no longer declares a LOOP-RESPONSIBLE SET (breaks repo-audit R28)"
    sed -n "${responsible}p" "$f" | grep -q '`deferred`' &&
        fail "backlog-loop: $f now counts 'deferred' in its loop-responsible set (breaks repo-audit R28: the index issue would be claimed)"

    # R30: the audit files human gates using the tracker's native gate type and
    # relies on the consumer recognizing it before anything else.
    grep -q 'issue_type` is `gate`' "$f" ||
        fail "backlog-loop: $f no longer recognizes the native gate type (breaks repo-audit R30: filed gates would be claimed as ordinary work)"

    # R77: the audit defers to an issue the consumer has claimed, recognized by
    # this literal key. A rename preserves namespace disjointness and passes
    # every other check here while silently voiding the whole deference rule.
    grep -q 'backlog_loop_run' "$f" ||
        fail "backlog-loop: $f no longer uses 'backlog_loop_run' as its claim marker (breaks repo-audit R77: deference would never trigger)"
done

if [ "$consumer_checked" -eq 1 ]; then
    echo "OK: metadata namespaces disjoint, no author-only or suppression label write site, consumer facts hold"
else
    echo "OK: metadata namespaces disjoint, no author-only or suppression label write site (no consumer present)"
fi
