#!/bin/sh
# Prove that check-backlog-loop.sh actually detects a broken tree.
#
# Usage: test-check-backlog-loop.sh [path-to-check-backlog-loop.sh]
#
# Copies the real skills tree into a fresh temporary directory per case,
# applies a single break, and requires the checker to exit non-zero AND to say
# why in a way that matches the case. Asserting the message matters: without it
# a case passes whenever the checker fails for any reason at all, including a
# reason unrelated to the break the case is named after -- and this checker has
# many independent assertions, so "it failed" carries almost no information.
#
# The cases come in three kinds.
#
#   DELETION cases remove a rule the procedure rests on -- the RECOVERY default
#   arm, the sentence closing the phase enum, `hooked` from `abandoned-claim`'s
#   exclusion list. Each of these is a real edit somebody could make while
#   tidying, and each one wedges a run rather than degrading it.
#
#   DRIFT cases leave every rule present and move one out from under another --
#   a phase renamed in the ledger with no arm added, a parked row renumbered
#   back below `abandoned-claim`, a `<cause>` row for a category CLASSIFY does
#   not carry. This is the failure mode parity cannot see, because both copies
#   drift together.
#
#   VACUITY cases break an extraction rather than a rule. Every assertion in
#   the checker is a loop over a table matched on its exact header line, so a
#   reformatting edit that touches no rule can empty the loop and leave a green
#   run asserting nothing. "Found nothing" and "found nothing wrong" have to be
#   distinguishable.
#
# One case runs the other way round: the UNMODIFIED tree must PASS. That is the
# only proof that the ` / ` split over the `<cause>` table's three multi-
# category cells works on the real file -- a checker that could not split them
# would report twelve categories against fifteen and fail here, and the fix
# would be to weaken the two-way census rather than the parser.
#
# Finally the whole break suite runs again against a deliberately weakened
# checker and requires *every* break to go undetected. Requiring all of them,
# rather than merely one, is what separates a suite that discriminates from a
# suite that crashed: an environmental failure would not miss exactly the full
# set.

set -eu

# At most one argument, and never an option: anything else is a typo to reject.
case "${1:-}" in -*) echo "usage: test-check-backlog-loop.sh [path-to-check-backlog-loop.sh]" >&2; exit 2 ;; esac
[ "$#" -le 1 ] || { echo "usage: test-check-backlog-loop.sh [path-to-check-backlog-loop.sh]" >&2; exit 2; }
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
checker="${1:-$repo_root/scripts/check-backlog-loop.sh}"

work=$(mktemp -d "${TMPDIR:-/tmp}/test-check-backlog-loop.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT HUP TERM

# A fresh copy of the real tree, one per case, so no case can see another's
# break. `prompts/` is included because the backlog-loop goal shares terminal
# authority with the skill; a correct host copy can still be deadlocked by an
# obsolete prompt-level stop.
#
# The directory name comes from `mktemp` and NOT from a counter this function
# increments. Every call site is `t=$(fresh_tree)`, which runs the function in
# a subshell, so an incremented counter would die with it and every case after
# the first would silently reuse -- and then overwrite -- case one's tree.
fresh_tree() {
    tree=$(mktemp -d "$work/case-XXXXXX")
    cp -R "$repo_root/skills" "$tree/skills"
    mkdir "$tree/prompts"
    cp "$repo_root/prompts/backlog-loop.goal.md" "$tree/prompts/backlog-loop.goal.md"
    cp "$repo_root/prompts/backlog-census.goal.md" "$tree/prompts/backlog-census.goal.md"
    echo "$tree"
}

LOOP_MD_CLAUDE="skills/claude/backlog-loop/SKILL.md"
LOOP_MD_CODEX="skills/codex/backlog-loop/SKILL.md"

# Append a line to a file in a case tree.
append_line() { # tree, relative-path, text
    printf '%s\n' "$3" >> "$1/$2"
}

# Replace the first occurrence of a literal string in a file in a case tree.
# `sed` is avoided here: every string below carries backticks, pipes, or both.
# Exits 2 rather than 0 when the target text is absent, because a break case
# that silently applied nothing would run the checker against a correct tree
# and report a MISS against the checker for the test's own defect.
replace_first() { # tree, relative-path, old, new
    OLD="$3" NEW="$4" python3 - "$1/$2" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if old not in s:
    sys.stderr.write("test bug: literal not present in %s: %r\n" % (p, old))
    sys.exit(2)
open(p, "w").write(s.replace(old, new, 1))
PY
}

# ---------------------------------------------------------------------------
# One case: run the checker under test against a broken tree and require both
# a non-zero exit and a message matching this case's expectation.
#
# Increments `break_cases` and, on a miss, `case_failures`; `run_suite` resets
# both before its first case. Never exits: the suite has to reach the end so the
# weakened-checker comparison below compares two runs of the same set.
# ---------------------------------------------------------------------------
expect_fail() { # name, expected-message-ERE, tree
    name="$1"
    expected="$2"
    tree="$3"
    break_cases=$((break_cases + 1))

    out=$(sh "$checker_under_test" "$tree" 2>&1) && rc=0 || rc=$?

    if [ "$rc" -eq 0 ]; then
        echo "  MISS: $name -- checker exited 0 on a broken tree" >&2
        case_failures=$((case_failures + 1))
        return 0
    fi
    if ! printf '%s\n' "$out" | grep -qE -- "$expected"; then
        echo "  WRONG REASON: $name" >&2
        echo "    expected message matching: $expected" >&2
        echo "    got: $(printf '%s\n' "$out" | head -n 1)" >&2
        case_failures=$((case_failures + 1))
        return 0
    fi
    echo "  ok: $name"
}

# One break applied to each host copy in turn, in its own tree. The message
# must name the mutated copy's path, so a checker that read only one host would
# miss the other copy's case. Used for the rules that carry a Codex-copy case.
both_hosts() { # name, old, new, expected-message-ERE
    for md in "$LOOP_MD_CLAUDE" "$LOOP_MD_CODEX"; do
        t=$(fresh_tree)
        replace_first "$t" "$md" "$2" "$3"
        expect_fail "$1 ($md)" "$md: $4" "$t"
    done
}

# One planted line appended to each host copy in turn, in its own tree. The
# message must name the mutated copy's path, as both_hosts does.
both_append() { # name, text, expected-message-ERE
    for md in "$LOOP_MD_CLAUDE" "$LOOP_MD_CODEX"; do
        t=$(fresh_tree)
        append_line "$t" "$md" "$2"
        expect_fail "$1 ($md)" "$md: $3" "$t"
    done
}

# The one line of a file in a case tree that matches a pattern, for a case that
# replaces or deletes exactly that line. Prints nothing and fails when no line
# matches: the case would otherwise mutate nothing and report a MISS against the
# checker for the test's own defect. Called as `x=$(line_of ...) || return 1`.
line_of() { # tree, relative-path, sed-regex, what-it-is
    found=$(sed -n "/$3/p" "$1/$2")
    [ -n "$found" ] || { echo "test bug: $4 missing before mutation" >&2; return 1; }
    printf '%s\n' "$found"
}

# A reference file planted in one host's copy of the skill: tree, host, text.
# The message a scan-type rule gives must name this path, so a checker that
# reads only SKILL.md, or only one host's references/, misses the case.
plant_reference() {
    mkdir -p "$1/skills/$2/backlog-loop/references"
    printf '%s\n' "$3" > "$1/skills/$2/backlog-loop/references/rationale.md"
}

# One line planted in references/rationale.md of each host copy in turn. The
# message must name the planted file's path.
both_reference_lines() { # name, text, expected-message-ERE
    for host in claude codex; do
        t=$(fresh_tree)
        plant_reference "$t" "$host" "$2"
        expect_fail "$1 (skills/$host/backlog-loop/references/rationale.md)" \
            "skills/$host/backlog-loop/references/rationale.md: $3" "$t"
    done
}

# ---------------------------------------------------------------------------
# The suite. Every case builds its own tree, applies exactly one break, and
# states the message it expects.
# ---------------------------------------------------------------------------
run_suite() { # checker path
    checker_under_test="$1"
    break_cases=0
    case_failures=0

    # -- DELETION: a rule removed -------------------------------------------

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '- Absent, or any value the `backlog_loop_phase` row above does not list:' \
        '- Never reached, kept for history:'
    expect_fail "the RECOVERY default arm is deleted" \
        "RECOVERY carries no arm for an absent or unrecognized" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '. These seven are the only phase values this procedure writes.' \
        '.'
    expect_fail "the sentence closing the backlog_loop_phase value set is deleted, every arm left in place" \
        "no longer states that its values are the only phase values" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'and `status` is not `blocked`, `hooked`, `pinned` or `deferred` |' \
        'and `status` is not `blocked`, `pinned` or `deferred` |'
    expect_fail "hooked is dropped from abandoned-claim's exclusion list" \
        'does not exclude .hooked.' "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'This procedure writes exactly four statuses: `open`, `in_progress`, `blocked`, and `closed`. It never writes `hooked`, `pinned`, or `deferred`.' \
        'This procedure writes the statuses the tracker accepts.'
    expect_fail "the ## CONSTRAINTS status sentence is removed" \
        "states no status this procedure never writes" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'RESIDUE PASS. For each issue this census classified' \
        'RESIDUE REPAIR. For each issue this census classified'
    expect_fail "the RESIDUE PASS opener is renamed out of ## CENSUS" \
        "carries no 'RESIDUE PASS.' opener" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '(REOPEN PASS, RESIDUE PASS, and GATE REPAIR PASS)' \
        '(REOPEN PASS and GATE REPAIR PASS)'
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        ', or RESIDUE PASS, which writes at most once per issue and then never again' \
        ''
    expect_fail "the WRITE GATE paragraph stops naming RESIDUE PASS" \
        "does not name RESIDUE PASS among the writes it covers" "$t"

    both_append "automatic PR close is reintroduced" \
        'Run `gh pr close <url>` after a review timeout.' \
        'backlog-loop may close a PR automatically'

    both_hosts "the open-PR preservation rule is removed" \
        'Never close a PR automatically.' \
        'A PR may be closed when it is stale.' \
        'open-PR preservation rule is missing'

    both_hosts "the bounded post-merge CI wait is removed" \
        'Wait up to 30 minutes total from `<first-seen-utc>`.' \
        'Wait as long as the queue entry needs.' \
        'bounded post-merge CI wait is missing'

    both_hosts "the post-merge CI queue resumed poll is removed" \
        'Recheck the durable queue at each iteration and in the next invocation.' \
        'Recheck the queue when convenient.' \
        'post-merge CI queue has no resumed poll'

    both_hosts "the durable post-merge CI queue key is removed" \
        '| `backlog_loop_postmerge_ci` |' \
        '| `backlog_loop_postmerge_ci_removed` |' \
        'durable post-merge CI queue key is missing'

    both_hosts "CI-off recovery waits on a missing workflow" \
        'If either route is `off` or missing, a missing workflow does not hold verification after the exact-merge clean-tree gate passes' \
        'If either route is `off` or missing, keep waiting for every workflow' \
        'CI-off recovery can wait forever'

    both_hosts "CI-off verification waits on a missing workflow" \
        'When either route is `off`, the exact-merge local gate is authoritative: a missing workflow does not keep the queue pending after that gate passes.' \
        'When either route is `off`, keep waiting for every missing workflow.' \
        'CI-off post-merge verification can wait forever'

    both_hosts "parked PR resume path is removed" \
        'OPEN PR RESUME. For each linked PR' \
        'PARKED PR REPORT. For each linked PR' \
        'a parked open PR has no later-run resume path'

    both_hosts "CI watch enumerates metadata from plain bd list" \
        'bd list --limit 0 --has-metadata-key backlog_loop_postmerge_ci --json' \
        'bd list --limit 0 --json' \
        'CI watch cannot enumerate queue entries'

    both_hosts "residue pass stops unsetting the FORGE-LINK class, so a parked CI queue entry survives" \
        'plus unsetting the RUN and FORGE-LINK classes (KEY CLASSES)' \
        'plus unsetting the RUN class (KEY CLASSES)' \
        'RESIDUE PASS leaves a parked issue'

    both_hosts "the FORGE-LINK class stops holding the post-merge CI queue key" \
        '`backlog_loop_postmerge_ci`, `backlog_loop_gate_receipt` | reclaim' \
        '`backlog_loop_gate_receipt` | reclaim' \
        'the KEY CLASSES FORGE-LINK row no longer lists .backlog_loop_postmerge_ci.'

    # A substring test for `claimed` stays green here: the replacement leaves
    # "reclaimed" in the block. Only a whole-token match sees the arm go.
    t=$(fresh_tree)
    claimed_arm=$(line_of "$t" "$LOOP_MD_CLAUDE" '^- `pr-open`, `built`, or `claimed`:' 'claimed arm') || return 1
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        "$claimed_arm" \
        '- `pr-open` or `built`: an issue reclaimed here is reclaimed whole.'
    expect_fail "the RECOVERY claimed arm is deleted while 'reclaimed' still appears in the block" \
        'declares phase .claimed. but no RECOVERY arm' "$t"

    # Whole-block substring matching stays green here too: `merged` survives
    # in three other arms' cross-references even after the arm that CLAIMS it
    # is deleted outright. Only opener-scoped matching sees it go.
    t=$(fresh_tree)
    merged_arm=$(line_of "$t" "$LOOP_MD_CLAUDE" '^- `merged` or `verified`:' 'merged/verified arm') || return 1
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        "$merged_arm" \
        ''
    expect_fail "the merged/verified RECOVERY bullet is deleted whole" \
        'declares phase .merged. but no RECOVERY arm' "$t"

    # Same shape, the other combined arm: `merge-requested` survives in the
    # default arm's own cross-reference ("follow the `merge-requested` arm's
    # rules"), so a whole-block test stays green after this bullet is gone.
    t=$(fresh_tree)
    merge_requested_arm=$(line_of "$t" "$LOOP_MD_CLAUDE" '^- `merge-requested`:' 'merge-requested arm') || return 1
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        "$merge_requested_arm" \
        '- `interrupted`: park the batch.'
    expect_fail "the merge-requested RECOVERY bullet is deleted whole" \
        'declares phase .merge-requested. but no RECOVERY arm' "$t"

    # A prefix match on the default arm's opening words stays green after its
    # trailing FINAL REPORT clause is gone -- the arm still opens the same way.
    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'Else reclaim. Name the unrecognized value, the arm taken, and the evidence key that chose it in the FINAL REPORT: an improvised value was written by something, and a recovery that swallows it leaves the next run to meet the same value with the same nothing to go on. Without this arm an unrecognized phase matches no arm at all and ends the run outright -- which is how one issue carrying one improvised value wedged every later invocation.' \
        'Else reclaim.'
    expect_fail "the default RECOVERY arm loses its FINAL REPORT naming clause" \
        'no longer tells FINAL REPORT to name the unrecognized value' "$t"

    # -- DRIFT: every rule present, one moved out from under another ---------

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| `backlog_loop_phase` | each transition | `claimed`, `built`, `shipping-requested`, `pr-open`,' \
        '| `backlog_loop_phase` | each transition | `claimed`, `built`, `shipping-requested`, `pr-opened`,'
    expect_fail "a phase value is renamed in the ledger with no arm added" \
        'declares phase .pr-opened. but no RECOVERY arm' "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| 11 | `deferred` | `status=deferred` |' \
        '| 13 | `deferred` | `status=deferred` |'
    expect_fail "deferred is renumbered back below abandoned-claim" \
        'CLASSIFY row 13 .deferred. does not outrank row 12 .abandoned-claim.' "$t"

    t=$(fresh_tree)
    append_line "$t" "$LOOP_MD_CLAUDE" \
        'Park it with `bd update <id> --status=deferred` and move on.'
    expect_fail "a --status=deferred write is added" \
        'writes .--status=deferred., which is outside' "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| `ready` | `none` |' \
        '| `ready` | `none` |
| `stalled` | `none` |'
    expect_fail "a <cause> row names a category CLASSIFY does not carry" \
        "name no CLASSIFY row" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| `ready` | `none` |
' \
        ''
    expect_fail "a CLASSIFY category loses its <cause> row" \
        "have no row in the EMIT <cause> table" "$t"

    # A bare char-class pattern for `--status=` stops at an opening quote and
    # captures nothing, so a quoted write was invisible to the old census.
    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'Reclaim means `bd update <id> --status=open --assignee=""' \
        'Reclaim means `bd update <id> --status="deferred" --assignee=""'
    expect_fail "a quoted --status=\"deferred\" write is added" \
        'writes .--status=deferred., which is outside' "$t"

    # R8 reads every form that writes a status, not only `--status=`: the
    # space-separated long flag, the short flag, and the commands that write a
    # status without naming one. A form the census cannot see is a status this
    # loop writes without anyone checking whose it is.
    both_append "a --status deferred write is added" \
        'Park it with `bd update <id> --status deferred` and move on.' \
        'writes .--status deferred., which is outside'
    both_append "a -s pinned write is added" \
        'Park it with `bd update <id> -s pinned` and move on.' \
        'writes .-s pinned., which is outside'
    both_append "a --status closed write is added" \
        'Finish it with `bd update <id> --status closed`.' \
        'writes .--status closed., which is outside'
    both_append "an in_progress status flag is written without the adoption guard" \
        'Take it with `bd update <id> -s in_progress`.' \
        'writes .-s in_progress., which is outside'
    both_append "a --status write behind a global option is added" \
        'Park it with `bd -C . update <id> --status hooked` and move on.' \
        'writes .--status hooked., which is outside'
    both_append "a quoted --status write is added" \
        'Park it with `bd update <id> --status "deferred"` and move on.' \
        'writes .--status deferred., which is outside'
    both_append "a --status write names no value the census can read" \
        'Park it with `bd update <id> --status <status>` and move on.' \
        '[0-9]+ .--status X. or .-s X. occurrence.s. could not be parsed into a value'
    both_append "bd defer is used to park an issue" \
        'Park it with `bd defer <id>` and move on.' \
        'line [0-9]+ runs .bd defer.'
    both_append "bd defer is used behind a global option" \
        'Park it with `bd -C . defer <id>` and move on.' \
        'line [0-9]+ runs .bd defer.'

    # `bd close` is a write of `closed`, permitted in step 7 VERIFY, THEN CLOSE
    # and the RECOVERY `verified` arm and nowhere else.
    both_append "bd close is run outside step 7 and the verified arm" \
        'Then run `bd close <id>`.' \
        'line [0-9]+ runs .bd close. outside step 7'
    both_append "bd close is run behind a global option outside step 7" \
        'Then run `bd -C . close <id>`.' \
        'line [0-9]+ runs .bd close. outside step 7'
    both_hosts "bd close is run in the merge-requested RECOVERY arm" \
        '- `merge-requested`: the outcome is unknown' \
        '- `merge-requested`: run `bd close <id>`; the outcome is unknown' \
        'line [0-9]+ runs .bd close. outside step 7'
    both_hosts "bd close is run in REAP" \
        '8. **REAP.** Runs at the end' \
        '8. **REAP.** Run `bd close <id>`. Runs at the end' \
        'line [0-9]+ runs .bd close. outside step 7'

    # Every token the exclusion names is still present; only the polarity
    # flips from "is not" to "is". Token-presence matching cannot see this.
    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '`backlog_loop_run` present, that run is NOT live, and `status` is not `blocked`, `hooked`, `pinned` or `deferred` |' \
        '`backlog_loop_run` present, that run is NOT live, and `status` is `blocked`, `hooked`, `pinned` or `deferred` |'
    expect_fail "the abandoned-claim exclusion cell is inverted" \
        "does not state the negation" "$t"

    # The substring "only phase values this procedure writes" survives a
    # negation inserted right after "are", so a substring test stays green.
    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'These seven are the only phase values this procedure writes.' \
        'These seven are **not necessarily** the only phase values this procedure writes.'
    expect_fail "the closed-enum sentence is negated rather than deleted" \
        "no longer states that its values are the only phase values" "$t"

    # Renumbered so the parked rows still outrank abandoned-claim (12 -> 13)
    # but no longer outrank dep-blocked (14 -> 9): the wedge this reopens is
    # a parked issue with an unmet dependency walked in as dep-blocked, which
    # is exactly what the CLASSIFY rationale in references/rationale.md forbids.
    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| 9 | `hooked` | `status=hooked` |' \
        '| 10 | `hooked` | `status=hooked` |'
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| 10 | `pinned` | `status=pinned` |' \
        '| 11 | `pinned` | `status=pinned` |'
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| 11 | `deferred` | `status=deferred` |' \
        '| 12 | `deferred` | `status=deferred` |'
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| 12 | `abandoned-claim` | `backlog_loop_run` present, that run is NOT live, and `status` is not `blocked`, `hooked`, `pinned` or `deferred` |' \
        '| 13 | `abandoned-claim` | `backlog_loop_run` present, that run is NOT live, and `status` is not `blocked`, `hooked`, `pinned` or `deferred` |'
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| 13 | `legacy-blocked` | `status=blocked`, no `backlog_loop_run`, and no unmet dependency |' \
        '| 14 | `legacy-blocked` | `status=blocked`, no `backlog_loop_run`, and no unmet dependency |'
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        "| 14 | \`dep-blocked\` | an unmet dependency, by \`--explain\`'s verdict above |" \
        "| 9 | \`dep-blocked\` | an unmet dependency, by \`--explain\`'s verdict above |"
    expect_fail "CLASSIFY is renumbered so dep-blocked outranks the parked rows" \
        'does not outrank row 9 .dep-blocked.' "$t"

    # Only the two backtick tokens swap position; the surrounding prose is
    # untouched, so this changes nothing but the evidence chain's order.
    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '`backlog_loop_merge` recorded -> treat as `merged` above. Else `backlog_loop_pr` recorded' \
        '`backlog_loop_pr` recorded -> treat as `merged` above. Else `backlog_loop_merge` recorded'
    expect_fail "the default arm's evidence chain is reordered" \
        'as backtick tokens in that order' "$t"

    # Restores the pre-katze-mh0j-equivalent unconditional sentence: RESIDUE
    # PASS still promises the termination decision, but step 2 no longer asks.
    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        "set except an issue whose open linked PR REPORT lists as awaiting a required approval, and no PR this census's RESIDUE PASS stripped is still \`OPEN\` -> the backlog is clear." \
        "set -> the backlog is clear."
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        ' An outstanding stripped PR withholds that verdict, but it does not stop independent ready work: carry and report every URL while batches remain selectable, and stop and report the still-open PR only after no agent-executable work remains.' \
        ''
    expect_fail "ITERATION step 2's clear-backlog sentence drops the stripped-PR condition" \
        "no longer carries the stripped-PR condition" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'A code-caused red trunk is recovery work, not a terminal blocker.' \
        'A code-caused red trunk ends this run.'
    expect_fail "TRUNK HEALTH loses the red-trunk recovery disposition" \
        "no longer classifies a code-caused red trunk as recovery work" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'A TRUNK REPAIR batch never drops a member here.' \
        'A TRUNK REPAIR batch follows the ordinary drop rule.'
    expect_fail "the plan-boundary budget can split a trunk-repair batch" \
        "plan-boundary budget may drop a TRUNK REPAIR member" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'Stop only when no legal agent-executable action remains.' \
        'Stop after three failures.'
    expect_fail "STOP EARLY loses the exhausted-progress gate" \
        "STOP EARLY is not gated on exhausting legal agent-executable progress" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'Counts of failed batches or merges never substitute for the reachability decision.' \
        'Counts of failed batches or merges never substitute for the reachability decision. 3 consecutive BATCHES end blocked or failed.'
    expect_fail "STOP EARLY regains a failed-batch counter" \
        "counter-shaped terminal rule '3 consecutive BATCHES'" "$t"

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-loop.goal.md" \
        'Stop the goal early only when backlog-loop has run its census and proved that no legal agent-executable action remains.' \
        'Stop the goal early if trunk health fails.'
    expect_fail "the companion goal loses its census reachability gate" \
        "goal is not gated on a census proving legal progress exhausted" "$t"

    # -- Goal prompts: success conditions the skill can satisfy ---------------
    #
    # Condition 1 was once `bd ready` returning nothing, which a label-only
    # human gate, a label defect, or a quarantined issue (all still offered as
    # ready work) keeps false forever. Every case below is a revert to text
    # that looked right against an older skill.

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-loop.goal.md" \
        '2. No non-epic issue remains in progress' \
        '1. `bd ready --json --exclude-type=epic` returns no actionable issue.
2. No non-epic issue remains in progress'
    expect_fail "the companion goal restores the bd ready success condition" \
        "contains obsolete goal text '1. .bd ready --json --exclude-type=epic. returns no actionable issue.'" "$t"

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-loop.goal.md" \
        '1. The backlog-loop census proves that no legal agent-executable action remains: no issue sits in its loop-responsible set except an issue whose open linked PR REPORT lists as awaiting a required approval and whose issue is reported as awaiting a person, and no PR its RESIDUE PASS stripped is still `OPEN`. A human gate, a label defect, and a quarantined issue each wait on a person, sit outside that set, and do not block success.' \
        '1. `bd ready --json --exclude-type=epic` returns no actionable issue.'
    expect_fail "the companion goal swaps its census success condition for the old bd ready one" \
        "goal no longer states its first success condition as the census proving no legal agent-executable action remains" "$t"

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-loop.goal.md" \
        ', or a merged member held by a recorded post-merge watch and reported with its `backlog_loop_postmerge_ci` queue entry.' \
        '.'
    expect_fail "the companion goal no longer allows a member held by a post-merge watch" \
        "goal no longer allows an in-progress member held by a recorded post-merge watch" "$t"

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-loop.goal.md" \
        'including CI route, quality gates, and merge. This prompt adds no rule of its own.' \
        'For every batch, follow the CI state selected by backlog-loop:
- When CI is available, use its documented bounded babysitter and require a mergeable CI decision.
- When CI is unavailable, use the documented local pre-merge and post-merge quality gates without waiting for nonexistent CI.'
    expect_fail "the companion goal restores its own CI paragraph" \
        "contains obsolete goal text 'For every batch, follow the CI state selected by backlog-loop:'" "$t"

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-loop.goal.md" \
        'Never ask me for input.' \
        'Merge with `gh pr merge <url> --squash --delete-branch`.
Never ask me for input.'
    expect_fail "the companion goal carries a gh pr merge example with no --match-head-commit" \
        "carries a gh pr merge example with no --match-head-commit" "$t"

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-census.goal.md" \
        'Never ask me for input.' \
        'Land it with `gh pr merge <url> --squash`.
Never ask me for input.'
    expect_fail "the census goal carries a gh pr merge example with no --match-head-commit" \
        "backlog-census.goal.md: carries a gh pr merge example with no --match-head-commit" "$t"

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-census.goal.md" \
        'Never ask me for input.' \
        'Stop the goal early if:
- three consecutive batches are blocked or failed;
Never ask me for input.'
    expect_fail "the census goal regains a failed-batch counter stop" \
        "backlog-census.goal.md: contains obsolete goal text '- three consecutive batches are blocked or failed;'" "$t"

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-census.goal.md" \
        '3. Every repair, every reopen, and every residue strip a loop run would perform is reported' \
        '3. Every repair and every reopen a loop run would perform is reported'
    expect_fail "the census goal stops listing residue strips beside repairs and reopens" \
        "census goal no longer lists residue strips beside repairs and reopens" "$t"

    # -- CE 3.30.1 compatibility: the merge gate and the child contracts -----
    #
    # Every one of these is a revert to text that was correct against an older
    # compound-engineering: LFG never applies an `advisory` finding and never
    # lists it under `## Unapplied review findings`, so a gate that reconciles
    # every returned finding can never be satisfied by a review that returns
    # one.

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'and reconcile `actionable_findings` only: each one is either an applied fix or an entry in `## Unapplied review findings`.' \
        'and reconcile every finding the review returned against either an applied fix or an entry in `## Unapplied review findings`.'
    expect_fail "pipeline step 4 reconciles every returned finding instead of actionable_findings" \
        "no longer reconciles actionable_findings only" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CODEX" \
        'and reconcile `actionable_findings` only: each one is either an applied fix or an entry in `## Unapplied review findings`.' \
        'and reconcile every finding the review returned against either an applied fix or an entry in `## Unapplied review findings`.'
    expect_fail "pipeline step 4 reconciles every returned finding, in the Codex copy alone" \
        "skills/codex/backlog-loop/SKILL.md: pipeline step 4 no longer reconciles actionable_findings only" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'with every entry in the review'"'"'s `actionable_findings` reconciled to either an applied-fix receipt or one of those entries' \
        'with every finding the review returned reconciled to either an applied-fix receipt or one of those entries'
    expect_fail "the merge gate counts every returned finding instead of actionable_findings" \
        "merge gate no longer counts actionable_findings only" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        ' `advisory` findings are not entries and never block a merge.' \
        ''
    expect_fail "the merge gate stops saying advisory findings never block a merge" \
        "merge gate no longer says advisory findings never block a merge" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'Record `advisory` findings under a separate non-checkbox `## Advisory review notes` heading in the PR body; they never gate the merge. ' \
        ''
    expect_fail "advisory findings have no separate non-checkbox PR-body heading" \
        "no longer records advisory findings under a separate non-checkbox heading" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'The `settled_conflict` and `settled_decision_conflicts` bullets LFG step 6 writes under that heading gate the merge like any unchecked entry, because a divergence from a settled decision needs a person. ' \
        ''
    expect_fail "the settled-conflict bullets stop gating the merge" \
        "no longer says the settled_conflict and settled_decision_conflicts bullets gate the merge" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'a `failed`, `degraded`, or `skipped` status, or a malformed return, takes the blocked path in step 7' \
        'a `degraded`, `blocked`, `skipped`, or malformed return takes the blocked path in step 7'
    expect_fail "the review's non-complete statuses revert to a set that has no failed and invents blocked" \
        "no longer names failed, degraded, and skipped as the non-complete review statuses" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'invoke `compound-engineering:ce-resolve-pr-feedback mode:pipeline <pr-url>` once, so no step can stop on a blocking question;' \
        'invoke `compound-engineering:ce-resolve-pr-feedback <pr-url>` once;'
    expect_fail "the step 8 resolver loses mode:pipeline" \
        "no longer invokes ce-resolve-pr-feedback in pipeline mode" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CODEX" \
        'invoke `compound-engineering:ce-resolve-pr-feedback mode:pipeline <pr-url>` once, so no step can stop on a blocking question;' \
        'invoke `compound-engineering:ce-resolve-pr-feedback <pr-url>` once;'
    expect_fail "the step 8 resolver loses mode:pipeline, in the Codex copy alone" \
        "skills/codex/backlog-loop/SKILL.md: step 8 no longer invokes ce-resolve-pr-feedback in pipeline mode" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '`compound-engineering:ce-resolve-pr-feedback`, `compound-engineering:ce-debug`. LFG' \
        '`compound-engineering:ce-resolve-pr-feedback`. LFG'
    expect_fail "preflight stops naming ce-debug among the skills it resolves" \
        "preflight no longer resolves compound-engineering:ce-debug" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CODEX" \
        '`compound-engineering:ce-resolve-pr-feedback`, `compound-engineering:ce-debug`. LFG' \
        '`compound-engineering:ce-resolve-pr-feedback`. LFG'
    expect_fail "preflight stops naming ce-debug, in the Codex copy alone" \
        "skills/codex/backlog-loop/SKILL.md: preflight no longer resolves compound-engineering:ce-debug" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        "LFG's \`ce-compound\` step is skipped deliberately: it would add a commit after the gated head. " \
        ''
    expect_fail "preflight no longer says the LFG ce-compound step is skipped deliberately" \
        "no longer says the LFG ce-compound step is skipped deliberately" "$t"

    both_hosts "needs-person enters the loop-responsible categories" \
        'Exactly five categories are the loop'"'"'s to clear: `ready`, `claimed-this-run`, `abandoned-claim`, `self-blocked-transient`, and a `dep-blocked` issue whose blocker is itself in one of those.' \
        'Exactly five categories are the loop'"'"'s to clear: `ready`, `claimed-this-run`, `abandoned-claim`, `self-blocked-transient`, `self-blocked-needs-person`, and a `dep-blocked` issue whose blocker is itself in one of those.' \
        "residual contract missing: loop-responsible category set"

    both_hosts 'optional pipeline guard' \
        'A completed failure of any required check on the exact head blocks the merge; a completed optional failure blocks unless it is `startup_failure` or a billing or quota error. A missing or pending optional check, including optional `startup_failure` and billing or quota errors counted as missing, does not delay a PR that GitHub reports `MERGEABLE`:' \
        'A completed failure of any check on the exact head blocks the merge, required or optional. A missing or pending optional check does not delay a PR that GitHub reports `MERGEABLE`:' \
        'residual contract missing: optional pipeline guard'

    both_hosts 'optional boundary guard' \
        'Required status checks require the babysitter'"'"'s passing CI decision; a missing or pending optional check, including optional `startup_failure` and billing or quota errors counted as missing, does not block a GitHub `MERGEABLE` PR after its exact-head local gates pass, and a completed optional failure of any other kind does.' \
        'Required status checks require the babysitter'"'"'s passing CI decision; a missing or pending optional check does not block a GitHub `MERGEABLE` PR after its exact-head local gates pass, and a completed optional failure does.' \
        'residual contract missing: optional boundary guard'

    # Residual contract break cases (U1-U5), also run against the exit-0 control.
    both_hosts 'CLAIM worktree root' \
        '4. **CLAIM.** `bd show <id>` for every member, then atomically claim each with `bd update <id> --claim` and set its run metadata, including `backlog_loop_phase=claimed`, `backlog_loop_base=<batch-base-sha>`, `backlog_loop_trunk_ci=<trunk-ci>`, `backlog_loop_worktrees=<worktree-root>`, and provisional `backlog_loop_ci=<batch-ci>`.' \
        '4. **CLAIM.** `bd show <id>` for every member, then atomically claim each with `bd update <id> --claim` and set its run metadata, including `backlog_loop_phase=claimed`, `backlog_loop_base=<batch-base-sha>`, `backlog_loop_trunk_ci=<trunk-ci>`, and provisional `backlog_loop_ci=<batch-ci>`.' \
        'residual contract missing: CLAIM worktree root'

    both_hosts 'worktree ledger writer' \
        '| `backlog_loop_worktrees` | CLAIM, then idempotently at the first CLEAN-TREE GATE RUN, or the first PR worktree OPEN PR RESUME creates | `<worktree-root>` |' \
        '| `backlog_loop_worktrees` | first CLEAN-TREE GATE RUN, or the first PR worktree OPEN PR RESUME creates | `<worktree-root>` |' \
        'residual contract missing: worktree ledger writer'

    both_hosts 'guarded ADOPTION park' \
        'then one `bd update <id> --if-status in_progress --status=blocked --unset-metadata backlog_loop_heartbeat --set-metadata backlog_loop_cause=transient:pr-open`, uncharged, and adopt it with the write above. Exit 13 means another invocation moved the member first: skip it and write nothing.' \
        'then one `bd update <id> --status=blocked --unset-metadata backlog_loop_heartbeat --set-metadata backlog_loop_cause=transient:pr-open`, uncharged, and adopt it with the write above.' \
        'residual contract missing: guarded ADOPTION park'

    both_hosts 'disposition precedence' \
        'this table decides what happens to the PR. The first matching row wins, and the last row is the catch-all for unnamed open states. "Charged" is defined under CHARGING.' \
        'this table decides what happens to the PR. "Charged" is defined under CHARGING.' \
        'residual contract missing: disposition precedence'

    both_hosts 'optional disposition exemption' \
        '| `OPEN`, no required check, an optional check missing or pending (`startup_failure` and billing or quota errors count as missing) | run the complete applicable local gate set on the exact head, including workflow verification coverage; keep the route `on` and post-merge CI expected, and write `backlog_loop_ci=off` only on proven absence of every producer (pipeline step 6), never because an optional check is slow; then I6'"'"'s guarded merge | no | `in_progress` at `merge-requested` |' \
        '| `OPEN`, no required check, an optional check missing or pending | run the complete applicable local gate set on the exact head, including workflow verification coverage; keep the route `on` and post-merge CI expected, and write `backlog_loop_ci=off` only on proven absence of every producer (pipeline step 6), never because an optional check is slow; then I6'"'"'s guarded merge | no | `in_progress` at `merge-requested` |' \
        'residual contract missing: optional disposition exemption'

    both_hosts 'red-check exemption' \
        '| `OPEN`, a required check is red, or an optional check has a completed failure other than `startup_failure` or a billing or quota error | one babysit round through its CI stream; a changed head is recorded and returns to P4-P6, at most two rounds, then the blocked path | yes, per round that ends still red | `blocked`, `transient:pr-open` |' \
        '| `OPEN`, a required check is red, or an optional check has a completed failure | one babysit round through its CI stream; a changed head is recorded and returns to P4-P6, at most two rounds, then the blocked path | yes, per round that ends still red | `blocked`, `transient:pr-open` |' \
        'residual contract missing: red-check exemption'

    both_hosts 'optional merge guard' \
        '(or `UNSTABLE` when every non-passing check is optional and still pending or missing, where `startup_failure` and billing or quota errors count as missing), and a `reviewDecision` other than `CHANGES_REQUESTED` or `REVIEW_REQUIRED`. Required checks must pass, and a completed failure of an optional check blocks too unless it is `startup_failure` or a billing or quota error; only a missing or pending optional check, including those errors, is bypassed by green exact-head local gates.' \
        '(or `UNSTABLE` when every non-passing check is optional and still pending or missing), and a `reviewDecision` other than `CHANGES_REQUESTED` or `REVIEW_REQUIRED`. Required checks must pass, and a completed failure of an optional check blocks too; only a missing or pending optional check is bypassed by green exact-head local gates.' \
        'residual contract missing: optional merge guard'

    both_hosts 'catch-all disposition' \
        '| `OPEN`, any state no earlier row names (`BLOCKED`, `UNKNOWN`, or `UNSTABLE`) | re-read once after 30 seconds and take the matching row if the state changed; otherwise write `transient:pr-open`, never merge, and list the PR and its state in REPORT | no | `blocked`, `transient:pr-open` |' \
        '' \
        'residual contract missing: catch-all disposition'

    both_hosts 'catch-all moved above the adopt row' \
        '| `OPEN`, head equals `backlog_loop_head`, base equals the gated base, required checks pass, `mergeStateStatus` is `CLEAN` or `HAS_HOOKS` (or `UNSTABLE` when every non-passing check is optional and still pending or missing, where `startup_failure` and billing or quota errors count as missing), no unresolved feedback | adopt the issue through ADOPTION'"'"'s guarded write; rerun the exact-head gates only when `backlog_loop_gate_receipt` does not hold this head, this base, and the current gate-set digest; then I6'"'"'s guarded merge | no | `in_progress` at `merge-requested` |
| `OPEN`, any state no earlier row names (`BLOCKED`, `UNKNOWN`, or `UNSTABLE`) | re-read once after 30 seconds and take the matching row if the state changed; otherwise write `transient:pr-open`, never merge, and list the PR and its state in REPORT | no | `blocked`, `transient:pr-open` |' \
        '| `OPEN`, any state no earlier row names (`BLOCKED`, `UNKNOWN`, or `UNSTABLE`) | re-read once after 30 seconds and take the matching row if the state changed; otherwise write `transient:pr-open`, never merge, and list the PR and its state in REPORT | no | `blocked`, `transient:pr-open` |
| `OPEN`, head equals `backlog_loop_head`, base equals the gated base, required checks pass, `mergeStateStatus` is `CLEAN` or `HAS_HOOKS` (or `UNSTABLE` when every non-passing check is optional and still pending or missing, where `startup_failure` and billing or quota errors count as missing), no unresolved feedback | adopt the issue through ADOPTION'"'"'s guarded write; rerun the exact-head gates only when `backlog_loop_gate_receipt` does not hold this head, this base, and the current gate-set digest; then I6'"'"'s guarded merge | no | `in_progress` at `merge-requested` |' \
        'residual contract missing: catch-all must be the last disposition row'

    both_hosts 'released needs-person census' \
        '| 6 | `self-blocked-needs-person` | (`status=blocked`, `backlog_loop_run` present, and `backlog_loop_cause` is `needs-person` or still absent), or (`status=blocked`, no `backlog_loop_run`, and `backlog_loop_cause` is `needs-person`) |' \
        '| 6 | `self-blocked-needs-person` | `status=blocked`, `backlog_loop_run` present, and `backlog_loop_cause` is `needs-person` or still absent |' \
        'residual contract missing: released needs-person census'

    both_hosts 'released needs-person ownership' \
        'That split is an ownership test and CENSUS extends it into a full accounting of every non-closed issue. A `needs-person` cause alone on a blocked issue marks this loop'"'"'s own release of a person-closed PR, even after its RUN keys are unset.' \
        'That split is an ownership test and CENSUS extends it into a full accounting of every non-closed issue.' \
        'residual contract missing: released needs-person ownership'

    both_hosts 'released needs-person REPORT' \
        'every `legacy-blocked` issue and every `self-blocked-needs-person` issue released by a person-close with the first line of its note every reported cycle,' \
        'every `legacy-blocked` issue with the first line of its note every reported cycle,' \
        'residual contract missing: released needs-person REPORT'

    both_hosts 'approval loop set' \
        'An issue whose open linked PR REPORT lists as awaiting a required approval is reported as awaiting a person and does not hold back the clear verdict. Everything else is somebody'"'"'s or something else'"'"'s.' \
        'Everything else is somebody'"'"'s or something else'"'"'s.' \
        'residual contract missing: approval loop set'

    both_hosts 'needs-person outside loop set' \
        '`quarantined`, `legacy-blocked`, and `self-blocked-needs-person` are deliberately NOT in the set, because they wait on a person.' \
        '`quarantined` and `legacy-blocked` are deliberately NOT in the set, both because they wait on a person.' \
        'residual contract missing: needs-person outside loop set'

    both_hosts 'approval termination' \
        'No issue in the loop-responsible set except an issue whose open linked PR REPORT lists as awaiting a required approval, and no PR this census'"'"'s RESIDUE PASS stripped is still `OPEN` -> the backlog is clear. Report that approval-waiting issue as awaiting a person; it does not hold back the clear verdict.' \
        'No issue in the loop-responsible set, and no PR this census'"'"'s RESIDUE PASS stripped is still `OPEN` -> the backlog is clear.' \
        'residual contract missing: approval termination'

    both_hosts 'adopt row UNSTABLE' \
        'required checks pass, `mergeStateStatus` is `CLEAN` or `HAS_HOOKS` (or `UNSTABLE` when every non-passing check is optional and still pending or missing, where `startup_failure` and billing or quota errors count as missing), no unresolved feedback | adopt the issue through ADOPTION'"'"'s guarded write;' \
        'required checks pass, `mergeStateStatus` is `CLEAN` or `HAS_HOOKS`, no unresolved feedback | adopt the issue through ADOPTION'"'"'s guarded write;' \
        'residual contract missing: adopt row UNSTABLE'

    both_hosts 'approval exception in recoverable-PR rule' \
        'or LINKED PR DISPOSITION sends it to `needs-person`, except that an issue whose open linked PR REPORT lists as awaiting a required approval is reported as awaiting a person and does not hold back the clear verdict. Nothing here decides' \
        'or LINKED PR DISPOSITION sends it to `needs-person`. Nothing here decides' \
        'residual contract missing: approval exception in recoverable-PR rule'

    both_hosts 'REVIEW_REQUIRED row charged' \
        '| `OPEN`, `reviewDecision` is `REVIEW_REQUIRED` | wait for the required approval and never approve; list the PR in REPORT as awaiting a required approval and its issue as awaiting a person, without holding back the clear verdict | no | `blocked`, `transient:pr-open` |' \
        '| `OPEN`, `reviewDecision` is `REVIEW_REQUIRED` | wait for the required approval and never approve; list the PR in REPORT as awaiting a required approval and its issue as awaiting a person, without holding back the clear verdict | yes | `blocked`, `transient:pr-open` |' \
        'the .REVIEW_REQUIRED. row no longer waits and reports the required approval without holding back the clear verdict'

    both_hosts 'catch-all merges' \
        '| `OPEN`, any state no earlier row names (`BLOCKED`, `UNKNOWN`, or `UNSTABLE`) | re-read once after 30 seconds and take the matching row if the state changed; otherwise write `transient:pr-open`, never merge, and list the PR and its state in REPORT | no | `blocked`, `transient:pr-open` |' \
        '| `OPEN`, any state no earlier row names (`BLOCKED`, `UNKNOWN`, or `UNSTABLE`) | re-read once after 30 seconds and take the matching row if the state changed; otherwise write `transient:pr-open`, then I6'"'"'s guarded merge, and list the PR and its state in REPORT | no | `blocked`, `transient:pr-open` |' \
        'residual contract missing: catch-all disposition'

    both_hosts 'catch-all charged' \
        '| `OPEN`, any state no earlier row names (`BLOCKED`, `UNKNOWN`, or `UNSTABLE`) | re-read once after 30 seconds and take the matching row if the state changed; otherwise write `transient:pr-open`, never merge, and list the PR and its state in REPORT | no | `blocked`, `transient:pr-open` |' \
        '| `OPEN`, any state no earlier row names (`BLOCKED`, `UNKNOWN`, or `UNSTABLE`) | re-read once after 30 seconds and take the matching row if the state changed; otherwise write `transient:pr-open`, never merge, and list the PR and its state in REPORT | yes | `blocked`, `transient:pr-open` |' \
        'residual contract missing: catch-all disposition'

    both_append "option-bearing switch targets default" \
        '`git -C <invoking-worktree> switch <default>`' \
        "the skill restores .git switch <default>. or a fast-forward"

    for host in claude codex; do
        t=$(fresh_tree)
        plant_reference "$t" "$host" '`git -c advice.detachedHead=false checkout <default>`'
        expect_fail "option-bearing checkout in reference ($host)" \
            "skills/$host/backlog-loop/references/rationale.md: the skill restores" "$t"
    done

    t=$(fresh_tree)
    replace_first "$t" "prompts/backlog-loop.goal.md" \
        '1. The backlog-loop census proves that no legal agent-executable action remains: no issue sits in its loop-responsible set except an issue whose open linked PR REPORT lists as awaiting a required approval and whose issue is reported as awaiting a person, and no PR its RESIDUE PASS stripped is still `OPEN`. A human gate, a label defect, and a quarantined issue each wait on a person, sit outside that set, and do not block success.' \
        '1. The backlog-loop census proves that no legal agent-executable action remains: no issue sits in its loop-responsible set, and no PR its RESIDUE PASS stripped is still `OPEN`. A human gate, a label defect, and a quarantined issue each wait on a person, sit outside that set, and do not block success.'
    expect_fail "goal loses required-approval exception" "goal no longer states its first success condition" "$t"

    # -- Linked PR disposition, charging, key classes (CR21-CR24) -------------
    #
    # A loop that never closes a PR can only meet a closed one because a person
    # closed it. Reclaiming it rebuilds the rejected change, and the old reclaim
    # wiped the attempt count as well, so the cycle had no bound.

    closed_action='write `needs-person` and release the PR link: one command sets `blocked`, unsets the RUN and FORGE-LINK classes, keeps every DURABLE key, and records the PR URL in a note. This loop never closes a PR, so a person closed it and a person decides; reopening the issue gets a fresh build. Never reclaim'

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        "$closed_action" \
        'reclaim the issue and rebuild the work'
    expect_fail "the CLOSED-not-merged row reclaims instead of writing needs-person" \
        "CLOSED-not-merged row does not write .needs-person. and release the PR link" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CODEX" \
        "$closed_action" \
        'reclaim the issue and rebuild the work'
    expect_fail "the CLOSED-not-merged row reclaims, in the Codex copy alone" \
        "skills/codex/backlog-loop/SKILL.md: .*CLOSED-not-merged row does not write" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        "$closed_action" \
        "$closed_action"', or reclaim when no other PR is open'
    expect_fail "the CLOSED-not-merged row keeps its needs-person clause but adds a reclaim" \
        "CLOSED-not-merged row .*reclaim" "$t"

    t=$(fresh_tree)
    closed_row=$(line_of "$t" "$LOOP_MD_CLAUDE" '^| `CLOSED`, not merged | write' 'CLOSED-not-merged row') || return 1
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        "$closed_row
" \
        ''
    expect_fail "the CLOSED-not-merged row is deleted from the disposition table" \
        "LINKED PR DISPOSITION carries no CLOSED-not-merged row" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '`merge-requested`: the outcome is unknown, which is exactly what this phase exists to record. Query `backlog_loop_pr` and apply LINKED PR DISPOSITION to its state; `MERGED` is the common answer and means treat as `merged` above.' \
        '`merge-requested`: the outcome is unknown, which is exactly what this phase exists to record. Query `backlog_loop_pr`. `MERGED` -> treat as `merged` above. `CLOSED` without a merge -> reclaim.'
    expect_fail "a RECOVERY arm handles a closed PR inline with a reclaim" \
        "reclaims a closed PR inline" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| linked PR state | action | charged | result |' \
        '| PR state | action | charged | result |'
    expect_fail "the disposition table header changes shape and no row parses" \
        "the LINKED PR DISPOSITION table did not parse" "$t"

    # The ceiling is per issue and covers every cause. A `transient:pr-open`
    # exemption parks a conflicting or unapproved PR forever.

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'for any cause, `transient:pr-open` included -> rewrite' \
        'for a cause other than `transient:pr-open` -> rewrite'
    expect_fail "REOPEN PASS exempts transient:pr-open from the attempt ceiling" \
        "REOPEN PASS no longer applies the attempt ceiling to every cause" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CODEX" \
        'for any cause, `transient:pr-open` included -> rewrite' \
        'for a cause other than `transient:pr-open` -> rewrite'
    expect_fail "REOPEN PASS exempts transient:pr-open from the attempt ceiling, in the Codex copy alone" \
        "skills/codex/backlog-loop/SKILL.md: REOPEN PASS no longer applies the attempt ceiling" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'bounds one issue across its whole life for every cause, `transient:pr-open` included, and REOPEN PASS enforces it.' \
        'bounds one issue across its whole life for every cause except `transient:pr-open`, and REOPEN PASS enforces it.'
    expect_fail "CHARGING exempts transient:pr-open from the attempt ceiling" \
        "CHARGING no longer applies the attempt ceiling to every cause" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'RELEASE GUARD, before REOPEN PASS or PROBATION PASS reopens anything:' \
        'RELEASE NOTE, before REOPEN PASS or PROBATION PASS reopens anything:'
    expect_fail "R32 recovery guard 1 is removed" \
        "RELEASE GUARD is missing" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'is not reopened here; OPEN PR RESUME and LINKED PR DISPOSITION own it' \
        'is reopened here; OPEN PR RESUME and LINKED PR DISPOSITION own it'
    expect_fail "R32 recovery guard 2 is removed" \
        "RELEASE GUARD no longer leaves an issue with a recorded PR" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'A delay alone is never proof.' \
        'A delay is proof.'
    expect_fail "R32 recovery guard 3 is removed" \
        "RELEASE GUARD no longer requires proved teardown" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '--set-metadata backlog_loop_ceiling="consumed | <iso>"' \
        '--set-metadata backlog_loop_ceiling="<iso>"'
    expect_fail "R32 recovery guard 4 is removed" \
        "PROBATION PASS no longer consumes the ceiling record" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'and `--set-metadata backlog_loop_attempts_total=<t+1>` (CHARGING;' \
        '(CHARGING;'
    expect_fail "R32 recovery guard 5 is removed" \
        "a charged recipe no longer writes backlog_loop_attempts_total" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'ORDER AND REFRESH.' \
        'ORDER NOTE.'
    expect_fail "R32 recovery guard 6 is removed" \
        "CENSUS no longer re-classifies after REOPEN" "$t"

    # Reclaim keeps the DURABLE class. Losing `backlog_loop_quarantine` frees an
    # issue a gate repair held back, and losing the attempt count unbounds the
    # rebuild cycle.

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'plus unsetting the rest of the RUN class and the FORGE-LINK class (KEY CLASSES)' \
        'plus unsetting every other ledger key, including `backlog_loop_attempts`'
    expect_fail "reclaim returns to unsetting every other ledger key" \
        "reclaim no longer unsets exactly the RUN and FORGE-LINK classes" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CODEX" \
        'plus unsetting the rest of the RUN class and the FORGE-LINK class (KEY CLASSES)' \
        'plus unsetting every other ledger key, including `backlog_loop_attempts`'
    expect_fail "reclaim returns to unsetting every other ledger key, in the Codex copy alone" \
        "skills/codex/backlog-loop/SKILL.md: reclaim no longer unsets exactly the RUN and FORGE-LINK classes" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        ', returning the issue to `bd ready`. No DURABLE key is unset:' \
        ' and `--unset-metadata backlog_loop_attempts`, returning the issue to `bd ready`. No DURABLE key is unset:'
    expect_fail "reclaim names a DURABLE key to unset while keeping the class clause" \
        "reclaim names a DURABLE key" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'plus unsetting every other RUN-class and FORGE-LINK-class key (KEY CLASSES).' \
        'plus unsetting every other RUN-class and FORGE-LINK-class key (KEY CLASSES) and `--unset-metadata backlog_loop_quarantine`.'
    expect_fail "REOPEN PASS unsets a DURABLE key" \
        "REOPEN PASS unsets a DURABLE key" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'keeps every DURABLE key, and records the PR URL in a note' \
        'unsets every DURABLE key, and records the PR URL in a note'
    expect_fail "the human-close release stops keeping the DURABLE class" \
        "CLOSED-not-merged row does not write .needs-person. and release the PR link" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'plus unsetting the RUN and FORGE-LINK classes (KEY CLASSES) and the `backlog_loop_census=<census-run>` stamp' \
        'plus unsetting the RUN and FORGE-LINK classes (KEY CLASSES) and `--unset-metadata backlog_loop_attempts` and the `backlog_loop_census=<census-run>` stamp'
    expect_fail "RESIDUE PASS unsets a DURABLE key" \
        "RESIDUE PASS unsets a DURABLE key" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| DURABLE | `backlog_loop_attempts`, `backlog_loop_attempts_total`, `backlog_loop_ceiling`, `backlog_loop_triaged`, `backlog_loop_cause`,' \
        '| DURABLE | `backlog_loop_attempts_total`, `backlog_loop_ceiling`, `backlog_loop_triaged`, `backlog_loop_cause`,'
    expect_fail "the DURABLE class stops listing the attempt count" \
        "DURABLE row no longer lists .backlog_loop_attempts." "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| class | members | unset by |' \
        '| class | keys | unset by |'
    expect_fail "the KEY CLASSES table header changes shape and no row parses" \
        "the KEY CLASSES table did not parse" "$t"

    # A cause that is written must be declared and must have a REOPEN PASS
    # proof, or the issue it labels can be neither cleared nor escalated.

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '`transient:pr-open` (an open linked PR that LINKED PR DISPOSITION parks), `transient:gate-failed` (a required quality gate or test failed on code this loop authored, so the defect is agent-fixable; charged, and the note carries the failing command and its error), `transient:review-residual` (the reason begins `review residual:`; the review left only findings that change no behavior, contract, or permission and need no design decision, such as a documentation note or a stale comment, and none is a `settled_conflict`, a `needs-human` residual, or a repeat of an earlier one; charged, and the note lists every finding with `file:line`, title, and `suggested_fix`), `transient:tool-failure` (the reason begins `tool failure:`; a child skill or tool failed for a reason outside the code under change: a review return with `failed`, `degraded`, or `skipped` status or a malformed return, a child that crashed or timed out, a pipeline interrupted mid-run, or a teardown that could not be proved; charged, and the note names the tool and its exact error), `transient:decision-recorded` (the reason begins `decision recorded:`; `ce-plan` returned `blocked` on an open question, or the review left only a residual that needs a design decision, and the question is not one `## HUMAN GATES` reserves for a person and the residual is not a `settled_conflict`, a change to a contract, permission, or security stance, or a contradiction of a `user-approved` decision; the loop chose its recommended option, appended `<decision> | rejected: <alt> | reason: <why>` to the design field the way OWNER-DECISION ISSUES does, read the field back, and wrote the note as `decision recorded: <question> | design entry: <decision> | rejected: <alt> | reason: <why>`; charged, and no work failed), or `needs-person`' \
        '`transient:pr-open` (an open linked PR that LINKED PR DISPOSITION parks), `transient:review-wait`, or `needs-person`'
    expect_fail "step 7 writes a cause the ledger's cause row does not declare" \
        "cause .transient:review-wait. is not declared in THE RUN LEDGER" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CODEX" \
        '`transient:pr-open` (an open linked PR that LINKED PR DISPOSITION parks), `transient:gate-failed` (a required quality gate or test failed on code this loop authored, so the defect is agent-fixable; charged, and the note carries the failing command and its error), `transient:review-residual` (the reason begins `review residual:`; the review left only findings that change no behavior, contract, or permission and need no design decision, such as a documentation note or a stale comment, and none is a `settled_conflict`, a `needs-human` residual, or a repeat of an earlier one; charged, and the note lists every finding with `file:line`, title, and `suggested_fix`), `transient:tool-failure` (the reason begins `tool failure:`; a child skill or tool failed for a reason outside the code under change: a review return with `failed`, `degraded`, or `skipped` status or a malformed return, a child that crashed or timed out, a pipeline interrupted mid-run, or a teardown that could not be proved; charged, and the note names the tool and its exact error), `transient:decision-recorded` (the reason begins `decision recorded:`; `ce-plan` returned `blocked` on an open question, or the review left only a residual that needs a design decision, and the question is not one `## HUMAN GATES` reserves for a person and the residual is not a `settled_conflict`, a change to a contract, permission, or security stance, or a contradiction of a `user-approved` decision; the loop chose its recommended option, appended `<decision> | rejected: <alt> | reason: <why>` to the design field the way OWNER-DECISION ISSUES does, read the field back, and wrote the note as `decision recorded: <question> | design entry: <decision> | rejected: <alt> | reason: <why>`; charged, and no work failed), or `needs-person`' \
        '`transient:pr-open` (an open linked PR that LINKED PR DISPOSITION parks), `transient:review-wait`, or `needs-person`'
    expect_fail "step 7 writes an undeclared cause, in the Codex copy alone" \
        "skills/codex/backlog-loop/SKILL.md: cause .transient:review-wait. is not declared" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'The legacy `transient:merge-precondition` is gone when' \
        'The legacy cause is gone when'
    expect_fail "a declared cause has no REOPEN PASS proof" \
        "REOPEN PASS carries no proof for cause .transient:merge-precondition." "$t"

    # -- R25: a parked PR is adopted by one status-guarded write -------------
    #
    # Without `--if-status blocked` two invocations can both move the parked
    # issue to `in_progress` and both merge-request the same PR.

    both_hosts "the adoption write loses its --if-status guard" \
        'bd update <id> --if-status blocked --status=in_progress --assignee <actor>' \
        'bd update <id> --status=in_progress --assignee <actor>' \
        "no ADOPTION write carries the --if-status blocked guard .breaks R25"

    both_hosts "the adoption write is split into a claim" \
        'bd update <id> --if-status blocked --status=in_progress --assignee <actor>' \
        'bd update <id> --claim --if-status blocked --assignee <actor>' \
        "no ADOPTION write carries the --if-status blocked guard .breaks R25"

    both_hosts "a nonzero adoption exit with an unchanged read-back stops meaning skip" \
        'Any nonzero exit with an unchanged read-back means another invocation adopted it first: skip the issue and write nothing.' \
        'Exit 13 means another invocation adopted it first: skip the issue and write nothing.' \
        "ADOPTION no longer says any nonzero exit with an unchanged read-back means skip"

    both_hosts "the adoption read-back is dropped" \
        'Read the issue back and require status `in_progress`, assignee `<actor>`, and `backlog_loop_run=<run-id>`.' \
        'The write is trusted.' \
        "ADOPTION no longer reads the issue back"

    both_hosts "an in_progress member under a dead run is adopted in place" \
        'A member still `in_progress` under a dead run (RECOVERY) is parked first, never adopted in place:' \
        'A member still `in_progress` under a dead run (RECOVERY) is re-stamped in place:' \
        "ADOPTION no longer parks an .in_progress. member of a dead run first"

    both_hosts "the disposition table's adopt row stops naming ADOPTION" \
        'adopt the issue through ADOPTION'"'"'s guarded write; rerun' \
        'adopt the issue: move it from `blocked` to `in_progress` in one write; rerun' \
        "the adopt row of LINKED PR DISPOSITION no longer adopts through ADOPTION"

    both_hosts "OPEN PR RESUME stops adopting through ADOPTION" \
        'adopt every member through ADOPTION first, so no other invocation can take the PR while its gates run' \
        'set each member in_progress once its gates pass' \
        "OPEN PR RESUME no longer adopts through ADOPTION before its gates"

    # The R8 carve-out: in_progress is a literal status flag in the adoption
    # write only.

    both_hosts "an in_progress status flag is written outside the adoption write" \
        'and `status` is not `blocked`, `hooked`, `pinned` or `deferred` |' \
        'and `status` is not `blocked`, `hooked`, `pinned` or `deferred`; run `bd update <id> --status=in_progress` |' \
        "writes .--status=in_progress. 2 time.s. but the anchored adoption write appears 1 time"

    # -- R26: a member that is not running never reads as live ----------------

    both_hosts "step 6's park write keeps the heartbeat" \
        '`bd update <id> --status=blocked --unset-metadata backlog_loop_heartbeat --append-notes="merge blocked;' \
        '`bd update <id> --status=blocked --append-notes="merge blocked;' \
        "a literal --status=blocked write does not unset .backlog_loop_heartbeat. in the same command .breaks R26"

    both_hosts "step 7's blocked write keeps the heartbeat" \
        '`bd update <id> --status=blocked --unset-metadata backlog_loop_heartbeat --append-notes="pipeline blocked:' \
        '`bd update <id> --status=blocked --append-notes="pipeline blocked:' \
        "a literal --status=blocked write does not unset .backlog_loop_heartbeat. in the same command .breaks R26"

    both_hosts "the adoption park-first write keeps the heartbeat" \
        '`bd update <id> --if-status in_progress --status=blocked --unset-metadata backlog_loop_heartbeat --set-metadata backlog_loop_cause=transient:pr-open`' \
        '`bd update <id> --if-status in_progress --status=blocked --set-metadata backlog_loop_cause=transient:pr-open`' \
        "a literal --status=blocked write does not unset .backlog_loop_heartbeat. in the same command .breaks R26"

    both_hosts "the rule that every blocked write unsets the heartbeat is deleted" \
        'Every write that sets `blocked`, in the table above or anywhere below, carries `--unset-metadata backlog_loop_heartbeat` in that same command.' \
        'A write that sets `blocked` may keep the heartbeat.' \
        "no longer says every write that sets .blocked. unsets the heartbeat"

    both_hosts "the verified write before the close keeps the heartbeat" \
        '--set-metadata backlog_loop_phase=verified --unset-metadata backlog_loop_heartbeat`' \
        '--set-metadata backlog_loop_phase=verified`' \
        "the step 7 write that records .verified. no longer unsets the heartbeat"

    both_hosts "LIVENESS stops treating a released or stale heartbeat as dead" \
        '`released`, a stale `live`, and an absent heartbeat are dead unless such a process exists.' \
        'A `released` heartbeat is read like any other.' \
        "LIVENESS no longer treats a .released. heartbeat, a stale .live. one, and an absent one as dead"

    both_hosts "the ledger row stops documenting the released suffix" \
        '`<iso> | released` once it lets go at exit' \
        'a timestamp once it lets go at exit' \
        "the .backlog_loop_heartbeat. ledger row no longer documents both suffix values"

    both_hosts "the heartbeat refresher loses its 10-minute cadence and lease renewal" \
        'Every 10 minutes it refreshes every `in_progress` issue carrying `backlog_loop_run=<run-id>`: it writes `backlog_loop_heartbeat="<iso> | live"` and runs `bd heartbeat <id>`' \
        'At each step boundary it writes `backlog_loop_heartbeat="<iso> | live"`' \
        "HEARTBEAT REFRESHER no longer refreshes every 10 minutes"

    both_hosts "the heartbeat refresher loses its lifetime bound" \
        'so its lifetime is bounded another way: 36 ticks (6 hours), and it stops at the first `<refresh>` that fails or that finds no `in_progress` issue carrying `backlog_loop_run=<run-id>`.' \
        'so it runs until I8 REAP ends it.' \
        "HEARTBEAT REFRESHER no longer bounds its own lifetime"

    both_hosts "LIVENESS counts a refresher as proof of a live run" \
        'A process that also carries `BACKLOG_LOOP_ROLE=refresher` is a refresher, and a refresher alone does not prove a live run: it outlives a dead run by up to 6 hours.' \
        'A process that also carries `BACKLOG_LOOP_ROLE=refresher` is a refresher.' \
        "LIVENESS no longer says a refresher alone does not prove a live run"

    both_hosts "FINAL REPORT stops releasing the members still held" \
        'write `backlog_loop_heartbeat="<iso> | released"` on every member this run still holds `in_progress`' \
        'leave the heartbeat on every member this run still holds `in_progress`' \
        "FINAL REPORT no longer writes a .released. heartbeat"

    both_hosts "the census WRITE GATE counts a heartbeat with no run beside it" \
        'a `live` `backlog_loop_heartbeat` under 30 minutes old on an issue whose `backlog_loop_run` is present and is not `<run-id>`' \
        'a `backlog_loop_heartbeat` under 30 minutes old on an issue whose `backlog_loop_run` is not `<run-id>`' \
        "the WRITE GATE no longer counts a heartbeat only when a different .backlog_loop_run. is present"

    # -- R18 and R27: preflight probes and post-merge verification ----------

    both_hosts "the 30-minute timeout stops running the exact-merge local gate" \
        'An entry still pending at that deadline stops waiting: run the applicable local quality gate set once through CLEAN-TREE GATE RUN at `<merge-sha>`, in a clean worktree, and write the entry `timeout-local-green` when it is green or `failed` when it is red, so the gate never runs twice for one entry' \
        'An entry still pending at that deadline stays pending until its workflows finish' \
        "post-merge CI pending past 30 minutes no longer runs the exact-merge local gate once"

    both_hosts "a green timeout gate stops closing the members and a red one stops entering TRUNK REPAIR" \
        'Green closes the members with the `timeout-local-green` receipt in the close reason; red enters TRUNK REPAIR with the gate'"'"'s evidence.' \
        'Both results keep the members in_progress.' \
        "the timeout gate no longer closes on green with a .timeout-local-green. receipt and enters TRUNK REPAIR on red"

    both_hosts "the verified write stops carrying the timeout-local-green value" \
        'A local-gate timeout writes `timeout-local-green` in place of `passed` in that same command.' \
        'A local-gate timeout writes nothing further.' \
        "the step 7 write no longer records .timeout-local-green. in place of .passed. after a local-gate timeout"

    both_hosts "expected workflows stop being computed from event and path filters" \
        'Expected workflows are computed from event and path filters at `<merge-sha>`: a workflow whose `push` trigger admits `<default>` and whose path filters match a file the merge commit changed, and any workflow whose filters cannot be decided.' \
        'Every workflow in the repository is expected.' \
        "step 7 no longer computes the expected workflows from event and path filters at the merge SHA"

    both_hosts "RECOVERY stops running the local gate after the 30 minutes" \
        'until 30 minutes have passed from the original first-seen time; then run step 7'"'"'s exact-merge local gate once.' \
        'until the expected run appears.' \
        "the RECOVERY .merged. arm no longer runs step 7's exact-merge local gate once after 30 minutes"

    both_hosts "trunk CI pending on an unmerged SHA is recorded on a batch that does not exist" \
        'Runs pending on a SHA this loop did not merge have no batch to record on: record nothing on any member, mark the exact-SHA LOCAL TRUNK GATE pending, and run it after CLAIM; do not treat pending CI as green.' \
        'Runs pending on a SHA this loop did not merge are recorded on the next batch.' \
        "trunk CI pending on a SHA this loop did not merge no longer marks the LOCAL TRUNK GATE pending"

    both_hosts "the post-merge queue recheck stops running every iteration on either route" \
        'POST-MERGE QUEUE RECHECK, every iteration and every invocation, on either route:' \
        'POST-MERGE QUEUE RECHECK, only while trunk CI is on:' \
        "the post-merge queue recheck no longer runs every iteration on either route"

    both_hosts "the post-merge queue enumeration passes --all again" \
        'never pass `--all`' \
        'pass `--all`' \
        "the post-merge queue enumeration no longer says never to pass .--all."

    both_hosts "a slow optional check rewrites the route to off in step 8" \
        'keep `backlog_loop_ci` as step 6 recorded it, because a slow optional check is not an absent producer, and advance to merge.' \
        'record `backlog_loop_ci=off` if no check has completed, and advance to merge.' \
        "step 8 no longer keeps the batch CI route when an optional check is slow"

    both_hosts "the disposition row rewrites the route to off for a pending optional check" \
        'keep the route `on` and post-merge CI expected, and write `backlog_loop_ci=off` only on proven absence of every producer (pipeline step 6), never because an optional check is slow' \
        'write `backlog_loop_ci=off` only when no check has completed' \
        "the pending-optional-check row no longer keeps the route .on. and writes .off. only on proven absence"

    both_hosts "preflight keeps the route on for a required check with no producer" \
        'A required check that no default-branch workflow can produce for a pull request stops the run at preflight on either CI route, naming the check:' \
        'If it has no known PR producer, keep the route `on` through step 8.' \
        "preflight no longer stops on a required check with no producer on either CI route, naming the check"

    both_hosts "the no-producer stop loses its uncertain-producer exemption" \
        'an undecidable enabled state, or a check pinned to a non-Actions app is an uncertain producer and never stops the run.' \
        'an undecidable enabled state is a producer that does not exist.' \
        "the no-producer stop no longer leaves an uncertain producer alone"

    both_hosts "preflight stops reading the approval requirement from both sources" \
        'from the flattened rules response read every `pull_request` rule'"'"'s `required_approving_review_count` and `require_code_owner_review`' \
        'from the flattened rules response read nothing' \
        "preflight no longer reads the required approving review count from both branch protection and pull_request rulesets"

    both_hosts "preflight stops naming the approval requirement before the first claim" \
        'Name it before the first claim as `approval required: <n> review(s) (<protection|ruleset>)`, or `approval required: none`.' \
        'Name it in the final report.' \
        "preflight no longer names the approval requirement before the first claim"

    both_hosts "the awaiting-approval row stops staying loop-responsible and listed" \
        'wait for the required approval and never approve; list the PR in REPORT as awaiting a required approval and its issue as awaiting a person, without holding back the clear verdict' \
        'park the PR as needs-person' \
        "the .REVIEW_REQUIRED. row no longer waits and reports the required approval without holding back the clear verdict"

    both_hosts "waiting on a required approval starts being charged" \
        'waiting on a required approval, an interruption park in RECOVERY' \
        'an interruption park in RECOVERY' \
        "CHARGING no longer lists waiting on a required approval as never charged"

    both_hosts "FINAL REPORT stops listing PRs awaiting a required approval" \
        'List every PR awaiting a required approval and every PR LINKED PR DISPOSITION sent to `needs-person`' \
        'List every PR LINKED PR DISPOSITION sent to `needs-person`' \
        "FINAL REPORT no longer lists every PR awaiting a required approval"

    both_hosts "STOP EARLY stops naming a no-producer required check as a global blocker" \
        'a required status check has no producer on either CI route;' \
        'a required status check is pending;' \
        "STOP EARLY no longer names a required check with no producer as a global terminal blocker"

    # -- R28: the remaining loop fixes ---------------------------------------

    both_hosts "the census bd ready loses --limit 0" \
        '`bd ready --explain --json --limit 0` is the AUTHORITY for the dependency question' \
        '`bd ready --explain --json` is the AUTHORITY for the dependency question' \
        "a .bd ready. call carries no .--limit 0."

    both_hosts "the GROW bd ready loses --limit 0" \
        '`bd ready --parent <epic-id> --json --limit 0 --exclude-type=epic`' \
        '`bd ready --parent <epic-id> --json --exclude-type=epic`' \
        "a .bd ready. call carries no .--limit 0."

    both_hosts "the preflight probe drops to a bare bd ready" \
        '`bd prime` and `bd ready --json --limit 0` must both work.' \
        '`bd prime` and `bd ready` must both work.' \
        "preflight no longer probes .bd ready --json --limit 0."

    both_hosts "STATE stops stating that every bd ready call carries --limit 0" \
        'Every `bd ready` call carries `--limit 0`: without it the tracker returns at most 100 rows, so a larger backlog reads as a smaller one.' \
        'Every `bd ready` call is cheap.' \
        "STATE no longer says every .bd ready. call carries .--limit 0."

    both_hosts "the census stops counting the rows of bd ready --explain" \
        'Count its rows: the `ready` and `blocked` arrays must hold `summary.total_ready` and `summary.total_blocked` rows' \
        'Trust its rows: the `ready` and `blocked` arrays are complete' \
        "CENSUS no longer counts the rows of .bd ready --explain --json --limit 0."

    both_hosts "the browser test runs from the invoking tree" \
        'run the browser test with its working directory in `<clean-tree>` at that commit, bootstrapped as CLEAN-TREE GATE RUN requires, and on an explicit port:' \
        'run the browser test from the working tree:' \
        "pipeline step 5 no longer runs the browser test with its working directory in .<clean-tree>."

    both_hosts "a batch with no browser-affected paths stops passing as N/A" \
        'the browser gate is `N/A: no browser-affected paths`' \
        'the browser gate is always required' \
        "pipeline step 5 no longer passes a batch with no browser-affected paths as N/A"

    both_hosts "a browser-affected batch whose server cannot start is waved through" \
        'a server that cannot start is a required gate that cannot execute, which is a stop under the terminal blockers, never an N/A' \
        'a server that cannot start is an N/A' \
        "pipeline step 5 no longer stops a browser-affected batch whose server cannot start"

    both_hosts "the browser test loses its explicit port" \
        'invoke `compound-engineering:ce-test-browser mode:pipeline --port <browser-port>` from that directory' \
        'invoke `compound-engineering:ce-test-browser mode:pipeline` from that directory' \
        "pipeline step 5 no longer invokes ce-test-browser on the explicit .<browser-port>."

    both_hosts "REAP stops stopping the browser server by port" \
        'For every port in `<owned-ports>`, list its listeners with `lsof -i :<port> -sTCP:LISTEN -t`, take each listener'"'"'s process group, and treat that group exactly like a `<pgid>` above:' \
        'Leave every port in `<owned-ports>` alone:' \
        "REAP no longer stops the browser server by port"

    both_hosts "the branch stops being written before pipeline step 4" \
        'Then write `backlog_loop_branch` on every member BEFORE step 4:' \
        'Then write `backlog_loop_branch` on every member at step 6:' \
        "pipeline step 3 no longer writes .backlog_loop_branch. before step 4"

    both_hosts "the ledger row writes the branch at step 6 again" \
        'pipeline step 3, the moment `ce-work` returns and before step 4 commits anything' \
        'pipeline step 6' \
        "the .backlog_loop_branch. ledger row no longer says it is written at pipeline step 3"

    both_hosts "step 6 writes the branch a second time" \
        'write `backlog_loop_head` and `backlog_loop_phase=built` for every member; `backlog_loop_branch` already holds the branch from step 3.' \
        'write `backlog_loop_branch`, `backlog_loop_head`, and `backlog_loop_phase=built` for every member.' \
        "pipeline step 6 writes .backlog_loop_branch. again"

    both_hosts "the apply stage pushes before the PR exists" \
        'Commit each applied fix locally without pushing:' \
        'Push each applied fix to the branch:' \
        "pipeline step 4 no longer commits applied fixes without pushing"

    both_hosts "BACKLOG_LOOP_RUN is exported only into commands the loop launches" \
        'Export `BACKLOG_LOOP_RUN=<run-id>` into the host session environment right after choosing `<run-id>` and before any child skill runs,' \
        'Export `BACKLOG_LOOP_RUN=<run-id>` into every such command' \
        "process hygiene no longer exports .BACKLOG_LOOP_RUN. into the host session environment before any child skill runs"

    both_hosts "the child brief stops restating the hygiene rules" \
        'Every child brief restates the hygiene rules in one sentence: run every gate, test, build, or app command non-interactively (`CI=1`, watch and UI modes off), never leave a watcher, dev server, or REPL alive past the command that needed it, and never signal a process you did not start.' \
        'Children know the hygiene rules.' \
        "process hygiene no longer says every child brief restates the hygiene rules"

    both_hosts "the step 5 brief stops carrying the hygiene sentence" \
        'End the brief, and the brief of every later child invocation, with the hygiene sentence from PREFLIGHT'"'"'s process-hygiene item.' \
        'Children read the hygiene rules themselves.' \
        "pipeline step 5 no longer ends every child brief with the hygiene sentence"

    both_hosts "macOS stops naming gtimeout" \
        '`timeout` is `gtimeout` from Homebrew coreutils on macOS;' \
        '`timeout` is optional;' \
        "process hygiene no longer names .gtimeout. for macOS"

    both_hosts "the gate timeout stops following the repository docs" \
        'which is 20m unless the repository'"'"'s CLAUDE.md, AGENTS.md, CONTRIBUTING.md, or README states a gate timeout,' \
        'which is always 20m,' \
        "process hygiene no longer takes .<gate-timeout>. from the repository docs when they state one"

    both_hosts "OPEN PR RESUME resumes in the invoking tree" \
        'Every `ce-babysit-pr`, `ce-resolve-pr-feedback`, and `ce-debug` round on a resumed PR runs with the PR branch checked out in a run-owned worktree and never in the invoking tree:' \
        'Every `ce-babysit-pr`, `ce-resolve-pr-feedback`, and `ce-debug` round on a resumed PR runs in the invoking tree:' \
        "OPEN PR RESUME no longer runs babysit, resolve, and debug in a run-owned worktree"

    both_hosts "OPEN PR RESUME loses the PR worktree command" \
        'git worktree add <worktree-root>/pr-<number> <branch>' \
        'git checkout <branch>' \
        "OPEN PR RESUME no longer creates the PR worktree under .<worktree-root>."

    both_hosts "the post-merge queue scan stops skipping closed rows" \
        'and skip any row whose `status` is `closed` without a `bd show`.' \
        'and read every row with a `bd show`.' \
        "the post-merge queue scan no longer skips closed members"

    both_hosts "the diagnostic run stops reporting proofs it cannot run" \
        'is reported as `would evaluate: <proof>`, for example' \
        'is reported as proven, for example' \
        "DIAGNOSTIC RUN no longer reports a proof it cannot run as .would evaluate"

    both_hosts "auto-resolving gates count as human gates" \
        'Only `label` and `native` gates count as human gates, because only they wait on a person.' \
        'Every gate counts as a human gate.' \
        "CENSUS no longer counts only .label. and .native. gates as human gates"

    both_hosts "auto-resolving gates stop being reported as such" \
        'An `auto-resolving:<await_type>` gate resolves itself on its timer, run, PR, or bead:' \
        'An `auto-resolving:<await_type>` gate waits on a person:' \
        "CENSUS no longer reports a non-human gate as auto-resolving"

    both_hosts "OWNER-DECISION writes the design field as a shell argument" \
        'run `bd update <id> --design-file <file>`. Read the field back and require the original text as an exact substring and the appended line in full;' \
        'run `bd update <id> --design "<text>"`.' \
        "OWNER-DECISION no longer writes the design field with .--design-file. and a read-back"

    both_hosts "the final REAP stops deleting the worktree root" \
        'delete `<worktree-root>` with `rmdir`' \
        'leave `<worktree-root>` in place' \
        "the final REAP no longer deletes .<worktree-root>."

    both_hosts "FINAL REPORT stops listing closed issues whose PR is still open" \
        'List every closed issue whose PR is still `OPEN` on the forge:' \
        'List every closed issue:' \
        "FINAL REPORT no longer lists closed issues whose PR is still .OPEN."

    both_hosts "the enumeration claim about bd list returns to an absolute" \
        'Whether `bd list --json` carries a `metadata` object or a `dependencies` array depends on the `bd` version' \
        '`bd list --json` returns neither a `metadata` object nor a `dependencies` array; it carries' \
        "CENSUS no longer states the .bd list --json. shape as version-dependent"

    # -- R29, R30, R31: a worktree-safe loop (U8) -----------------------------

    both_hosts "BASE restores a switch to the default branch and a fast-forward" \
        "Repeat step 1's trunk update." \
        'Repeat the update: `git switch <default>` and `git merge --ff-only <remote>/<default>`.' \
        "the skill restores .git switch <default>. or a fast-forward"

    both_hosts "preflight stops recording the invoking worktree" \
        'record `<invoking-worktree>`, the output of `git rev-parse --show-toplevel`, and whether it is linked: `git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`.' \
        'note the working directory.' \
        "preflight no longer records .<invoking-worktree>. and whether it is linked"

    both_hosts "a default branch checked out elsewhere becomes a stop" \
        'The default branch checked out in another worktree is the normal state of a linked worktree and is never a stop.' \
        'is a stop.' \
        "preflight no longer says a default branch checked out in another worktree is never a stop"

    both_hosts "the invoking worktree may be switched again" \
        'Never switch, fast-forward, reset, commit to, stash, or clean `<invoking-worktree>`: every branch operation of this loop runs in a run-owned worktree under `<worktree-root>`, which starts clean at an exact commit, so no uncommitted work enters a batch and no checked-out branch moves.' \
        'Tidy `<invoking-worktree>` as needed.' \
        "preflight no longer forbids switching, fast-forwarding, resetting, committing to, stashing, or cleaning .<invoking-worktree>."

    both_hosts "tracked .beads files stop being excluded paths" \
        'Save every tracked path under `.beads/` (`git ls-files .beads`) as `<excluded-paths>`:' \
        'Save nothing as `<excluded-paths>`:' \
        "preflight no longer saves every tracked .\.beads/. path as .<excluded-paths>."

    both_hosts "tracker churn may be committed" \
        'and that tracker churn is never staged, committed, or cleaned by this loop.' \
        'and that tracker churn rides along with the batch.' \
        "preflight no longer says tracker churn is never staged, committed, or cleaned"

    both_hosts "step 1 stops leaving the invoking worktree alone" \
        'Update trunk without touching `<invoking-worktree>`: `git fetch <remote> --prune`, then create or move `<trunk-tree>` as CLEAN-TREE GATE RUN defines, requiring exit 0 from each command.' \
        'Update trunk in place.' \
        "step 1 no longer updates trunk in .<trunk-tree>. without touching .<invoking-worktree>."

    both_hosts "step 1 stops forbidding a switch or fast-forward of the invoking worktree" \
        'Never switch the invoking worktree to `<default>`, fast-forward it, reset it, or use a tree-wide checkout: a linked worktree cannot check out a default branch that another worktree holds, and a fast-forward there would move the branch the operator has checked out.' \
        'Keep trunk current.' \
        "step 1 no longer forbids switching, fast-forwarding, or resetting the invoking worktree"

    both_hosts "step 1 stops comparing refs for local commits ahead of the remote" \
        'Compare refs for local commits the remote lacks: `git rev-list --count <remote>/<default>..refs/heads/<default>`, skipped when no local `<default>` ref exists.' \
        'Compare the working tree with the remote.' \
        "step 1 no longer compares refs for local commits the remote lacks"

    both_hosts "the trunk worktree stops being detached" \
        'creates it with `git worktree add --detach <trunk-tree> <remote>/<default>` when it is absent and otherwise moves it with `git -C <trunk-tree> switch --detach <remote>/<default>`.' \
        'creates it with `git worktree add <trunk-tree> <default>`.' \
        "CLEAN-TREE GATE RUN no longer creates and moves .<trunk-tree>. detached at .<remote>/<default>."

    both_hosts "children run in the invoking worktree again" \
        'ITERATION steps 3 through 7 run every child skill with `<trunk-tree>` as the working directory, never `<invoking-worktree>`.' \
        'ITERATION steps 3 through 7 run every child skill in the current directory.' \
        "CLEAN-TREE GATE RUN no longer runs every child skill of ITERATION steps 3 through 7 in .<trunk-tree>."

    both_hosts "a PR branch held elsewhere is reported instead of added detached" \
        'so add the tree detached instead: `git worktree add --detach <worktree-root>/pr-<number> <remote>/<branch>`.' \
        'so report the holder.' \
        "OPEN PR RESUME no longer adds a branch checked out elsewhere as a detached tree"

    both_hosts "a detached PR tree is pushed with a bare git push" \
        'tell the child to push with `git push <remote> HEAD:refs/heads/<branch>` and never with a bare `git push`.' \
        'tell the child to push.' \
        "OPEN PR RESUME no longer pushes a detached tree with an explicit refspec"

    both_hosts "an impossible push stops going to needs-person" \
        'the issue goes to `needs-person` naming the holder and the refusal.' \
        'the issue is retried.' \
        "OPEN PR RESUME no longer sends an impossible push to .needs-person."

    both_hosts "only the clean tree is bootstrapped" \
        'inside every run-owned worktree a child skill or gate runs in -- `<trunk-tree>`, `pr-<number>`, and `<clean-tree>` -- before the first one runs there, preferring its frozen/locked form.' \
        'inside `<clean-tree>` first, preferring its frozen/locked form.' \
        "CLEAN-TREE GATE RUN no longer bootstraps every run-owned worktree before a child or gate runs there"

    both_hosts "the merge command passes --delete-branch again" \
        'Then run `gh pr merge <url> --squash --match-head-commit <batch-head-sha>`, exactly one merge per batch.' \
        'Then run `gh pr merge <url> --squash --delete-branch --match-head-commit <batch-head-sha>`, exactly one merge per batch.' \
        "step 6 passes .--delete-branch. to .gh pr merge."

    both_hosts "step 6 stops warning against --delete-branch" \
        'never `--delete-branch`: its local cleanup switches the checkout to `<default>` and deletes the local head branch, which a worktree that holds either one refuses, and the refusal can leave the remote branch undeleted.' \
        'pass nothing else.' \
        "step 6 no longer says never .--delete-branch."

    both_hosts "step 6 stops deleting the remote head branch" \
        'Then delete the remote head branch with `gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/<branch>`: a missing reference means GitHub already deleted it, any other failure is reported, and the proven merge stands either way.' \
        'The branch stays on the forge.' \
        "step 6 no longer deletes the remote head branch through the API"

    both_append "a repository-wide worktree prune is added" \
        'When a worktree is stale, run `git worktree prune`.' \
        'instructs .git worktree prune.'

    both_hosts "the worktree-root rule stops forbidding a repository-wide prune" \
        'Only a path under it is ever removed, with `git worktree remove --force <path>`, which also clears a registration whose directory is already gone; nothing here prunes repository-wide, because a prune also drops the registration of any worktree of the operator whose directory is temporarily missing.' \
        'Stale registrations are cleaned up afterwards.' \
        "CLEAN-TREE GATE RUN no longer says only a path under .<worktree-root>. is removed and nothing prunes repository-wide"

    both_hosts "the clean-tree teardown stops clearing a missing registration" \
        'and run `git worktree remove --force <clean-tree>`, which also clears the registration of a tree whose directory is already gone.' \
        'and run `git worktree remove --force <clean-tree>`.' \
        "the clean-tree teardown no longer relies on .git worktree remove --force. to clear a registration whose directory is gone"

    both_hosts "dead-run recovery stops removing instead of pruning" \
        'remove every worktree registered under `backlog_loop_worktrees` with `git worktree remove --force <path>`, which also clears a registration whose directory is already gone, then delete the emptied directory with `rmdir`; never prune repository-wide,' \
        'remove `backlog_loop_worktrees` outright,' \
        "RECOVERY no longer removes the dead run's worktrees one by one under .backlog_loop_worktrees."

    both_hosts "the worktree root stops being outside every worktree" \
        'lies outside every worktree of this repository: its path is neither inside nor above any path `git worktree list --porcelain` names, and not inside `git rev-parse --git-common-dir`.' \
        'lies outside this repository.' \
        "CLEAN-TREE GATE RUN no longer requires .<worktree-root>. outside every worktree of the repository"

    both_hosts "REAP removes registered worktrees without the root scope" \
        'with `git worktree remove --force <path>`, and only for a path under `<worktree-root>` that `git worktree list --porcelain` registers; a worktree outside `<worktree-root>` is never removed, whoever created it,' \
        'for every worktree that `git worktree list` shows,' \
        "REAP no longer removes only registered paths under .<worktree-root>."

    both_hosts "REAP stops deleting the local head branch of a merged batch" \
        'delete its local head branch with `git branch -D <backlog_loop_branch>`' \
        'leave its local head branch in place' \
        "REAP no longer deletes the local head branch of a merged batch"

    both_hosts "REAP stops clearing a registration whose directory is gone" \
        'A registration whose directory is already gone is cleared by that same command, so REAP never prunes repository-wide.' \
        'REAP leaves such a registration for the operator.' \
        "REAP no longer clears a registration whose directory is already gone with the same removal"

    # -- The Codex copy is read too -----------------------------------------
    #
    # Same break as the first case, applied to the other host only. A checker
    # that read one copy would report this tree clean, and every operator on
    # that host would run the wedged procedure.

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CODEX" \
        '- Absent, or any value the `backlog_loop_phase` row above does not list:' \
        '- Never reached, kept for history:'
    expect_fail "the RECOVERY default arm is deleted from the Codex copy alone" \
        "skills/codex/backlog-loop/SKILL.md: RECOVERY carries no arm" "$t"

    # -- VACUITY: an extraction broken rather than a rule --------------------

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| # | category | test |' \
        '| # | category | test-name |'
    expect_fail "the CLASSIFY table header changes shape and no row parses" \
        "the CLASSIFY table did not parse" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        'RECOVERY, by the recorded phase.' \
        'RECOVERY BY PHASE.'
    expect_fail "the RECOVERY opener changes shape and no arm parses" \
        "extracted no '- ' arm" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| category | `<cause>` |' \
        '| category | `cause` |'
    expect_fail "the EMIT <cause> table header changes shape and no row parses" \
        "the EMIT <cause> table did not parse" "$t"

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" \
        '| key | written at | value |' \
        '| key | written-at | value |'
    expect_fail "THE RUN LEDGER's key table header changes shape and no row parses" \
        'backlog_loop_phase. row declares no phase value' "$t"

    # -- REFERENCES: scan-type rules read references/*.md, anchors do not ----

    both_reference_lines "a --status=deferred write is planted in references/rationale.md" \
        'Park it with `bd update <id> --status=deferred` and move on.' \
        'writes .--status=deferred., which is outside'

    both_reference_lines "a bd defer is planted in references/rationale.md" \
        'Park it with `bd defer <id>`.' \
        'line [0-9]+ runs .bd defer.'

    both_reference_lines "a gh pr close is planted in references/rationale.md" \
        'Run `gh pr close <url>` after a review timeout.' \
        'backlog-loop may close a PR automatically'

    both_reference_lines "a git worktree prune is planted in references/rationale.md" \
        'Then run `git worktree prune` to clear the registrations.' \
        'instructs .git worktree prune.'

    both_reference_lines "a bd ready call without --limit 0 is planted in references/rationale.md" \
        'Read the queue with `bd ready --json`.' \
        'a .bd ready. call carries no .--limit 0.'

    # An anchor moved out of SKILL.md into references/ is gone for the checker:
    # the anchor-type checks read SKILL.md only, so the move fails loudly.
    for host in claude codex; do
        t=$(fresh_tree)
        replace_first "$t" "skills/$host/backlog-loop/SKILL.md" \
            'Never close a PR automatically.' \
            'A PR may be closed when it is stale.'
        plant_reference "$t" "$host" 'Never close a PR automatically.'
        expect_fail "an anchor sentence moves from SKILL.md into references/ (skills/$host)" \
            "skills/$host/backlog-loop/SKILL.md: open-PR preservation rule is missing" "$t"
    done

    both_hosts "the DEADLINE definition is deleted" \
        'A DEADLINE is a wrapper exit status of 124 or 137 whose elapsed time is at or above `<gate-timeout>` minus 5 seconds; any other non-zero status is the command'"'"'s own failure.' \
        'A DEADLINE is a timeout.' \
        'residual contract missing: gate deadline definition'

    both_hosts "the DEADLINE second-hit rule drifts to gate-failed" \
        'A second DEADLINE, or a first one when `<gate-timeout>` already equals `<gate-timeout-cap>`, ends the gate as `transient:tool-failure` with the reason `tool failure: gate deadline`, and the note carries the command, both deadlines, and the observed elapsed time. A DEADLINE is never `transient:gate-failed`.' \
        'A second DEADLINE ends the gate as `transient:gate-failed`.' \
        'residual contract missing: gate deadline rerun'

    both_hosts "the I7 DEADLINE class sentence is deleted" \
        'A gate that ended in a DEADLINE is never `transient:gate-failed`: CLEAN-TREE GATE RUN reruns it once and, on a second DEADLINE, writes `transient:tool-failure` with the reason `tool failure: gate deadline`.' \
        'A gate may time out.' \
        'residual contract missing: gate deadline class'

    both_hosts "the reclaim force clause is removed" \
        'Never pass `--force`, `--any-replica`, or `--older-than`, and never write `bd update --assignee` on this path: a lease granted by another replica is skipped by the tracker, and a claim with no lease is not reclaimed.' \
        'Pass `--force` when needed.' \
        'residual contract missing: external lease pass'

    both_hosts "the open PR guard of EXTERNAL LEASE PASS is removed" \
        'skip it and report it as `held` when an open PR names the issue in its title, body, or head branch; otherwise run `bd reclaim --id <id>` with the tracker'"'"'s default grace window' \
        'run `bd reclaim --id <id>`' \
        'residual contract missing: external lease open PR guard'

    both_hosts "the EXTERNAL LEASE PASS read-back requirement is removed" \
        'report it as `reclaimed` only when the read-back shows `status=open` and no assignee.' \
        'report it as `reclaimed`.' \
        'residual contract missing: external lease read-back'

    both_hosts "the EXTERNAL LEASE PASS diagnostic sentence is removed" \
        'A diagnostic run prints `would evaluate: bd reclaim --id <id>` for each such issue and writes nothing.' \
        'A diagnostic run reclaims too.' \
        'residual contract missing: external lease diagnostic'

    both_hosts "the machine guard reverts to a single 60-second re-read" \
        'Above `2 x <cores>` -> reap again and re-read at 2-minute intervals, up to five re-reads and reaping between reads, and STOP with a report if the last re-read is still above that line.' \
        'Above `2 x <cores>` -> reap again, re-read after 60s, and STOP with a report if it is still above that line.' \
        'residual contract missing: machine guard bounded wait'

    both_hosts "the machine guard final STOP is deleted" \
        'Above `2 x <cores>` -> reap again and re-read at 2-minute intervals, up to five re-reads and reaping between reads, and STOP with a report if the last re-read is still above that line.' \
        'Above `2 x <cores>` -> reap again and re-read at 2-minute intervals, up to five re-reads.' \
        'residual contract missing: machine guard bounded wait'


    both_hosts "the decision-recorded class loses its design-field write" \
        'the loop chose its recommended option, appended `<decision> | rejected: <alt> | reason: <why>` to the design field the way OWNER-DECISION ISSUES does, read the field back, and wrote the note as `decision recorded: <question> | design entry: <decision> | rejected: <alt> | reason: <why>`; charged, and no work failed)' \
        'the loop wrote the note; charged)' \
        'residual contract missing: decision-recorded class'

    both_hosts "the decision-recorded REOPEN proof is removed" \
        '`transient:decision-recorded` is gone when `backlog_loop_attempts` is below the ceiling and the issue'"'"'s design field holds, as an exact substring read from `bd show <id> --json`, the entry its block note quotes after `design entry:`; it waits for no cooldown, because nothing outside the issue changed.' \
        '`transient:decision-recorded` is gone after a cooldown.' \
        'residual contract missing: decision-recorded proof'

    both_hosts "the decision-recorded same-invocation exception is removed" \
        'The one exception is `transient:decision-recorded`, because no work failed: CENSUS may reopen it in this invocation and the issue is attempted once more, and a second `transient:decision-recorded` for the same issue in this invocation is skipped like any other failure.' \
        'There is no exception.' \
        'residual contract missing: decision-recorded reattempt'

    both_hosts "the by-type owner-decision rule is removed" \
        'Applies to every issue whose `issue_type` is `decision`; skip none of those, whatever the body says.' \
        'Applies to a decision whose body says the loop may choose.' \
        'residual contract missing: owner-decision by type'

    both_hosts "the legacy owner-decision denial is no longer retired" \
        'whose newest note begins `needs-person: the body does not say the loop may choose`, is reopened with the reopen shape REOPEN PASS uses' \
        'whose newest note begins a denial, stays parked' \
        'residual contract missing: legacy denial retired'

    both_hosts "the decision retry brief is removed" \
        'A member recorded `transient:decision-recorded` is a retry too: its brief maps the newest decision entry in its design field into LFG'"'"'s settled-decisions brief exactly as for an owner-decision member, so the new planning request cannot reopen the question.' \
        'A decision member is a normal member.' \
        'residual contract missing: decision retry brief'
    # The by-type owner-decision rule: the retired denial must not return to the
    # section that decides.
    for md in "$LOOP_MD_CLAUDE" "$LOOP_MD_CODEX"; do
        t=$(fresh_tree)
        replace_first "$t" "$md" \
            'Never overwrite an existing design record.' \
            'Never overwrite an existing design record. A body that does not say the loop may choose is `needs-person`.'
        expect_fail "OWNER-DECISION ISSUES reinstates the body-keyed denial ($md)" \
            "$md: OWNER-DECISION ISSUES reinstates the body-keyed denial" "$t"
    done

    t=$(fresh_tree)
    replace_first "$t" "$LOOP_MD_CLAUDE" '## OWNER-DECISION ISSUES' '## OWNER DECISIONS'
    expect_fail "the OWNER-DECISION ISSUES heading is renamed so its extraction finds nothing" \
        "the OWNER-DECISION ISSUES section extracted nothing" "$t"

    # Not `return "$case_failures"`: a shell return status wraps at 256, so a
    # suite with 256 or more cases misreported its miss count. The callers read
    # `case_failures` itself.
    return 0
}

# ---------------------------------------------------------------------------
# The one case that runs the other way round. It is deliberately outside
# `run_suite`: a weakened checker exits 0 and would "pass" it, so it carries
# information against the real checker only and must not count as a break.
# ---------------------------------------------------------------------------
#
# `expect_pass` exits on a rejection, unlike `expect_fail`: none of these runs
# is part of the break count, and a checker that rejects a good tree makes
# every later result meaningless.
expect_pass() { # message when it passes, what it rejected, tree
    if sh "$checker" "$3" >/dev/null 2>&1; then
        echo "  ok: $1"
    else
        echo "FAIL: the checker rejects $2:" >&2
        sh "$checker" "$3" >&2 || true
        exit 1
    fi
}

echo "Running suite against $checker"
t=$(fresh_tree)
expect_pass "the unmodified tree passes, so the ' / ' split reconciles the real <cause> table's multi-category cells" \
    "an unmodified copy of the real tree" "$t"

# The same unmodified tree under a path that contains a space must pass too:
# an unquoted path list would split it into two paths and fail.
spaced="$work/checkout with space"
mkdir "$spaced"
cp -R "$t/skills" "$t/prompts" "$spaced/"
sh "$checker" "$spaced" >/dev/null 2>&1 || { echo "FAIL: the checker rejects a tree whose path contains a space" >&2; exit 1; }

# A valid reference file, identical in both hosts, changes nothing -- whether it
# is plain prose with none of the text the scan-type rules look for, or carries
# text they read and none of them rejects.
t=$(fresh_tree)
for host in claude codex; do
    plant_reference "$t" "$host" 'Rationale. A gate is a person'"'"'s question; the loop reads it and never answers it.'
done
expect_pass "a plain-prose references/rationale.md in both hosts passes" \
    "a tree with a plain-prose references/rationale.md in both hosts" "$t"

t=$(fresh_tree)
for host in claude codex; do
    plant_reference "$t" "$host" 'Rationale. Read the queue with `bd ready --json --limit 0`; park an issue with `bd update <id> --status=blocked`; remove a run-owned worktree with `git worktree remove --force <path>`.'
done
expect_pass "a valid references/rationale.md in both hosts passes" \
    "a tree with a valid references/rationale.md in both hosts" "$t"

run_suite "$checker"
suite_failures="$case_failures"
real_breaks="$break_cases"

if [ "$suite_failures" -ne 0 ]; then
    echo "FAIL: check-backlog-loop.sh missed or mis-reported $suite_failures case(s)" >&2
    exit 1
fi

# The guard on the guard. A checker that always succeeds must miss every break,
# not merely some: an environmental abort would produce a partial count, so
# requiring the full set is what proves the suite is actually discriminating.
weak="$work/weakened-check-backlog-loop.sh"
printf '#!/bin/sh\nexit 0\n' > "$weak"
echo "Running suite against a deliberately weakened checker (every break must go undetected)"
run_suite "$weak"
weak_failures="$case_failures"

if [ "$weak_failures" -ne "$real_breaks" ]; then
    echo "FAIL: the weakened checker went undetected in only $weak_failures of $real_breaks break cases;" >&2
    echo "      the suite is not discriminating (or it aborted partway)." >&2
    exit 1
fi

echo "OK: check-backlog-loop.sh caught all $real_breaks breaks with the right reason, and the suite rejects a weakened checker"
