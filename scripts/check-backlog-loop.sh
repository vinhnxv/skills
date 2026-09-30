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
#   R14 a code-caused red trunk enters a bounded TRUNK REPAIR batch instead of
#       ending the run before PICK BATCH can reach the issue that fixes it.
#       The repair is solo, limited to the observed failing gates, and must
#       turn those gates green before the ordinary merge authority applies.
#   R15 terminal decisions are based on exhausted legal progress, not event
#       counters. A scoped batch or merge failure is parked and the census is
#       consulted for independent work; only a blocker that prevents every
#       remaining agent-executable action can end the run.
#   R16 the companion goal prompt preserves the same authority. A prompt-level
#       unconditional trunk or counter stop wins before the skill can reach
#       its recovery mechanics, recreating the deadlock even when both host
#       copies are correct.
#   R19 the merge gate reconciles compound-engineering's `actionable_findings`
#       only. LFG never applies an `advisory` finding and never lists it under
#       `## Unapplied review findings`, so a gate that reconciles every
#       returned finding cannot be satisfied by a review that returns one, and
#       the batch blocks, is charged, and reaches `needs-person` over a finding
#       that was never meant to gate. The `settled_conflict` and
#       `settled_decision_conflicts` bullets LFG step 6 writes under that
#       heading stay merge-gating, and the non-complete review statuses are
#       the ones ce-code-review actually returns.
#   R20 the loop names the compound-engineering children it relies on by the
#       invocation that keeps them unattended: the off-route resolver runs in
#       `mode:pipeline` (full mode may stop on a blocking question), and
#       preflight resolves `ce-debug`, which `ce-babysit-pr` invokes for a
#       failing check, so a missing child surfaces before a claim and not
#       inside a babysit.
#   R21 LINKED PR DISPOSITION maps a PR `CLOSED` without a merge to
#       `needs-person` and releases the PR link, and no other text reclaims a
#       closed PR. This loop never closes a PR, so a closed one is a person's
#       rejection; reclaiming it rebuilds the rejected change, and the
#       rebuilding has no bound while the old reclaim wiped the attempt count.
#   R22 the attempt ceiling covers every cause, `transient:pr-open` included,
#       in REOPEN PASS and in CHARGING. An exempt cause parks a conflicting or
#       unapproved PR forever, because nothing else ends it.
#   R23 reclaim, reopen, and residue unset the RUN and FORGE-LINK classes and
#       never a DURABLE key, and the human-close release keeps the DURABLE
#       class. Losing `backlog_loop_quarantine` frees an issue a gate repair
#       held back; losing `backlog_loop_attempts` unbounds the rebuild cycle.
#   R24 every cause value the procedure names is declared in THE RUN LEDGER's
#       cause row and has a proof in REOPEN PASS. A cause with no proof labels
#       an issue that can neither be cleared nor escalated.
#   R25 a parked PR is adopted by ONE write guarded with `--if-status blocked`,
#       and every entry point that resumes a PR adopts through it. Without the
#       guard two invocations both move the parked issue to `in_progress` and
#       both merge-request the same PR. The adoption write is also the only text
#       R8 lets carry a literal `--status=in_progress`, which is why this rule
#       is evaluated before R8: a write that loses its guard must be reported
#       as a lost guard, not as a stray status.
#   R26 a member that is not running never reads as a live run. Every write that
#       sets `blocked` unsets `backlog_loop_heartbeat` in the same command, the
#       write before `bd close` does too, FINAL REPORT writes `released` on
#       members still held, LIVENESS reads `released`, a stale `live`, and an
#       absent heartbeat as dead, the census WRITE GATE counts a heartbeat only
#       beside a different `backlog_loop_run`, and the refresher keeps a live
#       run's heartbeat and claim lease fresh through a long child stage. A
#       fresh heartbeat left on a parked or finished member stops the next
#       invocation for 30 minutes over work nobody is doing; a stale one lets a
#       sibling reclaim work that is still moving.
#   R27 preflight stops the run when a required status check has no producer on
#       either CI route, naming the check, and names the required approving
#       review count from branch protection and `pull_request` rulesets before
#       the first claim; a PR awaiting that approval stays loop-responsible,
#       uncharged, and reported. A required check that can never appear parks
#       every PR behind it forever. Post-merge CI pending past 30 minutes runs
#       the exact-merge local gate once (R18 clauses), and a slow optional
#       check never rewrites the batch CI route to `off`.
#   R28 the remaining loop fixes. Every `bd ready` call carries `--limit 0`,
#       because the tracker returns at most 100 rows by default and a larger
#       backlog then reads as a smaller one, and the census counts the rows of
#       `bd ready --explain`. The browser test runs with its working directory
#       in the clean tree on an explicit port that REAP stops it by, the branch
#       is recorded before step 4 and nothing is pushed before step 7, the run
#       token is exported before any child skill and each child brief restates
#       the hygiene rules, OPEN PR RESUME runs babysit, resolve, and debug in a
#       run-owned worktree, the post-merge scan skips closed members, a
#       diagnostic census reports an unrunnable proof as `would evaluate`,
#       only human or untyped gates count as human gates, OWNER-DECISION writes
#       the design with `--design-file` and a read-back, the gate timeout names
#       `gtimeout` and follows the repository docs, the final REAP deletes the
#       run-owned worktree root, and FINAL REPORT lists closed issues whose PR
#       is still open.
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
# `bd update <id> --claim` and `bd close`, so they never appear in this form --
# except `in_progress` in ONE place, the status-guarded adoption write below.
ALLOWED_STATUS_WRITES="open blocked"

# The adoption write (R25), whole. `--claim` cannot be combined with
# `--if-status` and `bd heartbeat` refuses a blocked issue, so adoption names the
# status and the assignee itself. This is also the only text R8 lets carry a
# literal `--status=in_progress`.
ADOPTION_WRITE='bd update <id> --if-status blocked --status=in_progress --assignee <actor> --set-metadata backlog_loop_run=<run-id> --set-metadata backlog_loop_heartbeat="<iso> | live"'

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

# The LINKED PR DISPOSITION table: `| linked PR state | action | charged | result |`.
disposition_rows() { # file
    sed -n '/^| linked PR state | action | charged | result |$/,/^$/p' "$1" |
        grep '^| ' | grep -v '^| linked PR state |' || true
}

# One disposition row, found by the exact text of its first cell.
disposition_row() { # file, state cell
    disposition_rows "$1" | awk -F'|' -v want="$2" '
        { c = $2; sub(/^ +/, "", c); sub(/ +$/, "", c); if (c == want) print }
    '
}

# The KEY CLASSES table: `| class | members | unset by |`.
class_rows() { # file
    sed -n '/^| class | members | unset by |$/,/^$/p' "$1" |
        grep '^| ' | grep -v '^| class |' || true
}

# The members cell of one key class.
class_members() { # file, class
    class_rows "$1" | awk -F'|' -v want="$2" '
        { c = $2; gsub(/ /, "", c); if (c == want) print $3 }
    '
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
    [ "$(disposition_rows "$f" | grep -c . || true)" -gt 0 ] ||
        fail "$f: the LINKED PR DISPOSITION table did not parse -- no row matched under the '| linked PR state | action | charged | result |' header, so every R21 check below would pass vacuously"
    [ "$(class_rows "$f" | grep -c . || true)" -gt 0 ] ||
        fail "$f: the KEY CLASSES table did not parse -- no row matched under the '| class | members | unset by |' header, so every R23 check below would pass vacuously"

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
    # R25. A parked PR is adopted by one status-guarded write.
    #
    # Evaluated before R8 on purpose: R8 lets the adoption write carry the one
    # literal `--status=in_progress`, so a write that loses `--if-status
    # blocked` would otherwise be reported as a stray status instead of as the
    # lost guard it is.
    #
    # The write is anchored WHOLE and must sit exactly once, inside the
    # ADOPTION paragraph. The other clauses are anchored whole as well: "skip
    # the issue" survives a sentence that restricts it to exit 13, and a second
    # adopter that passes its own `--assignee` is refused with exit 1 before
    # the status guard is reached, so an exit-13-only rule loses the race.
    # -----------------------------------------------------------------------
    adoption=$(grep '^ADOPTION\. ' "$f" || true)
    [ -n "$adoption" ] ||
        fail "$f: no 'ADOPTION.' paragraph (breaks R25: a parked PR has no single write that adopts it, so every entry point improvises one and two invocations can take the same PR)"
    [ "$(grep -oF -- "$ADOPTION_WRITE" "$f" | grep -c . || true)" -eq 1 ] &&
        printf '%s\n' "$adoption" | grep -qF -- "$ADOPTION_WRITE" ||
        fail "$f: no ADOPTION write carries the --if-status blocked guard (breaks R25: an unguarded adoption lets two invocations both move the parked issue to in_progress and both merge-request the same PR; the write must appear exactly once, whole, inside the ADOPTION paragraph)"
    printf '%s\n' "$adoption" |
        grep -qF -- 'Read the issue back and require status `in_progress`, assignee `<actor>`, and `backlog_loop_run=<run-id>`.' ||
        fail "$f: ADOPTION no longer reads the issue back (breaks R25: an exit status is not proof the write landed, and a refused second adopter would proceed as though it held the PR)"
    printf '%s\n' "$adoption" |
        grep -qF -- 'Any nonzero exit with an unchanged read-back means another invocation adopted it first: skip the issue and write nothing.' ||
        fail "$f: ADOPTION no longer says any nonzero exit with an unchanged read-back means skip (breaks R25: a second adopter is refused with exit 1 before the status guard answers exit 13, so a rule keyed on exit 13 alone lets it carry on)"
    printf '%s\n' "$adoption" |
        grep -qF -- 'A member still `in_progress` under a dead run (RECOVERY) is parked first, never adopted in place:' ||
        fail "$f: ADOPTION no longer parks an \`in_progress\` member of a dead run first (breaks R25: adopting in place has no blocked-to-in_progress transition to guard, so two recovering invocations both take the PR)"
    disposition_rows "$f" | grep -F -- 'adopt the issue' |
        grep -qF -- "adopt the issue through ADOPTION's guarded write;" ||
        fail "$f: the adopt row of LINKED PR DISPOSITION no longer adopts through ADOPTION (breaks R25: the table's own adoption bypasses the status guard)"

    # -----------------------------------------------------------------------
    # R8, first half. Every literal `--status=` write is one of two values --
    # plus the anchored adoption write's `in_progress`, counted below.
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
        sed -e 's/^--status=//' -e 's/^"\(.*\)"$/\1/' -e "s/^${sq}\\(.*\\)${sq}\$/\\1/" > "$work/status-values"

    # `in_progress` is the one carve-out: each occurrence, quoted or not, must
    # be the anchored adoption write, so the counts have to agree.
    in_progress_writes=$(grep -cx 'in_progress' "$work/status-values" || true)
    adoption_writes=$(grep -oF -- "$ADOPTION_WRITE" "$f" | grep -c . || true)
    [ "$in_progress_writes" -eq "$adoption_writes" ] ||
        fail "$f: writes \`--status=in_progress\` $in_progress_writes time(s) but the anchored adoption write appears $adoption_writes time(s) (breaks R8: \`in_progress\` is a literal status flag in the status-guarded adoption write only, and anywhere else it writes a status the claim path owns)"

    grep -vx 'in_progress' "$work/status-values" | LC_ALL=C sort -u > "$work/status-writes"
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

    # -----------------------------------------------------------------------
    # R14. A red trunk caused by repository code is executable recovery work.
    #
    # This must live in ITERATION, before ordinary selection. A sentence in a
    # report or prompt cannot help an executor whose step 1 still says STOP.
    # The exact phrase anchors the disposition; the named subsection anchors
    # the mechanics that select or create repair issues and constrain scope.
    # -----------------------------------------------------------------------
    printf '%s\n' "$iteration" |
        grep -qF -- 'A code-caused red trunk is recovery work, not a terminal blocker.' ||
        fail "$f: ITERATION no longer classifies a code-caused red trunk as recovery work (breaks R14: step 1 stops before PICK BATCH can reach the issue that restores CI)"
    printf '%s\n' "$iteration" | grep -q '^   TRUNK REPAIR\.' ||
        fail "$f: ITERATION carries no 'TRUNK REPAIR.' procedure (breaks R14: the recovery disposition has no bounded selection, creation, or verification mechanics)"
    printf '%s\n' "$iteration" |
        grep -qF -- 'If any recorded failure has no matching issue, create one agent-executable P0 bug with `bd create`' ||
        fail "$f: TRUNK REPAIR no longer creates tracked agent work for an uncovered red gate (breaks R14: an untracked code failure still ends the run before any repair can be claimed)"
    printf '%s\n' "$iteration" |
        grep -qF -- 'The complete repair-member set is forced into one repair batch before normal ANCHOR selection' ||
        fail "$f: TRUNK REPAIR no longer forces the complete failure set ahead of ordinary work (breaks R14: a partial repair cannot make the full merge gate green)"
    printf '%s\n' "$iteration" |
        grep -qF -- 'A TRUNK REPAIR batch never drops a member here.' ||
        fail "$f: the plan-boundary budget may drop a TRUNK REPAIR member (breaks R14: the branch can leave one recorded trunk failure red and can never ship)"

    # -----------------------------------------------------------------------
    # R15. STOP is a reachability decision, not a failure counter.
    #
    # Counters are tempting circuit breakers but they terminate healthy work
    # behind one bad issue. The stop section must state the positive rule and
    # must not reintroduce the three historical counter-shaped exits.
    # -----------------------------------------------------------------------
    stop_early=$(section_of "$f" '## STOP EARLY AND REPORT')
    [ -n "$stop_early" ] ||
        fail "$f: no '## STOP EARLY AND REPORT' section (breaks R15: terminal authority has no bounded home)"
    printf '%s\n' "$stop_early" |
        grep -qF -- 'Stop only when no legal agent-executable action remains.' ||
        fail "$f: STOP EARLY is not gated on exhausting legal agent-executable progress (breaks R15: one scoped failure can terminate independent ready work)"
    for forbidden in '3 consecutive BATCHES' 'any id appears in two attempted batches' 'two merges fail in a row'; do
        if printf '%s\n' "$stop_early" | grep -qF -- "$forbidden"; then
            fail "$f: STOP EARLY still contains counter-shaped terminal rule '$forbidden' (breaks R15: event count can terminate the run while independent work remains)"
        fi
    done

    # An unmerged PR stays open, and a merged PR keeps a durable CI watch.
    if grep -qF -- 'gh pr close' "$f"; then
        fail "$f: backlog-loop may close a PR automatically (breaks R17)"
    fi
    grep -qF -- 'Never close a PR automatically.' "$f" ||
        fail "$f: open-PR preservation rule is missing (breaks R17)"
    grep -qF -- '| `backlog_loop_postmerge_ci` |' "$f" ||
        fail "$f: durable post-merge CI queue key is missing (breaks R18)"
    grep -qF -- 'Wait up to 30 minutes total from `<first-seen-utc>`.' "$f" ||
        fail "$f: bounded post-merge CI wait is missing (breaks R18)"
    grep -qF -- 'An entry still pending at that deadline stops waiting: run the applicable local quality gate set once through CLEAN-TREE GATE RUN at `<merge-sha>`, in a clean worktree, and write the entry `timeout-local-green` when it is green or `failed` when it is red, so the gate never runs twice for one entry' "$f" ||
        fail "$f: post-merge CI pending past 30 minutes no longer runs the exact-merge local gate once (breaks R18: a path-filtered or never-queued workflow holds the members in_progress at merged forever, and the goal's success conditions become unreachable)"
    grep -qF -- 'Green closes the members with the `timeout-local-green` receipt in the close reason; red enters TRUNK REPAIR with the gate'"'"'s evidence.' "$f" ||
        fail "$f: the timeout gate no longer closes on green with a \`timeout-local-green\` receipt and enters TRUNK REPAIR on red (breaks R18: the gate's result decides nothing)"
    grep -qF -- 'A local-gate timeout writes `timeout-local-green` in place of `passed` in that same command.' "$f" ||
        fail "$f: the step 7 write no longer records \`timeout-local-green\` in place of \`passed\` after a local-gate timeout (breaks R18: a close on the local gate reads as a green CI run)"
    grep -qF -- 'Expected workflows are computed from event and path filters at `<merge-sha>`: a workflow whose `push` trigger admits `<default>` and whose path filters match a file the merge commit changed, and any workflow whose filters cannot be decided.' "$f" ||
        fail "$f: step 7 no longer computes the expected workflows from event and path filters at the merge SHA (breaks R18: a workflow the merge never triggered is waited on for the full 30 minutes)"
    grep -qF -- 'until 30 minutes have passed from the original first-seen time; then run step 7'"'"'s exact-merge local gate once.' "$f" ||
        fail "$f: the RECOVERY \`merged\` arm no longer runs step 7's exact-merge local gate once after 30 minutes (breaks R18: an interrupted run resumes into an unbounded wait)"
    grep -qF -- 'Runs pending on a SHA this loop did not merge have no batch to record on: record nothing on any member, mark the exact-SHA LOCAL TRUNK GATE pending, and run it after CLAIM; do not treat pending CI as green.' "$f" ||
        fail "$f: trunk CI pending on a SHA this loop did not merge no longer marks the LOCAL TRUNK GATE pending (breaks R18: a queue entry is recorded on a batch that does not exist)"
    grep -qF -- 'POST-MERGE QUEUE RECHECK, every iteration and every invocation, on either route:' "$f" ||
        fail "$f: the post-merge queue recheck no longer runs every iteration on either route (breaks R18: under \`<trunk-ci>=off\` a merged member waits for the next invocation)"
    grep -qF -- 'never pass `--all`' "$f" ||
        fail "$f: the post-merge queue enumeration no longer says never to pass \`--all\` (breaks R18: every closed member in history is shown on every iteration)"
    grep -qF -- 'keep `backlog_loop_ci` as step 6 recorded it, because a slow optional check is not an absent producer, and advance to merge.' "$f" ||
        fail "$f: step 8 no longer keeps the batch CI route when an optional check is slow (breaks R18: a slow route is rewritten to \`off\` and post-merge CI stops being expected)"
    grep -qF -- 'keep the route `on` and post-merge CI expected, and write `backlog_loop_ci=off` only on proven absence of every producer (pipeline step 6), never because an optional check is slow' "$f" ||
        fail "$f: the pending-optional-check row no longer keeps the route \`on\` and writes \`off\` only on proven absence (breaks R18: a slow route is rewritten to \`off\`)"
    grep -qF -- 'Recheck the durable queue at each iteration and in the next invocation.' "$f" ||
        fail "$f: post-merge CI queue has no resumed poll (breaks R18)"
    grep -qF -- 'If either route is `off` or missing, a missing workflow does not hold verification after the exact-merge clean-tree gate passes' "$f" ||
        fail "$f: CI-off recovery can wait forever for a missing workflow despite a green exact-merge local gate"
    grep -qF -- 'When either route is `off`, the exact-merge local gate is authoritative: a missing workflow does not keep the queue pending after that gate passes.' "$f" ||
        fail "$f: CI-off post-merge verification can wait forever for a missing workflow"
    grep -qF -- 'OPEN PR RESUME. For each linked PR' "$f" ||
        fail "$f: a parked open PR has no later-run resume path"
    grep -qF -- 'backlog_loop_cause=transient:pr-open' "$f" ||
        fail "$f: a parked open PR is not recorded as recoverable"
    grep -qF -- 'bd list --limit 0 --has-metadata-key backlog_loop_postmerge_ci --json' "$f" ||
        fail "$f: CI watch cannot enumerate queue entries because bd list omits metadata"
    residue=$(sed -n '/^RESIDUE PASS\./,/^GATE REPAIR PASS\./p' "$f")
    printf '%s\n' "$residue" | grep -qF -- 'plus unsetting the RUN and FORGE-LINK classes (KEY CLASSES)' ||
        fail "$f: RESIDUE PASS leaves a parked issue in the pending CI watch"
    class_members "$f" FORGE-LINK | grep -qF -- '`backlog_loop_postmerge_ci`' ||
        fail "$f: the KEY CLASSES FORGE-LINK row no longer lists \`backlog_loop_postmerge_ci\` (breaks R18: residue, reclaim, and reopen leave a parked issue in the pending CI watch)"

    # -----------------------------------------------------------------------
    # R19. The merge gate counts actionable findings only.
    #
    # Each anchor is a WHOLE clause, never a bare token: `actionable_findings`
    # and `advisory` both survive in a sentence that negates the rule.
    # -----------------------------------------------------------------------
    grep -qF -- 'and reconcile `actionable_findings` only: each one is either an applied fix or an entry in `## Unapplied review findings`.' "$f" ||
        fail "$f: pipeline step 4 no longer reconciles actionable_findings only (breaks R19: an advisory finding LFG never applies or lists makes the merge gate unsatisfiable, so the batch blocks and is charged)"
    grep -qF -- 'with every entry in the review'"'"'s `actionable_findings` reconciled to either an applied-fix receipt or one of those entries' "$f" ||
        fail "$f: the merge gate no longer counts actionable_findings only (breaks R19: a review that returns an advisory finding can never cross the gate)"
    grep -qF -- '`advisory` findings are not entries and never block a merge.' "$f" ||
        fail "$f: the merge gate no longer says advisory findings never block a merge (breaks R19: advisory findings read as unreconciled entries)"
    grep -qF -- 'Record `advisory` findings under a separate non-checkbox `## Advisory review notes` heading in the PR body; they never gate the merge.' "$f" ||
        fail "$f: pipeline step 4 no longer records advisory findings under a separate non-checkbox heading (breaks R19: advisory findings are dropped, or land under the gating heading)"
    grep -qF -- 'The `settled_conflict` and `settled_decision_conflicts` bullets LFG step 6 writes under that heading gate the merge like any unchecked entry, because a divergence from a settled decision needs a person.' "$f" ||
        fail "$f: pipeline step 4 no longer says the settled_conflict and settled_decision_conflicts bullets gate the merge (breaks R19: a divergence from a settled decision merges without a person)"
    grep -qF -- 'Require `status: complete`; a `failed`, `degraded`, or `skipped` status, or a malformed return, takes the blocked path in step 7' "$f" ||
        fail "$f: pipeline step 4 no longer names failed, degraded, and skipped as the non-complete review statuses (breaks R19: a failed review is read as a review that found nothing)"

    # -----------------------------------------------------------------------
    # R20. The children the loop relies on are named the way that keeps them
    # unattended and resolvable.
    # -----------------------------------------------------------------------
    grep -qF -- 'invoke `compound-engineering:ce-resolve-pr-feedback mode:pipeline <pr-url>` once, so no step can stop on a blocking question;' "$f" ||
        fail "$f: step 8 no longer invokes ce-resolve-pr-feedback in pipeline mode (breaks R20: the resolver's full mode can stop on a blocking question inside an unattended run)"
    grep -qF -- '`compound-engineering:ce-resolve-pr-feedback`, `compound-engineering:ce-debug`.' "$f" ||
        fail "$f: preflight no longer resolves compound-engineering:ce-debug (breaks R20: ce-babysit-pr invokes it for a failing check, so a missing ce-debug surfaces inside a babysit instead of before a claim)"
    grep -qF -- "LFG's \`ce-compound\` step is skipped deliberately: it would add a commit after the gated head." "$f" ||
        fail "$f: preflight no longer says the LFG ce-compound step is skipped deliberately (breaks R20: a reader cannot tell a dropped LFG stage from an intended one)"

    # -----------------------------------------------------------------------
    # R21. A PR closed without a merge is a person's decision.
    #
    # The row is found by the exact text of its first cell, and its action is
    # anchored as a WHOLE clause: `needs-person` alone survives "reclaim, or
    # write needs-person when the ceiling is reached".
    # -----------------------------------------------------------------------
    closed_row=$(disposition_row "$f" '`CLOSED`, not merged')
    [ -n "$closed_row" ] ||
        fail "$f: LINKED PR DISPOSITION carries no CLOSED-not-merged row (breaks R21: a PR a person closed has no terminal path, so every entry point improvises one)"
    printf '%s\n' "$closed_row" |
        grep -qF -- 'write `needs-person` and release the PR link: one command sets `blocked`, unsets the RUN and FORGE-LINK classes, keeps every DURABLE key, and records the PR URL in a note.' ||
        fail "$f: the CLOSED-not-merged row does not write \`needs-person\` and release the PR link with the RUN and FORGE-LINK classes unset and the DURABLE class kept (breaks R21 and R23: a person's rejection is rebuilt, or a person who reopens the issue meets a stale PR link)"
    if printf '%s\n' "$closed_row" | sed 's/Never reclaim//' | grep -qi 'reclaim'; then
        fail "$f: the CLOSED-not-merged row reclaims the issue (breaks R21: reclaiming a rejected PR rebuilds the rejected change)"
    fi
    if grep -qE -- '`CLOSED`[^.|]{0,80}-> reclaim' "$f"; then
        fail "$f: a RECOVERY arm or OPEN PR RESUME reclaims a closed PR inline (breaks R21: divergent handling of a PR a person closed, outside LINKED PR DISPOSITION)"
    fi

    # -----------------------------------------------------------------------
    # R22. The attempt ceiling has no exempt cause.
    # -----------------------------------------------------------------------
    reopen_section=$(sed -n '/^REOPEN PASS\./,/^RESIDUE PASS\./p' "$f")
    printf '%s\n' "$reopen_section" |
        grep -qF -- 'for any cause, `transient:pr-open` included -> rewrite `backlog_loop_cause=needs-person`' ||
        fail "$f: REOPEN PASS no longer applies the attempt ceiling to every cause, \`transient:pr-open\` included (breaks R22: an exempt cause parks a PR forever)"
    if grep -qF -- 'for a cause other than `transient:pr-open`' "$f"; then
        fail "$f: the attempt ceiling exempts \`transient:pr-open\` again (breaks R22: a conflicting or unapproved PR parks forever)"
    fi
    grep '^CHARGING\.' "$f" |
        grep -qF -- 'bounds one issue across its whole life for every cause, `transient:pr-open` included, and REOPEN PASS enforces it.' ||
        fail "$f: CHARGING no longer applies the attempt ceiling to every cause, \`transient:pr-open\` included (breaks R22: no charged round ends an open PR)"

    # -----------------------------------------------------------------------
    # R23. No transition unsets a DURABLE key.
    #
    # The clause is anchored whole AND the DURABLE members are scanned for,
    # because keeping the clause and appending one key to the command leaves
    # the clause intact.
    # -----------------------------------------------------------------------
    durable=$(class_members "$f" DURABLE | grep -oE '`backlog_loop_[a-z_]+`' | tr -d '`' || true)
    for key in backlog_loop_attempts backlog_loop_quarantine; do
        printf '%s\n' "$durable" | grep -qxF -- "$key" ||
            fail "$f: the KEY CLASSES DURABLE row no longer lists \`$key\` (breaks R23: a transition that unsets the class no longer protects it)"
    done
    for key in backlog_loop_run backlog_loop_heartbeat; do
        class_members "$f" RUN | grep -qF -- "\`$key\`" ||
            fail "$f: the KEY CLASSES RUN row no longer lists \`$key\` (breaks R23: reclaim, reopen, residue, and drop leave it behind)"
    done
    class_members "$f" FORGE-LINK | grep -qF -- '`backlog_loop_pr`' ||
        fail "$f: the KEY CLASSES FORGE-LINK row no longer lists \`backlog_loop_pr\` (breaks R23: a stale PR link is read as the next claim's own PR)"

    reclaim=$(grep '^Reclaim means' "$f" || true)
    printf '%s\n' "$reclaim" |
        grep -qF -- 'plus unsetting the rest of the RUN class and the FORGE-LINK class (KEY CLASSES)' ||
        fail "$f: reclaim no longer unsets exactly the RUN and FORGE-LINK classes (breaks R23: a hand-copied key list drifts from the class table and can reach a DURABLE key)"
    printf '%s\n' "$reopen_section" |
        grep -qF -- 'plus unsetting every other RUN-class and FORGE-LINK-class key (KEY CLASSES)' ||
        fail "$f: REOPEN PASS no longer unsets exactly the RUN and FORGE-LINK classes (breaks R23: a hand-copied key list drifts from the class table)"
    printf '%s\n' "$residue" |
        grep -qF -- 'plus unsetting the RUN and FORGE-LINK classes (KEY CLASSES)' ||
        fail "$f: RESIDUE PASS no longer unsets exactly the RUN and FORGE-LINK classes (breaks R23: a hand-copied key list drifts from the class table)"
    for key in $durable; do
        if printf '%s\n' "$reclaim" | grep -qF -- "$key"; then
            fail "$f: reclaim names a DURABLE key (\`$key\`) (breaks R23: the attempt count, cause, quarantine, and edge records must outlive every reclaim)"
        fi
        if printf '%s\n' "$reopen_section" | grep -qF -- "--unset-metadata $key"; then
            fail "$f: REOPEN PASS unsets a DURABLE key (\`$key\`) (breaks R23: the attempt count is what bounds the reopen cycle)"
        fi
        if printf '%s\n' "$residue" | grep -qF -- "--unset-metadata $key"; then
            fail "$f: RESIDUE PASS unsets a DURABLE key (\`$key\`) (breaks R23: residue repair must leave the parking decision's own records)"
        fi
    done

    # -----------------------------------------------------------------------
    # R24. Every cause the procedure names is declared and has a REOPEN PASS
    # proof. Collected from every `transient:<subtype>` token in the file, so a
    # value written by any step is seen wherever it is written.
    # -----------------------------------------------------------------------
    ledger_heartbeat_row=$(sed -n '/^| key | written at | value |$/,/^$/p' "$f" | grep '^| `backlog_loop_heartbeat` |' || true)
    cause_row=$(sed -n '/^| key | written at | value |$/,/^$/p' "$f" | grep '^| `backlog_loop_cause` |' || true)
    for cause in $(grep -oE -- 'transient:[a-z][a-z-]*' "$f" | LC_ALL=C sort -u) needs-person; do
        printf '%s\n' "$cause_row" | grep -qF -- "\`$cause\`" ||
            fail "$f: cause \`$cause\` is not declared in THE RUN LEDGER's \`backlog_loop_cause\` row (breaks R24: a cause the ledger does not list reaches no REOPEN PASS proof and no census reading)"
        printf '%s\n' "$reopen_section" | grep -qF -- "$cause" ||
            fail "$f: REOPEN PASS carries no proof for cause \`$cause\` (breaks R24: an issue labelled with it can be neither cleared nor escalated)"
    done

    # R25, last clause. Placed after the paragraph-existence checks further up:
    # deleting OPEN PR RESUME outright is reported by its own rule, not here.
    grep '^ *OPEN PR RESUME\. ' "$f" |
        grep -qF -- 'adopt every member through ADOPTION first, so no other invocation can take the PR while its gates run' ||
        fail "$f: OPEN PR RESUME no longer adopts through ADOPTION before its gates (breaks R25: a PR is gated and merged by an invocation that never held it)"

    # -----------------------------------------------------------------------
    # R26. A member that is not running never reads as a live run.
    #
    # Every literal `--status=blocked` write is scanned, not a sample of the
    # known ones: the next park somebody adds is the one that forgets. The
    # span is cut at its backticks so a heartbeat unset in a neighbouring
    # command cannot satisfy it, and the scan has to find the writes that exist
    # today or it asserts nothing.
    # -----------------------------------------------------------------------
    blocked_writes=$(grep -oE -- '`[^`]*--status=blocked[^`]*`' "$f" || true)
    [ "$(printf '%s\n' "$blocked_writes" | grep -c . || true)" -ge 3 ] ||
        fail "$f: found fewer than three literal --status=blocked writes (breaks R26: the step 6 park, the step 7 block, and the ADOPTION park-first write are the writes the heartbeat check below scans, so finding none would pass it vacuously)"
    printf '%s\n' "$blocked_writes" | grep -vF -- '--unset-metadata backlog_loop_heartbeat' > "$work/blocked-keep-heartbeat" || true
    [ ! -s "$work/blocked-keep-heartbeat" ] ||
        fail "$f: a literal --status=blocked write does not unset \`backlog_loop_heartbeat\` in the same command (breaks R26: a parked member keeps a fresh heartbeat and reads as a live run for 30 minutes, so the next invocation stops over work nobody is doing): $(head -n 1 "$work/blocked-keep-heartbeat")"
    grep -qF -- 'Every write that sets `blocked`, in the table above or anywhere below, carries `--unset-metadata backlog_loop_heartbeat` in that same command.' "$f" ||
        fail "$f: no longer says every write that sets \`blocked\` unsets the heartbeat in the same command (breaks R26: the rule the scan above enforces has nowhere to live, so a later park has nothing telling its author)"
    grep -qF -- 'bd update <id> --set-metadata backlog_loop_postmerge_ci="<merge-sha> | <first-seen-utc> | passed" --set-metadata backlog_loop_phase=verified --unset-metadata backlog_loop_heartbeat' "$f" ||
        fail "$f: the step 7 write that records \`verified\` no longer unsets the heartbeat (breaks R26: \`bd close\` takes no metadata flag, so a finished member whose close fails keeps a fresh heartbeat)"
    grep -qF -- '`released`, a stale `live`, and an absent heartbeat are dead unless such a process exists.' "$f" ||
        fail "$f: LIVENESS no longer treats a \`released\` heartbeat, a stale \`live\` one, and an absent one as dead (breaks R26: a finished run blocks the next invocation for 30 minutes)"
    printf '%s\n' "$ledger_heartbeat_row" | grep -qF -- '`<iso> | live`' &&
        printf '%s\n' "$ledger_heartbeat_row" | grep -qF -- '`<iso> | released`' ||
        fail "$f: the \`backlog_loop_heartbeat\` ledger row no longer documents both suffix values, \`<iso> | live\` and \`<iso> | released\` (breaks R26: LIVENESS reads a state the ledger never declared)"
    grep -qF -- 'Every 10 minutes it refreshes every `in_progress` issue carrying `backlog_loop_run=<run-id>`: it writes `backlog_loop_heartbeat="<iso> | live"` and runs `bd heartbeat <id>`' "$f" ||
        fail "$f: HEARTBEAT REFRESHER no longer refreshes every 10 minutes, heartbeat and claim lease both (breaks R26: one long child stage outlasts the 30-minute window and a sibling reclaims live work)"
    section_of "$f" '## FINAL REPORT' |
        grep -qF -- 'write `backlog_loop_heartbeat="<iso> | released"` on every member this run still holds `in_progress`' ||
        fail "$f: FINAL REPORT no longer writes a \`released\` heartbeat on members still held (breaks R26: a merged member waiting on post-merge CI stays live for 30 minutes after the run ended)"
    grep -qF -- 'a `live` `backlog_loop_heartbeat` under 30 minutes old on an issue whose `backlog_loop_run` is present and is not `<run-id>`' "$f" ||
        fail "$f: the WRITE GATE no longer counts a heartbeat only when a different \`backlog_loop_run\` is present (breaks R26: an orphan heartbeat left by reopen or drop skips this run's own census writes)"

    # -----------------------------------------------------------------------
    # R27. Preflight stops on what the repository's rules make unsatisfiable
    # and names what a person must approve.
    #
    # A required check no workflow can produce never appears on any PR, so every
    # PR parks forever behind it; preflight is the one place that can name it
    # before a claim. Every anchor is a whole clause: the old sentence ("If it
    # has no known PR producer, keep the route `on` through step 8.") carried
    # the same tokens and is pinned absent below.
    # -----------------------------------------------------------------------
    grep -qF -- 'A required check that no default-branch workflow can produce for a pull request stops the run at preflight on either CI route, naming the check:' "$f" ||
        fail "$f: preflight no longer stops on a required check with no producer on either CI route, naming the check (breaks R27: every PR parks on a check that can never appear)"
    grep -qF -- 'an undecidable enabled state, or a check pinned to a non-Actions app is an uncertain producer and never stops the run.' "$f" ||
        fail "$f: the no-producer stop no longer leaves an uncertain producer alone (breaks R27: a matrix job name or an app-produced check stops a healthy run)"
    if grep -qF -- 'If it has no known PR producer, keep the route `on` through step 8.' "$f"; then
        fail "$f: preflight still keeps the route \`on\` for a required check with no producer (breaks R27: the PR parks on it forever)"
    fi
    grep -qF -- 'from the flattened rules response read every `pull_request` rule'"'"'s `required_approving_review_count` and `require_code_owner_review`' "$f" ||
        fail "$f: preflight no longer reads the required approving review count from both branch protection and pull_request rulesets (breaks R27: a ruleset-only approval requirement is never named)"
    grep -qF -- 'Name it before the first claim as `approval required: <n> review(s) (<protection|ruleset>)`, or `approval required: none`.' "$f" ||
        fail "$f: preflight no longer names the approval requirement before the first claim (breaks R27: the operator learns of it from a parked PR)"
    grep -qF -- 'wait for the required approval and never approve; this loop stays responsible and lists the PR in the report as awaiting a required approval' "$f" ||
        fail "$f: the \`REVIEW_REQUIRED\` row no longer waits, stays loop-responsible, and lists the PR as awaiting a required approval (breaks R27: the PR is either abandoned or approved by the loop)"
    grep -qF -- 'waiting on a required approval, an interruption park in RECOVERY' "$f" ||
        fail "$f: CHARGING no longer lists waiting on a required approval as never charged (breaks R27: a PR waiting on a person reaches the attempt ceiling)"
    section_of "$f" '## FINAL REPORT' |
        grep -qF -- 'List every PR awaiting a required approval and every PR LINKED PR DISPOSITION sent to `needs-person`' ||
        fail "$f: FINAL REPORT no longer lists every PR awaiting a required approval (breaks R27: the loop waits on a person nobody told)"
    printf '%s\n' "$stop_early" |
        grep -qF -- 'a required status check has no producer on either CI route;' ||
        fail "$f: STOP EARLY no longer names a required check with no producer as a global terminal blocker (breaks R27: the preflight stop has no reachability decision behind it)"

    # -----------------------------------------------------------------------
    # R28. The remaining loop fixes (U6). Every anchor is a whole clause.
    #
    # `bd ready` returns at most 100 rows unless told otherwise, so every call
    # that carries arguments names `--limit 0`; a bare `bd ready` span names
    # the list, not a call. The scan reads every such span in the file, so a
    # new call without the flag fails too, and an empty extraction fails
    # rather than passing over nothing.
    # -----------------------------------------------------------------------
    bd_ready_calls=$(grep -o '`bd ready [^`]*`' "$f" || true)
    [ -n "$bd_ready_calls" ] ||
        fail "$f: extracted no \`bd ready\` call with arguments (breaks R28: the --limit 0 scan would pass over nothing)"
    bd_ready_bad=$(printf '%s\n' "$bd_ready_calls" | grep -vF -- '--limit 0' || true)
    [ -z "$bd_ready_bad" ] ||
        fail "$f: a \`bd ready\` call carries no \`--limit 0\`: $(printf '%s' "$bd_ready_bad" | head -n 1) (breaks R28: the tracker returns at most 100 rows by default, so a larger backlog reads as a smaller one)"
    grep -qF -- '`bd prime` and `bd ready --json --limit 0` must both work.' "$f" ||
        fail "$f: preflight no longer probes \`bd ready --json --limit 0\` (breaks R28: the tracker probe runs the call the loop never makes)"
    grep -qF -- 'Every `bd ready` call carries `--limit 0`: without it the tracker returns at most 100 rows, so a larger backlog reads as a smaller one.' "$f" ||
        fail "$f: STATE no longer says every \`bd ready\` call carries \`--limit 0\` (breaks R28: a new call is written without the flag)"
    grep -qF -- 'Count its rows: the `ready` and `blocked` arrays must hold `summary.total_ready` and `summary.total_blocked` rows' "$f" ||
        fail "$f: CENSUS no longer counts the rows of \`bd ready --explain --json --limit 0\` (breaks R28: a truncated dependency authority is read as a complete one)"

    # Browser test: working directory and port.
    grep -qF -- 'run the browser test with its working directory in `<clean-tree>` at that commit, bootstrapped as CLEAN-TREE GATE RUN requires, and on an explicit port:' "$f" ||
        fail "$f: pipeline step 5 no longer runs the browser test with its working directory in \`<clean-tree>\` (breaks R28: ce-test-browser starts its server from its working directory, so the invoking tree's dirty paths are served)"
    grep -qF -- 'invoke `compound-engineering:ce-test-browser mode:pipeline --port <browser-port>` from that directory' "$f" ||
        fail "$f: pipeline step 5 no longer invokes ce-test-browser on the explicit \`<browser-port>\` (breaks R28: the server it leaves behind has no handle REAP can use)"
    grep -qF -- 'For every port in `<owned-ports>`, list its listeners with `lsof -i :<port> -sTCP:LISTEN -t`, take each listener'"'"'s process group, and treat that group exactly like a `<pgid>` above:' "$f" ||
        fail "$f: REAP no longer stops the browser server by port (breaks R28: a dev server outlives the iteration that started it)"

    # Branch before any commit, and no push before step 7.
    grep -qF -- 'Then write `backlog_loop_branch` on every member BEFORE step 4:' "$f" ||
        fail "$f: pipeline step 3 no longer writes \`backlog_loop_branch\` before step 4 (breaks R28: a branch the ledger does not name can reach the forge and RECOVERY cannot find it)"
    grep -qF -- 'pipeline step 3, the moment `ce-work` returns and before step 4 commits anything' "$f" ||
        fail "$f: the \`backlog_loop_branch\` ledger row no longer says it is written at pipeline step 3 (breaks R28: the ledger and the pipeline disagree on when the branch is recorded)"
    grep -qF -- 'write `backlog_loop_head` and `backlog_loop_phase=built` for every member; `backlog_loop_branch` already holds the branch from step 3.' "$f" ||
        fail "$f: pipeline step 6 writes \`backlog_loop_branch\` again instead of reading the step 3 record (breaks R28: two writers of one key)"
    grep -qF -- 'Commit each applied fix locally without pushing:' "$f" ||
        fail "$f: pipeline step 4 no longer commits applied fixes without pushing (breaks R28: LFG's apply stage publishes the branch at phase claimed)"

    # Run token and hygiene reach the children.
    grep -qF -- 'Export `BACKLOG_LOOP_RUN=<run-id>` into the host session environment right after choosing `<run-id>` and before any child skill runs,' "$f" ||
        fail "$f: process hygiene no longer exports \`BACKLOG_LOOP_RUN\` into the host session environment before any child skill runs (breaks R28: commands a child launches carry no token, so REAP and the dead-run sweep cannot find them)"
    grep -qF -- 'Every child brief restates the hygiene rules in one sentence: run every gate, test, build, or app command non-interactively (`CI=1`, watch and UI modes off), never leave a watcher, dev server, or REPL alive past the command that needed it, and never signal a process you did not start.' "$f" ||
        fail "$f: process hygiene no longer says every child brief restates the hygiene rules (breaks R28: a child starts a watcher nobody reaps)"
    grep -qF -- 'End the brief, and the brief of every later child invocation, with the hygiene sentence from PREFLIGHT'"'"'s process-hygiene item.' "$f" ||
        fail "$f: pipeline step 5 no longer ends every child brief with the hygiene sentence (breaks R28: the rule is stated but never handed to a child)"
    grep -qF -- '`timeout` is `gtimeout` from Homebrew coreutils on macOS;' "$f" ||
        fail "$f: process hygiene no longer names \`gtimeout\` for macOS (breaks R28: the deadline wrapper does not exist on the platform)"
    grep -qF -- 'which is 20m unless the repository'"'"'s CLAUDE.md, AGENTS.md, CONTRIBUTING.md, or README states a gate timeout,' "$f" ||
        fail "$f: process hygiene no longer takes \`<gate-timeout>\` from the repository docs when they state one (breaks R28: a documented long gate is killed at 20 minutes)"

    # OPEN PR RESUME runs in a run-owned worktree; closed members cost nothing.
    grep -qF -- 'Every `ce-babysit-pr`, `ce-resolve-pr-feedback`, and `ce-debug` round on a resumed PR runs with the PR branch checked out in a run-owned worktree and never in the invoking tree:' "$f" ||
        fail "$f: OPEN PR RESUME no longer runs babysit, resolve, and debug in a run-owned worktree (breaks R28: they push the checked-out branch and stop on a dirty checkout)"
    grep -qF -- 'git worktree add <worktree-root>/pr-<number> <branch>' "$f" ||
        fail "$f: OPEN PR RESUME no longer creates the PR worktree under \`<worktree-root>\` (breaks R28: REAP cannot tell the worktree is run-owned)"
    grep -qF -- 'and skip any row whose `status` is `closed` without a `bd show`.' "$f" ||
        fail "$f: the post-merge queue scan no longer skips closed members (breaks R28: one \`bd show\` per closed member in history, every iteration)"

    # Diagnostic census, gates, owner decisions, final REAP and report.
    grep -qF -- 'is reported as `would evaluate: <proof>`, for example' "$f" ||
        fail "$f: DIAGNOSTIC RUN no longer reports a proof it cannot run as \`would evaluate: <proof>\` (breaks R28: a readonly census either writes or claims a proof it never ran)"
    grep -qF -- 'Only `label` and `native` gates count as human gates, because only they wait on a person.' "$f" ||
        fail "$f: CENSUS no longer counts only \`label\` and \`native\` gates as human gates (breaks R28: a timer gate is reported as work for a person)"
    grep -qF -- 'An `auto-resolving:<await_type>` gate resolves itself on its timer, run, PR, or bead:' "$f" ||
        fail "$f: CENSUS no longer reports a non-human gate as auto-resolving (breaks R28: a timer gate is reported as work for a person)"
    grep -qF -- 'run `bd update <id> --design-file <file>`. Read the field back and require the original text as an exact substring and the appended line in full;' "$f" ||
        fail "$f: OWNER-DECISION no longer writes the design field with \`--design-file\` and a read-back (breaks R28: \`--design\` replaces the field, and nothing proves the original survived)"
    grep -qF -- 'delete `<worktree-root>` with `rmdir`' "$f" ||
        fail "$f: the final REAP no longer deletes \`<worktree-root>\` (breaks R28: every run leaves an empty directory behind)"
    grep -qF -- 'List every closed issue whose PR is still `OPEN` on the forge:' "$f" ||
        fail "$f: FINAL REPORT no longer lists closed issues whose PR is still \`OPEN\` (breaks R28: a person-closed issue orphans an open PR nobody reports)"
    grep -qF -- 'Whether `bd list --json` carries a `metadata` object or a `dependencies` array depends on the `bd` version' "$f" ||
        fail "$f: CENSUS no longer states the \`bd list --json\` shape as version-dependent (breaks R28: the claim is false on the bd version that returns metadata)"
done

# ---------------------------------------------------------------------------
# R16. The companion goal cannot reintroduce a stronger unconditional stop.
#
# Install-only trees may contain only skills/, so absence of prompts/ skips
# this repository-level check. When prompts/ exists, the matching goal is a
# required part of the contract and must carry both halves of the rule.
# ---------------------------------------------------------------------------
if [ -d "$root/prompts" ]; then
    goal="$root/prompts/backlog-loop.goal.md"
    [ -f "$goal" ] ||
        fail "prompts/ exists but carries no backlog-loop.goal.md (breaks R16: the launch contract for recovery-aware execution is missing)"
    grep -qF -- 'Do not stop the goal merely because trunk is red' "$goal" ||
        fail "$goal: the goal no longer permits TRUNK REPAIR on a red trunk (breaks R16: prompt authority can stop before the skill reaches recovery)"
    grep -qF -- 'Stop the goal early only when backlog-loop has run its census and proved that no legal agent-executable action remains.' "$goal" ||
        fail "$goal: the goal is not gated on a census proving legal progress exhausted (breaks R16: a scoped failure can end the goal while independent work remains)"
    for forbidden in '- trunk health fails;' '- three consecutive batches are blocked or failed;' '- the same issue ID is attempted twice;' '- two consecutive merges fail;'; do
        if grep -qF -- "$forbidden" "$goal"; then
            fail "$goal: contains obsolete unconditional stop '$forbidden' (breaks R16: prompt authority overrides the recovery-aware skill)"
        fi
    done
fi

echo "OK: $SKILL_NAME across $checked host cop(y/ies): every declared phase reaches a RECOVERY arm in its own opening clause, the default arm names its evidence chain in order and tells FINAL REPORT what happened, the closed enum holds against a negation, the parked statuses outrank abandoned-claim, dep-blocked and legacy-blocked and abandoned-claim states the negation excluding them, CLASSIFY and <cause> agree in both directions, only { $ALLOWED_STATUS_WRITES } are written including quoted, CONSTRAINTS names the three refusals, RESIDUE PASS sits under the WRITE GATE, ITERATION step 2 still gates on a stripped-but-open PR, code-caused red trunk enters a complete tracked TRUNK REPAIR batch that budget checks cannot split, STOP EARLY requires exhausted legal progress instead of failure counters, the merge gate counts actionable_findings only while settled-decision conflicts still gate it, the off-route resolver runs in pipeline mode and preflight resolves ce-debug, and a PR closed without a merge becomes needs-person and releases its link instead of being reclaimed, the attempt ceiling exempts no cause, no transition unsets a DURABLE key, every cause written is declared and has a REOPEN PASS proof, a parked PR is adopted by one status-guarded write that is the only literal in_progress status flag, every blocked or verified write unsets the heartbeat and FINAL REPORT releases members still held, post-merge CI pending past 30 minutes runs the exact-merge local gate once and never rewrites the batch CI route to off, preflight stops on a required check with no producer and names the approval requirement, every bd ready call carries --limit 0, the browser test runs in the clean tree on a port REAP stops, the branch is recorded before step 4 and nothing is pushed before step 7, the run token and hygiene rules reach every child, OPEN PR RESUME runs in a run-owned worktree, and the goal prompt preserves the same terminal authority"
