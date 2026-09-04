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

# The two-condition filter itself, so the definition above has ONE
# implementation. Both users below apply it; a second inline copy is a second
# place for the definition to drift from this comment.
bd_set_lines() { # file
    grep -nE 'bd [a-z]' "$1" | grep -E -- "$SET_FLAGS" || true
}

write_sites() { # file, name
    bd_set_lines "$1" | grep -F -- "$2" || true
}

# ---------------------------------------------------------------------------
# THE DECLARED-METADATA TABLE, the second source of written keys.
#
# A skill written as prose states its tracker writes in a table instead of a
# command line, and a checker that reads only command lines therefore sees
# NOTHING in such a skill -- every check below would pass on it for reasons
# that have nothing to do with the invariant. That is not hypothetical: it was
# the state of this file against `repo-audit`, which declares its whole
# namespace as a table and issues no literal `bd ... --set-metadata` anywhere.
#
# The table is identified by its header row and not by a heading, because a
# heading is prose and drifts: a DECLARED-METADATA TABLE is a markdown table
# whose header row's first cell is exactly `key` and whose last cell is exactly
# `value`. Both skills already carry one in that shape. Body rows run until the
# first line that is not a table row; the first cell's backticked token is the
# key.
# ---------------------------------------------------------------------------
declared_metadata_keys() { # file
    awk -F'|' '
        /^\| *key *\|/ { if ($NF ~ /^ *$/ && $(NF-1) ~ /^ *value *$/) { intable = 1; next } }
        intable && /^\|[ -]*-[ -|]*\|$/ { next }
        intable && !/^\|/ { intable = 0 }
        intable { gsub(/[` ]/, "", $2); if ($2 != "") print $2 }
    ' "$1" || true
}

# Every metadata key a file writes, from BOTH sources, unioned.
#
# The command-line source has TWO forms, because `bd` offers two and a check
# that reads one is a check that misses the other entirely. `bd update
# --set-metadata key=value` writes a bare key; `bd create --metadata
# '{"key":"value"}'` writes a JSON object, and that is the form an issue is
# created with -- so a namespace collision introduced at creation would be
# invisible to a bare-token scan.
#
# Tokens that are placeholders rather than literals -- `<key>` and friends --
# do not match the key charset and drop out.
written_metadata_keys() { # file
    sites=$(bd_set_lines "$1")
    {
        # bare form: the token after --metadata or --set-metadata
        printf '%s\n' "$sites" |
            sed -E 's/.*--(set-)?metadata[ =]+/\n/g' |
            sed -E 's/[ `].*//; s/=.*//'
        # JSON form: every object key inside a --metadata argument
        printf '%s\n' "$sites" |
            grep -oE '"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*:' |
            sed -E 's/^"//; s/"[[:space:]]*:$//'
        # declared form: the key column of the skill's own namespace table
        declared_metadata_keys "$1"
    } | grep -E '^[a-z][a-z0-9_]*$' | LC_ALL=C sort -u || true
}

# ---------------------------------------------------------------------------
# THE ANTI-VACUITY GUARD, run before any check that iterates over harvested
# keys. Every check below is a loop over `written_metadata_keys`, so an empty
# harvest makes all of them pass while asserting nothing. A green run has to
# mean the keys were found and compared, not that none were found.
#
# Global: at least one skill in the tree must yield at least one key.
# Per skill: every skill that RESERVES a prefix must yield at least one key
# carrying it. That is the exact form of the drift -- a skill still owns a
# namespace and the harvest no longer finds any of it, whether because the
# table header changed shape, the table moved, or the writes became prose.
# A skill absent from `RESERVED_PREFIXES` reserves nothing and is exempt, which
# is what still lets a third skill land without editing this file.
# ---------------------------------------------------------------------------
total_keys=0
for skill in $skills; do
    for f in $(copies_of "$skill"); do
        n=$(written_metadata_keys "$f" | grep -c . || true)
        total_keys=$((total_keys + n))
    done
done

[ "$total_keys" -gt 0 ] ||
    fail "no metadata key was harvested from any skill in $root/skills -- every namespace check below would pass vacuously"

for pair in $RESERVED_PREFIXES; do
    owner="${pair%%:*}"
    prefix="${pair#*:}"
    owner_copies=$(copies_of "$owner")
    [ -n "$owner_copies" ] || continue
    for f in $owner_copies; do
        own=$(written_metadata_keys "$f" | grep -c "^$prefix" || true)
        [ "$own" -gt 0 ] ||
            fail "$owner: $f yields no metadata key under its own reserved prefix '$prefix' -- the harvest went silent, so every namespace check below would pass vacuously for this skill"
    done
done

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
# 3. NO skill has a write site for either author-only label. Both are written
#    by a person and by nobody else, and the two are checked by one loop
#    because the argument for each is the same one: a label carries no author,
#    no timestamp and no namespace, so nothing at read time can tell a
#    machine's writing from a person's. The only defence is never to write it.
#
#    Every skill, not just the consumer. `backlog-loop` declares
#    `hard-blocker` author-only and `repo-audit` declares `audit-suppressed`
#    author-only, but the prohibition each declares binds BOTH -- an audit that
#    wrote `hard-blocker` would forge a person's judgement in the consumer's
#    tracker just as surely as a consumer that wrote `audit-suppressed` would
#    forge one in the audit's.
# ---------------------------------------------------------------------------
#    TWO detectors, because a skill written as prose issues no `bd` command
#    line at all and the command-line detector alone sees nothing in it. The
#    second reads the prose: a line that NAMES the label and carries an
#    affirmative write verb, with no negation on that same line, is a claim to
#    write it. Both procedures must be able to TALK about these labels -- to
#    declare the prohibition, to read one at decision time, to report one they
#    observed -- so the negation clause is what keeps the prohibition sentences
#    and every read-context sentence from tripping it.
#
#    STATED BLIND SPOT: the prose detector is a heuristic over one line. A
#    write claim spread across two sentences, or phrased without any of the
#    verbs below, is not caught. It is here because the alternative measured on
#    this tree was zero detection, not because prose can be decided statically.
# ---------------------------------------------------------------------------
WRITE_VERBS='\b(writes?|adds?|applies|apply|sets?|attaches|attach|marks?|labels)\b|--add-label|--labels|--set-labels'
NEGATIONS='\b([Nn]ever|NEVER|[Nn]o|NO|[Nn]ot|NOT|[Nn]othing|[Nn]either|[Nn]one|refuses?)\b|AUTHOR ONLY|author-only'

prose_write_claims() { # file, label
    grep -nF -- "$2" "$1" | grep -E -- "$WRITE_VERBS" | grep -Ev -- "$NEGATIONS" || true
}

for skill in $skills; do
    for f in $(copies_of "$skill"); do
        for label in $AUTHOR_ONLY_LABEL $SUPPRESSION_LABEL; do
            sites=$(write_sites "$f" "$label")
            [ -z "$sites" ] ||
                fail "$skill: $f has a write site for the author-only label '$label': $(echo "$sites" | head -n 1)"
            claims=$(prose_write_claims "$f" "$label")
            [ -z "$claims" ] ||
                fail "$skill: $f claims in prose to write the author-only label '$label': $(echo "$claims" | head -n 1)"
        done
    done
done

# ---------------------------------------------------------------------------
# 4. Facts in the consumer's text that `repo-audit`'s own protections rest on.
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

    # R77, second half: the audit's DEFERENCE BY STATUS table switches on the
    # VALUES of `backlog_loop_cause`, not just on the key's existence. A run
    # sweeps a `blocked` issue under `needs-person` and yields to one under a
    # `transient` cause. Rename either value and the audit still finds the key,
    # matches neither arm, and takes whichever default the executor invents.
    grep -q 'backlog_loop_cause' "$f" ||
        fail "backlog-loop: $f no longer records 'backlog_loop_cause' (breaks repo-audit R77: the deference-by-status table has nothing to switch on)"
    for cause in needs-person transient; do
        grep -F -- "$cause" "$f" | grep -q 'backlog_loop_cause\|`blocked`' ||
            fail "backlog-loop: $f no longer uses the '$cause' cause vocabulary (breaks repo-audit R77: the deference-by-status table's '$cause' arm can never match)"
    done

    # The author-only label's exact spelling. Check 3 forbids every skill from
    # writing `hard-blocker`, but that prohibition is only worth holding while
    # the consumer still USES that literal as its adoption signal; a rename
    # there leaves check 3 policing a string nothing reads.
    grep -qF -- "$AUTHOR_ONLY_LABEL" "$f" ||
        fail "backlog-loop: $f no longer names the '$AUTHOR_ONLY_LABEL' label (check 3 above would then police a string this procedure does not use)"
done

if [ "$consumer_checked" -eq 1 ]; then
    echo "OK: metadata namespaces disjoint, no author-only or suppression label write site, consumer facts hold"
else
    echo "OK: metadata namespaces disjoint, no author-only or suppression label write site (no consumer present)"
fi
