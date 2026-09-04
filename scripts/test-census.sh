#!/bin/sh
# Prove that backlog-loop's CENSUS section classifies a real Beads backlog.
#
# Usage: test-census.sh [--contract-only]
#
# This suite is NOT part of the push path. Half of it drives a model, so it is
# non-deterministic and slow, and a gate that goes yellow on every third run
# stops being read. Run it by hand before changing the CENSUS section, or
# nightly. `--contract-only` runs just the deterministic half, which is safe
# anywhere.
#
# It comes in two parts, and they fail for different reasons.
#
# PART 1, tracker contract. Pure shell against a seeded store, no model. It
# pins the `bd` behaviours the CENSUS section is built on: which flags hide
# rows, what a native gate looks like, that a human gate lands in `bd ready`
# unless something withholds it, that `--readonly` refuses writes, and that
# `bd export` is the only valid non-mutation oracle. When one of these fails
# the tracker changed underneath the procedure, and the procedure is wrong
# before any model reads it. Deterministic; run it on every change.
#
# PART 2, classification. Seeds a store per case, drives one census through
# the host CLI headless, and diffs the emitted `census <id> | <category> |
# <cause>` lines against an expected table. This is the only check that the
# prose actually classifies the way it says it does.
#
# Both parts skip cleanly rather than failing when a prerequisite is missing:
# a suite that reports red because `bd` is not installed teaches people to
# ignore it.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
contract_only=0
[ "${1:-}" = "--contract-only" ] && contract_only=1

# Every tracker command names its store with `-C`, so bd runs with this
# suite's working directory -- the repository -- rather than the store's. bd
# reads `beads.role` from git config and warns once per invocation when it is
# unset, which would bury the check output in a CI log. Supplying it through
# the environment answers the warning without touching the user's git config
# and without redirecting stderr, which would hide real errors too.
GIT_CONFIG_COUNT=${GIT_CONFIG_COUNT:-1}
GIT_CONFIG_KEY_0=${GIT_CONFIG_KEY_0:-beads.role}
GIT_CONFIG_VALUE_0=${GIT_CONFIG_VALUE_0:-contributor}
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

work=$(mktemp -d "${TMPDIR:-/tmp}/test-census.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

failures=0
checks=0

pass() { checks=$((checks + 1)); printf '  ok: %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL: %s\n' "$1"; }

# One empty Beads store per case. Each gets its own directory so a case cannot
# see another's issues; ids are prefix-scoped, so a shared store would also
# make the expected tables order-dependent.
#
# `bd init` is the one command that rejects the global `-C` flag, so it -- and
# only it -- runs in a subshell. Every other tracker command below names its
# store with `-C`, which keeps this suite's working directory fixed and stops a
# case from reading whichever store the previous one happened to leave as cwd.
fresh_store() {
    dir=$(mktemp -d "$work/store.XXXXXX")
    ( cd "$dir" && bd init --prefix cx >/dev/null 2>&1 )
    echo "$dir"
}

# Read one field out of the enumeration the CENSUS section prescribes.
# Keeping the query in exactly one place here is deliberate: if the procedure's
# command and the suite's command drift apart, the suite proves nothing.
enumerate() {
    bd -C "$1" list --all --limit 0 --include-gates --json
}

# Every id in a `bd ... --json` payload, sorted and space-separated, ready for
# the `case " $ids " in *" $id "*)` membership tests below. bd returns a bare
# list from some subcommands and an object keyed by "issues" from others, so
# both shapes are accepted rather than pinned to one.
sorted_ids_json() {
    python3 -c 'import json,sys
d=json.load(sys.stdin); rows=d if isinstance(d,list) else d.get("issues",d)
print(" ".join(sorted(r["id"] for r in rows)))'
}

# `bd gate create` has no --silent form, so a new gate's id has to be read out
# of its prose confirmation. Every caller checks the result for empty: if that
# wording ever changes -- exactly the drift this suite exists to catch -- sed
# prints nothing and still exits 0, and an unchecked empty id would leave the
# native-gate assertions comparing against "" instead of failing.
gate_id() {
    sed -n 's/^.*Created gate \([A-Za-z0-9-]*\).*$/\1/p'
}

# Assert that `missing` is absent from the id list `ids` while `baseline` is
# still present. The baseline half is what makes the check mean anything: these
# assertions pass on ABSENCE, so a query that came back empty for any reason
# unrelated to the flag under test would otherwise report that flag
# load-bearing while having proved nothing at all.
assert_hidden_without() {
    ids=$1; missing=$2; baseline=$3; ok_msg=$4; bad_msg=$5
    case " $ids " in
        *" $baseline "*) : ;;
        *) fail "$bad_msg -- the comparison query returned no baseline row, so it proves nothing"
           return ;;
    esac
    case " $ids " in
        *" $missing "*) fail "$bad_msg" ;;
        *) pass "$ok_msg" ;;
    esac
}

if ! command -v bd >/dev/null 2>&1; then
    echo "SKIP: bd is not installed; the census has no tracker to classify."
    exit 0
fi

echo "PART 1 - tracker contract"

store=$(fresh_store)

ready_issue=$(bd -C "$store" create "ready work" --silent)
gate=$(bd -C "$store" create "[HUMAN] provision the deploy account" -l human-gate --silent)
dependent=$(bd -C "$store" create "ship the deploy step" --silent)
prefix_only=$(bd -C "$store" create "[HUMAN] rotate the signing key" --silent)
legacy_block=$(bd -C "$store" create "left blocked by an earlier run" --silent)
pinned=$(bd -C "$store" create "pinned work" --silent)
deferred=$(bd -C "$store" create "deferred work" --silent)
native_target=$(bd -C "$store" create "step behind a native gate" --silent)

bd -C "$store" dep "$gate" --blocks "$dependent" >/dev/null
bd -C "$store" update "$legacy_block" --status=blocked --set-metadata backlog_loop_run=OLD-RUN \
    --append-notes "merge blocked: trunk moved | none" >/dev/null
bd -C "$store" update "$pinned" --status=pinned >/dev/null
bd -C "$store" update "$deferred" --status=deferred --defer "+30d" >/dev/null
native_gate=$(bd -C "$store" gate create --type=human --blocks "$native_target" 2>/dev/null | gate_id)
[ -n "$native_gate" ] \
    || fail "could not read a gate id out of 'bd gate create'; the native-gate checks below cannot run"

# The enumeration must hide nothing. Every flag in it is load-bearing, so each
# one is asserted against the query that drops it rather than against a count
# the suite could satisfy by accident.
all_ids=$(enumerate "$store" | sorted_ids_json)

omitted=0
for id in "$ready_issue" "$gate" "$dependent" "$prefix_only" "$legacy_block" \
          "$pinned" "$deferred" "$native_target" "$native_gate"; do
    # An id the guards above already reported as unreadable is skipped here
    # rather than reported a second time as an omission of "".
    [ -n "$id" ] || continue
    case " $all_ids " in
        *" $id "*) : ;;
        *) fail "enumeration omitted $id"; omitted=1 ;;
    esac
done
if [ "$omitted" -eq 0 ]; then
    pass "enumeration surfaces every seeded issue, gates and pinned included"
fi

without_all=$(bd -C "$store" list --limit 0 --include-gates --json | sorted_ids_json)
assert_hidden_without "$without_all" "$pinned" "$ready_issue" \
    "--all is load-bearing: a pinned issue is hidden without it" \
    "--all is not needed for a pinned issue; the procedure over-explains"

if [ -n "$native_gate" ]; then
    without_gates=$(bd -C "$store" list --all --limit 0 --json | sorted_ids_json)
    assert_hidden_without "$without_gates" "$native_gate" "$ready_issue" \
        "--include-gates is load-bearing: a native gate is hidden without it" \
        "--include-gates is not needed; the procedure over-explains"

    # A native gate is a gate by type and carries no labels, which is exactly why
    # the repair rule must never fire on one: its blocking edge is what it is for,
    # and it has nothing to declare that edge with.
    gate_shape=$(enumerate "$store" | python3 -c "import json,sys
d=json.load(sys.stdin); rows=d if isinstance(d,list) else d.get('issues',d)
r=[x for x in rows if x['id']=='$native_gate'][0]
print(r.get('issue_type'), len(r.get('labels') or []))")
    [ "$gate_shape" = "gate 0" ] \
        && pass "a native gate reports issue_type=gate and carries no labels" \
        || fail "native gate shape changed: got '$gate_shape', expected 'gate 0'"
fi

# The motivating defect, asserted directly: a human gate is open with no
# blocker, so the tracker offers it as ready work. Nothing in bd withholds it;
# only the CENSUS section does.
ready_ids=$(bd -C "$store" ready --json --exclude-type=epic | sorted_ids_json)
case " $ready_ids " in
    *" $gate "*) pass "bd ready offers a labeled human gate; withholding it is the procedure's job" ;;
    *) fail "bd ready no longer offers an unblocked human gate; the census rule may be obsolete" ;;
esac
case " $ready_ids " in
    *" $prefix_only "*) pass "bd ready offers a [HUMAN]-prefixed issue with no label" ;;
    *) fail "bd ready withheld a prefix-only issue on its own; check the label-defect rule" ;;
esac
case " $ready_ids " in
    *" $legacy_block "*) fail "bd ready returned a blocked issue" ;;
    *) pass "bd ready hides a blocked issue, which is why an empty list proves nothing" ;;
esac

# The dependency explanation covers dependency-blocked open issues only. The
# self-block the loop writes has no edge, so it appears in neither bucket --
# the reason every other category is read from stored status instead.
explain_ids=$(bd -C "$store" ready --explain --json | python3 -c 'import json,sys
d=json.load(sys.stdin)
ids=[r["id"] for k in ("ready","blocked") for r in (d.get(k) or [])]
print(" ".join(sorted(ids)))')
case " $explain_ids " in
    *" $legacy_block "*) fail "--explain now covers a dep-free blocked issue; simplify the census rule" ;;
    *) pass "--explain cannot see a dep-free blocked issue" ;;
esac
case " $explain_ids " in
    *" $dependent "*) pass "--explain names the blocker of a dependency-blocked issue" ;;
    *) fail "--explain no longer reports dependency-blocked issues" ;;
esac

# Acceptance replaces rather than appends, and unlike description and design it
# has no file form. Both are why the repair reads back before it removes an edge.
bd -C "$store" update "$gate" --acceptance "ORIGINAL AUTHOR TEXT" >/dev/null
bd -C "$store" update "$gate" --acceptance "SECOND WRITE" >/dev/null
acc=$(bd -C "$store" show "$gate" --json | python3 -c 'import json,sys
d=json.load(sys.stdin)
r = d[0] if isinstance(d, list) else d
print(r.get("acceptance_criteria") or "")')
case "$acc" in
    *ORIGINAL*) fail "--acceptance now appends; the read-modify-write rule is obsolete" ;;
    *SECOND*) pass "--acceptance replaces the field, so the repair must round-trip it" ;;
    *) fail "could not read acceptance_criteria back: got '$acc'" ;;
esac
if bd -C "$store" update --help 2>&1 | grep -q -- '--acceptance-file'; then
    fail "--acceptance-file now exists; the one-shell-argument warning is obsolete"
else
    pass "--acceptance has no file form, unlike --body-file and --design-file"
fi

# Read-only mode is a tracker guarantee, not a promise in prose. The diagnostic
# entry point depends on it.
if bd --readonly -C "$store" update "$ready_issue" --set-metadata probe=1 >/dev/null 2>&1; then
    fail "--readonly permitted a write; the diagnostic entry point has no enforcement"
else
    pass "--readonly refuses a write"
fi
bd --readonly -C "$store" list --limit 5 >/dev/null 2>&1 \
    && bd --readonly -C "$store" show "$ready_issue" >/dev/null 2>&1 \
    && pass "--readonly still permits the reads the census needs" \
    || fail "--readonly blocked a read the census needs"

# bd export is the non-mutation oracle. A filesystem diff is not: a plain read
# rewrites tracker bookkeeping without changing any issue field, so a suite
# built on file comparison fails on its first case for no real reason.
bd -C "$store" export > "$work/export.before" 2>/dev/null
bd -C "$store" show "$ready_issue" >/dev/null 2>&1
bd -C "$store" list --all --limit 0 >/dev/null 2>&1
bd -C "$store" export > "$work/export.after" 2>/dev/null
cmp -s "$work/export.before" "$work/export.after" \
    && pass "bd export is unchanged by reads, so it is a valid non-mutation oracle" \
    || fail "bd export changed across reads; the census has no non-mutation oracle"

if find "$store/.beads" -newer "$work/export.before" -type f 2>/dev/null | grep -q .; then
    pass "reads do touch tracker files, so a filesystem diff is not an oracle"
else
    fail "reads no longer touch tracker files; a filesystem diff may now be valid"
fi

if [ "$contract_only" -eq 1 ]; then
    printf '\n%d check(s), %d failure(s) [contract only]\n' "$checks" "$failures"
    [ "$failures" -eq 0 ] || exit 1
    exit 0
fi

echo ""
echo "PART 2 - classification"

# The twelve categories the CENSUS section files every issue under, in its own
# precedence order. Kept here so a rename in the procedure fails this suite
# rather than silently shrinking what it counts.
CATEGORIES='human-gate|label-defect|claimed-other-run|external-wip|claimed-this-run|self-blocked-needs-person|self-blocked-transient|dep-blocked|hooked|pinned|deferred|ready'

host_cli=""
for candidate in claude codex; do
    command -v "$candidate" >/dev/null 2>&1 && { host_cli=$candidate; break; }
done

if [ -z "$host_cli" ]; then
    echo "SKIP: no host CLI on PATH; classification needs one to run the census."
    printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
    [ "$failures" -eq 0 ] || exit 1
    exit 0
fi

# Drive one census over a seeded store and echo its emitted lines. The census
# writes them between two markers so the surrounding narration a model produces
# never reaches the diff. `--readonly` is not passed here: a loop-mode case
# must be able to observe the mutation passes.
run_census() {
    store_dir=$1
    mode=$2   # diagnostic | loop
    prompt="Read the backlog-loop skill at $repo_root/skills/claude/backlog-loop/SKILL.md.
Run ONLY its CENSUS section against the Beads tracker in $store_dir, as a $mode run.
Do not run ITERATION. Do not claim, plan, build, branch, push, or merge anything.
Use 'bd -C $store_dir ...' for every tracker command.
Print the census header line and every 'census <id> | <category> | <cause>' line,
between a line reading CENSUS-BEGIN and a line reading CENSUS-END, and nothing else
between those markers."
    timeout 600 "$host_cli" -p "$prompt" 2>/dev/null \
        | sed -n '/^CENSUS-BEGIN$/,/^CENSUS-END$/p' \
        | sed -e '/^CENSUS-BEGIN$/d' -e '/^CENSUS-END$/d'
}

# category_of <output> <id>  ->  the category the census filed that id under
category_of() {
    printf '%s\n' "$1" | sed -n "s/^census  *$2  *|  *\([a-z-]*\).*/\1/p" | head -1
}

expect_category() {
    got=$(category_of "$1" "$2")
    [ "$got" = "$3" ] \
        && pass "$4" \
        || fail "$4 (got '${got:-<no line>}', expected '$3')"
}

echo "  case: mixed backlog, one category per issue"
c1=$(fresh_store)
c1_ready=$(bd -C "$c1" create "ready work" --silent)
c1_gate=$(bd -C "$c1" create "[HUMAN] provision the deploy account" -l human-gate --silent)
c1_dep=$(bd -C "$c1" create "ship the deploy step" --silent)
c1_prefix=$(bd -C "$c1" create "[HUMAN] rotate the signing key" --silent)
c1_block=$(bd -C "$c1" create "left blocked by an earlier run" --silent)
bd -C "$c1" dep "$c1_gate" --blocks "$c1_dep" >/dev/null
bd -C "$c1" update "$c1_block" --status=blocked --set-metadata backlog_loop_run=OLD-RUN \
    --set-metadata backlog_loop_cause=needs-person --set-metadata backlog_loop_attempts=1 \
    --append-notes "post-merge verification failed: lint | none" >/dev/null

out=$(run_census "$c1" diagnostic)
if [ -z "$out" ]; then
    fail "census emitted nothing; the runner or the marker contract is broken"
else
    expect_category "$out" "$c1_ready"  ready         "a dependency-free open issue is ready"
    expect_category "$out" "$c1_gate"   human-gate    "a labeled gate is a human gate, never ready"
    expect_category "$out" "$c1_dep"    dep-blocked   "the issue behind the gate is dependency-blocked"
    expect_category "$out" "$c1_prefix" label-defect  "a [HUMAN] prefix with no label is a labeling defect"
    expect_category "$out" "$c1_block"  self-blocked-needs-person \
        "a post-merge verification block is never transient"

    # Count the data shape, not the word "census": the header is prose the
    # model composes, and a counter that merely looks for a prefix reports one
    # issue too many the moment that wording drifts. Naming the categories
    # makes the count independent of the header entirely, and makes this line
    # fail loudly if the procedure ever renames one.
    emitted=$(printf '%s\n' "$out" | grep -cE "^census +[^ |]+ +\\| +($CATEGORIES) +\\|" || true)
    [ "$emitted" -eq 5 ] \
        && pass "exactly one line per non-closed non-epic issue" \
        || fail "expected 5 census lines, got $emitted"
fi

echo "  case: a native gate is a gate and is never repaired"
c2=$(fresh_store)
c2_target=$(bd -C "$c2" create "step behind a native gate" --silent)
c2_gate=$(bd -C "$c2" gate create --type=human --blocks "$c2_target" 2>/dev/null | gate_id)
[ -n "$c2_gate" ] || fail "could not read a gate id out of 'bd gate create' for this case"
bd -C "$c2" create "unrelated ready work" --silent >/dev/null
bd -C "$c2" export > "$work/c2.before" 2>/dev/null

out=$(run_census "$c2" loop)
expect_category "$out" "$c2_gate"   human-gate  "a native gate classifies as a human gate"
expect_category "$out" "$c2_target" dep-blocked "the step behind it stays dependency-blocked"

bd -C "$c2" export > "$work/c2.after" 2>/dev/null
cmp -s "$work/c2.before" "$work/c2.after" \
    && pass "a loop-mode census removed no native gate edge" \
    || fail "a loop-mode census mutated the tracker around a native gate"

echo "  case: adoption gate holds the first run back"
c3=$(fresh_store)
c3_gate=$(bd -C "$c3" create "[HUMAN] approve the production rollout" -l human-gate --silent)
c3_dep=$(bd -C "$c3" create "wire the rollout flag" --silent)
bd -C "$c3" dep "$c3_gate" --blocks "$c3_dep" >/dev/null
bd -C "$c3" export > "$work/c3.before" 2>/dev/null

out=$(run_census "$c3" loop)
expect_category "$out" "$c3_gate" human-gate  "the labeled gate is recognized"
expect_category "$out" "$c3_dep"  dep-blocked "its dependent stays blocked while the convention is unadopted"

bd -C "$c3" export > "$work/c3.after" 2>/dev/null
cmp -s "$work/c3.before" "$work/c3.after" \
    && pass "no hard-blocker label anywhere means no edge is removed" \
    || fail "the first run removed a gate edge with no hard-blocker label in the tracker"

echo "  case: a diagnostic run writes nothing"
c4=$(fresh_store)
c4_gate=$(bd -C "$c4" create "[HUMAN] grant registry access" -l human-gate --silent)
c4_dep=$(bd -C "$c4" create "publish the image" --silent)
c4_other=$(bd -C "$c4" create "[HUMAN] declared hard blocker" -l human-gate,hard-blocker --silent)
bd -C "$c4" dep "$c4_gate" --blocks "$c4_dep" >/dev/null
bd -C "$c4" export > "$work/c4.before" 2>/dev/null

out=$(run_census "$c4" diagnostic)
expect_category "$out" "$c4_gate"  human-gate "the undeclared gate is recognized in diagnostic mode"
expect_category "$out" "$c4_other" human-gate "the declared gate is recognized too"

bd -C "$c4" export > "$work/c4.after" 2>/dev/null
cmp -s "$work/c4.before" "$work/c4.after" \
    && pass "a diagnostic run left the tracker's issue records unchanged" \
    || fail "a diagnostic run mutated the tracker"

printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
[ "$failures" -eq 0 ] || exit 1
