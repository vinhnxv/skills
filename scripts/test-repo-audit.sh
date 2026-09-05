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
# PART 2, the run. Seeds a target repository and a Beads store, feeds the
# fixture set to the orchestrator with NO SUBAGENTS SPAWNED, and diffs the
# emitted lines against what the emit contract says they must be. Driving the
# procedure from a fixture rather than from live discovery is deliberate: the
# handoff into a tracker that merges its own pull requests is the part of this
# skill that carries real risk, and a fixture makes it provable without waiting
# for the discovery engine to be trustworthy. A defect found here is a defect in
# the write protocol rather than an ambiguous result from an engine still
# settling.
#
# EVERY PART 2 CASE RUNS THE REDUCED FIXTURE ROSTER: no subagent is spawned, no
# wave is dispatched, and no round runs. NO CASE HERE RUNS THE FULL ROSTER
# against live discovery. That is a deliberate bound on this suite's cost, and
# the banner below prints both deadlines so the difference is visible rather
# than assumed -- a full-roster run is bounded at MAX_ROUNDS waves-worth of
# WAVE_DEADLINE plus POPULATION_DEADLINE, which is more wall clock than any
# suite should spend per case.
#
# Both parts skip cleanly rather than failing when a prerequisite is missing.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
skill="$repo_root/skills/claude/repo-audit/SKILL.md"

# A missing skill is a HARD FAILURE, not a skip. The two skips this suite does
# take -- no `bd`, no host CLI -- are about the environment the suite runs in,
# which the repository does not control. The skill's own path is not: if it is
# absent, either it was renamed and this literal was not, or the checkout is
# broken. Either way the CI step named "The finding record and the fingerprint
# corpus still hold" would print SKIP, exit 0, and run zero of its checks while
# reporting green -- the exact silent pass the rest of this suite exists to
# prevent. The message names the alternative path so a rename is a one-line fix
# rather than a hunt.
if [ ! -f "$skill" ]; then
    echo "FAIL: no repo-audit skill at $skill" >&2
    echo "      (if the skill was renamed or moved, update \`skill=\` in $0;" >&2
    echo "       skills currently present: $(ls "$repo_root/skills/claude" 2>/dev/null | tr '\n' ' '))" >&2
    exit 1
fi

fixtures_only=0
[ "${1:-}" = "--fixtures-only" ] && fixtures_only=1

# `bd` warns on every invocation when `beads.role` is unset, which would bury
# this suite's output in a CI log. Supplying it through the environment answers
# the warning without touching the user's git config and without redirecting
# stderr, which would hide real errors too.
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
# THE FINGERPRINT INPUTS ARE NOT THIS FIELD SET. `## VERIFICATION` names four
# and no others -- FILE IDENTITY, RULE, NORMALIZED EVIDENCE, and DISCRIMINATOR
# -- and says explicitly that the DIMENSION is not an input and that the LINE
# RANGE is never hashed into it. So of the fields above, only `path` (through
# file identity) and `evidence` reach the fingerprint at all; `dims` and
# `lines` are carried in the record for collapse, emission and the index row,
# and a fixture that varies either must produce the SAME fingerprint. Corpus
# case C5 is exactly that check: it shifts the line range and asserts C1's
# fingerprint. Stating the inputs wrongly here would make that case read as a
# contradiction rather than as the assertion it is.
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

# ---------------------------------------------------------------------------
# THE FINGERPRINT-STABILITY CORPUS.
#
# One seeded defect, written five times with a mutation that the normalization
# rules say must NOT change its fingerprint, plus two genuinely distinct
# defects that sit at the same location under the same rule and therefore MUST
# fingerprint apart.
#
# The five mutations are exactly the ones the procedure claims to survive:
#
#   C1  the defect as first read
#   C2  the file renamed -- carried by the rename map below, per R81
#   C3  reformatted: indentation and internal whitespace changed
#   C4  CRLF line endings instead of LF
#   C5  a comment inserted above it, which moves its line range
#
# C3's mutation is written with the whitespace UNNORMALIZED on purpose. The
# fixture record's `evidence` field is defined as normalized text, so a corpus
# that pre-normalized every variant would prove that identical strings hash
# identically and nothing else. The run is what must normalize it.
#
# C6 and C7 are the discriminator's job: same path, same rule, overlapping
# region, different defects. They fingerprint apart via the enclosing symbol,
# and a procedure that collapsed them would silently file one issue for two
# bugs.
# ---------------------------------------------------------------------------
corpus="$work/corpus"
mkdir -p "$corpus"

write_corpus() { # id, path, lines, evidence
    cat > "$corpus/$1.fixture" <<CORPUS
id: $1
dims: correctness and control flow
path: $2
lines: $3
evidence: $4
severity: P2
recipe: $2 | ${3%%-*} | literal:acquire(lock) | matches 1 | FIXTURESHA
receipt: $1 | $2:$3 | read the acquire and every exit; the release is not on the error path
CORPUS
}

write_corpus C1 "src/pool.py" "20-26" "def drain(self): acquire(lock) ; self._flush() ; release(lock)"
write_corpus C2 "src/pooling.py" "20-26" "def drain(self): acquire(lock) ; self._flush() ; release(lock)"
write_corpus C3 "src/pool.py" "20-26" "def drain(self):      acquire(lock)  ;  self._flush()  ;  release(lock)"
printf 'id: C4\r\ndims: correctness and control flow\r\npath: src/pool.py\r\nlines: 20-26\r\nevidence: def drain(self): acquire(lock) ; self._flush() ; release(lock)\r\nseverity: P2\r\nrecipe: src/pool.py | 20 | literal:acquire(lock) | matches 1 | FIXTURESHA\r\nreceipt: C4 | src/pool.py:20-26 | read the acquire and every exit; the release is not on the error path\r\n' > "$corpus/C4.fixture"
write_corpus C5 "src/pool.py" "23-29" "def drain(self): acquire(lock) ; self._flush() ; release(lock)"

write_corpus C6 "src/pool.py" "40-44" "def close(self): acquire(lock) ; self._shutdown()"
write_corpus C7 "src/pool.py" "40-44" "def reset(self): acquire(lock) ; self._clear()"

# The rename map C2 is measured against. R81 resolves a finding at a rename
# target back to the fingerprint recorded under the rename source, so the map
# is an input to the run rather than something it can infer from the fixtures.
cat > "$corpus/renames" <<'RENAMES'
src/pool.py -> src/pooling.py
RENAMES

CORPUS_ONE_FINGERPRINT='C1 C2 C3 C4 C5'
CORPUS_DISTINCT='C6 C7'

corpus_count=$(find "$corpus" -name '*.fixture' | wc -l | tr -d ' ')
[ "$corpus_count" -eq 7 ] \
    && pass "the fingerprint corpus holds all seven records" \
    || fail "the fingerprint corpus holds $corpus_count record(s), wanted 7"

# The corpus only proves anything if the variants really do differ as written.
# Five byte-identical files would pass every fingerprint assertion below for
# reasons that have nothing to do with normalization.
same=0
for a in C2 C3 C4 C5; do
    if cmp -s "$corpus/C1.fixture" "$corpus/$a.fixture"; then
        same=$((same + 1))
    fi
done
[ "$same" -eq 0 ] \
    && pass "every mutation in the corpus differs in bytes from the base record" \
    || fail "$same corpus mutation(s) are byte-identical to C1; they prove nothing"

# C4's whole point is the line-ending conversion, so assert the CR is there.
if od -c "$corpus/C4.fixture" 2>/dev/null | grep -q '\\r'; then
    pass "the line-ending variant really carries CRLF"
else
    fail "the line-ending variant carries no CR; the LF normalization is untested"
fi

# ---------------------------------------------------------------------------
# THE PROCEDURE READERS AND THE REPLAY HARNESS.
#
# These live in PART 1 and not in PART 2 because CI runs `--fixtures-only` and
# nothing else. A criterion-level rule asserted below the exit is asserted on a
# path no push ever takes, which is a rule nothing checks. Everything here is a
# read of the procedure plus `awk` over canned text: no model, no host CLI, no
# tracker, no network. PART 2 keeps only what genuinely needs a live model.
#
# PART 2 consumes the values parsed here rather than re-parsing them, so the
# deadline math and the emit assertions cannot drift apart.
# ---------------------------------------------------------------------------
const_val() { # NAME -> the first integer on its line in the constants block
    sed -n "s/^$1 *= *\([0-9][0-9]*\).*/\1/p" "$skill" | head -n 1
}

wave_min=$(const_val WAVE_DEADLINE)
pop_min=$(const_val POPULATION_DEADLINE)
max_rounds=$(const_val MAX_ROUNDS)
fanout_floor=$(const_val FANOUT_FLOOR)

for pair in "WAVE_DEADLINE:$wave_min" "POPULATION_DEADLINE:$pop_min" \
            "MAX_ROUNDS:$max_rounds" "FANOUT_FLOOR:$fanout_floor"; do
    [ -n "${pair#*:}" ] || {
        echo "FAIL: ${pair%%:*} did not parse out of the constants block."
        exit 1
    }
done

# The two rosters, each read from its own table. The dimension table is matched
# on its exact header line and terminated by the blank line after it, so a
# second table below it -- the criterion roster -- cannot inflate this count.
roster_size=$(sed -n '/^| class | dimension | cacheable | why |$/,/^$/p' "$skill" \
    | grep -c '^| \(latent defect\|health\|conformance\) |' || true)
[ "${roster_size:-0}" -ge 1 ] || { echo "FAIL: the dimension roster did not parse; the emit counts would be empty."; exit 1; }

criterion_rows=$(sed -n '/^| id | dimension | criterion | tier | guard | why this tier |$/,/^$/p' "$skill" \
    | grep '^| `[a-z][a-z]-[a-z0-9-]*` |' || true)
criterion_size=$(printf '%s' "$criterion_rows" | grep -c . || true)

pass "the dimension roster parses to $roster_size dimension(s)"

[ "${criterion_size:-0}" -ge 1 ] \
    && pass "the criterion roster parses to $criterion_size criteria" \
    || fail "the criterion roster did not parse; every criterion-level count below would be empty"

# ---------------------------------------------------------------------------
# THE CRITERION ROSTER'S OWN RULES. Every one is a static read of the
# procedure, so every one runs on the push path.
# ---------------------------------------------------------------------------
# A single-character FS is taken literally by awk; a bracketed-pipe regex is
# not, and ` *\| *` reads as an alternation of two space runs, which splits
# every row on whitespace instead. Trim in the action rather than the FS.
crit_field() { # column number (1-based, ignoring the leading empty field)
    printf '%s\n' "$criterion_rows" \
        | awk -F'|' -v c="$1" '{ f = $(c + 1); gsub(/^[ \t]+|[ \t]+$/, "", f); print f }' \
        | tr -d '`'
}

bad_tier=$(crit_field 4 | grep -vc '^\(in-file\|cross-file\|advisory\)$' || true)
[ "$bad_tier" -eq 0 ] \
    && pass "every criterion declares a tier from the closed set" \
    || fail "$bad_tier criterion row(s) declare a tier outside in-file/cross-file/advisory"

sed -n '/^| class | dimension | cacheable | why |$/,/^$/p' "$skill" \
    | awk -F'|' '/^\| (latent defect|health|conformance) \|/ { d = $3; gsub(/^[ \t]+|[ \t]+$/, "", d); print d }' \
    > "$work/dim-names"

crit_field 2 | sort -u > "$work/crit-dims"
sort -u "$work/dim-names" > "$work/dim-sorted"
comm -23 "$work/crit-dims" "$work/dim-sorted" > "$work/orphan-dims"
orphans=$(grep -c . "$work/orphan-dims" || true)
[ "$orphans" -eq 0 ] \
    && pass "every criterion names a dimension the roster carries" \
    || fail "$orphans criterion row(s) name a dimension outside the roster: $(tr '\n' ' ' < "$work/orphan-dims")"

over_cap=$(crit_field 2 | sort | uniq -c | awk '$1 > 4' | grep -c . || true)
[ "$over_cap" -eq 0 ] \
    && pass "no dimension carries more than four criteria" \
    || fail "$over_cap dimension(s) carry more than the four-criteria cap"

crit_field 2 > "$work/crit-dim-col"
crit_field 4 > "$work/crit-tier-col"
over_advisory=$(paste -d'\t' "$work/crit-dim-col" "$work/crit-tier-col" \
    | awk -F'\t' '$2 == "advisory" { print $1 }' | sort | uniq -c | awk '$1 > 1' | grep -c . || true)
[ "$over_advisory" -eq 0 ] \
    && pass "no dimension carries more than one advisory-tier criterion" \
    || fail "$over_advisory dimension(s) carry more than one advisory-tier criterion"

blank_guard=$(crit_field 5 | grep -cx '' || true)
[ "$blank_guard" -eq 0 ] \
    && pass "every criterion states a guard or the literal none" \
    || fail "$blank_guard criterion row(s) leave the guard column empty"

dup_ids=$(crit_field 1 | sort | uniq -d | grep -c . || true)
[ "$dup_ids" -eq 0 ] \
    && pass "every criterion id is unique" \
    || fail "$dup_ids criterion id(s) appear more than once"

# Reachability. `## FAN-OUT` gives every criterion at least one allocated
# pattern, which is only possible while a dimension's criteria fit inside its
# pattern budget. A criterion nothing can search for is a row that reports
# uncovered forever.
widest=$(crit_field 2 | sort | uniq -c | awk 'NR == 1 || $1 > m { m = $1 } END { print m + 0 }')
[ "$(const_val PATTERNS_PER_DIM)" -ge "$widest" ] \
    && pass "every criterion is reachable: PATTERNS_PER_DIM covers the widest dimension's $widest criteria" \
    || fail "the widest dimension carries $widest criteria but PATTERNS_PER_DIM is $(const_val PATTERNS_PER_DIM), so some criterion gets no pattern"

# No unused tier value. A tier nothing declares is scaffolding: it has a name,
# a documented disposition, and no way to ever be exercised.
for tier in in-file cross-file advisory; do
    crit_field 4 | grep -qx "$tier" \
        && pass "the $tier tier is declared by at least one criterion" \
        || fail "no criterion declares the $tier tier, so the value is unreachable scaffolding"
done

# ---------------------------------------------------------------------------
# THE REPLAY HARNESS. Canned orchestrator-side text, asserted against the same
# rules a live run is asserted against. `field_count_violations` is pure awk
# over an emitted record, so it belongs here rather than beside the host runs.
# ---------------------------------------------------------------------------
field_count_violations() {
    awk -F' \\| ' '
        /^audit-run /{ if (NF != 9) print "audit-run has " NF " fields, wanted 9" }
        /^dimension /{ if (NF != 6) print "dimension has " NF " fields, wanted 6" }
        /^criterion /{ if (NF != 7) print "criterion has " NF " fields, wanted 7" }
        /^finding /  { if (NF != 6) print "finding has " NF " fields, wanted 6" }
        { for (i = 1; i <= NF; i++) if ($i ~ /^[[:space:]]*$/) print "blank field " i " in: " $0 }
    '
}

prefix_count() { # prefix, record -> how many lines carry that prefix
    printf '%s\n' "$2" | grep -c "^$1 " || true
}

# A well-formed record for one dimension carrying two criteria. Every field is
# populated, because NO FIELD IS EVER BLANK is the rule being replayed, and the
# ids are real roster ids so the record cannot drift from what the run emits.
replay_good='audit-run tok-1 | abc1234 | write | 3 | none | 1/0 | 2 | 0 | none
dimension correctness and control flow | clean | 2/2/9 | 0.22 | 0.22 | full
criterion cc-error-path | correctness and control flow | in-file | clean | 1/2/5 | 0.40 | 0.20
criterion cc-stub | correctness and control flow | in-file | clean | 1/2/4 | 0.50 | 0.25
finding a1b2c3 | correctness and control flow | P2 | filed | bd-7 | src/a.py:10-12'

violations=$(printf '%s\n' "$replay_good" | field_count_violations)
[ -z "$violations" ] \
    && pass "replay: a well-formed record has no field-count or blank-field violation" \
    || fail "replay: a well-formed record was rejected: $violations"

[ "$(prefix_count criterion "$replay_good")" -eq 2 ] \
    && pass "replay: the criterion lines are counted by their own prefix" \
    || fail "replay: the criterion prefix count is wrong"

# A criterion line one field short is caught, the same way a short dimension
# line already is. Without this the new prefix would be unchecked text.
replay_short=$(printf '%s\n' "$replay_good" | sed 's/^criterion cc-stub.*/criterion cc-stub | correctness and control flow | in-file | clean | 1\/2\/4 | 0.50/')
printf '%s\n' "$replay_short" | field_count_violations | grep -q 'criterion has 6 fields' \
    && pass "replay: a criterion line one field short is caught" \
    || fail "replay: a short criterion line passed the field-count check"

replay_blank=$(printf '%s\n' "$replay_good" | sed 's/| in-file | clean | 1\/2\/5/|  | clean | 1\/2\/5/')
printf '%s\n' "$replay_blank" | field_count_violations | grep -q '^blank field' \
    && pass "replay: a blank field in a criterion line is caught" \
    || fail "replay: a blank criterion field passed the no-blank-field check"

# COUNT THE EMIT, replayed. A record one criterion line short of the roster is
# the failure U5 exists to make loud, and it is asserted here rather than in a
# live run because a live run is not on the push path.
emitted_criteria=$(prefix_count criterion "$replay_good")
short_record=$(printf '%s\n' "$replay_good" | grep -v '^criterion cc-stub')
[ "$(prefix_count criterion "$short_record")" -lt "$emitted_criteria" ] \
    && pass "replay: a record missing a criterion line counts one fewer than the record that carries it" \
    || fail "replay: dropping a criterion line did not change the criterion count"

[ "$(prefix_count dimension "$replay_good")" -eq 1 ] \
    && pass "replay: the dimension count is unaffected by the criterion lines beside it" \
    || fail "replay: criterion lines disturbed the dimension count"

# The second half of the count clause: every emitted criterion is a roster
# criterion, attributed to the dimension the roster gives it. A count alone
# would accept a record that emitted the right number of the wrong criteria.
emit_attribution_violations() { # record -> one line per criterion the roster contradicts
    printf '%s\n' "$1" | grep '^criterion ' | while IFS= read -r line; do
        eid=$(printf '%s\n' "$line" | awk -F'|' '{ sub(/^criterion[ \t]+/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1 }')
        edim=$(printf '%s\n' "$line" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }')
        rdim=$(paste -d'|' "$work/crit-ids" "$work/crit-dims-aligned" | awk -F'|' -v k="$eid" '$1 == k { print $2 }')
        if [ -z "$rdim" ]; then
            echo "$eid is emitted but is not in the criterion roster"
        elif [ "$rdim" != "$edim" ]; then
            echo "$eid is emitted under $edim, but the roster gives it $rdim"
        fi
    done
}

crit_field 1 > "$work/crit-ids"
crit_field 2 > "$work/crit-dims-aligned"

[ -z "$(emit_attribution_violations "$replay_good")" ] \
    && pass "replay: every emitted criterion is a roster criterion under its roster dimension" \
    || fail "replay: a well-formed record was contradicted by the roster: $(emit_attribution_violations "$replay_good")"

replay_misattributed=$(printf '%s\n' "$replay_good" | sed 's/^criterion cc-stub | correctness and control flow/criterion cc-stub | test integrity/')
emit_attribution_violations "$replay_misattributed" | grep -q 'the roster gives it' \
    && pass "replay: a criterion emitted under the wrong dimension is caught" \
    || fail "replay: a misattributed criterion line passed the roster check"

replay_unknown=$(printf '%s\n' "$replay_good" | sed 's/^criterion cc-stub/criterion cc-invented/')
emit_attribution_violations "$replay_unknown" | grep -q 'not in the criterion roster' \
    && pass "replay: a criterion line naming no roster criterion is caught" \
    || fail "replay: an invented criterion id passed the roster check"


# ---------------------------------------------------------------------------
# THE RETURN'S OWN DISCARD PATHS, REPLAYED.
#
# A canned return in the shape `## SUBAGENT CONTRACT` defines, run through the
# orchestrator-side checks that decide whether it is trusted. Every check here
# is arithmetic over text, so it belongs on the push path rather than behind a
# live model that CI never starts.
#
# receipt line: <candidate-id> | <criterion-id> | <path>:<lines> | <conclusion>
# count line:   count <criterion-id> | <declared integer>
# ---------------------------------------------------------------------------
recount_disagreements() { # return-text, then the criterion ids the dimension owns
    ret=$1; shift
    owned=" $* "
    printf '%s\n' "$ret" | awk -F'|' -v owned="$owned" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        /^receipt / { c = trim($2); seen[c]++
                      if (index(owned, " " c " ") == 0) print "receipt names " c ", outside the dimension set" }
        /^count /   { c = trim($1); sub(/^count[ \t]+/, "", c); declared[c] = trim($2) + 0 }
        END { for (c in declared) if (declared[c] != seen[c]) print "criterion " c " declared " declared[c] " receipt(s), carries " seen[c] + 0 }
    '
}

return_good='receipt k1 | cc-error-path | src/a.py:10-12 | no handler on the fallible call
receipt k2 | cc-error-path | src/b.py:40-41 | handler present, not a defect
receipt k3 | cc-stub | src/c.py:7-9 | placeholder on a live path
count cc-error-path | 2
count cc-stub | 1'

[ -z "$(recount_disagreements "$return_good" cc-existing cc-error-path cc-stub)" ] \
    && pass "replay: a return whose per-criterion counts match its receipts is trusted" \
    || fail "replay: a well-formed return was discarded"

return_foreign=$(printf '%s\n' "$return_good" | sed 's/^receipt k3 | cc-stub |/receipt k3 | ib-authz |/')
recount_disagreements "$return_foreign" cc-existing cc-error-path cc-stub | grep -q 'outside the dimension set' \
    && pass "replay: a receipt naming a criterion outside its dimension's set is caught" \
    || fail "replay: a foreign criterion id passed the dimension-set check"

return_miscount=$(printf '%s\n' "$return_good" | sed 's/^count cc-error-path | 2/count cc-error-path | 5/')
recount_disagreements "$return_miscount" cc-existing cc-error-path cc-stub | grep -q 'declared 5 receipt' \
    && pass "replay: a per-criterion count that disagrees with the recount is caught" \
    || fail "replay: an inflated per-criterion count passed the recount"

# A criterion the return declares but carries no receipt for is uncovered on its
# own, and its siblings keep their verdicts. This is the rule that stops one
# criterion's silence from being absorbed by a sibling's sampling.
return_silent=$(printf '%s\n%s\n' "$return_good" 'count cc-existing | 0')
silent=$(recount_disagreements "$return_silent" cc-existing cc-error-path cc-stub)
[ -z "$silent" ] \
    && pass "replay: a criterion declaring zero receipts disagrees with nothing, so coverage decides it" \
    || fail "replay: a zero-receipt criterion was mis-flagged as a count disagreement: $silent"

# ---------------------------------------------------------------------------
# THE RECIPE'S ARITY AND THE TIER'S DISPOSITION, REPLAYED.
#
# A recipe is one or two clause-lines, each exactly the five-field grammar.
# The parse gate is unchanged per clause, so these checks are about how many
# clauses there are, what forms may sit together, and whether every clause
# reproduced -- all of which are decidable over text.
# ---------------------------------------------------------------------------
recipe_verdict() { # recipe text (one clause per line) -> parseable | recipe-unparseable
    printf '%s\n' "$1" | awk -F'|' '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        NF > 0 { clauses++
                 if (NF != 5) bad = "field count"
                 f = trim($3)
                 if (f ~ /^classifier:/) classifier++
               }
        END { if (clauses < 1 || clauses > 2) print "recipe-unparseable"
              else if (bad != "")            print "recipe-unparseable"
              else if (classifier > 0 && clauses > 1) print "recipe-unparseable"
              else print "parseable" }
    '
}

one_clause='src/a.py | 10-12 | literal:open( | matches 1 | abc1234'
two_clause='src/route.py | 4-4 | literal:GET /widgets | matches 1 | abc1234
docs/api.md | 30-30 | literal:GET /widgets | absent 0 | abc1234'
three_clause=$(printf '%s\n%s\n' "$two_clause" 'src/x.py | 1-1 | literal:z | matches 1 | abc1234')
classifier_one='src/conf.py | 8-8 | classifier:rc-2 | matches 1 | abc1234'
classifier_mixed=$(printf '%s\n%s\n' "$classifier_one" 'src/use.py | 3-3 | literal:token | matches 1 | abc1234')

[ "$(recipe_verdict "$one_clause")" = parseable ] \
    && pass "replay: a one-clause recipe still parses, unchanged" \
    || fail "replay: the existing one-clause recipe stopped parsing"

[ "$(recipe_verdict "$two_clause")" = parseable ] \
    && pass "replay: a two-clause cross-file recipe parses" \
    || fail "replay: a two-clause recipe was rejected"

[ "$(recipe_verdict "$three_clause")" = recipe-unparseable ] \
    && pass "replay: a three-clause recipe is recipe-unparseable" \
    || fail "replay: a third clause was admitted"

[ "$(recipe_verdict "$classifier_one")" = parseable ] \
    && pass "replay: a single classifier-form clause parses" \
    || fail "replay: the classifier form stopped parsing"

[ "$(recipe_verdict "$classifier_mixed")" = recipe-unparseable ] \
    && pass "replay: a classifier clause paired with any other form is recipe-unparseable" \
    || fail "replay: a mixed-form recipe was admitted, which publishes the withheld location"

# PROOF AT FILE TIME over an arity-two recipe: every clause must reproduce.
proof_verdict() { # per-clause reproduce results, one per line -> filed | report-only
    printf '%s\n' "$1" | awk '/^no$/ { failed = 1 } END { print failed ? "report-only" : "filed" }'
}
[ "$(proof_verdict "$(printf 'yes\nyes\n')")" = filed ] \
    && pass "replay: a two-clause recipe whose clauses both reproduce files" \
    || fail "replay: a fully reproducing two-clause recipe did not file"
[ "$(proof_verdict "$(printf 'yes\nno\n')")" = report-only ] \
    && pass "replay: a two-clause recipe with one failing clause goes to the report" \
    || fail "replay: a half-reproducing recipe filed"

# The tier's disposition, and the one rule that outranks it.
tier_disposition() { # tier, classifier-match (yes/no) -> disposition
    if [ "$2" = yes ]; then echo "human-gate"
    elif [ "$1" = advisory ]; then echo "report-only"
    else echo "filed"; fi
}
[ "$(tier_disposition advisory no)" = report-only ] \
    && pass "replay: a confirmed advisory-tier finding is report-only and files nothing" \
    || fail "replay: an advisory finding reached the tracker"
[ "$(tier_disposition advisory yes)" = human-gate ] \
    && pass "replay: the credential test outranks the tier -- a matching region still files a rotation gate" \
    || fail "replay: an advisory-tier credential finding was silently left in the report"
[ "$(tier_disposition in-file no)" = filed ] \
    && pass "replay: an in-file finding's disposition is unchanged by the tier rule" \
    || fail "replay: the tier rule changed a non-advisory disposition"

# ---------------------------------------------------------------------------
# COVERAGE ADJUDICATION AT THE CRITERION, AND THE DIMENSION'S ROLL-UP.
#
# Coverage is arithmetic over recorded numbers, so the whole adjudication is
# replayable here. The two floors guard different things and are both checked:
# CRITERION_POPULATION_FLOOR stops one criterion earning a clean verdict on two
# match sites, POPULATION_FLOOR stops a whole dimension being allocated too
# narrowly to see anything.
# ---------------------------------------------------------------------------
# COVERAGE_FLOOR is a fraction, so it needs a reader that does not stop at the
# decimal point. const_val would return 0 for 0.6 and make every ratio pass.
const_ratio() { # NAME -> the decimal value on its line in the constants block
    sed -n "s/^$1 *= *\([0-9][0-9.]*\).*/\1/p" "$skill" | head -n 1
}
coverage_floor=$(const_ratio COVERAGE_FLOOR)
awk -v f="$coverage_floor" 'BEGIN { exit !(f > 0 && f < 1) }' \
    && pass "constants: COVERAGE_FLOOR reads back as a fraction between 0 and 1" \
    || fail "constants: COVERAGE_FLOOR parsed as '$coverage_floor', which no ratio can fail"

crit_floor=$(const_val CRITERION_POPULATION_FLOOR)
case "$crit_floor" in
    ''|*[!0-9]*) fail "CRITERION_POPULATION_FLOOR is absent from the constants block or is not a count: '$crit_floor'" ;;
    *) [ "$crit_floor" -lt "$(const_val POPULATION_FLOOR)" ] \
        && pass "constants: CRITERION_POPULATION_FLOOR sits below the dimension's POPULATION_FLOOR" \
        || fail "constants: a criterion floor at or above the dimension floor makes the dimension floor unreachable" ;;
esac

criterion_verdict() { # population, investigated, exhaustive(yes/no) -> clean|uncovered|skipped
    cpop=$1; cinv=$2; cexh=$3
    if [ "$cpop" -eq 0 ]; then
        [ "$cexh" = yes ] && echo skipped || echo uncovered
        return
    fi
    if [ "$cpop" -lt "$crit_floor" ]; then
        [ "$cexh" = yes ] && echo clean || echo uncovered
        return
    fi
    awk -v i="$cinv" -v p="$cpop" -v f="$coverage_floor" \
        'BEGIN { print (i / p >= f) ? "clean" : "uncovered" }'
}

[ "$(criterion_verdict 10 6 no)" = clean ] \
    && pass "coverage: a criterion meeting COVERAGE_FLOOR on its own population is clean" \
    || fail "coverage: a criterion at the floor was not clean"
[ "$(criterion_verdict 10 5 no)" = uncovered ] \
    && pass "coverage: a criterion below COVERAGE_FLOOR on its own population is uncovered" \
    || fail "coverage: a criterion under the floor escaped an uncovered verdict"
[ "$(criterion_verdict 2 2 no)" = uncovered ] \
    && pass "coverage: a ratio of one over a population under CRITERION_POPULATION_FLOOR is still uncovered" \
    || fail "coverage: a criterion earned a clean verdict on almost nothing"
[ "$(criterion_verdict 2 2 yes)" = clean ] \
    && pass "coverage: the exhaustive-search escape lets a genuinely rare criterion be clean" \
    || fail "coverage: a rare criterion is permanently uncovered, which no return can fix"
[ "$(criterion_verdict 0 0 yes)" = skipped ] \
    && pass "coverage: a criterion proving its population empty is skipped, not clean" \
    || fail "coverage: an empty population produced the wrong verdict"
[ "$(criterion_verdict 0 0 no)" = uncovered ] \
    && pass "coverage: an unproven empty population is uncovered -- no defects and nobody looking read alike" \
    || fail "coverage: silence passed as an empty population"

dimension_rollup() { # dimension population, then one criterion verdict per argument
    dpop=$1; shift
    any_uncovered=0; any_clean=0; any_other=0
    for v in "$@"; do
        case "$v" in
            uncovered) any_uncovered=1 ;;
            clean)     any_clean=1 ;;
            *)         any_other=1 ;;
        esac
    done
    [ "$any_uncovered" -eq 1 ] && { echo uncovered; return; }
    [ "$any_clean" -eq 0 ] && [ "$any_other" -eq 1 ] && { echo skipped; return; }
    [ "$dpop" -lt "$(const_val POPULATION_FLOOR)" ] && { echo uncovered; return; }
    echo clean
}

# AE3: three of four criteria covered, the fourth not -- the dimension does not
# report clean as a whole, and the three keep their own clean verdicts.
[ "$(dimension_rollup 40 clean clean clean uncovered)" = uncovered ] \
    && pass "roll-up: one uncovered criterion denies its dimension a clean verdict" \
    || fail "roll-up: a starved criterion was absorbed by its covered siblings"
[ "$(dimension_rollup 40 clean clean clean clean)" = clean ] \
    && pass "roll-up: a dimension whose every criterion is clean is clean" \
    || fail "roll-up: a fully covered dimension did not report clean"
[ "$(dimension_rollup 40 clean skipped clean skipped)" = clean ] \
    && pass "roll-up: a criterion that proved its population empty does not hold its dimension back" \
    || fail "roll-up: a skipped criterion denied a clean dimension"
[ "$(dimension_rollup 0 skipped skipped skipped skipped)" = skipped ] \
    && pass "roll-up: a dimension is skipped only when all of its criteria are" \
    || fail "roll-up: an all-skipped dimension reported something else"
[ "$(dimension_rollup 4 clean clean clean clean)" = uncovered ] \
    && pass "roll-up: the dimension's POPULATION_FLOOR still overrides clean criteria" \
    || fail "roll-up: a dimension allocated too narrowly to see anything reported clean"
[ "$(dimension_rollup 4 uncovered skipped skipped skipped)" = uncovered ] \
    && pass "roll-up: an uncovered criterion is read before either floor or the skip rule" \
    || fail "roll-up: the resolution order let an uncovered criterion be masked"

# ---------------------------------------------------------------------------
# THE LEDGER'S SKIP DECISION, REPLAYED.
#
# A ledger row is text and the skip decision over it is arithmetic, so the whole
# rule replays here. The row shape is the one `## THE INDEX ISSUE` renders:
#   <dimension> | <criterion> | <path> | <second-path|none> | <verdict> | <sha> | <digest> | <recorded-at>
# ---------------------------------------------------------------------------
ledger_row_fields() { # a row -> its field count
    printf '%s\n' "$1" | awk -F' [|] ' '{ print NF }'
}

# unchanged-paths is a space-joined list of the paths this run re-proved
# unchanged against an ancestor SHA; digest is the run's current roster digest.
ledger_skips() { # row, unchanged-paths, current-digest -> skip | audit:<reason>
    printf '%s\n' "$1" | awk -F' [|] ' -v unchanged=" $2 " -v cur="$3" '
        { crit = $2; p1 = $3; p2 = $4; verdict = $5; digest = $7 }
        END {
            if (verdict != "clean")                       { print "audit:verdict-" verdict; exit }
            if (digest != cur)                            { print "audit:digest-changed"; exit }
            if (index(unchanged, " " p1 " ") == 0)        { print "audit:path-changed"; exit }
            if (p2 == "none" && crit_cross)               { print "audit:no-second-path"; exit }
            if (p2 != "none" && index(unchanged, " " p2 " ") == 0) { print "audit:second-path-changed"; exit }
            print "skip"
        }
    ' crit_cross="${4:-0}"
}

row_in_file='correctness and control flow | cc-error-path | src/a.py | none | clean | abc1234 | d9 | 2026-09-01'
row_sibling='correctness and control flow | cc-stub | src/a.py | none | uncovered | abc1234 | d9 | 2026-09-01'
row_cross='interface and contract drift | id-doc-drift | src/route.py | docs/api.md | clean | abc1234 | d9 | 2026-09-01'
row_cross_half='interface and contract drift | id-doc-drift | src/route.py | none | clean | abc1234 | d9 | 2026-09-01'

# The replay rows name real roster criteria, so a row can never describe a
# criterion the procedure does not have -- the same grounding the emit replay
# takes, for the same reason.
for rid in cc-error-path cc-stub id-doc-drift; do
    grep -qx "$rid" "$work/crit-ids" \
        && pass "ledger: the replay row for $rid names a roster criterion" \
        || fail "ledger: the replay rows describe $rid, which is not in the criterion roster"
done

# The column count is read from the index's own row template rather than
# written here, so a template that gains or loses a column fails this check
# instead of leaving the replay rows quietly describing an older shape.
declared_cols=$(grep -A1 '^## LEDGER$' "$skill" | tail -n 1 | awk -F' [|] ' '{ print NF }')
[ "$declared_cols" -ge 2 ] \
    && pass "ledger: the index's LEDGER row template parses to $declared_cols column(s)" \
    || fail "ledger: the LEDGER row template did not parse, so no row shape is checkable"
[ "$(ledger_row_fields "$row_in_file")" -eq "$declared_cols" ] \
    && pass "ledger: the replayed rows carry exactly the columns the index declares" \
    || fail "ledger: the replay rows carry $(ledger_row_fields "$row_in_file") column(s), the index declares $declared_cols"

[ "$(ledger_skips "$row_in_file" "src/a.py" d9)" = skip ] \
    && pass "ledger: a clean row over an unchanged file authorises a skip for its criterion" \
    || fail "ledger: a valid row did not authorise a skip"

# The whole point of keying to the criterion: one criterion's row says nothing
# about its sibling in the same dimension and the same file.
[ "$(ledger_skips "$row_sibling" "src/a.py" d9)" = audit:verdict-uncovered ] \
    && pass "ledger: a sibling criterion's uncovered row is audited, while its neighbour skips" \
    || fail "ledger: an uncovered criterion was skipped on a sibling's clean verdict"

[ "$(ledger_skips "$row_in_file" "src/a.py" d10)" = audit:digest-changed ] \
    && pass "ledger: a changed roster digest invalidates rows recorded under the previous one" \
    || fail "ledger: a row survived a roster change"

[ "$(ledger_skips "$row_cross" "src/route.py docs/api.md" d9 1)" = skip ] \
    && pass "ledger: a cross-file row skips only once both recorded paths re-prove unchanged" \
    || fail "ledger: a fully re-proved cross-file row did not skip"

[ "$(ledger_skips "$row_cross" "src/route.py" d9 1)" = audit:second-path-changed ] \
    && pass "ledger: a cross-file row whose second path changed is audited -- that is the defect it would hide" \
    || fail "ledger: a cross-file row cached over a changed counterpart"

[ "$(ledger_skips "$row_cross_half" "src/route.py" d9 1)" = audit:no-second-path ] \
    && pass "ledger: a cross-file criterion with no recorded second path is never skip-eligible" \
    || fail "ledger: a half-recorded cross-file row authorised a skip"

# The second compaction level. Above COMPACT_ABOVE the rows are already at
# directory granularity; if that still will not fit, a dimension's criterion
# rows collapse into one row carrying `all`, and the run degrades to the cache
# granularity it had before criteria existed rather than stopping.
compact_criteria() { # rows -> one row per dimension+path, criterion column `all`
    printf '%s\n' "$1" | awk -F' [|] ' '
        { key = $1 SUBSEP $3
          if (!(key in seen)) { seen[key]; order[++n] = key; dim[key] = $1; path[key] = $3
                                p2[key] = $4; sha[key] = $6; dg[key] = $7; at[key] = $8 }
          if ($5 != "clean") dirty[key] = 1 }
        END { for (i = 1; i <= n; i++) { k = order[i]
                print dim[k] " | all | " path[k] " | " p2[k] " | " (dirty[k] ? "uncovered" : "clean") \
                      " | " sha[k] " | " dg[k] " | " at[k] } }
    '
}

collapsed=$(compact_criteria "$(printf '%s\n%s\n' "$row_in_file" "$row_sibling")")
[ "$(printf '%s\n' "$collapsed" | wc -l | tr -d ' ')" -eq 1 ] \
    && pass "compaction: a dimension's criterion rows collapse to one row for that path" \
    || fail "compaction: the second level did not reduce the row count"
[ "$(ledger_skips "$collapsed" "src/a.py" d9)" = audit:verdict-uncovered ] \
    && pass "compaction: a collapsed row authorises a skip only where every criterion under it was clean" \
    || fail "compaction: collapsing laundered an uncovered criterion into a clean row"

both_clean=$(compact_criteria "$(printf '%s\n%s\n' "$row_in_file" "$(printf '%s\n' "$row_sibling" | sed 's/| uncovered |/| clean |/')")")
[ "$(ledger_skips "$both_clean" "src/a.py" d9)" = skip ] \
    && pass "compaction: a collapsed row over uniformly clean criteria still caches, as it did before criteria existed" \
    || fail "compaction: the degraded path lost the caching it is supposed to preserve"

# ---------------------------------------------------------------------------
# THE FILING CEILING'S APPORTIONMENT, REPLAYED.
#
# The roster looks for far more than it did and the ceiling did not grow with
# it, so how the budget is divided decides what a reader of the tracker sees.
# Filed first-come, one prolific criterion spends the whole budget before a
# later criterion files anything.
# ---------------------------------------------------------------------------
apportion() { # ceiling, then "<criterion>:<confirmed>" per argument -> "<criterion>:<filed>" lines
    cap=$1; shift
    printf '%s\n' "$@" | awk -F: -v cap="$cap" '
        { crit[++n] = $1; want[n] = $2 + 0 }
        END {
            share = int(cap / n)
            used = 0
            for (i = 1; i <= n; i++) { got[i] = (want[i] < share) ? want[i] : share; used += got[i] }
            left = cap - used
            # Second pass: the unused share returns to whoever still has findings.
            changed = 1
            while (left > 0 && changed) {
                changed = 0
                for (i = 1; i <= n && left > 0; i++)
                    if (got[i] < want[i]) { got[i]++; left--; changed = 1 }
            }
            for (i = 1; i <= n; i++) print crit[i] ":" got[i]
        }
    '
}

# One prolific criterion and three quiet ones. First-come would file 40 of the
# prolific one's findings and none of the others.
apportioned=$(apportion 40 a:100 b:5 c:5 d:5)
[ "$(printf '%s\n' "$apportioned" | awk -F: '{ s += $2 } END { print s }')" -eq 40 ] \
    && pass "apportionment: the whole ceiling is spent, and no more than the ceiling" \
    || fail "apportionment: the filed total does not equal FILING_CEILING"
[ "$(printf '%s\n' "$apportioned" | awk -F: '$1 == "b" { print $2 }')" -eq 5 ] \
    && pass "apportionment: a quiet criterion files everything it confirmed rather than being crowded out" \
    || fail "apportionment: a prolific criterion crowded out a quiet one's confirmed findings"
[ "$(printf '%s\n' "$apportioned" | awk -F: '$1 == "a" { print $2 }')" -eq 25 ] \
    && pass "apportionment: the unused share returns to the criterion that can still use it" \
    || fail "apportionment: the returned share was not redistributed"

# Nobody is over the ceiling, so nobody is apportioned away from.
under=$(apportion 40 a:3 b:4)
[ "$(printf '%s\n' "$under" | awk -F: '{ s += $2 } END { print s }')" -eq 7 ] \
    && pass "apportionment: a run under the ceiling files every confirmed finding" \
    || fail "apportionment: a run under the ceiling lost findings to the division"

# A single criterion holding everything still gets the whole budget: the rule
# apportions, it does not cap a criterion at its share.
solo=$(apportion 40 a:100)
[ "$(printf '%s\n' "$solo" | awk -F: '{ print $2 }')" -eq 40 ] \
    && pass "apportionment: one criterion holding every confirmed finding still fills the ceiling" \
    || fail "apportionment: the division starved the only criterion with findings"

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

# `timeout` is GNU coreutils and is absent from a stock macOS, where Homebrew
# installs the same binary as `gtimeout`. Probe rather than assume: an
# unresolved `timeout` would fail every case with "command not found" folded
# into an empty emit, which reads as a procedure defect rather than a missing
# prerequisite.
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

# ---------------------------------------------------------------------------
# THE PER-CASE DEADLINE, DERIVED FROM THE PROCEDURE'S OWN CONSTANTS BLOCK.
#
# Never copied from the census suite. That suite's kill is sized for a
# procedure that reads a six-issue tracker; a repo-audit case drives preflight,
# a sweep, deduplication, verification, filing and a report, and a deadline
# borrowed from the smaller procedure would kill every case mid-run. The
# runner's own guard would then report each kill as a runner failure rather
# than as a classification result, which is a suite that reports noise.
#
# Every case here runs the REDUCED FIXTURE ROSTER -- no subagent, no wave, no
# round -- so the bound that applies is one wave's worth of orchestrator wall
# clock. The full-roster bound is computed too, and printed, so the cost this
# suite is declining to spend is visible rather than assumed.
# ---------------------------------------------------------------------------
# The constants and both rosters were parsed and validated in PART 1, which is
# the part CI runs. Re-parsing them here would let the deadline math and the
# emit assertions drift apart.
case_deadline=$((wave_min * 60))
waves=$(((roster_size + fanout_floor - 1) / fanout_floor))
full_deadline=$((max_rounds * waves * (wave_min + pop_min) * 60))

echo "  roster: $roster_size dimensions, $waves wave(s) at a width of $fanout_floor"
echo "  per-case deadline: ${case_deadline}s (WAVE_DEADLINE), reduced fixture roster, no spawn"
echo "  a full-roster case would be bounded at ${full_deadline}s; none runs here"
# Every invocation of the host CLI, counted rather than guessed: two positive
# controls, one run for each of cases A, B, C and G, two each for D, E and both
# halves of F, and one for H under its own one-second deadline. A hand-written
# literal here drifts the moment a case is added, and this number exists to
# tell a reader what the suite will cost before they start it.
HOST_RUNS_PLANNED=15
echo "  worst case for this suite: $HOST_RUNS_PLANNED host runs, so up to $(((HOST_RUNS_PLANNED - 1) * case_deadline + 1))s"
echo ""

# ---------------------------------------------------------------------------
# The seeded target repository. The fixtures name paths, and a run that cannot
# resolve them audits nothing; the report cases additionally need a real VCS to
# ask whether the report path is ignored.
# ---------------------------------------------------------------------------
fresh_target() { # ignore_reports: yes | no
    ignore_reports=$1
    dir=$(mktemp -d "$work/target.XXXXXX")
    mkdir -p "$dir/src"
    for f in reader.py queue.py config.py pool.py pooling.py; do
        printf 'def placeholder():\n    return None\n' > "$dir/src/$f"
    done
    (
        cd "$dir" || exit 1
        git init -q .
        # bd init APPENDS its own entries to .gitignore, so it runs before the
        # report-path entry and before the commit. Otherwise the seeded tree is
        # dirty from the moment it is created, and preflight would record a
        # dirty path in every single case.
        bd init --prefix ra >/dev/null 2>&1
        [ "$ignore_reports" = yes ] && printf 'docs/audits/\n' >> .gitignore
        git add -A
        git -c user.email=suite@example.invalid -c user.name=suite commit -qm seed
    )
    echo "$dir"
}

# Counted by parsing the payload, not by counting lines that carry an "id"
# key. `bd` pretty-prints one field per line today, so a line count happens to
# agree -- but it agrees by formatting rather than by structure, and a compact
# payload or one nested id would silently miscount the very number that decides
# whether a run wrote nothing. `bd` returns a bare list from some subcommands
# and an object keyed by "issues" from others, so both shapes are accepted.
issue_count() { # target_dir
    bd -C "$1" list --all --limit 0 --json 2>/dev/null | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(0); raise SystemExit
rows = d if isinstance(d, list) else d.get("issues", d)
print(len(rows))' 2>/dev/null || echo 0
}

# Writes the host's combined output to $host_out and sets $host_status. It
# does NOT print to stdout: a status set inside a command substitution dies
# with the subshell, and every caller here needs both the output and the exit
# code of the same invocation.
host_out="$work/host-out"
host_run() { # prompt, tools
    _prompt=$1
    _tools=$2
    if [ "$host_cli" = "claude" ] && [ -n "$_tools" ]; then
        set -- --allowedTools "$_tools"
    else
        set --
    fi
    # Tallied through the filesystem, not through a shell variable. Nine of
    # this suite's fifteen invocations sit inside `$( )`, which runs this
    # function in a subshell -- an incremented variable dies with it, and the
    # count printed at the end would report 6 of 15 on every complete run.
    printf 'x' >> "$host_runs_file"
    set +e
    "$deadline" "$case_deadline" "$host_cli" -p "$_prompt" "$@" > "$host_out" 2>&1
    host_status=$?
    set -e
}
host_runs_file="$work/host-runs"
: > "$host_runs_file"
host_runs() { wc -c < "$host_runs_file" | tr -d ' '; }

# Feed a fixture set to the orchestrator with NO SUBAGENTS SPAWNED. The
# procedure's discovery half is skipped by handing it findings that are already
# verified; what runs is everything from deduplication onward.
run_audit() { # target_dir, mode, fixture_dir, label, extra_instructions
    target=$1; mode=$2; fx=$3; label=$4; extra=$5
    prompt="Read the repo-audit skill at $skill.
The target repository is $target and its Beads store is there; issue every
tracker command as 'bd -C $target ...'.
Its discovery half has already run. Treat the verified findings in $fx as its
output: one record per .fixture file, one 'key: value' per line. If $fx holds a
file named 'renames', each of its lines is 'old-path -> new-path' for the rename
reconciliation.
Spawn NO subagents. Run everything from deduplication onward as a $mode run.
$extra
Print the audit-run header line, one dimension line per roster dimension, and
one finding line per surviving candidate, between a line reading AUDIT-BEGIN and
a line reading AUDIT-END, and nothing else between those markers."
    # No criterion line is asked for. These cases spawn no subagents, so the
    # discovery half that measures per-criterion coverage never runs, and any
    # criterion line the model printed would be invented. The COUNT THE EMIT
    # criterion clause is replayed in PART 1 over a canned record instead --
    # which is also where CI can reach it.
    host_run "$prompt" 'Bash(bd:*),Read,Write,Glob,Grep'
    # Each case's transcript is named after its own target and label, so two
    # cases never overwrite one another's evidence.
    if [ -n "${AUDIT_RAW_DIR:-}" ]; then
        mkdir -p "$AUDIT_RAW_DIR"
        cp "$host_out" "$AUDIT_RAW_DIR/${target##*/}-$label.log"
    fi
    if [ "$host_status" -ne 0 ]; then
        echo "__AUDIT_RUNNER_FAILED__ $host_cli exited $host_status"
        return
    fi
    sed -n '/^AUDIT-BEGIN$/,/^AUDIT-END$/p' "$host_out" \
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

# Normalize the two fields no suite can predict -- the fingerprint hash and the
# tracker id -- so an emitted table can be diffed against an expected one. The
# fingerprint is replaced positionally by the order of first appearance, which
# keeps the DISTINCTNESS of the field checkable while dropping its value.
normalize_findings() {
    awk -F' \\| ' '
        /^finding /{
            fp = $1; sub(/^finding /, "", fp)
            if (!(fp in seen)) { seen[fp] = ++n }
            id = $5; if (id != "none") { id = "ID" }
            printf "finding #%d | %s | %s | %s | %s | %s\n", seen[fp], $2, $3, $4, id, $6
        }
    '
}

# ---------------------------------------------------------------------------
# POSITIVE CONTROLS, BEFORE ANY NEGATIVE ASSERTION.
#
# A serially degraded read-only run satisfies every "no write" and every
# coverage assertion below for reasons that have nothing to do with the
# procedure. So prove first that this harness CAN write to the tracker and CAN
# spawn an agent. An unproven control fails with its own text; it never passes,
# and it never lets the assertion it guards pass either.
# ---------------------------------------------------------------------------
write_proven=0
spawn_proven=0

control_target=$(fresh_target no)
host_run "Run exactly this command and nothing else, then print the word DONE:
bd -C $control_target create 'control probe' --silent" 'Bash(bd:*)'
if [ "$host_status" -eq 0 ] && [ "$(issue_count "$control_target")" -ge 1 ]; then
    write_proven=1
    pass "positive control: this harness can write an issue through the host CLI"
else
    fail "positive control unproven: no issue reached the store, so every no-write assertion below would be vacuous"
fi

spawn_token="spawn-$$-$(date +%s)"
spawn_probe="$work/spawn-probe"
host_run "Spawn exactly one subagent whose only instruction is to write the
text $spawn_token into the file $spawn_probe. Wait for it, then print DONE." \
    'Task,Write,Bash'
if [ "$host_status" -eq 0 ] && [ -f "$spawn_probe" ] && grep -q "$spawn_token" "$spawn_probe"; then
    spawn_proven=1
    pass "positive control: this harness can spawn a subagent that writes a file"
else
    fail "positive control unproven: no subagent wrote the probe file, so a host that cannot spawn is indistinguishable from one that can"
fi

guarded() { # flag, description -> 0 when the guarding control was proven
    [ "$1" -eq 1 ] && return 0
    fail "not run, its positive control was unproven: $2"
    return 1
}

# The spawn control guards every FILING assertion, and this is why. The
# procedure degrades a host that cannot spawn to a serial run, and a serial run
# is READ-ONLY by its own rule. So on such a host every writing case here files
# nothing for a reason that has nothing to do with the write protocol: case B's
# "filed at least one finding" fails, and case A's "wrote only the index"
# passes, both misattributed. The cases themselves ask for no subagent -- they
# drive the tracker half from a fixture -- but what they assert about filing is
# only meaningful on a host where the procedure would not have degraded.
filing_proven=0
[ "$write_proven" -eq 1 ] && [ "$spawn_proven" -eq 1 ] && filing_proven=1

# ---------------------------------------------------------------------------
# CASE A - the first run against a fresh target.
#
# It files NOTHING whichever prompt invoked it, and makes exactly one tracker
# write: the index issue. Expect three finding lines, all report-only.
# ---------------------------------------------------------------------------
echo ""
echo "  case A: first run, fresh target, writing mode"
target_a=$(fresh_target no)
emit_a=$(run_audit "$target_a" writing "$fixtures" first "This is the first run against this repository.")

if emit_usable "$emit_a"; then
    headers=$(printf '%s\n' "$emit_a" | grep -c '^audit-run ' || true)
    [ "$headers" -eq 1 ] \
        && pass "the run emitted exactly one audit-run header" \
        || fail "the run emitted $headers audit-run header(s), wanted 1"

    dims=$(printf '%s\n' "$emit_a" | grep -c '^dimension ' || true)
    [ "$dims" -eq "$roster_size" ] \
        && pass "the run emitted one dimension line per roster dimension" \
        || fail "the run emitted $dims dimension line(s), wanted $roster_size"

    finds=$(printf '%s\n' "$emit_a" | grep -c '^finding ' || true)
    [ "$finds" -eq "$count" ] \
        && pass "the run emitted one finding line per fixture record" \
        || fail "the run emitted $finds finding line(s), wanted $count"

    violations=$(printf '%s\n' "$emit_a" | field_count_violations)
    [ -z "$violations" ] \
        && pass "every emitted line parses into its declared field set with no blank field" \
        || fail "emitted line(s) violate the field set: $(printf '%s' "$violations" | head -n 1)"

    printf '%s\n' "$emit_a" | grep -q '^audit-run .*first-run' \
        && pass "the header carries the first-run flag" \
        || fail "the header does not carry the first-run flag"

    # THE EXPECTED TABLE. Fingerprints are positional and issue ids are folded
    # to ID, so what is diffed is the dimension list, the severity, the
    # disposition, the resolution to an issue or not, and the location.
    cat > "$work/expected-a" <<'EXPECTED'
finding #1 | correctness and control flow | P1 | report-only | none | src/reader.py:41-47
finding #2 | state, ordering, and idempotency,correctness and control flow | P0 | report-only | none | src/queue.py:88-96
finding #3 | input boundaries and untrusted data | P0 | report-only | none | src/config.py:12-12
EXPECTED
    printf '%s\n' "$emit_a" | normalize_findings | sort > "$work/actual-a"
    sort "$work/expected-a" > "$work/expected-a.sorted"
    if diff -u "$work/expected-a.sorted" "$work/actual-a" > "$work/diff-a" 2>&1; then
        pass "the first run's finding lines diff clean against the expected table"
    else
        fail "the first run's finding lines differ from the expected table: $(head -n 8 "$work/diff-a" | tr '\n' ' ')"
    fi

    if guarded "$filing_proven" "the first run files nothing but the index"; then
        n=$(issue_count "$target_a")
        [ "$n" -eq 1 ] \
            && pass "the first run made exactly one tracker write" \
            || fail "the first run left $n issue(s) in the store, wanted 1 (the index)"
    fi
fi

# ---------------------------------------------------------------------------
# CASE B - the second run against the same target. Now it files.
# ---------------------------------------------------------------------------
echo ""
echo "  case B: second run against the same target"
emit_b=$(run_audit "$target_a" writing "$fixtures" second "This repository already holds this audit's index issue.")

if emit_usable "$emit_b"; then
    filed=$(printf '%s\n' "$emit_b" | grep -c '^finding .* | filed | ' || true)
    [ "$filed" -ge 1 ] \
        && pass "the second run filed at least one finding" \
        || fail "the second run filed nothing; the first-run carve-out did not end"

    noneid=$(printf '%s\n' "$emit_b" | grep '^finding .* | filed | ' | grep -c '| none |' || true)
    [ "$noneid" -eq 0 ] \
        && pass "every filed finding line resolves to a tracker id" \
        || fail "$noneid filed finding line(s) carry no issue id"

    if guarded "$filing_proven" "the second run's issues reach the store"; then
        n=$(issue_count "$target_a")
        [ "$n" -gt 1 ] \
            && pass "the second run left $n issue(s) in the store" \
            || fail "the second run left $n issue(s); nothing was filed"
    fi
fi

# ---------------------------------------------------------------------------
# CASE C - a read-only run writes nothing at all.
# ---------------------------------------------------------------------------
echo ""
echo "  case C: read-only run"
target_c=$(fresh_target no)
before_c=$(issue_count "$target_c")
emit_c=$(run_audit "$target_c" readonly "$fixtures" readonly "Every bd command carries the tracker's read-only flag.")

if emit_usable "$emit_c"; then
    printf '%s\n' "$emit_c" | grep -q '^audit-run [^|]* | [^|]* | readonly | ' \
        && pass "the read-only run's header declares the readonly mode" \
        || fail "the read-only run's header does not declare the readonly mode"

    if guarded "$write_proven" "the read-only run wrote nothing"; then
        after_c=$(issue_count "$target_c")
        [ "$after_c" -eq "$before_c" ] \
            && pass "the read-only run left the store untouched" \
            || fail "the read-only run changed the store from $before_c to $after_c issue(s)"
    fi
fi

# ---------------------------------------------------------------------------
# CASE D - the fingerprint-stability corpus.
#
# Five mutations of one defect must yield ONE fingerprint; two co-located
# distinct defects under the same rule must yield TWO. So the seven records
# must emit exactly three distinct fingerprints.
# ---------------------------------------------------------------------------
echo ""
echo "  case D: the fingerprint corpus"
target_d=$(fresh_target no)
run_audit "$target_d" writing "$corpus" corpus-first "This is the first run against this repository." >/dev/null
emit_d=$(run_audit "$target_d" writing "$corpus" corpus "This repository already holds this audit's index issue.")

if emit_usable "$emit_d"; then
    distinct=$(printf '%s\n' "$emit_d" | grep '^finding ' \
        | awk -F' \\| ' '{ fp = $1; sub(/^finding /, "", fp); print fp }' \
        | sort -u | wc -l | tr -d ' ')
    [ "$distinct" -eq 3 ] \
        && pass "the corpus yielded three distinct fingerprints: one for the five mutations, two for the co-located pair" \
        || fail "the corpus yielded $distinct distinct fingerprint(s), wanted 3 ($CORPUS_ONE_FINGERPRINT as one, $CORPUS_DISTINCT apart)"

    # Distinctness alone does not prove the collapse happened. Seven finding
    # lines, five of them carrying the same correctly-computed fingerprint,
    # yield exactly three distinct values and would pass the check above while
    # filing five issues for one defect. The line count is what says the five
    # became one.
    corpus_finds=$(printf '%s\n' "$emit_d" | grep -c '^finding ' || true)
    [ "$corpus_finds" -eq 3 ] \
        && pass "the corpus emitted three finding lines, so the five mutations collapsed to one candidate" \
        || fail "the corpus emitted $corpus_finds finding line(s), wanted 3; the mutations did not collapse"
fi

# ---------------------------------------------------------------------------
# CASE E - a public target redacts, in the filed issue as well as the emit.
# ---------------------------------------------------------------------------
echo ""
echo "  case E: public target, security-class finding"
target_e=$(fresh_target no)
run_audit "$target_e" writing "$fixtures" public-first "This is the first run against this repository. Treat the repository's visibility as PUBLIC." >/dev/null
emit_e=$(run_audit "$target_e" writing "$fixtures" public "This repository already holds this audit's index issue. Treat the repository's visibility as PUBLIC.")

if emit_usable "$emit_e" && guarded "$filing_proven" "the public target's filed issues carry no exploit detail"; then
    bodies=$(bd -C "$target_e" list --all --limit 0 --json 2>/dev/null; bd -C "$target_e" list --type gate --json 2>/dev/null)
    if printf '%s' "$bodies" | grep -q 'fh = open(path)'; then
        fail "a filed issue quotes the evidence literal on a public target"
    else
        pass "no filed issue quotes an evidence literal on a public target"
    fi
    if printf '%s' "$bodies" | grep -q 'literal:\|re2:'; then
        fail "a filed issue carries a recipe literal or pattern on a public target"
    else
        pass "no filed issue carries a recipe literal or pattern on a public target"
    fi
fi

# ---------------------------------------------------------------------------
# CASE F - the report, and the two-artifact split.
#
# F1: a target whose report path the VCS ignores says so twice.
# F2: a PUBLIC target whose report path is TRACKED writes no security section
#     to disk and says so in the closing summary.
# ---------------------------------------------------------------------------
echo ""
echo "  case F: the report and the disclosure split"
target_f1=$(fresh_target yes)
run_audit "$target_f1" writing "$fixtures" report-ignored-first "This is the first run against this repository." >/dev/null
emit_f1=$(run_audit "$target_f1" writing "$fixtures" report-ignored "This repository already holds this audit's index issue. Write the report as the procedure requires.")
emit_usable "$emit_f1" || true

report_f1=$(find "$target_f1/docs/audits" -name '*-audit.md' 2>/dev/null | head -n 1)
if [ -n "$report_f1" ]; then
    pass "the run wrote a report to the path the procedure names"
    opening=$(head -n 30 "$report_f1" | grep -ci 'ignored' || true)
    closing=$(tail -n 40 "$report_f1" | grep -ci 'ignored' || true)
    if [ "$opening" -ge 1 ] && [ "$closing" -ge 1 ]; then
        pass "the ignored report path is stated in both the opening and the closing summary"
    else
        fail "the ignored report path is stated $opening time(s) in the opening and $closing in the closing summary; wanted both"
    fi
    for want in 'P4' 'refuted' 'skipped'; do
        grep -qi "$want" "$report_f1" \
            && pass "the report carries the $want material the tracker never receives" \
            || fail "the report does not mention $want"
    done
    for want in 'suppress' 'defer' 'ceiling'; do
        grep -qi "$want" "$report_f1" \
            && pass "the report accounts for what was $want-related" \
            || fail "the report does not account for anything $want-related"
    done
    grep -qi 'bd .*close' "$report_f1" \
        && pass "the report closes with a bulk-retraction recipe" \
        || fail "the report carries no bulk-retraction recipe"
else
    fail "the run wrote no report under $target_f1/docs/audits"
fi

target_f2=$(fresh_target no)
run_audit "$target_f2" writing "$fixtures" report-tracked-first "This is the first run against this repository. Treat the repository's visibility as PUBLIC." >/dev/null
emit_f2=$(run_audit "$target_f2" writing "$fixtures" report-tracked "This repository already holds this audit's index issue. Treat the repository's visibility as PUBLIC. Write the report as the procedure requires.")
emit_usable "$emit_f2" || true

report_f2=$(find "$target_f2/docs/audits" -name '*-audit.md' 2>/dev/null | head -n 1)
if [ -n "$report_f2" ]; then
    if grep -q 'fh = open(path)' "$report_f2"; then
        fail "the public target's committed report carries exploit detail"
    else
        pass "the public target's committed report carries no exploit detail"
    fi
    tail -n 40 "$report_f2" | grep -qi 'withheld\|not written\|no ignored path' \
        && pass "the closing summary says the security detail was withheld" \
        || fail "the closing summary does not say the security detail was withheld"
else
    fail "the public run wrote no report under $target_f2/docs/audits"
fi

# ---------------------------------------------------------------------------
# CASE G - the emit self-count. A run one dimension line short names the
# missing dimension and stops BEFORE the report and before any write.
# ---------------------------------------------------------------------------
echo ""
echo "  case G: a short emit stops the run"
target_g=$(fresh_target no)
before_g=$(issue_count "$target_g")
emit_g=$(run_audit "$target_g" writing "$fixtures" short-emit \
    "This repository already holds this audit's index issue. One roster dimension -- dead and duplicated code -- produced no dimension line at all.")

case "$emit_g" in
    __AUDIT_RUNNER_FAILED__*) fail "audit runner failed:${emit_g#__AUDIT_RUNNER_FAILED__}" ;;
    *)
        printf '%s\n' "$emit_g" | grep -qi 'dead and duplicated code' \
            && pass "the short run names the missing dimension" \
            || fail "the short run does not name the missing dimension"

        if guarded "$write_proven" "the short run wrote nothing"; then
            after_g=$(issue_count "$target_g")
            [ "$after_g" -eq "$before_g" ] \
                && pass "the short run wrote nothing" \
                || fail "the short run wrote $((after_g - before_g)) issue(s) after failing its own count"
        fi
        ;;
esac

# ---------------------------------------------------------------------------
# CASE H - a case killed by the deadline reports a RUNNER FAILURE rather than
# an empty emit. Driven with a one-second deadline, so it is cheap and certain.
# ---------------------------------------------------------------------------
echo ""
echo "  case H: a deadline kill is a runner failure, not an empty result"
saved_deadline=$case_deadline
case_deadline=1
killed=$(run_audit "$(fresh_target no)" writing "$fixtures" killed "This is the first run against this repository.")
case_deadline=$saved_deadline
case "$killed" in
    __AUDIT_RUNNER_FAILED__*) pass "a killed case reports a runner failure" ;;
    "") fail "a killed case reported an empty emit; the kill is indistinguishable from a run that emitted nothing" ;;
    *) fail "a killed case returned output; the deadline did not fire" ;;
esac

host_runs_made=$(host_runs)
printf '\n%d check(s), %d failure(s), %d host run(s)\n' "$checks" "$failures" "$host_runs_made"
[ "$host_runs_made" -eq "$HOST_RUNS_PLANNED" ] ||
    printf 'note: the suite planned %d host run(s) and made %d; the printed cost estimate is stale\n' \
        "$HOST_RUNS_PLANNED" "$host_runs_made"
[ "$failures" -eq 0 ] || exit 1
