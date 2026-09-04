#!/bin/sh
# Drive repo-audit's procedure and diff what it emits against an expected table.
#
# Usage: test-repo-audit.sh [--fixtures-only]
#
# This suite is NOT part of the push path, for the reason the census suite's
# PART 2 already states about itself: it drives a model through a host CLI, so
# it is slow and non-deterministic, and a gate that goes yellow on every third
# run stops being read.
#
# It comes in two parts.
#
# PART 1, the fixture set. Pure shell. It defines the verified-finding record
# the tracker half of the procedure is proven against, writes a set of them,
# and checks that the set parses and discriminates. No model, no tracker.
#
# PART 2, the run. Seeds a Beads store, feeds the fixture set to the
# orchestrator with NO SUBAGENTS SPAWNED, and diffs the emitted lines against
# what the emit contract says they must be. Driving the procedure from a
# fixture rather than from live discovery is deliberate: the handoff into a
# tracker that merges its own pull requests is the part of this skill that
# carries real risk, and a fixture makes it provable without waiting for the
# discovery engine to be trustworthy. A defect found here is a defect in the
# write protocol rather than an ambiguous result from an engine still settling.
#
# Both parts skip cleanly rather than failing when a prerequisite is missing.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
skill="$repo_root/skills/claude/repo-audit/SKILL.md"

fixtures_only=0
[ "${1:-}" = "--fixtures-only" ] && fixtures_only=1

GIT_CONFIG_COUNT=${GIT_CONFIG_COUNT:-1}
GIT_CONFIG_KEY_0=${GIT_CONFIG_KEY_0:-beads.role}
GIT_CONFIG_VALUE_0=${GIT_CONFIG_VALUE_0:-contributor}
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

work=$(mktemp -d "${TMPDIR:-/tmp}/test-repo-audit.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

failures=0
checks=0
pass() { checks=$((checks + 1)); printf '  ok: %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL: %s\n' "$1"; }

[ -f "$skill" ] || { echo "SKIP: no repo-audit skill at $skill."; exit 0; }

# ---------------------------------------------------------------------------
# THE VERIFIED-FINDING FIXTURE RECORD.
#
# One record per file, one `key: value` per line, in this order. These are the
# fields the write protocol consumes -- everything a finding carries once
# verification has confirmed it and before deduplication looks at the tracker.
# Discovery produces them; a fixture stands in for discovery.
#
#   id         a fixture-local identifier, used to say which record a check is about
#   dims       the dimension list, comma-separated; more than one means collapsed
#   path       repository-relative path
#   lines      line range, as `<first>-<last>`
#   evidence   the NORMALIZED evidence text -- one line, whitespace collapsed.
#              Normalized because it is a fingerprint input: two runs that read
#              the same defect through different indentation must fingerprint it
#              the same way, and a raw quote does not.
#   severity   P0..P4, as the verification pass assigned it
#   recipe     the detection recipe, in the procedure's own five-field grammar
#   receipt    the investigation receipt: id, read region, and what was concluded
#
# The fingerprint inputs are `dims`, `path`, `lines`, and `evidence`. They are
# listed here rather than left implicit because a fixture that varies a
# non-input field must produce the SAME fingerprint, and a suite that cannot
# say which fields are inputs cannot check that.
# ---------------------------------------------------------------------------
FIXTURE_FIELDS='id dims path lines evidence severity recipe receipt'

fixtures="$work/fixtures"
mkdir -p "$fixtures"

write_fixture() { # id, dims, path, lines, evidence, severity, recipe, receipt
    cat > "$fixtures/$1.fixture" <<FIXTURE
id: $1
dims: $2
path: $3
lines: $4
evidence: $5
severity: $6
recipe: $7
receipt: $8
FIXTURE
}

echo "PART 1 - the verified-finding fixture set"

write_fixture F1 \
    "correctness and control flow" \
    "src/reader.py" "41-47" \
    "fh = open(path) ; data = fh.read() ; return parse(data)" \
    "P1" \
    "src/reader.py | 41 | literal:open(path) | matches 1 | FIXTURESHA" \
    "F1 | src/reader.py:41-47 | read the open call and both exits; no close on the error path"

write_fixture F2 \
    "state, ordering, and idempotency,correctness and control flow" \
    "src/queue.py" "88-96" \
    "if not seen: seen.add(k) ; enqueue(k)" \
    "P0" \
    "src/queue.py | 88 | re2:seen\.add\([a-z]+\) | matches 1 | FIXTURESHA" \
    "F2 | src/queue.py:88-96 | traced both callers; the add and the enqueue are not atomic"

write_fixture F3 \
    "input boundaries and untrusted data" \
    "src/config.py" "12-12" \
    "REDACTED" \
    "P0" \
    "src/config.py | 12 | classifier:rc-1 | matches 1 | FIXTURESHA" \
    "F3 | src/config.py:12-12 | classified the region; it matches rc-1 and is never quoted"

# The set must be non-empty and every record must carry every field. A suite
# whose fixture set silently emptied would report every later absence check as
# a pass, which is the failure this whole file is built to refuse.
count=$(find "$fixtures" -name '*.fixture' | wc -l | tr -d ' ')
[ "$count" -ge 3 ] \
    && pass "the fixture set holds $count records" \
    || fail "the fixture set holds $count record(s); every check below would be vacuous"

malformed=""
for f in "$fixtures"/*.fixture; do
    for key in $FIXTURE_FIELDS; do
        grep -q "^$key: ." "$f" || malformed="$malformed $(basename "$f"):$key"
    done
done
[ -z "$malformed" ] \
    && pass "every record carries every field of the record definition" \
    || fail "record(s) missing a non-empty field:$malformed"

# A collapsed finding is the one whose dimension list has more than one member,
# and the emit self-count depends on being able to tell them apart.
collapsed=$(grep -l '^dims: .*,' "$fixtures"/*.fixture | wc -l | tr -d ' ')
[ "$collapsed" -eq 1 ] \
    && pass "exactly one record is collapsed, so the pre- and post-collapse counts differ" \
    || fail "$collapsed record(s) are collapsed; the emit self-count cannot be exercised"

# A redacted record must carry no quoted region at all, and its recipe must
# take the classifier form. Both halves, because either alone passes on a
# record that redacted the evidence and then published the value in its recipe.
if grep -q '^evidence: REDACTED$' "$fixtures/F3.fixture" &&
   grep -q '^recipe: .* | classifier:rc-' "$fixtures/F3.fixture"; then
    pass "the redacted record quotes nothing and carries a classifier-form recipe"
else
    fail "the redacted record does not hold both halves of the redaction"
fi

if [ "$fixtures_only" -eq 1 ]; then
    printf '\n%d check(s), %d failure(s) [fixtures only]\n' "$checks" "$failures"
    [ "$failures" -eq 0 ] || exit 1
    exit 0
fi

echo ""
echo "PART 2 - the run"

host_cli=""
for candidate in claude codex; do
    command -v "$candidate" >/dev/null 2>&1 && { host_cli=$candidate; break; }
done

deadline=""
for candidate in timeout gtimeout; do
    command -v "$candidate" >/dev/null 2>&1 && { deadline=$candidate; break; }
done

if ! command -v bd >/dev/null 2>&1; then
    echo "SKIP: bd is not installed; the write protocol has no tracker to write to."
    printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
    [ "$failures" -eq 0 ] || exit 1
    exit 0
fi
if [ -z "$host_cli" ] || [ -z "$deadline" ]; then
    [ -z "$host_cli" ] \
        && echo "SKIP: no host CLI on PATH; the procedure needs one to run." \
        || echo "SKIP: no timeout/gtimeout on PATH; the run needs a deadline wrapper."
    printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
    [ "$failures" -eq 0 ] || exit 1
    exit 0
fi

fresh_store() {
    dir=$(mktemp -d "$work/store.XXXXXX")
    ( cd "$dir" && bd init --prefix ra >/dev/null 2>&1 )
    echo "$dir"
}

# Feed the fixture set to the orchestrator with NO SUBAGENTS SPAWNED. The
# procedure's discovery half is skipped by handing it findings that are already
# verified; what runs is everything from deduplication onward.
run_audit() { # store_dir, mode
    store_dir=$1
    mode=$2   # writing | readonly
    prompt="Read the repo-audit skill at $skill.
Its discovery half has already run. Treat the verified findings in $fixtures as
its output: one record per .fixture file, one 'key: value' per line.
Spawn NO subagents. Run everything from deduplication onward as a $mode run,
against the Beads tracker in $store_dir, using 'bd -C $store_dir ...' for every
tracker command.
Print the audit-run header line, one dimension line per roster dimension, and
one finding line per surviving candidate, between a line reading AUDIT-BEGIN and
a line reading AUDIT-END, and nothing else between those markers."
    if [ "$host_cli" = "claude" ]; then
        set -- --allowedTools 'Bash(bd:*)'
    else
        set --
    fi
    raw=$("$deadline" 900 "$host_cli" -p "$prompt" "$@" 2>&1); status=$?
    if [ -n "${AUDIT_RAW_DIR:-}" ]; then
        mkdir -p "$AUDIT_RAW_DIR"
        printf '%s\n' "$raw" > "$AUDIT_RAW_DIR/${store_dir##*/}-$mode.log"
    fi
    if [ "$status" -ne 0 ]; then
        echo "__AUDIT_RUNNER_FAILED__ $host_cli exited $status"
        return
    fi
    printf '%s\n' "$raw" \
        | sed -n '/^AUDIT-BEGIN$/,/^AUDIT-END$/p' \
        | sed -e '/^AUDIT-BEGIN$/d' -e '/^AUDIT-END$/d'
}

emit_usable() {
    case "$1" in
        __AUDIT_RUNNER_FAILED__*)
            fail "audit runner failed:${1#__AUDIT_RUNNER_FAILED__}"; return 1 ;;
        "")
            fail "the run emitted nothing; the runner or the marker contract is broken"; return 1 ;;
    esac
    return 0
}

store=$(fresh_store)
emitted=$(run_audit "$store" writing)

if emit_usable "$emitted"; then
    # Positive control on the emit itself: the header must be there, exactly
    # once, and distinguishable from the data lines. Everything below counts
    # lines, and a run that emitted only narration would satisfy every
    # "no bad line" assertion there is.
    headers=$(printf '%s\n' "$emitted" | grep -c '^audit-run ' || true)
    [ "$headers" -eq 1 ] \
        && pass "the run emitted exactly one audit-run header" \
        || fail "the run emitted $headers audit-run header(s), wanted 1"

    dims=$(printf '%s\n' "$emitted" | grep -c '^dimension ' || true)
    [ "$dims" -eq 9 ] \
        && pass "the run emitted one dimension line per roster dimension" \
        || fail "the run emitted $dims dimension line(s), wanted 9"

    finds=$(printf '%s\n' "$emitted" | grep -c '^finding ' || true)
    [ "$finds" -eq "$count" ] \
        && pass "the run emitted one finding line per fixture record" \
        || fail "the run emitted $finds finding line(s), wanted $count"

    blank=$(printf '%s\n' "$emitted" | grep -nE '\|[[:space:]]*\|' || true)
    [ -z "$blank" ] \
        && pass "no emitted line carries a blank field" \
        || fail "an emitted line carries a blank field: $(printf '%s' "$blank" | head -n 1)"
fi

printf '\n%d check(s), %d failure(s)\n' "$checks" "$failures"
[ "$failures" -eq 0 ] || exit 1
