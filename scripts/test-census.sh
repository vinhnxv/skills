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

# The ids this issue depends on, space-separated. `bd show --json` returns the
# edges as objects; the repair's read-back needs only their ids.
deps_of() {
    bd -C "$1" show "$2" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print(" ".join(x["id"] for x in (r.get("dependencies") or [])))'
}

# One field or metadata value off an issue, empty when unset. The repair is
# verified through these rather than through the census's own prose: the whole
# failure this suite guards is a run that reports a repair it did not perform.
acc_of() {
    bd -C "$1" show "$2" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print(r.get("acceptance_criteria") or "")'
}

meta_of() {
    bd -C "$1" show "$2" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print((r.get("metadata") or {}).get(sys.argv[1], ""))' "$3"
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

# Assert that dropping a flag hides exactly `missing` from the enumeration and
# nothing else, by comparing against the full expected survivor set. A mere
# "missing is absent" test is not enough: it passes on a query that returned
# nothing at all, or returned one unrelated row, for any reason having nothing
# to do with the flag under test -- and would then report that flag
# load-bearing while having proved nothing. Both `full` and `got` are
# space-separated id lists, deliberately left unquoted below so the shell
# splits them into words; ids are `[A-Za-z0-9-]` and cannot glob.
assert_hides_exactly() {
    full=$1; got=$2; missing=$3; ok_msg=$4; bad_msg=$5
    want=$(printf '%s\n' $full | grep -vx "$missing" | sort | tr '\n' ' ')
    have=$(printf '%s\n' $got | sort | tr '\n' ' ')
    if [ "$want" = "$have" ]; then
        pass "$ok_msg"
    else
        fail "$bad_msg (expected exactly [${want% }], got [${have% }])"
    fi
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
assert_hides_exactly "$all_ids" "$without_all" "$pinned" \
    "--all is load-bearing: a pinned issue, and only it, is hidden without it" \
    "--all does not hide exactly the pinned issue; the procedure's claim is wrong"

if [ -n "$native_gate" ]; then
    without_gates=$(bd -C "$store" list --all --limit 0 --json | sorted_ids_json)
    assert_hides_exactly "$all_ids" "$without_gates" "$native_gate" \
        "--include-gates is load-bearing: the native gate, and only it, is hidden without it" \
        "--include-gates does not hide exactly the native gate; the procedure's claim is wrong"

    # A native gate is a gate by type and carries no labels, which is exactly why
    # the repair rule must never fire on one: its blocking edge is what it is for,
    # and it has nothing to declare that edge with.
    # The match is checked before it is indexed. `$native_gate` parsed fine or
    # we would not be in this branch, but the enumeration that must contain it
    # is exactly what this suite exists to catch regressing -- and an
    # unguarded [0] turns that regression into an IndexError that aborts the
    # whole run, hiding every check after this one.
    gate_shape=$(enumerate "$store" | python3 -c "import json,sys
d=json.load(sys.stdin); rows=d if isinstance(d,list) else d.get('issues',d)
m=[x for x in rows if x['id']=='$native_gate']
print('%s %d' % (m[0].get('issue_type'), len(m[0].get('labels') or [])) if m else 'MISSING')")
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
acc=$(acc_of "$store" "$gate")
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

# A metadata KEY may not contain `-` or `:`, and every bd id contains `-`. That
# is why the gate repair indexes removed edges as a space-separated VALUE
# instead of one key per edge: a key-per-edge simply cannot be written.
if bd -C "$store" update "$ready_issue" --set-metadata "probe_key-with-dash=v" >/dev/null 2>&1; then
    fail "metadata keys now accept '-'; the repair could use one key per edge after all"
else
    pass "metadata keys reject '-', so a key per edge is not available to the repair"
fi
if bd -C "$store" update "$ready_issue" --set-metadata "probe_list=$gate $dependent" >/dev/null 2>&1; then
    pass "a metadata value holds a space-separated id list, which is what the repair indexes with"
else
    fail "a metadata value can no longer hold a space-separated id list"
fi

# `bd dep remove` takes the DEPENDENT first, then what it depends on. Reversing
# them is NOT an error: it exits 0 and prints a success line while leaving the
# edge in place. The gate repair ends in this command, so a swapped argument
# order would rewrite the gate's acceptance, quarantine the dependent, report a
# successful repair, and remove nothing -- which is why the procedure verifies
# the removal by re-reading the edge rather than by trusting the exit status.
bd -C "$store" dep remove "$gate" "$dependent" >/dev/null 2>&1
case " $(deps_of "$store" "$dependent") " in
    *" $gate "*) pass "bd dep remove silently no-ops on the reversed argument order" ;;
    *) fail "bd dep remove now honors <blocker> <dependent>; the repair's argument-order warning is obsolete" ;;
esac
bd -C "$store" dep remove "$dependent" "$gate" >/dev/null 2>&1
case " $(deps_of "$store" "$dependent") " in
    *" $gate "*) fail "bd dep remove <dependent> <blocker> did not remove the edge the repair depends on" ;;
    *) pass "bd dep remove <dependent> <blocker> removes the edge, which is the order the repair uses" ;;
esac

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

# The enumeration cannot answer the marker rows or the dependency rows on its
# own. `bd list --json` carries neither a `metadata` object nor a `dependencies`
# array -- only a `dependency_count` with nothing to resolve it against. The
# procedure said otherwise and told the census to read edges straight out of the
# enumeration, which no run could ever have done.
list_row=$(bd -C "$store" list --all --limit 0 --include-gates --json 2>/dev/null \
    | python3 -c 'import sys,json; r=json.load(sys.stdin); print(json.dumps(sorted(r[0].keys())) if r else "[]")')
case "$list_row" in
    *'"metadata"'*) fail "bd list now returns metadata; the per-key queries below are no longer needed" ;;
    *) pass "bd list carries no metadata, so marker rows need their own query" ;;
esac
case "$list_row" in
    *'"dependencies"'*) fail "bd list now returns dependencies; the census may read edges from it again" ;;
    *) pass "bd list carries no dependencies, so the census cannot walk edges from it" ;;
esac

# What the census uses instead. One query per marker key answers that key for
# the whole backlog, so the cost is flat in the number of keys rather than in
# the number of issues.
mk=$(fresh_store)
mk_marked=$(bd -C "$mk" create "carries a run marker" --silent)
mk_bare=$(bd -C "$mk" create "carries nothing" --silent)
bd -C "$mk" update "$mk_marked" --set-metadata backlog_loop_run=SOME-RUN >/dev/null
mk_hit=$(bd -C "$mk" list --has-metadata-key backlog_loop_run --json 2>/dev/null \
    | python3 -c 'import sys,json; print(" ".join(sorted(x["id"] for x in json.load(sys.stdin))))')
[ "$mk_hit" = "$mk_marked" ] \
    && pass "--has-metadata-key returns exactly the issues carrying that key" \
    || fail "--has-metadata-key returned '$mk_hit', wanted exactly '$mk_marked' (bare: $mk_bare)"

# Blocking propagates through a blocked parent, and an issue's own edge list
# cannot show it: the child's only edge is `parent-child` to the parent, whose
# own blocker lives somewhere else entirely. Re-deriving readiness from edges
# therefore disagrees with the tracker, which is why `--explain` is the
# authority for the dependency question rather than a source of names.
pp=$(fresh_store)
pp_parent=$(bd -C "$pp" create "parent that is itself blocked" --silent)
pp_child=$(bd -C "$pp" create "child whose only edge is parent-child" --parent "$pp_parent" --silent)
pp_blocker=$(bd -C "$pp" create "what blocks the parent" --silent)
bd -C "$pp" dep "$pp_blocker" --blocks "$pp_parent" >/dev/null
pp_blocked=$(bd -C "$pp" ready --explain --json 2>/dev/null \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(" ".join(sorted(x["id"] for x in d["blocked"])))')
case " $pp_blocked " in
    *" $pp_child "*) pass "--explain reports a child blocked through its blocked parent" ;;
    *) fail "--explain did not report $pp_child blocked; blocked set was '$pp_blocked'" ;;
esac

# ---------------------------------------------------------------------------
# PART 1b - tracker contract for repo-audit's write protocol.
#
# Everything above is a `bd` behaviour, not `backlog-loop` content, and this
# block adds to that same skill-agnostic half. A second always-skipping script
# and a second always-green CI step would prove the same thing twice and be
# read half as often.
#
# ALREADY PINNED ABOVE, and deliberately not repeated here: the metadata key
# charset (a key may hold no `-` or `:`, which is why the audit's fingerprint
# table lives in an issue body rather than in queryable metadata); `--readonly`
# refusing a write, which the audit's read-only mode rests on exactly as the
# census's diagnostic run does; `--has-metadata-key` returning exactly the
# issues carrying the key, which every audit-owned-issue listing uses;
# `--acceptance` replacing rather than appending and having no file form, which
# is why the audit composes the recipe and the re-verify instruction into one
# write; `bd dep remove` no-opping on the reversed argument order; and the
# `bd`-absent skip at the top of this file.
# ---------------------------------------------------------------------------

echo ""
echo "PART 1b - tracker contract for the audit's write protocol"

ra=$(fresh_store)

# A baseline the absence tests are read against. Concluding anything from an
# empty result without one is the failure mode this whole file exists to stop:
# a query that returns nothing because the store is empty satisfies every
# "X is absent" assertion ever written against it.
ra_open=$(bd -C "$ra" create "an ordinary open issue" --silent)
[ -n "$ra_open" ] || fail "could not create a baseline issue; every absence check below would be vacuous"

# --- closed rows and the default listing ---
ra_closed=$(bd -C "$ra" create "will be closed" --silent)
bd -C "$ra" close "$ra_closed" >/dev/null 2>&1
ra_default=$(bd -C "$ra" list --limit 0 --json 2>/dev/null | sorted_ids_json)
ra_allinc=$(bd -C "$ra" list --all --limit 0 --include-gates --json 2>/dev/null | sorted_ids_json)
case " $ra_default " in
    *" $ra_open "*) : ;;
    *) fail "the default listing omitted the baseline open issue; the closed-row check below is vacuous" ;;
esac
assert_hides_exactly "$ra_open $ra_closed" "$ra_default" "$ra_closed" \
    "a default listing hides a closed issue, and only it" \
    "a default listing no longer hides exactly the closed issue"
case " $ra_allinc " in
    *" $ra_closed "*) pass "an all-inclusive listing returns the closed issue, which is how the audit reconciles" ;;
    *) fail "an all-inclusive listing no longer returns a closed issue; reconciliation cannot see its own closures" ;;
esac

# --- --metadata-field matches a value exactly, never a prefix of it ---
bd -C "$ra" update "$ra_open" --set-metadata repo_audit_probe=alpha >/dev/null
mf_exact=$(bd -C "$ra" list --all --limit 0 --metadata-field repo_audit_probe=alpha --json 2>/dev/null | sorted_ids_json)
mf_partial=$(bd -C "$ra" list --all --limit 0 --metadata-field repo_audit_probe=alph --json 2>/dev/null | sorted_ids_json)
[ "$mf_exact" = "$ra_open" ] \
    && pass "--metadata-field matches an exact value" \
    || fail "--metadata-field did not return the issue carrying the exact value (got '$mf_exact')"
[ -z "$mf_partial" ] \
    && pass "--metadata-field does not match a prefix of the value, so a run token cannot collide with a longer one" \
    || fail "--metadata-field matched a prefix of the value (got '$mf_partial'); run-token queries can collide"

# --- the P0-P4 band round-trips, since severity maps directly onto it ---
band_ok=1
for band in P0 P1 P2 P3 P4; do
    bd -C "$ra" update "$ra_open" --priority "$band" >/dev/null 2>&1 || { band_ok=0; break; }
    got=$(bd -C "$ra" show "$ra_open" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print(r.get("priority",""))')
    case "$got" in
        "$band"|"${band#P}") : ;;
        *) band_ok=0; break ;;
    esac
done
[ "$band_ok" -eq 1 ] \
    && pass "--priority round-trips every value in the P0-P4 band" \
    || fail "--priority did not round-trip '$band' (read back '$got'); severity has no mapping"

# --- --estimate and --parent round-trip ---
bd -C "$ra" update "$ra_open" --estimate 45 >/dev/null 2>&1
est=$(bd -C "$ra" show "$ra_open" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print(r.get("estimated_minutes") or "")')
[ "$est" = "45" ] \
    && pass "--estimate round-trips, so the audit can size an issue for the consumer's batch budget" \
    || fail "--estimate did not round-trip (read back '$est')"

ra_epic=$(bd -C "$ra" create "durable per-dimension epic" --type epic --silent)
ra_child=$(bd -C "$ra" create "a finding under that epic" --parent "$ra_epic" --silent)
par=$(bd -C "$ra" show "$ra_child" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print(r.get("parent_id") or r.get("parent") or "")')
[ "$par" = "$ra_epic" ] \
    && pass "--parent round-trips, so a finding lands under its dimension epic" \
    || fail "--parent did not round-trip (read back '$par', wanted '$ra_epic')"

# --- --deps discovered-from: makes the provenance edge without withholding ---
ra_disc=$(bd -C "$ra" create "found while auditing" --deps "discovered-from:$ra_open" --silent)
case " $(deps_of "$ra" "$ra_disc") " in
    *" $ra_open "*) pass "--deps discovered-from: creates the provenance edge" ;;
    *) fail "--deps discovered-from: created no edge to $ra_open" ;;
esac
ra_ready=$(bd -C "$ra" ready --json 2>/dev/null | sorted_ids_json)
case " $ra_ready " in
    *" $ra_disc "*) pass "a discovered-from edge does not withhold the new issue from a ready listing" ;;
    *) fail "a discovered-from edge withheld $ra_disc from ready; every filed finding would be blocked" ;;
esac

# --- a multi-line acceptance value survives as ONE shell argument ---
bd -C "$ra" update "$ra_open" --acceptance "first line
second line
third line" >/dev/null
acc_lines=$(acc_of "$ra" "$ra_open" | wc -l | tr -d " ")
[ "$acc_lines" -ge 3 ] \
    && pass "--acceptance preserves a multi-line value passed as one argument" \
    || fail "--acceptance collapsed a multi-line value to $acc_lines line(s); the recipe cannot share the field"

# --- appending a note changes no other field ---
bd -C "$ra" export > "$work/ra.before" 2>/dev/null
before_acc=$(acc_of "$ra" "$ra_open")
bd -C "$ra" update "$ra_open" --append-notes "a note the audit appended" >/dev/null
bd -C "$ra" export > "$work/ra.after" 2>/dev/null
after_acc=$(acc_of "$ra" "$ra_open")
if cmp -s "$work/ra.before" "$work/ra.after"; then
    fail "appending a note left the export unchanged; the oracle cannot see a note at all"
elif [ "$before_acc" = "$after_acc" ] && [ -n "$before_acc" ]; then
    pass "appending a note changes the export and leaves acceptance intact"
else
    fail "appending a note altered acceptance_criteria ('$before_acc' -> '$after_acc')"
fi

# --- the empty-description asymmetry the index write is built around ---
if bd -C "$ra" update "$ra_open" --description "" >/dev/null 2>&1; then
    pass "update accepts an empty description inline, silently"
else
    fail "update now refuses an empty inline description; the index write's guard is obsolete"
fi
: > "$work/empty-body"
if bd -C "$ra" update "$ra_open" --body-file "$work/empty-body" >/dev/null 2>&1; then
    fail "update now accepts an empty body file; the asymmetry the index write guards against is gone"
else
    bd -C "$ra" update "$ra_open" --body-file "$work/empty-body" 2>&1 | grep -q -- "--allow-empty-description" \
        && pass "update refuses an empty body file and names --allow-empty-description as the bypass" \
        || fail "update refused an empty body file without naming the bypass flag"
fi
ec_inline=$(bd -C "$ra" create "created with an empty inline description" --description "" --silent 2>/dev/null || true)
ec_file=$(bd -C "$ra" create "created with an empty body file" --body-file "$work/empty-body" --silent 2>/dev/null || true)
if [ -n "$ec_inline" ] && [ -n "$ec_file" ]; then
    pass "CREATE accepts an empty body through both forms, which is why the index create is guarded by a read-back"
else
    fail "create no longer accepts an empty body through both forms (inline '$ec_inline', file '$ec_file'); the guard may be removable"
fi

# --- a deferred issue leaves ready and stays in an all-inclusive listing ---
ra_defer=$(bd -C "$ra" create "the audit index issue" --silent)
bd -C "$ra" update "$ra_defer" --set-metadata repo_audit_index=1 >/dev/null
bd -C "$ra" update "$ra_defer" --status=deferred --defer "+3650d" >/dev/null
ra_ready2=$(bd -C "$ra" ready --json 2>/dev/null | sorted_ids_json)
case " $ra_ready2 " in
    *" $ra_disc "*) : ;;
    *) fail "the ready listing lost an unrelated issue; the deferral check below is vacuous" ;;
esac
case " $ra_ready2 " in
    *" $ra_defer "*) fail "a deferred issue is still offered as ready; the index would be claimed and built" ;;
    *) pass "a deferred issue leaves the ready listing, which is what parks the index outside the consumer's reach" ;;
esac
ra_bykey=$(bd -C "$ra" list --all --limit 0 --include-gates --has-metadata-key repo_audit_index --json 2>/dev/null | sorted_ids_json)
[ "$ra_bykey" = "$ra_defer" ] \
    && pass "a deferred issue is still returned by an all-inclusive metadata-key listing, which is how the index is found" \
    || fail "an all-inclusive metadata-key listing returned '$ra_bykey', wanted exactly '$ra_defer'; the index becomes unfindable"

# --- a body at the index size cap round-trips byte-identically ---
python3 -c "import sys; sys.stdout.write('x' * (256 * 1024))" > "$work/big-body"
bd -C "$ra" update "$ra_open" --body-file "$work/big-body" >/dev/null 2>&1
bd -C "$ra" show "$ra_open" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
sys.stdout.write(r.get("description") or "")' > "$work/big-readback"
if cmp -s "$work/big-body" "$work/big-readback"; then
    pass "a body at the index size cap round-trips byte-identically through the file form"
else
    fail "a body at the index size cap did not round-trip ($(wc -c < "$work/big-body" | tr -d " ") bytes written, $(wc -c < "$work/big-readback" | tr -d " ") read back)"
fi

# --- what the two gate forms actually do ---
#
# The ordinary create form takes a gate type ALONGSIDE labels and metadata in
# one command. That is pinned explicitly because the gate type is absent from
# `--type`'s own help text, which makes it the behaviour here most likely to
# move without anyone meaning to move it -- and the audit files every `[HUMAN]`
# gate through this form.
ra_gate=$(bd -C "$ra" create "[HUMAN] rotate the credential at rc-1" \
    --type gate --labels human-gate --metadata '{"repo_audit_gate":"1"}' --silent 2>/dev/null || true)
if [ -z "$ra_gate" ]; then
    fail "bd create no longer accepts --type gate; every [HUMAN] gate the audit files has no write form"
else
    gate_row=$(bd -C "$ra" show "$ra_gate" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print("%s|%s|%s|%s" % (r.get("issue_type"), ",".join(sorted(r.get("labels") or [])), r.get("dependency_count", 0), (r.get("metadata") or {}).get("repo_audit_gate","")))')
    [ "$gate_row" = "gate|human-gate|0|1" ] \
        && pass "one create call makes a gate carrying its label and metadata and NO dependency edge" \
        || fail "the one-call gate form changed shape: got '$gate_row', wanted 'gate|human-gate|0|1'"

    ra_default2=$(bd -C "$ra" list --all --limit 0 --json 2>/dev/null | sorted_ids_json)
    case " $ra_default2 " in
        *" $ra_open "*) : ;;
        *) fail "the default listing lost the baseline issue; the gate-visibility checks are vacuous" ;;
    esac
    case " $ra_default2 " in
        *" $ra_gate "*) fail "a gate-type issue now appears in the default listing; the audit's own reconciliation would double-count it" ;;
        *) pass "a gate-type issue is absent from the default listing, so every audit lookup must query it separately" ;;
    esac
    case " $(bd -C "$ra" ready --json 2>/dev/null | sorted_ids_json) " in
        *" $ra_gate "*) fail "a gate-type issue is offered as ready work; the consumer would build it" ;;
        *) pass "a gate-type issue is withheld from ready by the tracker itself" ;;
    esac
    case " $(bd -C "$ra" list --type gate --json 2>/dev/null | sorted_ids_json) " in
        *" $ra_gate "*) pass "an explicit gate-type query returns it, which is the only way the audit sees its own gates" ;;
        *) fail "an explicit gate-type query no longer returns a gate; the audit cannot enumerate what it filed" ;;
    esac
fi

# The dedicated subcommand is NOT what the audit uses, and this pins why: it
# requires an issue to block and offers no way to set a title, a label, a body,
# a parent, or metadata -- so a gate created through it could carry neither the
# operator's instructions nor the audit's own marker.
gate_help=$(bd gate create --help 2>&1)
gc_missing=""
for flag in --title --labels --description --parent --metadata; do
    printf '%s' "$gate_help" | grep -q -- "$flag" || gc_missing="$gc_missing $flag"
done
printf '%s' "$gate_help" | grep -q -- "--blocks" \
    && pass "bd gate create still requires an issue to block" \
    || fail "bd gate create no longer takes --blocks; the reason the audit avoids it may be gone"
[ "$gc_missing" = " --title --labels --description --parent --metadata" ] \
    && pass "bd gate create offers no title, label, body, parent or metadata flag, which is why the audit uses create instead" \
    || fail "bd gate create's flag set changed; it now offers$(printf '%s' " --title --labels --description --parent --metadata" | tr " " "\n" | grep -vx "$(printf '%s' "$gc_missing" | tr " " "\n")" | tr "\n" " ")"

if [ "$contract_only" -eq 1 ]; then
    printf '\n%d check(s), %d failure(s) [contract only]\n' "$checks" "$failures"
    [ "$failures" -eq 0 ] || exit 1
    exit 0
fi

echo ""
echo "PART 2 - classification"

# The fifteen categories the CENSUS section files every issue under, in its
# own precedence order. Kept here so a rename in the procedure fails this suite
# rather than silently shrinking what it counts.
CATEGORIES='human-gate|label-defect|quarantined|claimed-other-run|external-wip|self-blocked-needs-person|self-blocked-transient|claimed-this-run|abandoned-claim|legacy-blocked|dep-blocked|hooked|pinned|deferred|ready'

host_cli=""
for candidate in claude codex; do
    command -v "$candidate" >/dev/null 2>&1 && { host_cli=$candidate; break; }
done

# `timeout` is GNU coreutils and is absent from a stock macOS, where Homebrew
# installs the same binary as `gtimeout`. Probe rather than assume: an
# unresolved `timeout` would fail every case with "command not found" folded
# into an empty census, which reads as a classification bug rather than a
# missing prerequisite.
deadline=""
for candidate in timeout gtimeout; do
    command -v "$candidate" >/dev/null 2>&1 && { deadline=$candidate; break; }
done

if [ -z "$host_cli" ] || [ -z "$deadline" ]; then
    [ -z "$host_cli" ] \
        && echo "SKIP: no host CLI on PATH; classification needs one to run the census." \
        || echo "SKIP: no timeout/gtimeout on PATH; classification needs a deadline wrapper."
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
    # Capture first, filter second, and check the status in between. Piping the
    # host CLI straight into sed discards its exit status, so a run the
    # deadline killed part-way through still passes its partial output to the
    # filter -- and if both markers happened to be emitted before the kill, a
    # dead run reports a clean census.
    # `--allowedTools 'Bash(bd:*)'` is load-bearing and narrowly scoped. Without
    # it the host CLI's permission classifier denies every tracker write, so a
    # loop-mode case cannot mutate anything -- and every "nothing was mutated"
    # assertion below then passes for that reason alone, proving nothing about
    # the procedure. Scoping it to `bd` keeps the child unable to touch
    # anything else. Codex takes different flags, so it stays read-only there
    # and the write-capability control below reports those cases as unproven.
    # Built with `set --` rather than an unquoted variable: word splitting on
    # an unquoted expansion is a `sh` behaviour that zsh does not share, so the
    # variable form silently passes "--allowedTools Bash(bd:*)" as ONE argument
    # under some shells and the CLI rejects it. `store_dir` and `mode` are
    # already saved above, so reusing the positional parameters here is safe.
    if [ "$host_cli" = "claude" ]; then
        set -- --allowedTools 'Bash(bd:*)'
    else
        set --
    fi
    raw=$("$deadline" 600 "$host_cli" -p "$prompt" "$@" 2>&1); status=$?
    # The census is executed by a model, so a case can fail because the
    # procedure is wrong OR because that run skipped a pass it should have run.
    # Those two look identical in the pass/fail line, and re-running the suite
    # to find out costs an hour. Setting CENSUS_RAW_DIR keeps each run's whole
    # transcript, which is the only artifact that tells them apart. Unset by
    # default: CI wants the verdict, not the transcripts.
    if [ -n "${CENSUS_RAW_DIR:-}" ]; then
        mkdir -p "$CENSUS_RAW_DIR"
        # Named after the store, not a counter: this function runs inside a
        # command substitution, so a counter increments in a subshell, resets on
        # the next call, and every case overwrites the previous one's
        # transcript. Each case gets its own `fresh_store`, so its basename is
        # already unique and survives the subshell.
        printf '%s\n' "$raw" > "$CENSUS_RAW_DIR/${store_dir##*/}-$mode.log"
    fi
    if [ "$status" -ne 0 ]; then
        echo "__CENSUS_RUNNER_FAILED__ $host_cli exited $status"
        return
    fi
    printf '%s\n' "$raw" \
        | sed -n '/^CENSUS-BEGIN$/,/^CENSUS-END$/p' \
        | sed -e '/^CENSUS-BEGIN$/d' -e '/^CENSUS-END$/d'
}

# Gate every case on the runner having actually produced a census. Without this
# a failed or empty run falls through to expect_category, which reports a pile
# of category mismatches and buries the real cause.
census_usable() {
    case "$1" in
        __CENSUS_RUNNER_FAILED__*)
            fail "census runner failed:${1#__CENSUS_RUNNER_FAILED__}"; return 1 ;;
        "")
            fail "census emitted nothing; the runner or the marker contract is broken"; return 1 ;;
    esac
    return 0
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

echo "  case: an adopted repository repairs an undeclared gate edge (write control)"
# This runs FIRST because it is the positive control for every case after it.
# It is the only case in which a repair is supposed to fire, so it is also the
# only proof that this run can mutate a tracker at all. Every later case
# asserts that something was NOT changed, and under a host CLI that denies
# writes those assertions pass no matter what the procedure does -- the exact
# silent pass this suite exists to catch. `write_proven` carries the result
# forward so those cases report "unproven" instead of a false green.
c5=$(fresh_store)
c5_adopted=$(bd -C "$c5" create "[HUMAN] declared blocker elsewhere" -l human-gate,hard-blocker --silent)
c5_gate=$(bd -C "$c5" create "[HUMAN] provision the staging account" -l human-gate --silent)
c5_dep=$(bd -C "$c5" create "wire the staging deploy" --silent)
bd -C "$c5" dep "$c5_gate" --blocks "$c5_dep" >/dev/null
bd -C "$c5" update "$c5_gate" --acceptance "AUTHOR ORIGINAL ACCEPTANCE" >/dev/null

out=$(run_census "$c5" loop)
census_usable "$out" || out=""
expect_category "$out" "$c5_gate"    human-gate "the undeclared gate is still classified a human gate"
expect_category "$out" "$c5_adopted" human-gate "the declared gate elsewhere is what adopts the convention"

write_proven=0
case " $(deps_of "$c5" "$c5_dep") " in
    *" $c5_gate "*) fail "the undeclared gate edge survived a repair in an adopted repository" ;;
    *) write_proven=1; pass "an adopted repository removes the undeclared gate edge" ;;
esac

c5_acc=$(acc_of "$c5" "$c5_gate")
case "$c5_acc" in
    *"AUTHOR ORIGINAL ACCEPTANCE"*)
        pass "the gate's original acceptance text survived the release-condition write" ;;
    *) fail "the repair destroyed the gate's acceptance text: got '$c5_acc'" ;;
esac
[ "$c5_acc" != "AUTHOR ORIGINAL ACCEPTANCE" ] \
    && pass "a release condition was written alongside the author's text" \
    || fail "the edge was repaired but no release condition was recorded on the gate"

[ -n "$(meta_of "$c5" "$c5_dep" backlog_loop_quarantine)" ] \
    && pass "the freed issue is quarantined, so no run can build it yet" \
    || fail "the freed issue carries no quarantine; the loop can ship the work the gate held"

case " $(meta_of "$c5" "$c5_gate" backlog_loop_edge_removed) " in
    *" $c5_dep "*) pass "the gate indexes the removed edge, so a re-run skips it" ;;
    *) fail "the gate has no removal index for the freed issue; a re-run would repair it twice" ;;
esac

echo "  case: mixed backlog, one category per issue"
c1=$(fresh_store)
c1_ready=$(bd -C "$c1" create "ready work" --silent)
c1_gate=$(bd -C "$c1" create "[HUMAN] provision the deploy account" -l human-gate --silent)
c1_dep=$(bd -C "$c1" create "ship the deploy step" --silent)
c1_prefix=$(bd -C "$c1" create "[HUMAN] rotate the signing key" --silent)
c1_block=$(bd -C "$c1" create "left blocked by an earlier run" --silent)
# A block from before any marker existed: blocked, no metadata at all, and no
# dependency edge to explain it. This is the population the whole section was
# written for, and it is recognized from the ABSENCE of both fields -- never
# from the note, which a person may have written and which no query can trust.
c1_legacy=$(bd -C "$c1" create "blocked by a loop that recorded only a note" --silent)
bd -C "$c1" dep "$c1_gate" --blocks "$c1_dep" >/dev/null
bd -C "$c1" update "$c1_legacy" --status=blocked \
    --append-notes "backlog-loop cannot ship this unit: release-boundary conflict" >/dev/null
bd -C "$c1" update "$c1_block" --status=blocked --set-metadata backlog_loop_run=OLD-RUN \
    --set-metadata backlog_loop_cause=needs-person --set-metadata backlog_loop_attempts=1 \
    --append-notes "post-merge verification failed: lint | none" >/dev/null

out=$(run_census "$c1" diagnostic)
if census_usable "$out"; then
    expect_category "$out" "$c1_ready"  ready         "a dependency-free open issue is ready"
    expect_category "$out" "$c1_gate"   human-gate    "a labeled gate is a human gate, never ready"
    expect_category "$out" "$c1_dep"    dep-blocked   "the issue behind the gate is dependency-blocked"
    expect_category "$out" "$c1_prefix" label-defect  "a [HUMAN] prefix with no label is a labeling defect"
    expect_category "$out" "$c1_block"  self-blocked-needs-person \
        "a post-merge verification block is never transient"
    expect_category "$out" "$c1_legacy" legacy-blocked \
        "a blocked issue with no marker and no edge is legacy, not dependency-blocked"

    # Count the data shape, not the word "census": the header is prose the
    # model composes, and a counter that merely looks for a prefix reports one
    # issue too many the moment that wording drifts. Naming the categories
    # makes the count independent of the header entirely, and makes this line
    # fail loudly if the procedure ever renames one.
    emitted=$(printf '%s\n' "$out" | grep -cE "^census +[^ |]+ +\\| +($CATEGORIES) +\\|" || true)
    [ "$emitted" -eq 6 ] \
        && pass "exactly one line per non-closed non-epic issue" \
        || fail "expected 6 census lines, got $emitted"
fi

echo "  case: a native gate is a gate and is never repaired"
c2=$(fresh_store)
c2_target=$(bd -C "$c2" create "step behind a native gate" --silent)
c2_gate=$(bd -C "$c2" gate create --type=human --blocks "$c2_target" 2>/dev/null | gate_id)
[ -n "$c2_gate" ] || fail "could not read a gate id out of 'bd gate create' for this case"
bd -C "$c2" create "unrelated ready work" --silent >/dev/null
bd -C "$c2" export > "$work/c2.before" 2>/dev/null

out=$(run_census "$c2" loop)
census_usable "$out" || out=""
expect_category "$out" "$c2_gate"   human-gate  "a native gate classifies as a human gate"
expect_category "$out" "$c2_target" dep-blocked "the step behind it stays dependency-blocked"

bd -C "$c2" export > "$work/c2.after" 2>/dev/null
if [ "$write_proven" -eq 1 ]; then
    cmp -s "$work/c2.before" "$work/c2.after" \
        && pass "a loop-mode census removed no native gate edge" \
        || fail "a loop-mode census mutated the tracker around a native gate"
else
    fail "unproven -- a loop-mode census removed no native gate edge: no case in this run showed the census can write at all, so an unchanged tracker proves nothing"
fi

echo "  case: adoption gate holds the first run back"
c3=$(fresh_store)
c3_gate=$(bd -C "$c3" create "[HUMAN] approve the production rollout" -l human-gate --silent)
c3_dep=$(bd -C "$c3" create "wire the rollout flag" --silent)
bd -C "$c3" dep "$c3_gate" --blocks "$c3_dep" >/dev/null
bd -C "$c3" export > "$work/c3.before" 2>/dev/null

out=$(run_census "$c3" loop)
census_usable "$out" || out=""
expect_category "$out" "$c3_gate" human-gate  "the labeled gate is recognized"
expect_category "$out" "$c3_dep"  dep-blocked "its dependent stays blocked while the convention is unadopted"

bd -C "$c3" export > "$work/c3.after" 2>/dev/null
if [ "$write_proven" -eq 1 ]; then
    cmp -s "$work/c3.before" "$work/c3.after" \
        && pass "no hard-blocker label anywhere means no edge is removed" \
        || fail "the first run removed a gate edge with no hard-blocker label in the tracker"
else
    fail "unproven -- no hard-blocker label anywhere means no edge is removed: no case in this run showed the census can write at all, so an unchanged tracker proves nothing"
fi

echo "  case: a diagnostic run writes nothing"
c4=$(fresh_store)
c4_gate=$(bd -C "$c4" create "[HUMAN] grant registry access" -l human-gate --silent)
c4_dep=$(bd -C "$c4" create "publish the image" --silent)
c4_other=$(bd -C "$c4" create "[HUMAN] declared hard blocker" -l human-gate,hard-blocker --silent)
bd -C "$c4" dep "$c4_gate" --blocks "$c4_dep" >/dev/null
bd -C "$c4" export > "$work/c4.before" 2>/dev/null

out=$(run_census "$c4" diagnostic)
census_usable "$out" || out=""
expect_category "$out" "$c4_gate"  human-gate "the undeclared gate is recognized in diagnostic mode"
expect_category "$out" "$c4_other" human-gate "the declared gate is recognized too"

bd -C "$c4" export > "$work/c4.after" 2>/dev/null
if [ "$write_proven" -eq 1 ]; then
    cmp -s "$work/c4.before" "$work/c4.after" \
        && pass "a diagnostic run left the tracker's issue records unchanged" \
        || fail "a diagnostic run mutated the tracker"
else
    fail "unproven -- a diagnostic run left the tracker's issue records unchanged: no case in this run showed the census can write at all, so an unchanged tracker proves nothing"
fi

printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
[ "$failures" -eq 0 ] || exit 1
