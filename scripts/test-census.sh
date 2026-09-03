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

work=$(mktemp -d "${TMPDIR:-/tmp}/test-census.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

failures=0
checks=0

pass() { checks=$((checks + 1)); printf '  ok: %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL: %s\n' "$1"; }

# One empty Beads store per case. Each gets its own directory so a case cannot
# see another's issues; ids are prefix-scoped, so a shared store would also
# make the expected tables order-dependent.
fresh_store() {
    dir=$(mktemp -d "$work/store.XXXXXX")
    ( cd "$dir" && bd init --prefix cx >/dev/null 2>&1 )
    echo "$dir"
}

# Read one field out of the enumeration the CENSUS section prescribes.
# Keeping the query in exactly one place here is deliberate: if the procedure's
# command and the suite's command drift apart, the suite proves nothing.
enumerate() {
    ( cd "$1" && bd list --all --limit 0 --include-gates --json )
}

if ! command -v bd >/dev/null 2>&1; then
    echo "SKIP: bd is not installed; the census has no tracker to classify."
    exit 0
fi

echo "PART 1 - tracker contract"

store=$(fresh_store)
cd "$store"

ready_issue=$(bd create "ready work" --silent)
gate=$(bd create "[HUMAN] provision the deploy account" -l human-gate --silent)
dependent=$(bd create "ship the deploy step" --silent)
prefix_only=$(bd create "[HUMAN] rotate the signing key" --silent)
legacy_block=$(bd create "left blocked by an earlier run" --silent)
pinned=$(bd create "pinned work" --silent)
deferred=$(bd create "deferred work" --silent)
native_target=$(bd create "step behind a native gate" --silent)

bd dep "$gate" --blocks "$dependent" >/dev/null
bd update "$legacy_block" --status=blocked --set-metadata backlog_loop_run=OLD-RUN \
    --append-notes "merge blocked: trunk moved | none" >/dev/null
bd update "$pinned" --status=pinned >/dev/null
bd update "$deferred" --status=deferred --defer "+30d" >/dev/null
native_gate=$(bd gate create --type=human --blocks "$native_target" 2>/dev/null \
    | sed -n 's/^.*Created gate \([A-Za-z0-9-]*\).*$/\1/p')

# The enumeration must hide nothing. Every flag in it is load-bearing, so each
# one is asserted against the query that drops it rather than against a count
# the suite could satisfy by accident.
all_ids=$(enumerate "$store" | python3 -c 'import json,sys
d=json.load(sys.stdin); rows=d if isinstance(d,list) else d.get("issues",d)
print(" ".join(sorted(r["id"] for r in rows)))')

for id in "$ready_issue" "$gate" "$dependent" "$prefix_only" "$legacy_block" \
          "$pinned" "$deferred" "$native_target" "$native_gate"; do
    case " $all_ids " in
        *" $id "*) : ;;
        *) fail "enumeration omitted $id" ;;
    esac
done
pass "enumeration surfaces every seeded issue, gates and pinned included"

without_all=$(bd list --limit 0 --include-gates --json | python3 -c 'import json,sys
d=json.load(sys.stdin); rows=d if isinstance(d,list) else d.get("issues",d)
print(" ".join(sorted(r["id"] for r in rows)))')
case " $without_all " in
    *" $pinned "*) fail "--all is not needed for a pinned issue; the procedure over-explains" ;;
    *) pass "--all is load-bearing: a pinned issue is hidden without it" ;;
esac

without_gates=$(bd list --all --limit 0 --json | python3 -c 'import json,sys
d=json.load(sys.stdin); rows=d if isinstance(d,list) else d.get("issues",d)
print(" ".join(sorted(r["id"] for r in rows)))')
case " $without_gates " in
    *" $native_gate "*) fail "--include-gates is not needed; the procedure over-explains" ;;
    *) pass "--include-gates is load-bearing: a native gate is hidden without it" ;;
esac

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

# The motivating defect, asserted directly: a human gate is open with no
# blocker, so the tracker offers it as ready work. Nothing in bd withholds it;
# only the CENSUS section does.
ready_ids=$(bd ready --json --exclude-type=epic | python3 -c 'import json,sys
d=json.load(sys.stdin); rows=d if isinstance(d,list) else d.get("issues",d)
print(" ".join(sorted(r["id"] for r in rows)))')
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
explain_ids=$(bd ready --explain --json | python3 -c 'import json,sys
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
bd update "$gate" --acceptance "ORIGINAL AUTHOR TEXT" >/dev/null
bd update "$gate" --acceptance "SECOND WRITE" >/dev/null
acc=$(bd show "$gate" --json | python3 -c 'import json,sys
d=json.load(sys.stdin)
r = d[0] if isinstance(d, list) else d
print(r.get("acceptance_criteria") or "")')
case "$acc" in
    *ORIGINAL*) fail "--acceptance now appends; the read-modify-write rule is obsolete" ;;
    *SECOND*) pass "--acceptance replaces the field, so the repair must round-trip it" ;;
    *) fail "could not read acceptance_criteria back: got '$acc'" ;;
esac
if bd update --help 2>&1 | grep -q -- '--acceptance-file'; then
    fail "--acceptance-file now exists; the one-shell-argument warning is obsolete"
else
    pass "--acceptance has no file form, unlike --body-file and --design-file"
fi

# Read-only mode is a tracker guarantee, not a promise in prose. The diagnostic
# entry point depends on it.
if bd --readonly update "$ready_issue" --set-metadata probe=1 >/dev/null 2>&1; then
    fail "--readonly permitted a write; the diagnostic entry point has no enforcement"
else
    pass "--readonly refuses a write"
fi
bd --readonly list --limit 5 >/dev/null 2>&1 && bd --readonly show "$ready_issue" >/dev/null 2>&1 \
    && pass "--readonly still permits the reads the census needs" \
    || fail "--readonly blocked a read the census needs"

# bd export is the non-mutation oracle. A filesystem diff is not: a plain read
# rewrites tracker bookkeeping without changing any issue field, so a suite
# built on file comparison fails on its first case for no real reason.
bd export > "$work/export.before" 2>/dev/null
bd show "$ready_issue" >/dev/null 2>&1
bd list --all --limit 0 >/dev/null 2>&1
bd export > "$work/export.after" 2>/dev/null
cmp -s "$work/export.before" "$work/export.after" \
    && pass "bd export is unchanged by reads, so it is a valid non-mutation oracle" \
    || fail "bd export changed across reads; the census has no non-mutation oracle"

if find .beads -newer "$work/export.before" -type f 2>/dev/null | grep -q .; then
    pass "reads do touch tracker files, so a filesystem diff is not an oracle"
else
    fail "reads no longer touch tracker files; a filesystem diff may now be valid"
fi

cd "$repo_root"

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
c1_ready=$( cd "$c1" && bd create "ready work" --silent )
c1_gate=$( cd "$c1" && bd create "[HUMAN] provision the deploy account" -l human-gate --silent )
c1_dep=$( cd "$c1" && bd create "ship the deploy step" --silent )
c1_prefix=$( cd "$c1" && bd create "[HUMAN] rotate the signing key" --silent )
c1_block=$( cd "$c1" && bd create "left blocked by an earlier run" --silent )
( cd "$c1" && bd dep "$c1_gate" --blocks "$c1_dep" >/dev/null )
( cd "$c1" && bd update "$c1_block" --status=blocked --set-metadata backlog_loop_run=OLD-RUN \
    --set-metadata backlog_loop_cause=needs-person --set-metadata backlog_loop_attempts=1 \
    --append-notes "post-merge verification failed: lint | none" >/dev/null )

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
c2_target=$( cd "$c2" && bd create "step behind a native gate" --silent )
c2_gate=$( cd "$c2" && bd gate create --type=human --blocks "$c2_target" 2>/dev/null \
    | sed -n 's/^.*Created gate \([A-Za-z0-9-]*\).*$/\1/p' )
( cd "$c2" && bd create "unrelated ready work" --silent >/dev/null )
( cd "$c2" && bd export > "$work/c2.before" 2>/dev/null )

out=$(run_census "$c2" loop)
expect_category "$out" "$c2_gate"   human-gate  "a native gate classifies as a human gate"
expect_category "$out" "$c2_target" dep-blocked "the step behind it stays dependency-blocked"

( cd "$c2" && bd export > "$work/c2.after" 2>/dev/null )
cmp -s "$work/c2.before" "$work/c2.after" \
    && pass "a loop-mode census removed no native gate edge" \
    || fail "a loop-mode census mutated the tracker around a native gate"

echo "  case: adoption gate holds the first run back"
c3=$(fresh_store)
c3_gate=$( cd "$c3" && bd create "[HUMAN] approve the production rollout" -l human-gate --silent )
c3_dep=$( cd "$c3" && bd create "wire the rollout flag" --silent )
( cd "$c3" && bd dep "$c3_gate" --blocks "$c3_dep" >/dev/null )
( cd "$c3" && bd export > "$work/c3.before" 2>/dev/null )

out=$(run_census "$c3" loop)
expect_category "$out" "$c3_gate" human-gate  "the labeled gate is recognized"
expect_category "$out" "$c3_dep"  dep-blocked "its dependent stays blocked while the convention is unadopted"

( cd "$c3" && bd export > "$work/c3.after" 2>/dev/null )
cmp -s "$work/c3.before" "$work/c3.after" \
    && pass "no hard-blocker label anywhere means no edge is removed" \
    || fail "the first run removed a gate edge with no hard-blocker label in the tracker"

echo "  case: a diagnostic run writes nothing"
c4=$(fresh_store)
c4_gate=$( cd "$c4" && bd create "[HUMAN] grant registry access" -l human-gate --silent )
c4_dep=$( cd "$c4" && bd create "publish the image" --silent )
c4_other=$( cd "$c4" && bd create "[HUMAN] declared hard blocker" -l human-gate,hard-blocker --silent )
( cd "$c4" && bd dep "$c4_gate" --blocks "$c4_dep" >/dev/null )
( cd "$c4" && bd export > "$work/c4.before" 2>/dev/null )

out=$(run_census "$c4" diagnostic)
expect_category "$out" "$c4_gate"  human-gate "the undeclared gate is recognized in diagnostic mode"
expect_category "$out" "$c4_other" human-gate "the declared gate is recognized too"

( cd "$c4" && bd export > "$work/c4.after" 2>/dev/null )
cmp -s "$work/c4.before" "$work/c4.after" \
    && pass "a diagnostic run left the tracker's issue records unchanged" \
    || fail "a diagnostic run mutated the tracker"

printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
[ "$failures" -eq 0 ] || exit 1
