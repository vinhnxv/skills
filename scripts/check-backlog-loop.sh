#!/bin/sh
# Assert the invariants ONE skill -- `backlog-loop` -- depends on internally.
#
# Usage: check-backlog-loop.sh [tree-root]
#
# tree-root defaults to the repository root (this script's parent directory).
#
# check-parity.sh compares a skill against its own other host copy, so it
# passes on two copies that are identically wrong. check-cross-skill.sh owns
# only the invariants that span two DIFFERENT skills, so nothing in it can see
# a rule `backlog-loop` keeps with itself. The rules below are that third kind:
# each is a fact one part of the procedure rests on and another part supplies,
# inside one file, and each one has already been deleted once and wedged a run.
#
# What is checked, and what breaks when it goes:
#
#   R5  every `backlog_loop_phase` value the ledger declares reaches a RECOVERY
#       arm, and RECOVERY carries a default arm for an absent or unrecognized
#       value. A phase with no arm ends the run outright, on every invocation,
#       until a person edits the tracker by hand.
#   R9  the ledger row states that its value set is closed. Without that
#       sentence the arm list can be enumerated correctly and still be an open
#       set, so a later run improvises an eighth value and the default arm is
#       the only thing between it and the wedge above.
#   R1  the `hooked`, `pinned` and `deferred` rows outrank `abandoned-claim` in
#       CLASSIFY, and `abandoned-claim` excludes all three. Below them, a
#       parked issue carrying a dead marker is read as this loop's own wreckage
#       and reopened into a pool a person removed it from -- on every run.
#   R8  the procedure writes only `open` and `blocked` as literal `--status=`
#       flags, and `## CONSTRAINTS` names the three statuses it refuses. A run
#       that parks an issue is writing under the authority of whoever reads
#       that status next, and `deferred` in particular is a sibling skill's
#       own parking mechanism.
#   R11 `## CENSUS` carries the RESIDUE PASS opener. Without the pass a person
#       clears every parked issue's dead ledger residue by hand.
#   R12 the WRITE GATE paragraph counts RESIDUE PASS among the writes it
#       covers. A mutation pass outside the write gate mutates a person's
#       tracker during a diagnostic run and while another invocation holds a
#       live heartbeat.
#   Both directions of the CLASSIFY-to-`<cause>` census: a category with no
#       `<cause>` row emits a blank third field, and a `<cause>` row for a
#       category CLASSIFY does not carry is a row nothing can ever reach.
#
# Every check runs over BOTH host copies, because a rule deleted from one copy
# is a rule that is gone for every operator on that host.
#
# Exits 0 with a one-line summary, or non-zero naming the specific rule.

set -eu

SKILL_NAME="backlog-loop"

# The statuses this procedure is allowed to write with a literal `--status=`
# flag. `in_progress` and `closed` are written too, but through `bd start` and
# `bd close`, so they never appear in this form.
ALLOWED_STATUS_WRITES="open blocked"

# The statuses the procedure must refuse to write, and which CLASSIFY must
# reach before `abandoned-claim`.
PARKED_STATUSES="hooked pinned deferred"

root="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -d "$root/skills" ] || fail "no skills tree at $root/skills"

# Every SKILL.md copy of one skill, both hosts, whichever exist. Same shape as
# check-cross-skill.sh's helper, and for the same reason: a host tree that is
# absent is not a failure, but a host tree that is present is checked.
copies_of() {
    for host in claude codex; do
        f="$root/skills/$host/$1/SKILL.md"
        [ -f "$f" ] && echo "$f"
    done
    return 0
}

# ---------------------------------------------------------------------------
# EXTRACTION. Every table is matched on its EXACT header line and terminated by
# the blank line after it. A range that ran to the next heading instead would
# swallow the table below it, and the two-way census would then reconcile one
# roster against itself.
# ---------------------------------------------------------------------------

# The CLASSIFY precedence table: `| # | category | test |`.
classify_rows() { # file
    sed -n '/^| # | category | test |$/,/^$/p' "$1" | grep '^| [0-9]' || true
}

# The EMIT `<cause>` table: `| category | `<cause>` |`.
cause_rows() { # file
    sed -n '/^| category | `<cause>` |$/,/^$/p' "$1" | grep '^| `' || true
}

# THE RUN LEDGER's key table, one row.
ledger_phase_row() { # file
    sed -n '/^| key | written at | value |$/,/^$/p' "$1" |
        grep '^| `backlog_loop_phase` |' || true
}

# RECOVERY has no header line and no terminator before `## CENSUS`, so it is
# bounded from its own opener to the blank line AFTER its last `- ` arm. Ending
# it at the next blank line instead would cut the block at the blank between
# the opener and the first arm and leave nothing to search.
recovery_block() { # file
    awk '
        /^RECOVERY,/ { inb = 1 }
        inb && seen && /^$/ { exit }
        inb { print; if ($0 ~ /^- /) seen = 1 }
    ' "$1"
}

recovery_arms() { # file
    recovery_block "$1" | grep '^- ' || true
}

# One `## ALL-CAPS` section, up to the next one.
section_of() { # file, heading
    awk -v h="$2" '
        $0 == h { inb = 1; next }
        inb && /^## / { exit }
        inb { print }
    ' "$1"
}

# The phase values the ledger declares, from the row's value cell. The closing
# sentence carries no backticks, so it contributes nothing here -- which is why
# it needs an assertion of its own below.
phase_values() { # file
    ledger_phase_row "$1" |
        awk -F'|' '{ print $4 }' |
        grep -oE '`[a-z][a-z0-9-]*`' | tr -d '`' | LC_ALL=C sort -u || true
}

# The `#` column of one CLASSIFY row, found by its category.
classify_row_number() { # file, category
    classify_rows "$1" | awk -F'|' -v want="$2" '
        { n = $2; c = $3; gsub(/[ \t`]/, "", n); gsub(/[ \t`]/, "", c)
          if (c == want) print n }
    '
}

# The `test` column of one CLASSIFY row, found by its category.
classify_row_test() { # file, category
    classify_rows "$1" | awk -F'|' -v want="$2" '
        { c = $3; gsub(/[ \t`]/, "", c); if (c == want) print $4 }
    '
}

classify_categories() { # file
    classify_rows "$1" |
        awk -F'|' '{ c = $3; gsub(/[ \t`]/, "", c); print c }' |
        grep -E '^[a-z][a-z0-9-]*$' | LC_ALL=C sort -u || true
}

# The `<cause>` table has 12 rows for 15 categories: three cells name two or
# three categories at once, joined by ` / `. Split the category cell on that
# separator before reading tokens off it, or the two-way census below reports
# orphans against a correct file and the check has to be weakened to pass.
cause_categories() { # file
    cause_rows "$1" |
        awk -F'|' '{ c = $2; gsub(/ \/ /, "\n", c); print c }' |
        grep -oE '`[a-z][a-z0-9-]*`' | tr -d '`' | LC_ALL=C sort -u || true
}

work=$(mktemp -d "${TMPDIR:-/tmp}/check-backlog-loop.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

copies=$(copies_of "$SKILL_NAME")
[ -n "$copies" ] ||
    fail "no $SKILL_NAME/SKILL.md under $root/skills for either host -- every rule below would pass vacuously"

checked=0

for f in $copies; do
    checked=$((checked + 1))

    classify=$(classify_rows "$f")
    causes=$(cause_rows "$f")
    phases=$(phase_values "$f")
    arms=$(recovery_arms "$f")
    recovery=$(recovery_block "$f")

    n_classify=$(printf '%s\n' "$classify" | grep -c . || true)
    n_causes=$(printf '%s\n' "$causes" | grep -c . || true)
    n_phases=$(printf '%s\n' "$phases" | grep -c . || true)
    n_arms=$(printf '%s\n' "$arms" | grep -c . || true)

    # -----------------------------------------------------------------------
    # THE ANTI-VACUITY GUARD, before anything that iterates. Every check below
    # is a loop over one of these four extractions, so an empty one makes all
    # of them pass while asserting nothing -- and an empty one is the LIKELY
    # failure here, because each extraction is pinned to an exact header line
    # that a reformatting edit changes without touching a rule. A green run has
    # to mean the rows were found and compared, not that none were found.
    # -----------------------------------------------------------------------
    [ "$n_classify" -gt 0 ] ||
        fail "$f: the CLASSIFY table did not parse -- no row matched under the '| # | category | test |' header, so every precedence and census check below would pass vacuously"
    [ "$n_causes" -gt 0 ] ||
        fail "$f: the EMIT <cause> table did not parse -- no row matched under the '| category | \`<cause>\` |' header, so the two-way category census below would pass vacuously"
    [ "$n_phases" -gt 0 ] ||
        fail "$f: THE RUN LEDGER's \`backlog_loop_phase\` row declares no phase value, so the RECOVERY arm census below would pass vacuously"
    [ "$n_arms" -gt 0 ] ||
        fail "$f: the RECOVERY block extracted no '- ' arm, so every RECOVERY check below would pass vacuously"

    # -----------------------------------------------------------------------
    # R9. The ledger row closes its own value set.
    #
    # Checked separately from the arm census because the two fail apart: a run
    # can enumerate every declared value into an arm and still meet a value
    # nothing declared, which is exactly the improvised `deferred_watch` that
    # wedged this loop. Deleting this sentence leaves the arm list green.
    # -----------------------------------------------------------------------
    ledger_phase_row "$f" | grep -q 'only phase values this procedure writes' ||
        fail "$f: THE RUN LEDGER's \`backlog_loop_phase\` row no longer states that its values are the only phase values this procedure writes (breaks R9: the enum is open again, so a later run can improvise a value no arm was written for)"

    # -----------------------------------------------------------------------
    # R5, first half. Every declared phase value reaches a RECOVERY arm.
    #
    # Matched as a WHOLE backtick-delimited token and never as a substring:
    # "reclaimed" contains "claimed", so a substring test stays green after the
    # `claimed` arm is deleted -- which is the one arm whose loss silently
    # abandons a claimed-but-unbuilt batch.
    # -----------------------------------------------------------------------
    for phase in $phases; do
        printf '%s\n' "$recovery" | grep -qF -- "\`$phase\`" ||
            fail "$f: THE RUN LEDGER declares phase \`$phase\` but no RECOVERY arm names it as a backtick-delimited token (breaks R5: a run interrupted at that phase matches no arm and ends outright)"
    done

    # -----------------------------------------------------------------------
    # R5, second half. RECOVERY carries a default arm.
    #
    # The declared values are not the whole population: the `<cause>` table
    # already admits the phase can be ABSENT, and an earlier run wrote a value
    # the ledger never listed. Both reach this arm and nothing else.
    # -----------------------------------------------------------------------
    printf '%s\n' "$arms" |
        grep -qE '^- Absent, or any value the .backlog_loop_phase. row above does not list:' ||
        fail "$f: RECOVERY carries no arm for an absent or unrecognized \`backlog_loop_phase\` (breaks R5: an absent or improvised phase reaches no arm, and one such value wedges every later invocation)"

    # -----------------------------------------------------------------------
    # R1, first half. The parked rows outrank `abandoned-claim`.
    #
    # Compared as row NUMBERS rather than by file order, because the numbers
    # are what the rationale block and three other sentences cite; a table
    # reordered without renumbering would satisfy a positional test and leave
    # every citation pointing at the wrong row.
    # -----------------------------------------------------------------------
    abandoned=$(classify_row_number "$f" abandoned-claim)
    [ -n "$abandoned" ] ||
        fail "$f: the CLASSIFY table carries no \`abandoned-claim\` row (breaks R1: the row the parked statuses must outrank is gone, so the ordering rule below has nothing to compare against)"

    for status in $PARKED_STATUSES; do
        n=$(classify_row_number "$f" "$status")
        [ -n "$n" ] ||
            fail "$f: the CLASSIFY table carries no \`$status\` row (breaks R1: a parked issue then falls through to \`abandoned-claim\` and is reopened into the pool a person removed it from)"
        [ "$n" -lt "$abandoned" ] ||
            fail "$f: CLASSIFY row $n \`$status\` does not outrank row $abandoned \`abandoned-claim\` (breaks R1: a parked issue carrying a dead marker is filed as this loop's own wreckage and RECOVERY reopens it on every run)"
    done

    # -----------------------------------------------------------------------
    # R1, second half. `abandoned-claim`'s status test excludes all three.
    #
    # The precedence order alone is not enough: it is an exclusion list rather
    # than a list of the statuses this procedure writes, so an operator-defined
    # status keeps reaching this row and therefore RECOVERY. Dropping one of
    # the three from the list makes the row collide with its own predecessor
    # the moment the table is reordered again.
    # -----------------------------------------------------------------------
    test_cell=$(classify_row_test "$f" abandoned-claim)
    for status in $PARKED_STATUSES; do
        printf '%s\n' "$test_cell" | grep -qF -- "\`$status\`" ||
            fail "$f: the \`abandoned-claim\` CLASSIFY row does not exclude \`$status\` (breaks R1: the two rows overlap, so the precedence order is the only thing keeping a parked issue out of this row)"
    done

    # -----------------------------------------------------------------------
    # The CLASSIFY-to-`<cause>` census, both directions.
    #
    # EMIT states that every category has a `<cause>`, so no line is ever left
    # with a blank third field. A category with no row breaks that promise; a
    # `<cause>` row for a category CLASSIFY does not carry is a row nothing can
    # ever emit, and it is how a renamed category looks from this side.
    # -----------------------------------------------------------------------
    classify_categories "$f" > "$work/classify-cats"
    cause_categories "$f" > "$work/cause-cats"

    LC_ALL=C comm -23 "$work/classify-cats" "$work/cause-cats" > "$work/no-cause"
    missing=$(grep -c . "$work/no-cause" || true)
    [ "$missing" -eq 0 ] ||
        fail "$f: $missing CLASSIFY categor(y/ies) have no row in the EMIT <cause> table, so their census line would carry a blank third field: $(tr '\n' ' ' < "$work/no-cause")"

    LC_ALL=C comm -13 "$work/classify-cats" "$work/cause-cats" > "$work/orphan-cause"
    orphans=$(grep -c . "$work/orphan-cause" || true)
    [ "$orphans" -eq 0 ] ||
        fail "$f: $orphans EMIT <cause> categor(y/ies) name no CLASSIFY row, so nothing can ever emit them: $(tr '\n' ' ' < "$work/orphan-cause")"

    # -----------------------------------------------------------------------
    # R8, first half. Every literal `--status=` write is one of two values.
    #
    # Read off the whole file rather than one section, because the write that
    # matters is the one somebody adds to a procedure step years from now. A
    # status this procedure does not write is a status somebody else's
    # decision owns -- `deferred` most of all, since `repo-audit` parks its own
    # index issue there precisely so this loop cannot claim it.
    # -----------------------------------------------------------------------
    grep -o -- '--status=[A-Za-z0-9_-]*' "$f" | sed 's/^--status=//' | LC_ALL=C sort -u > "$work/status-writes"
    while read -r status; do
        [ -n "$status" ] || continue
        case " $ALLOWED_STATUS_WRITES " in
            *" $status "*) ;;
            *) fail "$f: writes \`--status=$status\`, which is outside the { $ALLOWED_STATUS_WRITES } this procedure may write (breaks R8: parking an issue under a status this loop does not own overrides whoever reads that status next)" ;;
        esac
    done < "$work/status-writes"

    # -----------------------------------------------------------------------
    # R8, second half. `## CONSTRAINTS` names the three statuses it refuses.
    #
    # The write census above is a census of what the file DOES; this is the
    # rule that binds what a later edit may do. Without it the census passes on
    # a file whose prose has gone silent, and the next author has nothing
    # telling them the omission was deliberate.
    # -----------------------------------------------------------------------
    constraints=$(section_of "$f" '## CONSTRAINTS')
    [ -n "$constraints" ] ||
        fail "$f: no '## CONSTRAINTS' section (breaks R8: the sentence naming the statuses this procedure refuses to write has nowhere to live)"

    refusal=$(printf '%s\n' "$constraints" | grep 'never writes' || true)
    [ -n "$refusal" ] ||
        fail "$f: '## CONSTRAINTS' states no status this procedure never writes (breaks R8: nothing forbids a later run inventing a fifth status for a batch member it cannot complete)"
    for status in $PARKED_STATUSES; do
        printf '%s\n' "$refusal" | grep -qF -- "\`$status\`" ||
            fail "$f: '## CONSTRAINTS' does not name \`$status\` among the statuses this procedure never writes (breaks R8: that status is a person's or a sibling skill's parking decision, and nothing here says so)"
    done

    # -----------------------------------------------------------------------
    # R11 and R12. RESIDUE PASS exists and sits under the WRITE GATE.
    #
    # Two assertions and not one. The pass alone is a mutation pass that runs
    # in a diagnostic run and while another invocation holds a live heartbeat;
    # the WRITE GATE's list alone names a pass that is not there.
    # -----------------------------------------------------------------------
    census=$(section_of "$f" '## CENSUS')
    [ -n "$census" ] ||
        fail "$f: no '## CENSUS' section (breaks R11: the residue repair has nowhere to live)"

    printf '%s\n' "$census" | grep -q '^RESIDUE PASS\.' ||
        fail "$f: '## CENSUS' carries no 'RESIDUE PASS.' opener (breaks R11: ledger residue an earlier run left on a parked issue is repaired only by a person editing metadata by hand)"

    gate=$(printf '%s\n' "$census" | grep '^WRITE GATE,' || true)
    [ -n "$gate" ] ||
        fail "$f: '## CENSUS' carries no 'WRITE GATE,' paragraph (breaks R12: every mutation pass below it is then unguarded)"
    printf '%s\n' "$gate" | grep -qF -- 'RESIDUE PASS' ||
        fail "$f: the WRITE GATE paragraph does not name RESIDUE PASS among the writes it covers (breaks R12: the pass mutates a person's tracker during a diagnostic run and while another invocation holds a live heartbeat)"
done

echo "OK: $SKILL_NAME across $checked host cop(y/ies): every declared phase reaches a RECOVERY arm, the default arm and the closed enum hold, the parked statuses outrank abandoned-claim and are excluded from it, CLASSIFY and <cause> agree in both directions, only { $ALLOWED_STATUS_WRITES } are written, CONSTRAINTS names the three refusals, and RESIDUE PASS sits under the WRITE GATE"
