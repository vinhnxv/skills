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
# accepts, a missing required key, an invocation policy at the wrong path.
# Those are the shapes a parity-only checker is blind to by construction, and
# they are the ones this suite exists to keep covered.
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

# Fresh copy of the real tree; echoes the tree root to build cases against.
# mktemp -d gives each case its own empty directory: this function runs inside
# a command substitution, so a shell variable used as a counter would live in a
# subshell and never advance, silently making every case share one tree.
fresh_tree() {
    dir=$(mktemp -d "$work/case.XXXXXX")
    cp -R "$repo_root/skills" "$dir/skills"
    echo "$dir"
}

# GNU and BSD sed disagree about -i; normalize.
sed_inplace() {
    sed "$1" "$2" > "$2.tmp" && mv "$2.tmp" "$2"
}

# Apply an edit to both host copies of backlog-loop's SKILL.md.
both_copies() {
    for host in claude codex; do
        sed_inplace "$1" "$2/skills/$host/backlog-loop/SKILL.md"
    done
}

run_checker() {
    status=0
    sh "$checker_under_test" "$1" > "$work/out" 2>&1 || status=$?
    echo "$status"
}

failures=0
break_cases=0

# A break the checker must catch, and the text it must say when it does.
expect_fail() {
    label="$1"; root="$2"; want="$3"
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
    label="$1"; root="$2"
    if [ "$(run_checker "$root")" -eq 0 ]; then
        echo "  clean: $label"
    else
        echo "  FALSE ALARM: $label -- $(head -n 1 "$work/out")"
        failures=$((failures + 1))
    fi
}

run_suite() {
    checker_under_test="$1"
    failures=0
    break_cases=0

    t=$(fresh_tree)
    expect_pass "unmodified tree" "$t"

    # ---- drift: the two copies disagree ----

    t=$(fresh_tree)
    printf '\nA line added to only one host copy.\n' >> "$t/skills/claude/backlog-loop/SKILL.md"
    expect_fail "body edit in the Claude copy only" "$t" "bodies differ"

    t=$(fresh_tree)
    printf '\nA line added to only one host copy.\n' >> "$t/skills/codex/backlog-loop/SKILL.md"
    expect_fail "body edit in the Codex copy only" "$t" "bodies differ"

    t=$(fresh_tree)
    sed_inplace '2i\
disable-model-invocation: true' "$t/skills/codex/backlog-loop/SKILL.md"
    expect_fail "disable-model-invocation added to the Codex copy" "$t" "which Codex rejects"

    t=$(fresh_tree)
    sed_inplace '/^disable-model-invocation: true$/d' "$t/skills/claude/backlog-loop/SKILL.md"
    expect_fail "disable-model-invocation removed from the Claude copy" "$t" "is missing 'disable-model-invocation'"

    t=$(fresh_tree)
    sed_inplace 's/^description: .*/description: Edited in one copy only./' \
        "$t/skills/claude/backlog-loop/SKILL.md"
    expect_fail "description edited in the Claude copy only" "$t" "frontmatter differs outside"

    t=$(fresh_tree)
    sed_inplace '2i\
license: MIT' "$t/skills/claude/backlog-loop/SKILL.md"
    expect_fail "an allowed key added to the Claude copy only" "$t" "frontmatter differs outside"

    # A nested block: the divergence is inside the value, not on the key line,
    # so a check that compares one line per key cannot see it.
    t=$(fresh_tree)
    both_copies '2i\
metadata:\
  version: 1\
  audience: everyone' "$t"
    sed_inplace 's/^  audience: everyone$/  audience: nobody/' \
        "$t/skills/codex/backlog-loop/SKILL.md"
    expect_fail "nested frontmatter value diverges" "$t" "frontmatter differs outside"

    t=$(fresh_tree)
    printf 'shared\n' > "$t/skills/claude/backlog-loop/reference.md"
    expect_fail "auxiliary file present in the Claude copy only" "$t" "different files"

    t=$(fresh_tree)
    printf 'one\n' > "$t/skills/claude/backlog-loop/reference.md"
    printf 'two\n' > "$t/skills/codex/backlog-loop/reference.md"
    expect_fail "auxiliary file differs between copies" "$t" "differs between the two host copies"

    t=$(fresh_tree)
    cp -R "$t/skills/claude/backlog-loop" "$t/skills/claude/only-on-one-host"
    expect_fail "skill present under skills/claude only" "$t" "missing from skills/codex"

    t=$(fresh_tree)
    cp -R "$t/skills/codex/backlog-loop" "$t/skills/codex/only-on-one-host"
    expect_fail "skill present under skills/codex only" "$t" "missing from skills/claude"

    # ---- false pass: the copies agree, but neither is installable ----

    t=$(fresh_tree)
    both_copies '/^name: /d' "$t"
    expect_fail "name removed from both copies" "$t" "no non-empty 'name:'"

    t=$(fresh_tree)
    both_copies '/^description: /d' "$t"
    expect_fail "description removed from both copies" "$t" "no non-empty 'description:'"

    t=$(fresh_tree)
    both_copies 's/^name: .*/name: renamed-in-frontmatter/' "$t"
    expect_fail "name no longer matches the directory" "$t" "does not match its directory"

    t=$(fresh_tree)
    for host in claude codex; do
        mv "$t/skills/$host/backlog-loop" "$t/skills/$host/backlogloop"
        sed_inplace 's/^name: .*/name: back logloop/' "$t/skills/$host/backlogloop/SKILL.md"
    done
    expect_fail "name matches the directory only if whitespace is ignored" "$t" "does not match its directory"

    t=$(fresh_tree)
    for host in claude codex; do
        mv "$t/skills/$host/backlog-loop" "$t/skills/$host/Bad_Name"
        sed_inplace 's/^name: .*/name: Bad_Name/' "$t/skills/$host/Bad_Name/SKILL.md"
    done
    expect_fail "name is not hyphen-case" "$t" "hyphen-case"

    t=$(fresh_tree)
    both_copies '4d' "$t"
    expect_fail "frontmatter is never closed" "$t" "well-formed frontmatter"

    t=$(fresh_tree)
    both_copies '1i\
' "$t"
    expect_fail "a blank line precedes the opening delimiter" "$t" "well-formed frontmatter"

    # A body line that looks like frontmatter must not stand in for the real
    # key: with `name:` deleted from both frontmatter blocks and an identical
    # decoy planted in both bodies, an unscoped check reports the tree clean.
    t=$(fresh_tree)
    both_copies '/^name: /d' "$t"
    both_copies 's/^## PREFLIGHT$/name: backlog-loop\
\
## PREFLIGHT/' "$t"
    expect_fail "name only present as a decoy line in the body" "$t" "no non-empty 'name:'"

    t=$(fresh_tree)
    rm -f "$t/skills/codex/backlog-loop/agents/openai.yaml"
    expect_fail "agents/openai.yaml removed from the Codex tree" "$t" "missing skills/codex"

    t=$(fresh_tree)
    sed_inplace 's/allow_implicit_invocation: false/allow_implicit_invocation: true/' \
        "$t/skills/codex/backlog-loop/agents/openai.yaml"
    expect_fail "allow_implicit_invocation flipped to true" "$t" "bare scalar false"

    t=$(fresh_tree)
    cat > "$t/skills/codex/backlog-loop/agents/openai.yaml" <<'YAML'
policy:
  allow_implicit_invocation: true
defaults:
  allow_implicit_invocation: false
YAML
    expect_fail "a decoy false outside the policy block" "$t" "bare scalar false"

    t=$(fresh_tree)
    cat > "$t/skills/codex/backlog-loop/agents/openai.yaml" <<'YAML'
agents:
  policy:
    allow_implicit_invocation: false
YAML
    expect_fail "allow_implicit_invocation nested at the wrong path" "$t" "direct child"

    # The flag is genuinely under `policy:` -- just one level too deep, which
    # is where Codex stops reading it. A depth-blind match reports this clean.
    t=$(fresh_tree)
    cat > "$t/skills/codex/backlog-loop/agents/openai.yaml" <<'YAML'
policy:
  defaults:
    allow_implicit_invocation: false
YAML
    expect_fail "allow_implicit_invocation nested one level under policy" "$t" "direct child"

    # Both copies agree, both are valid YAML, and the first value satisfies
    # every check -- while a host may resolve the second one.
    t=$(fresh_tree)
    both_copies '2i\
description: A second, conflicting description.' "$t"
    expect_fail "duplicate frontmatter key in both copies" "$t" "duplicate frontmatter key"

    t=$(fresh_tree)
    both_copies 's/^description: .*/description: [not, a, string]/' "$t"
    expect_fail "required value is a YAML sequence, not a scalar" "$t" "non-scalar"

    # Check 10 stops at its first match, so a second, contradicting value
    # below it is invisible to it -- and is what a YAML loader may resolve.
    t=$(fresh_tree)
    cat > "$t/skills/codex/backlog-loop/agents/openai.yaml" <<'YAML'
policy:
  allow_implicit_invocation: false
  allow_implicit_invocation: true
YAML
    expect_fail "allow_implicit_invocation declared twice inside policy" "$t" "duplicate key(s) inside 'policy:'"

    t=$(fresh_tree)
    cat > "$t/skills/codex/backlog-loop/agents/openai.yaml" <<'YAML'
policy:
  allow_implicit_invocation: false
policy:
  allow_implicit_invocation: true
YAML
    expect_fail "policy block declared twice" "$t" "duplicate top-level key"

    t=$(fresh_tree)
    printf 'policy:\n  allow_implicit_invocation: "false"\n' \
        > "$t/skills/codex/backlog-loop/agents/openai.yaml"
    expect_fail "allow_implicit_invocation quoted instead of scalar false" "$t" "bare scalar false"

    t=$(fresh_tree)
    for host in claude codex; do mv "$t/skills/$host/backlog-loop" "$t/skills/$host/two words"; done
    expect_fail "skill directory name contains a space" "$t" "two words"

    t=$(fresh_tree)
    rm -rf "$t/skills/claude/backlog-loop" "$t/skills/codex/backlog-loop"
    expect_fail "no skills at all" "$t" "no skills found"

    return "$failures"
}

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
