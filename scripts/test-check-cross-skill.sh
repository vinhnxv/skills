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
