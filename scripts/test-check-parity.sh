#!/bin/sh
# Prove that check-parity.sh actually detects a broken tree.
#
# Usage: test-check-parity.sh [path-to-check-parity.sh]
#
# Copies the real skills tree into a fresh temporary directory per case,
# applies a single break, and requires the checker to exit non-zero AND to say
# why in a way that matches the case. Asserting the message matters: without
# it a case passes whenever the checker fails for any reason at all, including
# a reason unrelated to the break the case is named after.
#
# Cases come in two kinds. Drift cases make the two host copies disagree.
# False-pass cases leave the copies in perfect agreement but make each of them
# something a host would reject -- unclosed frontmatter, a name no host
# accepts, a missing required key, an invocation policy at the wrong path, a
# file neither host allows. Those are the shapes a parity-only checker is blind
# to by construction, and they are the ones this suite exists to keep covered.
#
# Every case is run once per skill in the tree rather than against one
# hardcoded name, because a checker that stops after the first skill it finds
# passes a suite that only ever breaks the first skill. To make that
# discriminate before a second real skill exists, fresh_tree() plants a
# synthetic clone of the first skill in every case tree.
#
# Finally the whole suite runs again against a deliberately weakened checker
# and requires *every* break to go undetected. Requiring all of them, rather
# than merely one, is what separates a suite that discriminates from a suite
# that crashed: an environmental failure would not miss exactly the full set.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
checker="${1:-$repo_root/scripts/check-parity.sh}"

work=$(mktemp -d "${TMPDIR:-/tmp}/test-check-parity.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# The clone fresh_tree() plants in every case tree. Its name must sort after a
# real skill's for no reason the suite depends on -- the cases are run per
# skill, in whatever order discovery returns.
SYNTHETIC_SKILL="synthetic-parity-probe"

# GNU and BSD sed disagree about -i; normalize.
sed_inplace() {
    sed "$1" "$2" > "$2.tmp" && mv "$2.tmp" "$2"
}

# tree, host, skill -> the directory holding that copy of that skill.
skill_dir() {
    echo "$1/skills/$2/$3"
}

# Skill names present in a tree, sorted. Read from the Claude host because
# every skill exists under both; a case that removes one host's copy is applied
# after discovery, never before it.
list_tree_skills() {
    for d in "$1"/skills/claude/*; do
        [ -d "$d" ] || continue
        basename "$d"
    done | LC_ALL=C sort
}

# Plant a second skill in a case tree: a clone of the first real one, renamed
# in its directory, its `name:` frontmatter, and its agents/openai.yaml.
#
# Without this the per-skill parameterization below ships with its own
# discriminating case never exercised -- the suite would run once, over one
# skill, and prove nothing about a checker that handles only the first. That is
# the vacuity class this repository has already had to fix twice (1a93005,
# 5f709e2), so the clone lands with the parameterization rather than waiting for
# a second real skill to arrive.
plant_synthetic_skill() {
    tree="$1"
    source_skill=$(list_tree_skills "$tree" | head -n 1)
    if [ -z "$source_skill" ]; then
        echo "FAIL: no skill under $tree/skills/claude to clone" >&2
        exit 1
    fi
    for host in claude codex; do
        cp -R "$(skill_dir "$tree" "$host" "$source_skill")" \
              "$(skill_dir "$tree" "$host" "$SYNTHETIC_SKILL")"
        sed_inplace "s/^name: .*/name: $SYNTHETIC_SKILL/" \
            "$(skill_dir "$tree" "$host" "$SYNTHETIC_SKILL")/SKILL.md"
        # A no-op today -- the policy file names no skill -- but the clone has
        # to stay a clone if one is ever added there.
        yaml="$(skill_dir "$tree" "$host" "$SYNTHETIC_SKILL")/agents/openai.yaml"
        [ -f "$yaml" ] || continue
        sed_inplace "s/^\\([[:space:]]*\\)name:[[:space:]].*/\\1name: $SYNTHETIC_SKILL/" "$yaml"
    done
}

# Fresh copy of the real tree plus the synthetic skill; echoes the tree root to
# build cases against. mktemp -d gives each case its own empty directory: this
# function runs inside a command substitution, so a shell variable used as a
# counter would live in a subshell and never advance, silently making every
# case share one tree.
fresh_tree() {
    dir=$(mktemp -d "$work/case.XXXXXX")
    cp -R "$repo_root/skills" "$dir/skills"
    plant_synthetic_skill "$dir"
    echo "$dir"
}

# Apply an edit to both host copies of one skill's SKILL.md.
both_copies() {
    for host in claude codex; do
        sed_inplace "$1" "$(skill_dir "$2" "$host" "$3")/SKILL.md"
    done
}

# Delete the frontmatter's closing '---' in both host copies. Done by matching
# the delimiter rather than by line number because the block's length differs
# between skills, and between the two copies of one skill: the Claude copy
# carries disable-model-invocation and the Codex copy does not, so one fixed
# line number deletes a different line in each.
unclose_frontmatter() {
    for host in claude codex; do
        f="$(skill_dir "$1" "$host" "$2")/SKILL.md"
        awk 'NR == 1 { print; next }
             !dropped && /^---$/ { dropped = 1; next }
             { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
}

run_checker() {
    status=0
    sh "$checker_under_test" "$1" > "$work/out" 2>&1 || status=$?
    echo "$status"
}

failures=0
break_cases=0
case_skill=""

# Every case label names the skill it broke, so a checker that only ever looks
# at the first skill reports which one it stopped at.
label_for() {
    if [ -n "$case_skill" ]; then
        echo "[$case_skill] $1"
    else
        echo "$1"
    fi
}

# A break the checker must catch, and the text it must say when it does.
expect_fail() {
    label=$(label_for "$1"); root="$2"; want="$3"
    break_cases=$((break_cases + 1))
    if [ "$(run_checker "$root")" -eq 0 ]; then
        echo "  NOT DETECTED: $label"
        failures=$((failures + 1))
    elif ! grep -q "$want" "$work/out"; then
        echo "  WRONG REASON: $label (no match for '$want')"
        echo "                said: $(head -n 1 "$work/out")"
        failures=$((failures + 1))
    else
        echo "  detected: $label"
    fi
}

expect_pass() {
    label=$(label_for "$1"); root="$2"
    if [ "$(run_checker "$root")" -eq 0 ]; then
        echo "  clean: $label"
    else
        echo "  FALSE ALARM: $label -- $(head -n 1 "$work/out")"
        failures=$((failures + 1))
    fi
}

# Every case that breaks one named skill. Run once per discovered skill.
run_skill_cases() {
    skill="$1"

    # ---- drift: the two copies disagree ----

    t=$(fresh_tree)
    printf '\nA line added to only one host copy.\n' >> "$(skill_dir "$t" claude "$skill")/SKILL.md"
    expect_fail "body edit in the Claude copy only" "$t" "bodies differ"

    t=$(fresh_tree)
    printf '\nA line added to only one host copy.\n' >> "$(skill_dir "$t" codex "$skill")/SKILL.md"
    expect_fail "body edit in the Codex copy only" "$t" "bodies differ"

    t=$(fresh_tree)
    sed_inplace '2i\
disable-model-invocation: true' "$(skill_dir "$t" codex "$skill")/SKILL.md"
    expect_fail "disable-model-invocation added to the Codex copy" "$t" "which Codex rejects"

    t=$(fresh_tree)
    sed_inplace '/^disable-model-invocation: true$/d' "$(skill_dir "$t" claude "$skill")/SKILL.md"
    expect_fail "disable-model-invocation removed from the Claude copy" "$t" "is missing 'disable-model-invocation'"

    t=$(fresh_tree)
    sed_inplace 's/^description: .*/description: Edited in one copy only./' \
        "$(skill_dir "$t" claude "$skill")/SKILL.md"
    expect_fail "description edited in the Claude copy only" "$t" "frontmatter differs outside"

    t=$(fresh_tree)
    sed_inplace '2i\
license: MIT' "$(skill_dir "$t" claude "$skill")/SKILL.md"
    expect_fail "an allowed key added to the Claude copy only" "$t" "frontmatter differs outside"

    # A nested block: the divergence is inside the value, not on the key line,
    # so a check that compares one line per key cannot see it.
    t=$(fresh_tree)
    both_copies '2i\
metadata:\
  version: 1\
  audience: everyone' "$t" "$skill"
    sed_inplace 's/^  audience: everyone$/  audience: nobody/' \
        "$(skill_dir "$t" codex "$skill")/SKILL.md"
    expect_fail "nested frontmatter value diverges" "$t" "frontmatter differs outside"

    t=$(fresh_tree)
    printf 'shared\n' > "$(skill_dir "$t" claude "$skill")/reference.md"
    expect_fail "auxiliary file present in the Claude copy only" "$t" "different files"

    t=$(fresh_tree)
    printf 'one\n' > "$(skill_dir "$t" claude "$skill")/reference.md"
    printf 'two\n' > "$(skill_dir "$t" codex "$skill")/reference.md"
    expect_fail "auxiliary file differs between copies" "$t" "differs between the two host copies"

    # Identical in both copies, so the copy-to-copy comparison is blind to it.
    # Only the per-host allowed set can see this one.
    t=$(fresh_tree)
    printf 'shared\n' > "$(skill_dir "$t" claude "$skill")/reference.md"
    printf 'shared\n' > "$(skill_dir "$t" codex "$skill")/reference.md"
    expect_fail "a third file added identically to both copies" "$t" "outside the allowed set"

    t=$(fresh_tree)
    cp -R "$(skill_dir "$t" claude "$skill")" "$t/skills/claude/only-on-one-host"
    expect_fail "skill present under skills/claude only" "$t" "missing from skills/codex"

    t=$(fresh_tree)
    cp -R "$(skill_dir "$t" codex "$skill")" "$t/skills/codex/only-on-one-host"
    expect_fail "skill present under skills/codex only" "$t" "missing from skills/claude"

    # ---- false pass: the copies agree, but neither is installable ----

    t=$(fresh_tree)
    both_copies '/^name: /d' "$t" "$skill"
    expect_fail "name removed from both copies" "$t" "no non-empty 'name:'"

    t=$(fresh_tree)
    both_copies '/^description: /d' "$t" "$skill"
    expect_fail "description removed from both copies" "$t" "no non-empty 'description:'"

    t=$(fresh_tree)
    both_copies 's/^name: .*/name: renamed-in-frontmatter/' "$t" "$skill"
    expect_fail "name no longer matches the directory" "$t" "does not match its directory"

    # The declared name differs from its directory by internal whitespace and
    # nothing else, so a checker that collapses whitespace before comparing
    # reports this pair as matching. The literal pair is independent of the
    # skill under test: what varies here is which directory gets renamed away,
    # not what the two strings have to be for the case to discriminate.
    t=$(fresh_tree)
    for host in claude codex; do
        mv "$(skill_dir "$t" "$host" "$skill")" "$t/skills/$host/spacedname"
        sed_inplace 's/^name: .*/name: spaced name/' "$t/skills/$host/spacedname/SKILL.md"
    done
    expect_fail "name matches the directory only if whitespace is ignored" "$t" "does not match its directory"

    t=$(fresh_tree)
    for host in claude codex; do
        mv "$(skill_dir "$t" "$host" "$skill")" "$t/skills/$host/Bad_Name"
        sed_inplace 's/^name: .*/name: Bad_Name/' "$t/skills/$host/Bad_Name/SKILL.md"
    done
    expect_fail "name is not hyphen-case" "$t" "hyphen-case"

    t=$(fresh_tree)
    unclose_frontmatter "$t" "$skill"
    expect_fail "frontmatter is never closed" "$t" "well-formed frontmatter"

    t=$(fresh_tree)
    both_copies '1i\
' "$t" "$skill"
    expect_fail "a blank line precedes the opening delimiter" "$t" "well-formed frontmatter"

    # A body line that looks like frontmatter must not stand in for the real
    # key: with `name:` deleted from both frontmatter blocks and an identical
    # decoy planted in both bodies, an unscoped check reports the tree clean.
    # Appended rather than inserted at a named heading, because the heading a
    # given skill happens to carry is not something this suite may assume.
    t=$(fresh_tree)
    both_copies '/^name: /d' "$t" "$skill"
    for host in claude codex; do
        printf '\nname: %s\n' "$skill" >> "$(skill_dir "$t" "$host" "$skill")/SKILL.md"
    done
    expect_fail "name only present as a decoy line in the body" "$t" "no non-empty 'name:'"

    t=$(fresh_tree)
    rm -f "$(skill_dir "$t" codex "$skill")/agents/openai.yaml"
    expect_fail "agents/openai.yaml removed from the Codex tree" "$t" "missing skills/codex"

    t=$(fresh_tree)
    sed_inplace 's/allow_implicit_invocation: false/allow_implicit_invocation: true/' \
        "$(skill_dir "$t" codex "$skill")/agents/openai.yaml"
    expect_fail "allow_implicit_invocation flipped to true" "$t" "bare scalar false"

    t=$(fresh_tree)
    cat > "$(skill_dir "$t" codex "$skill")/agents/openai.yaml" <<'YAML'
policy:
  allow_implicit_invocation: true
defaults:
  allow_implicit_invocation: false
YAML
    expect_fail "a decoy false outside the policy block" "$t" "bare scalar false"

    t=$(fresh_tree)
    cat > "$(skill_dir "$t" codex "$skill")/agents/openai.yaml" <<'YAML'
agents:
  policy:
    allow_implicit_invocation: false
YAML
    expect_fail "allow_implicit_invocation nested at the wrong path" "$t" "direct child"

    # The flag is genuinely under `policy:` -- just one level too deep, which
    # is where Codex stops reading it. A depth-blind match reports this clean.
    t=$(fresh_tree)
    cat > "$(skill_dir "$t" codex "$skill")/agents/openai.yaml" <<'YAML'
policy:
  defaults:
    allow_implicit_invocation: false
YAML
    expect_fail "allow_implicit_invocation nested one level under policy" "$t" "direct child"

    # Both copies agree, both are valid YAML, and the first value satisfies
    # every check -- while a host may resolve the second one.
    t=$(fresh_tree)
    both_copies '2i\
description: A second, conflicting description.' "$t" "$skill"
    expect_fail "duplicate frontmatter key in both copies" "$t" "duplicate frontmatter key"

    t=$(fresh_tree)
    both_copies 's/^description: .*/description: [not, a, string]/' "$t" "$skill"
    expect_fail "required value is a YAML sequence, not a scalar" "$t" "non-scalar"

    # Non-empty, no rejected prefix, and still not a string once YAML loads it.
    t=$(fresh_tree)
    both_copies 's/^description: .*/description: true/' "$t" "$skill"
    expect_fail "required value is a bare YAML boolean" "$t" "boolean or null"

    t=$(fresh_tree)
    both_copies 's/^description: .*/description: null/' "$t" "$skill"
    expect_fail "required value is a bare YAML null" "$t" "boolean or null"

    t=$(fresh_tree)
    both_copies 's/^description: .*/description: 3.10/' "$t" "$skill"
    expect_fail "required value is a bare YAML number" "$t" "bare numeric"

    # A quoted token is a string and must keep passing.
    t=$(fresh_tree)
    both_copies 's/^description: .*/description: "true"/' "$t" "$skill"
    expect_pass "required value is a quoted 'true', which is a string" "$t"

    # Check 10 stops at its first match, so a second, contradicting value
    # below it is invisible to it -- and is what a YAML loader may resolve.
    t=$(fresh_tree)
    cat > "$(skill_dir "$t" codex "$skill")/agents/openai.yaml" <<'YAML'
policy:
  allow_implicit_invocation: false
  allow_implicit_invocation: true
YAML
    expect_fail "allow_implicit_invocation declared twice inside policy" "$t" "duplicate key(s) inside 'policy:'"

    t=$(fresh_tree)
    cat > "$(skill_dir "$t" codex "$skill")/agents/openai.yaml" <<'YAML'
policy:
  allow_implicit_invocation: false
policy:
  allow_implicit_invocation: true
YAML
    expect_fail "policy block declared twice" "$t" "duplicate top-level key"

    t=$(fresh_tree)
    printf 'policy:\n  allow_implicit_invocation: "false"\n' \
        > "$(skill_dir "$t" codex "$skill")/agents/openai.yaml"
    expect_fail "allow_implicit_invocation quoted instead of scalar false" "$t" "bare scalar false"

    t=$(fresh_tree)
    for host in claude codex; do
        mv "$(skill_dir "$t" "$host" "$skill")" "$t/skills/$host/two words"
    done
    expect_fail "skill directory name contains a space" "$t" "two words"
}

run_suite() {
    checker_under_test="$1"
    failures=0
    break_cases=0

    # ---- cases that do not name a skill ----
    case_skill=""

    t=$(fresh_tree)
    expect_pass "unmodified tree" "$t"

    t=$(fresh_tree)
    for host in claude codex; do
        for s in $discovered_skills; do
            rm -rf "$t/skills/$host/$s"
        done
    done
    expect_fail "no skills at all" "$t" "no skills found"

    # ---- every other case, once per skill ----
    for skill_under_test in $discovered_skills; do
        case_skill="$skill_under_test"
        run_skill_cases "$skill_under_test"
    done
    case_skill=""

    return "$failures"
}

# Discovered once, from a fresh tree rather than from the repository root, and
# never inside a case: one case creates a skill directory inside its own tree,
# so per-case discovery would give the two passes different case counts and the
# weakened-checker comparison below would compare two different suites.
discovered_skills=$(list_tree_skills "$(fresh_tree)")
echo "Skills under test: $(echo "$discovered_skills" | tr '\n' ' ')"

echo "Running suite against $checker"
suite_failures=0
run_suite "$checker" || suite_failures=$?
real_breaks="$break_cases"

if [ "$suite_failures" -ne 0 ]; then
    echo "FAIL: check-parity.sh missed or mis-reported $suite_failures case(s)" >&2
    exit 1
fi

# The guard on the guard. A checker that always succeeds must miss every break,
# not merely some: an environmental abort would produce a partial count, so
# requiring the full set is what proves the suite is actually discriminating.
weak="$work/weakened-check-parity.sh"
printf '#!/bin/sh\nexit 0\n' > "$weak"
echo "Running suite against a deliberately weakened checker (every break must go undetected)"
weak_failures=0
run_suite "$weak" || weak_failures=$?

if [ "$weak_failures" -ne "$real_breaks" ]; then
    echo "FAIL: the weakened checker went undetected in only $weak_failures of $real_breaks break cases;" >&2
    echo "      the suite is not discriminating (or it aborted partway)." >&2
    exit 1
fi

echo "OK: check-parity.sh caught all $real_breaks breaks with the right reason, and the suite rejects a weakened checker"
