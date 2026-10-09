#!/bin/sh
# Prove that backlog-loop's CENSUS section classifies a real Beads backlog.
#
# Usage: test-census.sh [--full | --contract-only]
#
# With no argument it runs the deterministic half only, which is safe anywhere.
# `--contract-only` says the same thing explicitly. `--full` also runs PART 2,
# which drives a model, so it is non-deterministic and slow, and a gate that
# goes yellow on every third run stops being read: run it by hand before
# changing the CENSUS section, or nightly. Any other argument exits 2, and so
# does `--full` together with `--contract-only`.
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
usage() { echo "usage: test-census.sh [--full | --contract-only]" >&2; exit 2; }
contract_only=1
asked_contract=0
for arg in "$@"; do
    case "$arg" in
        --full) contract_only=0 ;;
        --contract-only) asked_contract=1 ;;
        *) usage ;;
    esac
done
[ "$contract_only" -eq 1 ] || [ "$asked_contract" -eq 0 ] || usage

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
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT HUP TERM

failures=0
checks=0

pass() { checks=$((checks + 1)); printf '  ok: %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL: %s\n' "$1"; }

# `bd export` of one store into a file: the non-mutation oracle. Snapshot a
# store before and after an operation and `cmp -s` the two files.
export_of() { # store, file
    bd -C "$1" export > "$2" 2>/dev/null
}

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
    # Keep bd's output for the failure path only: this runs inside a command
    # substitution, so a failed init cannot `fail` the case, and swallowing its
    # stderr would leave a suite that stops with no reason. Print it, then
    # return non-zero so `set -e` ends the run.
    if ! ( cd "$dir" && bd init --prefix cx ) > "$dir.init.log" 2>&1; then
        echo "FAIL: bd init --prefix cx failed in $dir:" >&2
        cat "$dir.init.log" >&2
        return 1
    fi
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
    field_of "$1" "$2" acceptance_criteria
}

meta_of() {
    bd -C "$1" show "$2" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print((r.get("metadata") or {}).get(sys.argv[1], ""))' "$3"
}

# Any top-level field off an issue, empty when absent. The residue repair's
# whole contract is that it strips metadata and leaves the parking status and
# the note record standing, so proving it needs a reader that is not `meta_of`.
field_of() {
    bd -C "$1" show "$2" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print(r.get(sys.argv[1]) or "")' "$3"
}

# An issue's labels, sorted and space-separated, empty when it has none. The
# gate check below reads the label back rather than trusting the create call's
# exit status: the loop's human-gate rule is keyed on it.
labels_of() {
    bd -C "$1" show "$2" --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
print(" ".join(sorted(r.get("labels") or [])))'
}

# The database a checkout resolves to. Two checkouts that share a store must
# report the same path, or an issue filed from one is invisible to the other.
where_db() {
    bd -C "$1" where --json 2>/dev/null | python3 -c 'import json,sys
print(json.load(sys.stdin).get("database_path", ""))'
}

# The exit status of a command that is expected to fail, without tripping
# `set -e`. The guarded writes below are pinned by exit status as well as by
# what they leave behind, because the procedure branches on 13.
status_of() {
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}

# An ISO UTC timestamp a given number of minutes in the past. The liveness test
# measures the heartbeat against the wall clock, so both the dead and the live
# marker below are computed rather than written as literals: a frozen timestamp
# would decide those cases by how long ago this suite was edited.
iso_ago() {
    python3 -c 'import datetime,sys
print((datetime.datetime.now(datetime.timezone.utc)
       - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"
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
export_of "$store" "$work/export.before"
bd -C "$store" show "$ready_issue" >/dev/null 2>&1
bd -C "$store" list --all --limit 0 >/dev/null 2>&1
export_of "$store" "$work/export.after"
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
# PART 1b - tracker contract for source-to-beads.
#
# The general writer needs a complete view of closed and gate issues for
# deduplication, exact metadata matching, and one-call human-gate creation.
echo ""
echo "PART 1b - tracker contract for source-to-beads"

sb=$(fresh_store)
sb_body="$work/source-to-beads-body.md"
printf 'Source: plan U1\nAction: implement one bounded unit\n' > "$sb_body"
sb_open=$(bd -C "$sb" create "Implement plan unit" --type task --body-file "$sb_body" \
    --acceptance "The unit's verification passes" \
    --metadata '{"source_to_beads_key":"plan-u1","source_to_beads_source":"plan.md#u1"}' --silent)
sb_closed=$(bd -C "$sb" create "Completed prior unit" --type task --silent)
bd -C "$sb" close "$sb_closed" >/dev/null

sb_all=$(bd -C "$sb" list --all --include-gates --limit 0 --json | sorted_ids_json)
case " $sb_all " in
    *" $sb_open "*) sb_has_open=1 ;;
    *) sb_has_open=0 ;;
esac
case " $sb_all " in
    *" $sb_closed "*) sb_has_closed=1 ;;
    *) sb_has_closed=0 ;;
esac
[ "$sb_has_open" -eq 1 ] && [ "$sb_has_closed" -eq 1 ] \
    && pass "all-state listing includes open and closed work for deduplication" \
    || fail "all-state listing omits an issue needed for deduplication"

sb_exact=$(bd -C "$sb" list --all --include-gates --limit 0 --metadata-field source_to_beads_key=plan-u1 --json | sorted_ids_json)
sb_partial=$(bd -C "$sb" list --all --include-gates --limit 0 --metadata-field source_to_beads_key=plan-u --json | sorted_ids_json)
[ "$sb_exact" = "$sb_open" ] && [ -z "$sb_partial" ] \
    && pass "source key lookup matches an exact value" \
    || fail "source key lookup is not exact"

[ "$(meta_of "$sb" "$sb_open" source_to_beads_source)" = "plan.md#u1" ] \
    && [ "$(acc_of "$sb" "$sb_open")" = "The unit's verification passes" ] \
    && pass "source metadata and acceptance criteria round-trip at creation" \
    || fail "source metadata or acceptance criteria did not round-trip"

sb_gate=$(bd -C "$sb" create "[HUMAN] Grant staging access" --type gate \
    --labels human-gate --body-file "$sb_body" \
    --acceptance "Agent can verify access" \
    --metadata '{"source_to_beads_key":"plan-access","source_to_beads_source":"plan.md#access"}' --silent 2>/dev/null || true)
if [ -z "$sb_gate" ]; then
    fail "bd create cannot create a complete standalone human gate"
else
    gate_type=$(field_of "$sb" "$sb_gate" issue_type)
    gate_parent=$(field_of "$sb" "$sb_gate" parent)
    gate_key=$(meta_of "$sb" "$sb_gate" source_to_beads_key)
    [ "$gate_type" = gate ] && [ -z "$gate_parent" ] && [ "$gate_key" = plan-access ] \
        && pass "one create call persists a standalone gate with source identity" \
        || fail "gate type, parent, or source identity did not round-trip"
    [ "$(labels_of "$sb" "$sb_gate")" = human-gate ] \
        && pass "a gate created with --labels reads back exactly the human-gate label" \
        || fail "gate label did not round-trip: got '$(labels_of "$sb" "$sb_gate")', expected 'human-gate'"
    sb_gates=$(bd -C "$sb" list --all --include-gates --limit 0 --json | sorted_ids_json)
    case " $sb_gates " in
        *" $sb_gate "*) pass "explicit gate listing includes the human gate" ;;
        *) fail "explicit gate listing omits the human gate" ;;
    esac
fi

# source-to-beads names each issue `<prefix>-s<first 8 hex of sha256(key)>`, with
# the key `s2b1|<repo-id>|<anchor>|<action-kind>`. `s2b_repo_id` and `s2b_id`
# restate the procedure's grammar, so an SSH clone and an HTTPS clone of one
# repository must land on one id, and the second create must be refused.
s2b_repo_id() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E \
        -e 's#^[a-z][a-z0-9+.-]*://##' -e 's#^[^@/]*@##' \
        -e 's#^([^/:]+):[0-9]+/#\1/#' -e 's#^([^/:]+):#\1/#' \
        -e 's#/$##' -e 's#\.git$##'
}
s2b_id() {
    printf '%s' "$2" | python3 -c 'import hashlib,sys
print("%s-s%s" % (sys.argv[1], hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8]))' "$1"
}
s2b_ssh=$(s2b_repo_id 'git@GitHub.com:Org/Repo.git')
s2b_https=$(s2b_repo_id 'https://github.com/Org/Repo')
s2b_ssh_url=$(s2b_repo_id 'ssh://git@github.com:22/Org/Repo.git')
[ "$s2b_ssh" = github.com/org/repo ] && [ "$s2b_https" = "$s2b_ssh" ] && [ "$s2b_ssh_url" = "$s2b_ssh" ] \
    && pass "SSH (scp-style and ssh://) and HTTPS origins normalize to one repo-id" \
    || fail "repo-id differs across remotes: scp '$s2b_ssh', https '$s2b_https', ssh:// '$s2b_ssh_url'"

s2b_store=$(fresh_store)
s2b_key_ssh="s2b1|$s2b_ssh|RA-0123456789|fix"
s2b_key_https="s2b1|$s2b_https|RA-0123456789|fix"
s2b_id_ssh=$(s2b_id cx "$s2b_key_ssh")
s2b_id_https=$(s2b_id cx "$s2b_key_https")
s2b_made=$(bd -C "$s2b_store" create "Fix the audited defect" --type bug --id "$s2b_id_ssh" \
    --body-file "$sb_body" --metadata "{\"source_to_beads_key\":\"$s2b_key_ssh\"}" --silent 2>/dev/null || true)
export_of "$s2b_store" "$work/export.s2b.before"
s2b_rc=$(status_of bd -C "$s2b_store" create "Fix the audited defect, reworded" --type bug --id "$s2b_id_https" \
    --body-file "$sb_body" --metadata "{\"source_to_beads_key\":\"$s2b_key_https\"}" --silent)
export_of "$s2b_store" "$work/export.s2b.after"
[ "$s2b_id_ssh" = "$s2b_id_https" ] && [ "$s2b_made" = "$s2b_id_ssh" ] && [ "$s2b_rc" -ne 0 ] \
    && cmp -s "$work/export.s2b.before" "$work/export.s2b.after" \
    && [ "$(field_of "$s2b_store" "$s2b_id_ssh" title)" = "Fix the audited defect" ] \
    && [ "$(meta_of "$s2b_store" "$s2b_id_ssh" source_to_beads_key)" = "$s2b_key_ssh" ] \
    && pass "a second create under the key derived from the HTTPS origin is refused and the first issue is unchanged" \
    || fail "derived-id create-once: ssh id '$s2b_id_ssh', https id '$s2b_id_https', first create '$s2b_made', second exit $s2b_rc, or the first issue changed"

# A gate filed under a derived id keeps its native shape, its label, and the
# create-once guarantee.
s2b_gate_key="s2b1|$s2b_ssh|RA-0123456789|human"
s2b_gate_id=$(s2b_id cx "$s2b_gate_key")
s2b_gate=$(bd -C "$s2b_store" create "[HUMAN] Decide the release channel" --type gate --id "$s2b_gate_id" \
    --labels human-gate --body-file "$sb_body" \
    --metadata "{\"source_to_beads_key\":\"$s2b_gate_key\"}" --silent 2>/dev/null || true)
s2b_gate_rc=$(status_of bd -C "$s2b_store" create "[HUMAN] Decide the release channel" --type gate --id "$s2b_gate_id" --labels human-gate --silent)
[ "$s2b_gate" = "$s2b_gate_id" ] && [ "$(field_of "$s2b_store" "$s2b_gate_id" issue_type)" = gate ] \
    && [ "$(labels_of "$s2b_store" "$s2b_gate_id")" = human-gate ] \
    && [ "$(meta_of "$s2b_store" "$s2b_gate_id" source_to_beads_key)" = "$s2b_gate_key" ] \
    && [ "$s2b_gate_rc" -ne 0 ] \
    && pass "a gate created under a derived id reads back as a labeled gate and a repeat create is refused" \
    || fail "derived-id gate: id '$s2b_gate', type '$(field_of "$s2b_store" "$s2b_gate_id" issue_type)', labels '$(labels_of "$s2b_store" "$s2b_gate_id")', repeat exit $s2b_gate_rc"

# ---------------------------------------------------------------------------
# PART 1c - tracker contract for guarded writes, liveness, adoption, and ids.
#
# The loop adopts a parked PR with one guarded write, refreshes a lease with
# `bd heartbeat`, and source-to-beads creates issues under a deterministic id.
# Each of those leans on a behavior that is absent from `--help` or easy to
# misread, so each is pinned here by what the tracker does rather than by what
# the procedure says it does. Every refusal is paired with a write that the same
# guard permits, so a guard that rejects everything cannot pass.
echo ""
echo "PART 1c - tracker contract for guards, liveness, adoption, and ids"

gw=$(fresh_store)

# A status guard that does not match writes nothing and exits 13.
gw_issue=$(bd -C "$gw" create "guarded write target" --silent)
export_of "$gw" "$work/export.gw.before"
rc=$(status_of bd -C "$gw" update "$gw_issue" --if-status blocked --set-metadata probe=1)
export_of "$gw" "$work/export.gw.after"
[ "$rc" -eq 13 ] && cmp -s "$work/export.gw.before" "$work/export.gw.after" \
    && [ -z "$(meta_of "$gw" "$gw_issue" probe)" ] \
    && pass "--if-status mismatch exits 13 and writes nothing" \
    || fail "--if-status mismatch: exit $rc, or the store changed (expected exit 13, export unchanged)"
rc=$(status_of bd -C "$gw" update "$gw_issue" --if-status open --set-metadata probe=1)
[ "$rc" -eq 0 ] && [ "$(meta_of "$gw" "$gw_issue" probe)" = 1 ] \
    && pass "--if-status that matches performs the write" \
    || fail "--if-status that matches did not write: exit $rc"

# An assignee guard likewise. The empty string is the "unclaimed" value the
# source-to-beads update path relies on.
export_of "$gw" "$work/export.gw.before"
rc=$(status_of bd -C "$gw" update "$gw_issue" --if-assignee alice --set-metadata probe=2)
export_of "$gw" "$work/export.gw.after"
[ "$rc" -eq 13 ] && cmp -s "$work/export.gw.before" "$work/export.gw.after" \
    && [ "$(meta_of "$gw" "$gw_issue" probe)" = 1 ] \
    && pass "--if-assignee mismatch exits 13 and writes nothing" \
    || fail "--if-assignee mismatch: exit $rc, or the store changed (expected exit 13, export unchanged)"
rc=$(status_of bd -C "$gw" update "$gw_issue" --if-assignee '' --if-status open --set-metadata probe=3)
[ "$rc" -eq 0 ] && [ "$(meta_of "$gw" "$gw_issue" probe)" = 3 ] \
    && pass "--if-assignee '' with --if-status open writes to an unclaimed open issue" \
    || fail "--if-assignee '' with --if-status open did not write: exit $rc"

# A heartbeat refreshes a lease its owner holds. Nobody else may refresh it, and
# an issue that is not in_progress has no lease to refresh.
hb=$(fresh_store)
hb_issue=$(bd -C "$hb" create "leased work" --silent)
[ "$(status_of bd -C "$hb" --actor alice heartbeat "$hb_issue")" -ne 0 ] \
    && pass "bd heartbeat refuses an open, unclaimed issue" \
    || fail "bd heartbeat succeeded on an open issue that nobody holds"
bd -C "$hb" --actor alice update "$hb_issue" --claim >/dev/null 2>&1
[ "$(status_of bd -C "$hb" --actor alice heartbeat "$hb_issue")" -eq 0 ] \
    && pass "bd heartbeat succeeds for the actor holding the issue in_progress" \
    || fail "bd heartbeat failed for the owner of an in_progress issue"
[ "$(status_of bd -C "$hb" --actor bob heartbeat "$hb_issue")" -ne 0 ] \
    && pass "bd heartbeat refuses an actor that does not own the issue" \
    || fail "bd heartbeat let a non-owner refresh the lease"

# The adoption of a parked PR (KTD10). `bd heartbeat` refuses a blocked issue
# and --claim cannot be combined with a guard, so adoption is one guarded write
# that names the status and assignee itself; a successful heartbeat afterwards
# proves the adopter now holds a lease it can keep alive.
ad=$(fresh_store)
ad_issue=$(bd -C "$ad" create "parked pull request" --silent)
bd -C "$ad" update "$ad_issue" --status=blocked --set-metadata backlog_loop_run=OLD-RUN \
    --append-notes "merge blocked: trunk moved | none" >/dev/null
[ "$(field_of "$ad" "$ad_issue" status)" = blocked ] \
    && [ "$(status_of bd -C "$ad" --actor alice heartbeat "$ad_issue")" -ne 0 ] \
    && pass "bd heartbeat refuses a blocked issue, so a parked PR cannot be adopted by heartbeat alone" \
    || fail "bd heartbeat accepted a blocked issue, or the parked issue is not blocked"
export_of "$ad" "$work/export.ad.before"
rc=$(status_of bd -C "$ad" --actor alice update "$ad_issue" --claim --if-status blocked)
export_of "$ad" "$work/export.ad.after"
[ "$rc" -ne 0 ] && cmp -s "$work/export.ad.before" "$work/export.ad.after" \
    && pass "--claim cannot be combined with --if-status, and the refusal writes nothing" \
    || fail "--claim with --if-status: exit $rc, or the store changed (expected a refusal, export unchanged)"
ad_write() {
    bd -C "$ad" update "$ad_issue" --if-status blocked --status=in_progress --assignee "$1" \
        --set-metadata "backlog_loop_run=$2" --set-metadata "backlog_loop_heartbeat=$3 | live"
}
rc=$(status_of ad_write alice NEW-RUN "$(iso_ago 0)")
[ "$rc" -eq 0 ] \
    && [ "$(field_of "$ad" "$ad_issue" status)" = in_progress ] \
    && [ "$(field_of "$ad" "$ad_issue" assignee)" = alice ] \
    && [ "$(meta_of "$ad" "$ad_issue" backlog_loop_run)" = NEW-RUN ] \
    && pass "the adoption write moves a blocked issue to in_progress under the adopter and stamps the run" \
    || fail "the adoption write did not land: exit $rc, status '$(field_of "$ad" "$ad_issue" status)', assignee '$(field_of "$ad" "$ad_issue" assignee)'"
[ "$(status_of bd -C "$ad" --actor alice heartbeat "$ad_issue")" -eq 0 ] \
    && pass "bd heartbeat succeeds for the adopter straight after the adoption write" \
    || fail "bd heartbeat failed for the adopter after the adoption write; the adopter holds no lease"
export_of "$ad" "$work/export.ad.before"
rc=$(status_of ad_write bob OTHER-RUN "$(iso_ago 0)")
export_of "$ad" "$work/export.ad.after"
[ "$rc" -ne 0 ] && cmp -s "$work/export.ad.before" "$work/export.ad.after" \
    && [ "$(field_of "$ad" "$ad_issue" assignee)" = alice ] \
    && [ "$(meta_of "$ad" "$ad_issue" backlog_loop_run)" = NEW-RUN ] \
    && pass "a second adopter is refused and writes nothing, so two runs never hold one parked PR" \
    || fail "a second adoption of the same parked issue: exit $rc, or the store changed"

# RECOVERY parks a dead run's in_progress member before adopting it. The
# status guard must refuse a member another invocation or person moved first,
# without overwriting that decision or clearing its heartbeat.
park_store=$(fresh_store)
park_issue=$(bd -C "$park_store" create "dead-run member awaiting adoption" --silent)
bd -C "$park_store" update "$park_issue" --status=in_progress \
    --set-metadata backlog_loop_run=OLD-RUN \
    --set-metadata "backlog_loop_heartbeat=$(iso_ago 60) | live" >/dev/null
rc=$(status_of bd -C "$park_store" update "$park_issue" --if-status in_progress --status=blocked \
    --unset-metadata backlog_loop_heartbeat --set-metadata backlog_loop_cause=transient:pr-open)
[ "$rc" -eq 0 ] && [ "$(field_of "$park_store" "$park_issue" status)" = blocked ] \
    && [ -z "$(meta_of "$park_store" "$park_issue" backlog_loop_heartbeat)" ] \
    && [ "$(meta_of "$park_store" "$park_issue" backlog_loop_cause)" = transient:pr-open ] \
    && pass "ADOPTION's guarded park succeeds for an in_progress member and clears its heartbeat" \
    || fail "ADOPTION's matching park: exit $rc, wrong status/cause, or the heartbeat survived"
bd -C "$park_store" update "$park_issue" --status=deferred \
    --set-metadata "backlog_loop_heartbeat=$(iso_ago 60) | live" \
    --append-notes "a person deferred this member before adoption" >/dev/null
export_of "$park_store" "$work/export.park.before"
rc=$(status_of bd -C "$park_store" update "$park_issue" --if-status in_progress --status=blocked \
    --unset-metadata backlog_loop_heartbeat --set-metadata backlog_loop_cause=transient:pr-open)
export_of "$park_store" "$work/export.park.after"
[ "$rc" -eq 13 ] && cmp -s "$work/export.park.before" "$work/export.park.after" \
    && [ "$(field_of "$park_store" "$park_issue" status)" = deferred ] \
    && [ -n "$(meta_of "$park_store" "$park_issue" backlog_loop_heartbeat)" ] \
    && pass "ADOPTION's park exits 13 with export unchanged after the member moves to deferred" \
    || fail "ADOPTION's stale park: exit $rc, export changed, or deferred status/heartbeat was overwritten"

# EXTERNAL LEASE PASS reaps through `bd reclaim --id` and nothing else. An
# `external-wip` issue that never took a lease (a plain status write), and one
# whose lease is still live, are both left exactly as they are: the pass may
# only release a claim the tracker itself records as expired.
lease_store=$(fresh_store)
lease_none=$(bd -C "$lease_store" create "in progress with no lease" --silent)
lease_live=$(bd -C "$lease_store" create "in progress under a live lease" --silent)
bd -C "$lease_store" update "$lease_none" --status=in_progress >/dev/null
bd -C "$lease_store" update "$lease_live" --claim >/dev/null
export_of "$lease_store" "$work/export.lease.before"
rc=$(status_of bd -C "$lease_store" reclaim --id "$lease_none" --id "$lease_live")
export_of "$lease_store" "$work/export.lease.after"
[ "$rc" -eq 0 ] && cmp -s "$work/export.lease.before" "$work/export.lease.after" \
    && [ "$(field_of "$lease_store" "$lease_none" status)" = in_progress ] \
    && [ "$(field_of "$lease_store" "$lease_live" status)" = in_progress ] \
    && pass "bd reclaim --id leaves an unleased and a live-leased in_progress issue untouched" \
    || fail "bd reclaim --id: exit $rc, or it changed an issue with no expired lease"

# OWNER-DECISION ISSUES decides every non-gate `decision` issue by type, so the
# scan has to be offered one whose body says nothing about the loop choosing.
# The tracker must list it as ready work and report its type as `decision`.
dec_store=$(fresh_store)
dec_issue=$(bd -C "$dec_store" create "choose a retry strategy for the sync job" --type decision --silent)
dec_ready=$(bd -C "$dec_store" ready --json --limit 0 --exclude-type=epic | sorted_ids_json)
case " $dec_ready " in
    *" $dec_issue "*) [ "$(field_of "$dec_store" "$dec_issue" issue_type)" = decision ] \
        && pass "bd ready offers a plain decision issue and reports its type, so the by-type scan can find it" \
        || fail "a decision issue reads back with a type other than decision" ;;
    *) fail "bd ready no longer offers a plain decision issue; the by-type owner-decision scan would never see it" ;;
esac

# FOLLOW-UP FILING creates an ordinary issue with a deterministic id, its
# fingerprint as metadata, and a non-blocking `discovered-from` edge to the
# member. The tracker has to refuse a second create of the same id, keep the
# metadata, and still offer the follow-up as ready work: an edge that blocked it
# would turn every filed finding into a stalled issue.
fu_store=$(fresh_store)
fu_member=$(bd -C "$fu_store" create "batch anchor" --silent)
fu_prefix=$(bd -C "$fu_store" config get issue_prefix)
fu_id="$fu_prefix-f$(python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' 'src/a.go:12|tidy a')"
fu_made=$(bd -C "$fu_store" create "Tidy a" --id "$fu_id" --type task --priority P4 --labels tech-debt \
    --metadata "{\"backlog_loop_followup_key\":\"src/a.go:12|tidy a\",\"backlog_loop_followup_of\":\"$fu_member\"}" --silent)
fu_dup_rc=$(status_of bd -C "$fu_store" create "Tidy a again" --id "$fu_id" --silent)
bd -C "$fu_store" dep add "$fu_id" "$fu_member" --type discovered-from >/dev/null
fu_ready=$(bd -C "$fu_store" ready --json --limit 0 --exclude-type=epic | sorted_ids_json)
case " $fu_ready " in *" $fu_id "*) fu_is_ready=1 ;; *) fu_is_ready=0 ;; esac
[ "$fu_made" = "$fu_id" ] && [ "$fu_dup_rc" -ne 0 ] && [ "$fu_is_ready" -eq 1 ] \
    && [ "$(meta_of "$fu_store" "$fu_id" backlog_loop_followup_key)" = 'src/a.go:12|tidy a' ] \
    && [ "$(meta_of "$fu_store" "$fu_id" backlog_loop_followup_of)" = "$fu_member" ] \
    && [ "$(labels_of "$fu_store" "$fu_id")" = tech-debt ] \
    && pass "a follow-up created by deterministic id keeps its metadata, refuses a duplicate id, and stays ready behind a discovered-from edge" \
    || fail "follow-up creation: id '$fu_made', duplicate exit $fu_dup_rc, ready $fu_is_ready, or its metadata/labels did not read back"

# The UNBLOCK REPORT ranks a person's act by the issues it makes reachable,
# counted over the `blocked_by` lists `bd ready --explain --json` reports. One
# human gate that holds two issues has to show both under that gate's id.
ub_store=$(fresh_store)
ub_gate=$(bd -C "$ub_store" create "[HUMAN] provision the staging account" -l human-gate --silent)
ub_a=$(bd -C "$ub_store" create "deploy step one" --silent)
ub_b=$(bd -C "$ub_store" create "deploy step two" --silent)
bd -C "$ub_store" dep "$ub_gate" --blocks "$ub_a" >/dev/null
bd -C "$ub_store" dep "$ub_gate" --blocks "$ub_b" >/dev/null
ub_held=$(bd -C "$ub_store" ready --explain --json --limit 0 | python3 -c 'import json,sys
d=json.load(sys.stdin)
gate=sys.argv[1]
held=[r["id"] for r in (d.get("blocked") or []) if gate in [b if isinstance(b, str) else b.get("id", "") for b in (r.get("blocked_by") or [])]]
print(" ".join(sorted(held)))' "$ub_gate")
[ "$ub_held" = "$(printf '%s\n' "$ub_a" "$ub_b" | LC_ALL=C sort | paste -sd' ' -)" ] \
    && pass "bd ready --explain reports both issues a human gate holds under that gate's id, which is what the UNBLOCK REPORT counts" \
    || fail "bd ready --explain: the issues held by one gate read '$ub_held', expected both"

# A person-closed PR releases RUN and FORGE-LINK keys but leaves the durable
# needs-person cause and the first note line. These are the stored fields row 6
# and REPORT consume; classification itself remains owned by the skill.
release_store=$(fresh_store)
release_issue=$(bd -C "$release_store" create "pull request closed by a person" --silent)
bd -C "$release_store" update "$release_issue" --status=in_progress \
    --set-metadata backlog_loop_run=OLD-RUN \
    --set-metadata "backlog_loop_heartbeat=$(iso_ago 60) | live" \
    --set-metadata backlog_loop_phase=pr-open \
    --set-metadata backlog_loop_trunk_ci=on --set-metadata backlog_loop_ci=on \
    --set-metadata backlog_loop_base=base-sha \
    --set-metadata backlog_loop_worktrees=/tmp/released-run \
    --set-metadata backlog_loop_branch=old-branch --set-metadata backlog_loop_head=head-sha \
    --set-metadata backlog_loop_pr=https://example.com/pull/1 \
    --set-metadata backlog_loop_merge=merge-sha \
    --set-metadata backlog_loop_postmerge_ci=pending \
    --set-metadata backlog_loop_gate_receipt=head-sha@base-sha@gates >/dev/null
release_note='person closed PR: https://example.com/pull/1
A person decides whether to reopen the issue.'
bd -C "$release_store" update "$release_issue" --status=blocked \
    --set-metadata backlog_loop_cause=needs-person \
    --unset-metadata backlog_loop_run --unset-metadata backlog_loop_heartbeat \
    --unset-metadata backlog_loop_phase --unset-metadata backlog_loop_trunk_ci \
    --unset-metadata backlog_loop_ci --unset-metadata backlog_loop_base \
    --unset-metadata backlog_loop_worktrees --unset-metadata backlog_loop_compose_projects \
    --unset-metadata backlog_loop_branch --unset-metadata backlog_loop_head \
    --unset-metadata backlog_loop_pr --unset-metadata backlog_loop_merge \
    --unset-metadata backlog_loop_postmerge_ci --unset-metadata backlog_loop_gate_receipt \
    --append-notes "$release_note" >/dev/null
release_first_line=$(field_of "$release_store" "$release_issue" notes | sed -n '1p')
[ "$(field_of "$release_store" "$release_issue" status)" = blocked ] \
    && [ "$(meta_of "$release_store" "$release_issue" backlog_loop_cause)" = needs-person ] \
    && [ "$release_first_line" = 'person closed PR: https://example.com/pull/1' ] \
    && pass "person-close release preserves blocked needs-person and the first note line for row 6 and REPORT" \
    || fail "person-close release changed the blocked status, needs-person cause, or first note line"
release_keys_left=$(bd -C "$release_store" show "$release_issue" --json | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
keys="backlog_loop_run backlog_loop_heartbeat backlog_loop_phase backlog_loop_trunk_ci backlog_loop_ci backlog_loop_base backlog_loop_worktrees backlog_loop_compose_projects backlog_loop_branch backlog_loop_head backlog_loop_pr backlog_loop_merge backlog_loop_postmerge_ci backlog_loop_gate_receipt".split()
print(" ".join(k for k in keys if k in (r.get("metadata") or {})))')
[ -z "$release_keys_left" ] \
    && pass "person-close release removes every RUN and FORGE-LINK key, including the run marker" \
    || fail "person-close release left RUN or FORGE-LINK keys: $release_keys_left"

# `bd ready` stops at 100 rows unless told otherwise, which silently truncates a
# large backlog. One import seeds the 102 issues that make that visible. The ids
# are explicit: batch creation draws random three-character ids, and at this
# count two of them collide often enough to fail a run for no reason.
rd=$(fresh_store)
rd_file="$work/ready-seed.jsonl"
: > "$rd_file"
n=0
while [ "$n" -lt 102 ]; do
    printf '{"id":"cx-r%d","title":"ready row %d"}\n' "$n" "$n" >> "$rd_file"
    n=$((n + 1))
done
if bd -C "$rd" import "$rd_file" >/dev/null; then
    rd_default=$(bd -C "$rd" ready --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); print(len(d if isinstance(d,list) else d.get("issues",d)))')
    rd_all=$(bd -C "$rd" ready --json --limit 0 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); print(len(d if isinstance(d,list) else d.get("issues",d)))')
    [ "$rd_all" = 102 ] && [ "$rd_default" = 100 ] \
        && pass "bd ready caps at 100 by default and --limit 0 returns all 102 seeded issues" \
        || fail "bd ready limit changed: default returned '$rd_default', --limit 0 returned '$rd_all' (expected 100 and 102)"
else
    fail "could not seed 102 issues with one 'bd import'; the bd ready limit check cannot run"
fi

# Create-once is atomic because a duplicate explicit id is refused, and --force
# does not override it. The refusal must leave the first issue untouched.
id_store=$(fresh_store)
id_want="cx-s0123abcd"
id_got=$(bd -C "$id_store" create "first writer" --id "$id_want" --silent 2>/dev/null || true)
export_of "$id_store" "$work/export.id.before"
id_rc=$(status_of bd -C "$id_store" create "second writer" --id "$id_want" --silent)
id_force_rc=$(status_of bd -C "$id_store" create "second writer" --id "$id_want" --force --silent)
export_of "$id_store" "$work/export.id.after"
[ "$id_got" = "$id_want" ] && [ "$id_rc" -ne 0 ] && [ "$id_force_rc" -ne 0 ] \
    && cmp -s "$work/export.id.before" "$work/export.id.after" \
    && [ "$(field_of "$id_store" "$id_want" title)" = "first writer" ] \
    && pass "create --id refuses a duplicate even with --force and leaves the first issue unchanged" \
    || fail "create --id duplicate: first id '$id_got', exit $id_rc, forced exit $id_force_rc, or the first issue changed"

# A native gate comes out of one create call with its type set; the gate check
# in PART 1b covers the rest of its shape.
ng=$(fresh_store)
ng_gate=$(bd -C "$ng" create "[HUMAN] supply the signing key" --type gate --silent 2>/dev/null || true)
[ -n "$ng_gate" ] && [ "$(field_of "$ng" "$ng_gate" issue_type)" = gate ] \
    && pass "bd create --type gate yields issue_type=gate in one call" \
    || fail "bd create --type gate did not yield issue_type=gate (id '$ng_gate')"

# A linked worktree shares the main checkout's store. The audit and the loop
# both file issues from throwaway worktrees, and the work is lost if those land
# in a database that vanishes with the worktree.
wt=$(fresh_store)
wt_path="$work/linked-worktree"
if git -C "$wt" worktree add -q -b linked-branch "$wt_path" >/dev/null 2>&1; then
    wt_issue=$(bd -C "$wt_path" create "filed from a linked worktree" --silent 2>/dev/null || true)
    [ -n "$wt_issue" ] \
        && [ "$(field_of "$wt" "$wt_issue" title)" = "filed from a linked worktree" ] \
        && pass "an issue created inside a linked worktree reads back from the main checkout" \
        || fail "an issue created inside a linked worktree (id '$wt_issue') is not visible from the main checkout"
    wt_main_db=$(where_db "$wt")
    wt_linked_db=$(where_db "$wt_path")
    [ -n "$wt_main_db" ] && [ "$wt_main_db" = "$wt_linked_db" ] \
        && pass "bd where resolves to the same database from the main checkout and a linked worktree" \
        || fail "bd where differs between checkouts: main '$wt_main_db', worktree '$wt_linked_db'"
else
    fail "could not add a linked worktree to the seeded store; the worktree checks cannot run"
fi

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
    # Codex has no `-p` prompt flag (`-p` is `--profile` there); it takes the
    # prompt as the argument of `exec`.
    if [ "$host_cli" = "claude" ]; then
        set -- claude -p "$prompt" --allowedTools 'Bash(bd:*)'
    else
        set -- codex exec "$prompt"
    fi
    # `raw=$(...); status=$?` would end the whole suite here under `set -e`
    # the first time the CLI fails, before the runner-failed report below.
    raw=$("$deadline" 600 "$@" 2>&1) && status=0 || status=$?
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
c1_person=$(bd -C "$c1" create "pull request closed by a person" --silent)
c1_transient=$(bd -C "$c1" create "open pull request awaiting checks" --silent)
bd -C "$c1" update "$c1_person" --status=blocked \
    --set-metadata backlog_loop_cause=needs-person \
    --append-notes "person closed PR: https://example.com/pull/1" >/dev/null
bd -C "$c1" update "$c1_transient" --status=blocked \
    --set-metadata backlog_loop_run=OLD-RUN \
    --set-metadata backlog_loop_cause=transient:pr-open >/dev/null
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

    expect_category "$out" "$c1_person" self-blocked-needs-person \
        "a person-closed PR released without RUN keys still waits on a person"
    expect_category "$out" "$c1_transient" self-blocked-transient \
        "a run-marked transient PR block remains transient"
    printf '%s\n' "$out" | grep -qE "^census +$c1_person +\| +self-blocked-needs-person +\| +needs-person([[:space:]]|$)" \
        && pass "the released person-close retains cause needs-person" \
        || fail "the released person-close lost its needs-person cause"
    printf '%s\n' "$out" | grep -qE "^census +$c1_legacy +\| +legacy-blocked +\| +no-marker-no-edge([[:space:]]|$)" \
        && pass "a no-run no-cause block retains the legacy cause" \
        || fail "the no-run no-cause legacy block has the wrong cause"

    # Count the data shape, not the word "census": the header is prose the
    # model composes, and a counter that merely looks for a prefix reports one
    # issue too many the moment that wording drifts. Naming the categories
    # makes the count independent of the header entirely, and makes this line
    # fail loudly if the procedure ever renames one.
    emitted=$(printf '%s\n' "$out" | grep -cE "^census +[^ |]+ +\\| +($CATEGORIES) +\\|" || true)
    [ "$emitted" -eq 8 ] \
        && pass "exactly one line per non-closed non-epic issue" \
        || fail "expected 8 census lines, got $emitted"
fi

echo "  case: a native gate is a gate and is never repaired"
c2=$(fresh_store)
c2_target=$(bd -C "$c2" create "step behind a native gate" --silent)
c2_gate=$(bd -C "$c2" gate create --type=human --blocks "$c2_target" 2>/dev/null | gate_id)
[ -n "$c2_gate" ] || fail "could not read a gate id out of 'bd gate create' for this case"
bd -C "$c2" create "unrelated ready work" --silent >/dev/null
export_of "$c2" "$work/c2.before"

out=$(run_census "$c2" loop)
census_usable "$out" || out=""
expect_category "$out" "$c2_gate"   human-gate  "a native gate classifies as a human gate"
expect_category "$out" "$c2_target" dep-blocked "the step behind it stays dependency-blocked"

export_of "$c2" "$work/c2.after"
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
export_of "$c3" "$work/c3.before"

out=$(run_census "$c3" loop)
census_usable "$out" || out=""
expect_category "$out" "$c3_gate" human-gate  "the labeled gate is recognized"
expect_category "$out" "$c3_dep"  dep-blocked "its dependent stays blocked while the convention is unadopted"

export_of "$c3" "$work/c3.after"
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
export_of "$c4" "$work/c4.before"

out=$(run_census "$c4" diagnostic)
census_usable "$out" || out=""
expect_category "$out" "$c4_gate"  human-gate "the undeclared gate is recognized in diagnostic mode"
expect_category "$out" "$c4_other" human-gate "the declared gate is recognized too"

export_of "$c4" "$work/c4.after"
if [ "$write_proven" -eq 1 ]; then
    cmp -s "$work/c4.before" "$work/c4.after" \
        && pass "a diagnostic run left the tracker's issue records unchanged" \
        || fail "a diagnostic run mutated the tracker"
else
    fail "unproven -- a diagnostic run left the tracker's issue records unchanged: no case in this run showed the census can write at all, so an unchanged tracker proves nothing"
fi

echo "  case: a parked issue's dead ledger residue is stripped, its parking is not"
# The wedge this fixture exists for. `deferred_watch` is a phase value the
# ledger table does not list, and it is seeded on purpose: an improvised phase
# must never reach classification, because the status row above
# `abandoned-claim` answers first and never reads the phase at all.
c6=$(fresh_store)
c6_pr="https://github.com/example/repo/pull/4242"
c6_parked=$(bd -C "$c6" create "recurrence watch, parked by a person" --silent)
bd -C "$c6" create "ready work beside it" --silent >/dev/null
# All ten RESIDUE PASS keys, not just the four the fixture used to name -- an
# edit that dropped one --unset-metadata flag from the procedure would not be
# caught by a key this fixture never seeded.
bd -C "$c6" update "$c6_parked" --status=deferred \
    --set-metadata backlog_loop_run=OLD-RUN-2026 \
    --set-metadata backlog_loop_heartbeat="$(iso_ago 180)" \
    --set-metadata backlog_loop_phase=deferred_watch \
    --set-metadata backlog_loop_base=0ldbase1 \
    --set-metadata backlog_loop_branch=backlog-loop/OLD-RUN-2026 \
    --set-metadata backlog_loop_head=0ldhead22 \
    --set-metadata backlog_loop_pr="$c6_pr" \
    --set-metadata backlog_loop_merge=0ldmerge33 \
    --set-metadata backlog_loop_ci=on \
    --set-metadata backlog_loop_worktrees=/tmp/backlog-loop-worktrees/OLD-RUN-2026 \
    --append-notes "parked until the failure recurs" >/dev/null

out=$(run_census "$c6" loop)
census_usable "$out" || out=""
expect_category "$out" "$c6_parked" deferred \
    "a parked issue carrying a dead marker classifies by its status, not as wreckage"

if [ "$write_proven" -eq 1 ]; then
    c6_left=""
    for key in backlog_loop_run backlog_loop_phase backlog_loop_heartbeat backlog_loop_base \
        backlog_loop_branch backlog_loop_head backlog_loop_pr backlog_loop_merge \
        backlog_loop_ci backlog_loop_worktrees; do
        if [ -n "$(meta_of "$c6" "$c6_parked" "$key")" ]; then
            c6_left="$c6_left $key"
        fi
    done
    [ -z "$c6_left" ] \
        && pass "the residue pass unset every dead ledger key on the parked issue" \
        || fail "the parked issue still carries$c6_left"

    c6_status=$(field_of "$c6" "$c6_parked" status)
    [ "$c6_status" = "deferred" ] \
        && pass "the repair left the parking decision standing" \
        || fail "the repair moved a parked issue out of its status: got '${c6_status:-<none>}'"

    case "$(field_of "$c6" "$c6_parked" notes)" in
        *"$c6_pr"*) pass "the stripped PR URL survives in the issue's notes" ;;
        *) fail "the stripped PR URL is recorded nowhere, so nobody can retire that PR" ;;
    esac

    [ -n "$(meta_of "$c6" "$c6_parked" backlog_loop_census)" ] \
        && pass "the repair stamps backlog_loop_census, which is how the report finds it" \
        || fail "the repaired issue carries no backlog_loop_census stamp"

    # Idempotence, proved rather than asserted from prose: a second census
    # over the now-repaired issue has no dead marker left to find, so it must
    # classify the same and write nothing. Only meaningful here, inside the
    # branch that already proved the first census actually stripped the
    # residue -- a second run over a still-unrepaired issue would not be
    # idempotence, only a repeat of the first, unproven run.
    export_of "$c6" "$work/c6.before"
    out2=$(run_census "$c6" loop)
    census_usable "$out2" || out2=""
    expect_category "$out2" "$c6_parked" deferred \
        "a second census over a repaired issue still classifies it by its status"
    export_of "$c6" "$work/c6.after"
    cmp -s "$work/c6.before" "$work/c6.after" \
        && pass "a second census over a repaired issue finds no marker and writes nothing" \
        || fail "a second census over a repaired issue mutated the tracker again"
else
    fail "unproven -- a parked issue's dead ledger residue is stripped: no case in this run showed the census can write at all, so a repair cannot be told from a denied write"
fi

echo "  case: a dead marker under a status this loop writes is still its own wreckage"
# The control for the case above, and the only fixture that covers the
# `abandoned-claim` row at all. Same dead marker and same improvised phase; the
# one difference is a status this procedure does write, which is exactly what
# that row's exclusion list has to let through.
c7=$(fresh_store)
c7_pr="https://github.com/example/repo/pull/4343"
c7_abandoned=$(bd -C "$c7" create "half-built by a run that died" --silent)
bd -C "$c7" update "$c7_abandoned" --status=in_progress \
    --set-metadata backlog_loop_run=OLD-RUN-2026 \
    --set-metadata backlog_loop_heartbeat="$(iso_ago 180)" \
    --set-metadata backlog_loop_phase=deferred_watch \
    --set-metadata backlog_loop_pr="$c7_pr" >/dev/null

out=$(run_census "$c7" loop)
census_usable "$out" || out=""
expect_category "$out" "$c7_abandoned" abandoned-claim \
    "a dead marker under in_progress is filed as this loop's own wreckage"

if [ "$write_proven" -eq 1 ]; then
    [ -n "$(meta_of "$c7" "$c7_abandoned" backlog_loop_run)" ] \
        && pass "the residue pass left an abandoned claim's marker alone, because RECOVERY owns that issue" \
        || fail "the residue pass stripped an abandoned claim's marker, which is the evidence RECOVERY decides on"
else
    fail "unproven -- the residue pass left an abandoned claim's marker alone: no case in this run showed the census can write at all, so an unchanged marker proves nothing"
fi

echo "  case: one live foreign heartbeat stops every write in the store"
# This case cannot share a store with the repair above, because the WRITE GATE
# is run-global rather than per issue: one foreign heartbeat under 30 minutes
# old skips every mutation pass, and a repair case sharing the store would read
# its keys back intact for a reason that has nothing to do with the pass.
c8=$(fresh_store)
c8_live=$(bd -C "$c8" create "held by a run that is still moving" --silent)
c8_residue=$(bd -C "$c8" create "parked with residue, beside a live run" --silent)
bd -C "$c8" update "$c8_live" --status=deferred \
    --set-metadata backlog_loop_run=LIVE-RUN-2026 \
    --set-metadata backlog_loop_heartbeat="$(iso_ago 2)" >/dev/null
bd -C "$c8" update "$c8_residue" --status=deferred \
    --set-metadata backlog_loop_run=OLD-RUN-2026 \
    --set-metadata backlog_loop_heartbeat="$(iso_ago 180)" \
    --set-metadata backlog_loop_phase=deferred_watch >/dev/null
export_of "$c8" "$work/c8.before"

out=$(run_census "$c8" loop)
census_usable "$out" || out=""
expect_category "$out" "$c8_live" claimed-other-run \
    "a live run's claim outranks the status row, so its issue is never reported parked"
expect_category "$out" "$c8_residue" deferred \
    "the parked issue beside it is still classified by its status"

export_of "$c8" "$work/c8.after"
if [ "$write_proven" -eq 1 ]; then
    cmp -s "$work/c8.before" "$work/c8.after" \
        && pass "a live foreign heartbeat stopped every write, the residue strip included" \
        || fail "the census wrote to a store in which another run holds a live heartbeat"
else
    fail "unproven -- a live foreign heartbeat stopped every write: no case in this run showed the census can write at all, so an unchanged tracker proves nothing"
fi

printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
[ "$failures" -eq 0 ] || exit 1
