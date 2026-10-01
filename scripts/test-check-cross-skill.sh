#!/bin/sh
# Mutation tests for the cross-skill contract. Every case must fail for its
# named reason; a checker that always succeeds must miss every case.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
checker="${1:-$repo_root/scripts/check-cross-skill.sh}"
work=$(mktemp -d "${TMPDIR:-/tmp}/test-check-cross-skill.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
fresh_tree() {
    tree=$(mktemp -d "$work/case-XXXXXX")
    cp -R "$repo_root/skills" "$tree/skills"
    printf '%s\n' "$tree"
}
replace_all() {
    OLD="$3" NEW="$4" python3 - "$1/$2" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
old, new = os.environ["OLD"], os.environ["NEW"]
if old not in s:
    sys.stderr.write("test bug: missing literal %r in %s\n" % (old, p))
    sys.exit(2)
open(p, "w").write(s.replace(old, new))
PY
}
AUDIT=skills/claude/repo-audit/SKILL.md
WRITER=skills/claude/source-to-beads/SKILL.md
CONSUMER=skills/claude/backlog-loop/SKILL.md
expect_fail() {
    name="$1"; expected="$2"; tree="$3"
    cases=$((cases + 1))
    out=$(sh "$under_test" "$tree" 2>&1) && rc=0 || rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  MISS: $name" >&2
        misses=$((misses + 1))
    elif ! printf '%s\n' "$out" | grep -qE -- "$expected"; then
        echo "  WRONG REASON: $name: $(printf '%s\n' "$out" | head -n 1)" >&2
        misses=$((misses + 1))
    else
        echo "  ok: $name"
    fi
}
both_replace() {
    label="$1"; want="$2"; skill="$3"; old="$4"; new="$5"
    for host in claude codex; do
        t=$(fresh_tree)
        replace_all "$t" "skills/$host/$skill/SKILL.md" "$old" "$new"
        expect_fail "$label ($host)" "$want" "$t"
    done
}
both_append() {
    label="$1"; want="$2"; skill="$3"; text="$4"
    for host in claude codex; do
        t=$(fresh_tree)
        printf '\n%s\n' "$text" >> "$t/skills/$host/$skill/SKILL.md"
        expect_fail "$label ($host)" "$want" "$t"
    done
}
run_suite() {
    under_test="$1"; cases=0; misses=0
    t=$(fresh_tree)
    printf '\nRun `bd list --all --json` before audit.\n' >> "$t/$AUDIT"
    expect_fail "audit calls Beads" "repo-audit: .*contains a Beads command" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd --version` before audit.\n' >> "$t/$AUDIT"
    expect_fail "audit checks Beads availability" "repo-audit: .*contains a Beads command" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd config` before audit.\n' >> "$t/$AUDIT"
    expect_fail "audit invokes another Beads subcommand" "repo-audit: .*contains a Beads command" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd -C . list` before audit.\n' >> "$t/$AUDIT"
    expect_fail "audit invokes Beads with a directory option" "repo-audit: .*contains a Beads command" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd -q list` before audit.\n' >> "$t/$AUDIT"
    expect_fail "audit invokes Beads with a quiet option" "repo-audit: .*contains a Beads command" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd update <id> --set-metadata backlog_loop_run=1`.\n' >> "$t/$WRITER"
    expect_fail "writer crosses consumer namespace" "reserved to 'backlog-loop'" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd -C . update <id> --set-metadata backlog_loop_run=1`.\n' >> "$t/$WRITER"
    expect_fail "writer crosses consumer namespace with a directory option" "reserved to 'backlog-loop'" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd update <id> --set-metadata repo_audit_sha=abc`.\n' >> "$t/$WRITER"
    expect_fail "writer mutates legacy audit metadata" "legacy audit metadata key" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd update <id> --set-metadata source_to_beads_probe=1`.\n' >> "$t/$CONSUMER"
    expect_fail "consumer crosses writer namespace" "reserved to 'source-to-beads'" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd update <id> --set-metadata shared_probe_key=1`.\n' >> "$t/$WRITER"
    printf '\nRun `bd update <id> --set-metadata shared_probe_key=1`.\n' >> "$t/$CONSUMER"
    expect_fail "unreserved metadata collision" "both write metadata key" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$WRITER" 'source_to_beads_key' 'source_to_beads_anchor'
    expect_fail "writer key vanishes" "missing metadata key 'source_to_beads_key'" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$WRITER" 'bd list --all --include-gates --limit 0 --json' 'bd list --json'
    expect_fail "writer loses full dedup scan" "missing full Beads dedup scan" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$WRITER" 'repo_audit_fingerprint' 'old_audit_fingerprint'
    expect_fail "writer loses legacy dedup" "missing legacy audit deduplication" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$WRITER" 'both open and closed issues' 'open issues'
    expect_fail "writer overlooks closed semantic matches" "missing closed-issue semantic deduplication" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$WRITER" 'stable `RA-` finding ID' 'report run identifier'
    expect_fail "writer keys repeated audit runs separately" "missing cross-report audit identity" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$WRITER" '[HUMAN]' '[PERSON]'
    expect_fail "writer loses human gate title" "missing human-gate title contract" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$WRITER" 'human-gate' 'person-gate'
    expect_fail "writer loses human gate label" "missing human-gate label contract" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$WRITER" 'with no parent and no dependency on agent work' 'inside an epic'
    expect_fail "writer nests human gates" "missing standalone human-gate contract" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$WRITER" 'unless no agent work can run' 'whenever convenient'
    expect_fail "writer broadens human gate blocker exception" "missing hard-blocker exception" "$t"

    t=$(fresh_tree)
    printf '\nThe writer adds `hard-blocker` to new gates.\n' >> "$t/$WRITER"
    expect_fail "writer forges author-only label in prose" "claims in prose to write author-only label 'hard-blocker'" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd update <id> --add-label audit-suppressed`.\n' >> "$t/$WRITER"
    expect_fail "writer forges legacy suppression label" "write site for author-only label 'audit-suppressed'" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd create work -l hard-blocker`.\n' >> "$t/$WRITER"
    expect_fail "writer forges author-only label with a short flag" "write site for author-only label 'hard-blocker'" "$t"

    t=$(fresh_tree)
    printf '\nRun `bd -q create work -l audit-suppressed`.\n' >> "$t/$WRITER"
    expect_fail "writer forges legacy label with global and short flags" "write site for author-only label 'audit-suppressed'" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$CONSUMER" 'status=deferred' 'status=parked'
    expect_fail "consumer loses deferred category" "no longer classifies deferred issues" "$t"

    t=$(fresh_tree)
    replace_all "$t" "$CONSUMER" 'issue_type` is `gate`' 'issue_type` is `blocker`'
    expect_fail "consumer loses native gate type" "no longer recognizes native gate issues" "$t"

    # Producer contract (R18): the loop keeps recognizing a gate a person
    # reserved and never repairs or decides it; the writer files that form.
    both_replace "consumer loses the human-gate label" "backlog-loop: .*no longer recognizes the human-gate label" backlog-loop 'carries the `human-gate` label, or' 'carries the `person-gate` label, or'
    both_replace "consumer repairs native gate edges" "backlog-loop: .*no longer exempts native gate edges from gate repair" backlog-loop 'A native gate (`issue_type=gate`) is NEVER repaired or quarantined: its blocking edge is declared by construction, so every edge a producer such as `source-to-beads` writes on one stands.' 'A native gate (`issue_type=gate`) is repaired like any other gate.'
    both_replace "consumer treats any decision as owner-decision" "backlog-loop: .*no longer limits owner-decision issues to a decision that grants the choice" backlog-loop 'an issue is one only when its `issue_type` is `decision` and its body says the loop may choose' 'an issue is one when its body asks for a product or design call'
    both_replace "consumer decides a reserved question" "backlog-loop: .*no longer reports a decision it may not choose as needs-person" backlog-loop 'Any other `decision` issue is a person'"'"'s question, however it reads: never pick an option for it, never batch it, and open no PR for it.' 'Pick the recommended option for any other decision issue too.'
    both_replace "writer loses the native gate form" "source-to-beads: .*missing native gate form for hard-blockers" source-to-beads 'File every user-reserved question and every hard-blocker as a native gate with `bd create --type gate`: `backlog-loop` declares a native gate'"'"'s edges by construction, so no `hard-blocker` label is needed.' 'File a hard-blocker as an ordinary issue.'
    both_replace "writer loses the agent-decidable decision form" "source-to-beads: .*missing agent-decidable decision form" source-to-beads 'Keep an agent-decidable technical choice a `decision` issue whose body says the loop may choose.' 'Keep a technical choice a decision issue.'

    both_replace "audit loses the handoff section" "repo-audit: .*missing worktree handoff section" repo-audit '## Worktree handoff' '## Worktree notes'
    both_replace "writer loses the handoff section" "source-to-beads: .*missing worktree handoff section" source-to-beads 'Worktree handoff' 'Worktree notes'
    both_replace "audit loses root resolution" "repo-audit: .*missing handoff root resolution" repo-audit 'Resolve `<root>` as the first `worktree` entry of `git worktree list --porcelain`' 'Resolve the root somehow'
    both_replace "writer loses root resolution" "source-to-beads: .*missing handoff root resolution" source-to-beads 'Resolve `<root>` as the first `worktree` entry of `git worktree list --porcelain`' 'Resolve the root somehow'
    both_replace "audit skips checksum verification" "repo-audit: .*missing handoff copy verification" repo-audit 'compare the sha256 of each copy with its source' 'copy without checking'
    both_replace "writer skips checksum verification" "source-to-beads: .*missing handoff copy verification" source-to-beads 'compare the sha256 of each copy with its source' 'copy without checking'
    both_replace "audit copies a sidecar without an ignored root path" "repo-audit: .*missing handoff sidecar safety" repo-audit 'makes the verdict `not safe to delete`, names the worktree path of the sidecar, and suppresses the remove command' 'is fine to leave behind'
    both_replace "writer copies a sidecar without an ignored root path" "source-to-beads: .*missing handoff sidecar safety" source-to-beads 'makes the verdict `not safe to delete`, names the worktree path of the sidecar, and suppresses the remove command' 'is fine to leave behind'
    both_replace "audit loses the printed remove command" "repo-audit: .*missing printed remove command gated on the verdict" repo-audit 'When the verdict is `safe to delete`, print the literal `git worktree remove <worktree>` command for the operator to run.' 'Tell the operator the worktree may be deleted.'
    both_replace "writer loses the printed remove command" "source-to-beads: .*missing printed remove command gated on the verdict" source-to-beads 'When the verdict is `safe to delete`, print the literal `git worktree remove <worktree>` command for the operator to run.' 'Tell the operator the worktree may be deleted.'
    both_replace "audit prints the remove command without the verdict gate" "repo-audit: .*missing printed remove command gated on the verdict" repo-audit 'When the verdict is `safe to delete`, print' 'Always print'
    both_replace "writer prints the remove command without the verdict gate" "source-to-beads: .*missing printed remove command gated on the verdict" source-to-beads 'When the verdict is `safe to delete`, print' 'Always print'
    both_replace "audit drops the never-run rule" "repo-audit: .*missing no-remove rule" repo-audit 'Never run `git worktree remove` or `git worktree prune`; removal belongs to the operator.' 'Removal is easy.'
    both_replace "writer drops the never-run rule" "source-to-beads: .*missing no-remove rule" source-to-beads 'Never run `git worktree remove` or `git worktree prune`; removal belongs to the operator.' 'Removal is easy.'
    both_append "audit instructs running worktree remove" "repo-audit: .*instructs running" repo-audit 'Afterward run `git worktree remove <worktree>` to clean up.'
    both_append "writer instructs running worktree remove" "source-to-beads: .*instructs running" source-to-beads 'Afterward run `git worktree remove <worktree>` to clean up.'
    both_append "audit instructs running worktree prune" "repo-audit: .*instructs running" repo-audit 'Then run `git worktree prune`.'
    both_append "writer instructs running worktree prune" "source-to-beads: .*instructs running" source-to-beads 'Then run `git worktree prune`.'
    both_replace "audit loses the finalize-time handoff" "repo-audit: .*missing finalize-time handoff" repo-audit 'Run the handoff once when the report is finalized, before presenting any choice, so every exit, an abandoned session included, already holds the root copy.' 'Run the handoff when convenient.'
    both_replace "audit loses the exit rerun" "repo-audit: .*missing handoff rerun on every exit" repo-audit 'Rerun it on every exit, idempotently: on Stop with report, and on Beads and Fix before printing the command.' 'Rerun it sometimes.'
    both_replace "writer runs the handoff before its receipt" "source-to-beads: .*missing post-receipt handoff" source-to-beads 'Run the handoff after the receipt, reading every receipt issue id back with `bd -C <root> show <id> --json` first.' 'Run the handoff before the receipt.'
    both_replace "writer loses the database comparison" "source-to-beads: .*missing bd where comparison" source-to-beads 'compare `bd where` in the current directory with `bd -C <root> where`' 'assume the database'
    both_append "audit compares databases itself" "repo-audit: .*contains a Beads command" repo-audit 'Compare `bd where` with `bd -C <root> where` before the copy.'

    return "$misses"
}
echo "Running suite against $checker"
failures=0
run_suite "$checker" || failures=$?
real_cases="$cases"
[ "$failures" -eq 0 ] || { echo "FAIL: $failures mutation case(s) missed" >&2; exit 1; }
weak="$work/weakened.sh"
printf '#!/bin/sh\nexit 0\n' > "$weak"
echo "Running suite against a deliberately weakened checker"
weak_misses=0
run_suite "$weak" || weak_misses=$?
[ "$weak_misses" -eq "$real_cases" ] || { echo "FAIL: weakened checker missed only $weak_misses of $real_cases cases" >&2; exit 1; }
echo "OK: all $real_cases breaks detected; weakened checker rejected"
