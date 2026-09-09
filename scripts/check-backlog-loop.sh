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
#       arm AS A TOKEN IN THAT ARM'S OWN OPENING CLAUSE -- the text before its
#       first colon -- and RECOVERY carries a default arm for an absent or
#       unrecognized value. A phase with no arm ends the run outright, on
#       every invocation, until a person edits the tracker by hand. Scoped to
#       the opener because every arm's body cross-references sibling arms by
#       phase token (three arms say "treat as `merged` above"), so a
#       whole-block substring test stays green after an entire arm bullet is
#       deleted: its token survives in another arm's prose.
#   R6  the default RECOVERY arm's fallback evidence -- `backlog_loop_merge`,
#       `backlog_loop_pr`, `backlog_loop_branch` -- is named in that reading
#       order. Reading them out of order, or dropping one, lets recovery
#       consult a weaker key before a stronger one answers, or consult none.
#   R7  the default RECOVERY arm still tells `## FINAL REPORT` to name the
#       unrecognized value, the arm taken, and the evidence key that chose it.
#       Losing that sentence swallows an improvised phase value silently, and
#       the next run meets the same value with nothing recorded about it.
#   R9  the ledger row states that its value set is closed, ANCHORED ON THE
#       WHOLE CLOSING CLAUSE rather than a substring: "the only phase values
#       this procedure writes" is still a substring of a sentence negating it
#       ("are **not necessarily** the only phase values..."). Without the
#       intact clause the arm list can be enumerated correctly and still be an
#       open set, so a later run improvises an eighth value and the default
#       arm is the only thing between it and the wedge above.
#   R1  the `hooked`, `pinned` and `deferred` rows outrank `abandoned-claim` in
#       CLASSIFY, and `abandoned-claim` states the NEGATED compound clause
#       excluding all three -- not merely token presence, which survives the
#       clause being inverted from "is not" to "is". Below `abandoned-claim`,
#       a parked issue carrying a dead marker is read as this loop's own
#       wreckage and reopened into a pool a person removed it from -- on every
#       run.
#   R3  the same three rows also outrank `dep-blocked` and `legacy-blocked`.
#       Renumbering the table so `dep-blocked` sits below the parked rows
#       while `abandoned-claim` stays below them too satisfies R1's
#       comparison and still wedges the loop: a parked issue with an unmet
#       dependency is then classified `dep-blocked` and walked transitively
#       into the loop-responsible set, so no run can ever report the backlog
#       clear.
#   R8  the procedure writes only `open` and `blocked` as literal `--status=`
#       flags -- MATCHED WHETHER OR NOT THE VALUE IS QUOTED, because a bare
#       char-class pattern captures nothing past an opening quote and silently
#       drops a write such as `--status="deferred"` from the census -- and
#       `## CONSTRAINTS` names the three statuses it refuses. A run that parks
#       an issue is writing under the authority of whoever reads that status
#       next, and `deferred` in particular is a sibling skill's own parking
#       mechanism.
#   R11 `## CENSUS` carries the RESIDUE PASS opener. Without the pass a person
#       clears every parked issue's dead ledger residue by hand.
#   R12 the WRITE GATE paragraph counts RESIDUE PASS among the writes it
#       covers. A mutation pass outside the write gate mutates a person's
#       tracker during a diagnostic run and while another invocation holds a
#       live heartbeat.
#   R13 `## ITERATION` step 2's clear-backlog sentence still carries the
#       stripped-PR condition RESIDUE PASS promises: the backlog is clear only
#       when no PR that pass stripped is still `OPEN`. Losing the condition
#       lets a run that stripped the only record of an open PR report the
#       backlog clear anyway.
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
# flag. `in_progress` and `closed` are written too, but through
# `bd update <id> --claim` and `bd close`, so they never appear in this form.
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
    #
    # Anchored on the WHOLE closing clause, "are the only phase values this
    # procedure writes.", rather than the substring "only phase values this
    # procedure writes": that substring survives a negation inserted right
    # after "are" -- "are **not necessarily** the only phase values this
    # procedure writes." -- which asserts the opposite of a closed set and
    # would otherwise still match.
    # -----------------------------------------------------------------------
    ledger_phase_row "$f" | grep -qF -- 'are the only phase values this procedure writes.' ||
        fail "$f: THE RUN LEDGER's \`backlog_loop_phase\` row no longer states that its values are the only phase values this procedure writes (breaks R9: the enum is open again, so a later run can improvise a value no arm was written for)"

    # -----------------------------------------------------------------------
    # R5, first half. Every declared phase value reaches a RECOVERY arm, named
    # in that arm's own OPENING CLAUSE -- the text before its first colon.
    #
    # Matched as a WHOLE backtick-delimited token and never as a substring:
    # "reclaimed" contains "claimed", so a substring test stays green after the
    # `claimed` arm is deleted -- which is the one arm whose loss silently
    # abandons a claimed-but-unbuilt batch.
    #
    # Scoped to the opener and never the whole arm's body, and never the whole
    # RECOVERY block: every arm's body cross-references sibling arms by phase
    # token -- the default arm says "follow the `merge-requested` arm's
    # rules" and "follow the `shipping-requested` arm's search", and three
    # arms say "treat as `merged` above", so `merged` alone occurs four times
    # in the unmodified block. A whole-block test therefore stays green after
    # an entire arm bullet is deleted, because its token survives in another
    # arm's cross-reference; only the opener is where an arm actually CLAIMS a
    # phase.
    # -----------------------------------------------------------------------
    openers=$(printf '%s\n' "$arms" | awk -F: '{ print $1 }')
    for phase in $phases; do
        printf '%s\n' "$openers" | grep -qF -- "\`$phase\`" ||
            fail "$f: THE RUN LEDGER declares phase \`$phase\` but no RECOVERY arm names it as a backtick-delimited token in that arm's own opening clause (breaks R5: a run interrupted at that phase matches no arm and ends outright)"
    done

    # -----------------------------------------------------------------------
    # R5, second half. RECOVERY carries a default arm.
    #
    # The declared values are not the whole population: the `<cause>` table
    # already admits the phase can be ABSENT, and an earlier run wrote a value
    # the ledger never listed. Both reach this arm and nothing else.
    # -----------------------------------------------------------------------
    default_arm=$(printf '%s\n' "$arms" |
        grep -E '^- Absent, or any value the .backlog_loop_phase. row above does not list:' || true)
    [ -n "$default_arm" ] ||
        fail "$f: RECOVERY carries no arm for an absent or unrecognized \`backlog_loop_phase\` (breaks R5: an absent or improvised phase reaches no arm, and one such value wedges every later invocation)"

    # -----------------------------------------------------------------------
    # R6. The default arm reads its fallback evidence in a fixed order: the
    # merge key first, then the PR, then the branch.
    #
    # A prefix match on the arm's opening words (the R5 check above) proves
    # only that the arm still exists, not that its body still says anything
    # useful. Checked as an ORDERED sequence of backtick tokens rather than
    # mere presence, because reordering the three sentences -- consulting
    # `backlog_loop_pr` before `backlog_loop_merge` -- would have recovery
    # query a weaker signal before the stronger one that should settle it
    # first, and dropping one silently loses that whole fallback rung.
    # -----------------------------------------------------------------------
    evidence_order=$(printf '%s\n' "$default_arm" | grep -oE -- '`backlog_loop_(merge|pr|branch)`')
    expected_evidence_order='`backlog_loop_merge`
`backlog_loop_pr`
`backlog_loop_branch`'
    [ "$evidence_order" = "$expected_evidence_order" ] ||
        fail "$f: the RECOVERY default arm does not name \`backlog_loop_merge\`, \`backlog_loop_pr\`, \`backlog_loop_branch\` as backtick tokens in that order (breaks R6: the fallback evidence chain is read out of order, or an evidence key is missing, so recovery from an unrecognized phase can consult a weaker signal before a stronger one answers, or consult nothing)"

    # -----------------------------------------------------------------------
    # R7. The default arm still tells FINAL REPORT what happened.
    #
    # `grep -qE` above matches only the arm's opening words, so deleting this
    # trailing clause -- and with it the only record of an improvised phase
    # value -- passed unnoticed. Anchored on the whole clause rather than a
    # keyword, so reordering the evidence chain it closes cannot survive
    # either: this and the R6 check above are two ends of the same sentence.
    # -----------------------------------------------------------------------
    printf '%s\n' "$default_arm" |
        grep -qF -- 'Name the unrecognized value, the arm taken, and the evidence key that chose it in the FINAL REPORT:' ||
        fail "$f: the RECOVERY default arm no longer tells FINAL REPORT to name the unrecognized value, the arm taken, and the evidence key that chose it (breaks R7: an improvised phase value is swallowed silently, and the next run meets the same value with nothing recorded about how the last one was handled)"

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

    # -----------------------------------------------------------------------
    # R3. The parked rows also outrank `dep-blocked` and `legacy-blocked`.
    #
    # A table renumbered so `dep-blocked` sits below the parked rows -- while
    # `abandoned-claim` stays below them too, satisfying the check above --
    # still wedges the loop: a parked issue with an unmet dependency on ready
    # work is then classified `dep-blocked` and walked transitively into the
    # loop-responsible set, so no run can ever report the backlog clear. That
    # is the rationale bullet at SKILL.md naming rows 9-11 above row 12, and
    # this is the comparison that actually enforces it.
    # -----------------------------------------------------------------------
    depblocked=$(classify_row_number "$f" dep-blocked)
    [ -n "$depblocked" ] ||
        fail "$f: the CLASSIFY table carries no \`dep-blocked\` row (breaks R3: the row the parked statuses must outrank is gone, so the ordering rule below has nothing to compare against)"
    legacyblocked=$(classify_row_number "$f" legacy-blocked)
    [ -n "$legacyblocked" ] ||
        fail "$f: the CLASSIFY table carries no \`legacy-blocked\` row (breaks R3: the row the parked statuses must outrank is gone, so the ordering rule below has nothing to compare against)"

    for status in $PARKED_STATUSES; do
        n=$(classify_row_number "$f" "$status")
        [ -n "$n" ] ||
            fail "$f: the CLASSIFY table carries no \`$status\` row (breaks R1: a parked issue then falls through to \`abandoned-claim\` and is reopened into the pool a person removed it from)"
        [ "$n" -lt "$abandoned" ] ||
            fail "$f: CLASSIFY row $n \`$status\` does not outrank row $abandoned \`abandoned-claim\` (breaks R1: a parked issue carrying a dead marker is filed as this loop's own wreckage and RECOVERY reopens it on every run)"
        [ "$n" -lt "$depblocked" ] ||
            fail "$f: CLASSIFY row $n \`$status\` does not outrank row $depblocked \`dep-blocked\` (breaks R3: a parked issue with an unmet dependency is then classified dep-blocked and walked into the loop-responsible set, so no run can ever report the backlog clear)"
        [ "$n" -lt "$legacyblocked" ] ||
            fail "$f: CLASSIFY row $n \`$status\` does not outrank row $legacyblocked \`legacy-blocked\` (breaks R3: a parked issue is then classified legacy-blocked instead of recognized as parked, and RECOVERY never sees it)"
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
    # R1, third check. The exclusion is a NEGATION, not merely a set of tokens
    # that happen to be present.
    #
    # The loop above tests token PRESENCE only: flipping the cell from
    # "`status` is not `blocked`, `hooked`, `pinned` or `deferred`" to
    # "`status` is `blocked`, `hooked`, `pinned` or `deferred`" leaves every
    # token in place and stays green, while the row's meaning inverts from an
    # exclusion into a match -- and now files every ordinary dead-run
    # abandoned claim as though it carried a parked status.
    # -----------------------------------------------------------------------
    printf '%s\n' "$test_cell" |
        grep -qF -- '`status` is not `blocked`, `hooked`, `pinned` or `deferred`' ||
        fail "$f: the \`abandoned-claim\` CLASSIFY row does not state the negation \`status\` is not \`blocked\`, \`hooked\`, \`pinned\` or \`deferred\` (breaks R1: the clause reads as a positive match rather than an exclusion, so an ordinary dead-run abandoned claim is misfiled as though it carried a parked status)"

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
    #
    # Matched three ways -- bare, double-quoted, single-quoted -- because a
    # quoted value such as `--status="deferred"` is invisible to a bare
    # `[A-Za-z0-9_-]*` char class: it stops at the opening quote and captures
    # an EMPTY value, which the old loop here then silently `continue`d past.
    # The raw occurrence count is compared against the parsed count so any
    # remaining unparsable form -- a quoting style this pattern does not
    # anticipate -- fails loudly instead of vanishing from the census the
    # same way.
    # -----------------------------------------------------------------------
    sq="'"
    status_pattern="--status=(\"[^\"]*\"|${sq}[^${sq}]*${sq}|[A-Za-z0-9_-]+)"
    raw_status_writes=$(grep -o -- '--status=' "$f" | grep -c . || true)
    status_matches=$(grep -oE -- "$status_pattern" "$f" || true)
    parsed_status_writes=$(printf '%s\n' "$status_matches" | grep -c . || true)
    [ "$raw_status_writes" -eq "$parsed_status_writes" ] ||
        fail "$f: $((raw_status_writes - parsed_status_writes)) literal \`--status=\` occurrence(s) could not be parsed into a value (breaks R8: an unparsable write is invisible to the census below, so the status it writes is never checked)"

    printf '%s\n' "$status_matches" |
        sed -e 's/^--status=//' -e 's/^"\(.*\)"$/\1/' -e "s/^${sq}\\(.*\\)${sq}\$/\\1/" |
        LC_ALL=C sort -u > "$work/status-writes"
    while read -r status; do
        [ -n "$status" ] ||
            fail "$f: a literal \`--status=\` write carries an empty value (breaks R8: an empty status is not one of { $ALLOWED_STATUS_WRITES }, and it is invisible to the allowed-value check below unless this fails)"
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

    # -----------------------------------------------------------------------
    # R13. ITERATION step 2's clear-backlog sentence still carries the
    # stripped-PR condition RESIDUE PASS promises.
    #
    # RESIDUE PASS states that a stripped PR still open reaches the
    # termination decision; without this clause in step 2 that promise is
    # unkept, and a run that stripped the only record of an open PR can
    # report the backlog clear while nobody is watching that PR land.
    # -----------------------------------------------------------------------
    iteration=$(section_of "$f" '## ITERATION')
    [ -n "$iteration" ] ||
        fail "$f: no '## ITERATION' section (breaks R13: the clear-backlog decision has nowhere to live)"
    printf '%s\n' "$iteration" |
        grep -qF -- "and no PR this census's RESIDUE PASS stripped is still \`OPEN\` -> the backlog is clear." ||
        fail "$f: ITERATION step 2's clear-backlog sentence no longer carries the stripped-PR condition (breaks R13: a run that stripped the only record of an open PR can report the backlog clear while nobody is watching that PR)"
done

echo "OK: $SKILL_NAME across $checked host cop(y/ies): every declared phase reaches a RECOVERY arm in its own opening clause, the default arm names its evidence chain in order and tells FINAL REPORT what happened, the closed enum holds against a negation, the parked statuses outrank abandoned-claim, dep-blocked and legacy-blocked and abandoned-claim states the negation excluding them, CLASSIFY and <cause> agree in both directions, only { $ALLOWED_STATUS_WRITES } are written including quoted, CONSTRAINTS names the three refusals, RESIDUE PASS sits under the WRITE GATE, and ITERATION step 2 still gates on a stripped-but-open PR"
