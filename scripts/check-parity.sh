#!/bin/sh
# Verify that each skill's two host copies stay in sync and that each copy is
# shaped the way its host requires.
#
# Usage: check-parity.sh [tree-root]
#
# tree-root defaults to the repository root (this script's parent directory).
# Pass an explicit root to check a copy of the tree somewhere else -- that is
# how scripts/test-check-parity.sh drives its temporary trees.
#
# Exits 0 with a one-line summary, or non-zero naming the specific failure.
#
# This script is the only gate that runs on every push: `claude plugin
# validate` needs a binary a stock CI runner does not have, and it accepts
# several shapes both hosts reject. So the host requirements it would have
# covered -- required keys, hyphen-case names, well-formed frontmatter -- are
# checked here directly rather than deferred to it.

set -eu

# Frontmatter keys Codex accepts. Source:
# ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py, which
# rejects any other key. Widening the set Codex accepts is a one-line change
# here.
CODEX_ALLOWED_KEYS="name description license allowed-tools metadata"

# Keys both hosts need in order to surface a skill at all. A skill missing one
# installs but cannot be found or invoked.
REQUIRED_KEYS="name description"

# The one frontmatter key the two copies are allowed to differ on: Claude
# Code's explicit-invocation marker, which Codex's validator would reject.
CLAUDE_ONLY_KEY="disable-model-invocation"

# Paths a host tree is allowed to carry alone, relative to the skill directory.
# Everything else must exist in both copies and be byte-identical.
CODEX_ONLY_FILES="./agents/openai.yaml"

root="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
claude_root="$root/skills/claude"
codex_root="$root/skills/codex"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/check-parity.XXXXXX")
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -d "$claude_root" ] || fail "no Claude skills tree at $claude_root"
[ -d "$codex_root" ] || fail "no Codex skills tree at $codex_root"

# Frontmatter must open on line 1 and close again. Without this, a file whose
# opening '---' is never closed parses as "all frontmatter, empty body" and
# compares equal to another such file, so two unusable skills look clean.
frontmatter_is_well_formed() {
    awk 'NR == 1 { if ($0 != "---") { bad = 1; exit } ; next }
         /^---$/ { closed = 1; exit }
         END { exit (bad || !closed) ? 1 : 0 }' "$1"
}

# Everything below the closing '---'.
strip_frontmatter() {
    awk 'BEGIN { n = 0 }
         /^---$/ { n++; if (n <= 2) next }
         n >= 2' "$1"
}

# The frontmatter block itself, without its '---' delimiters. Every check on a
# frontmatter value reads through this rather than grepping the file: a body
# line beginning with `name:` or `description:` -- ordinary prose in a
# repository about skill authoring -- would otherwise satisfy the check and
# turn a missing key into a silent pass.
frontmatter_only() {
    awk 'BEGIN { n = 0 }
         /^---$/ { n++; if (n >= 2) exit; next }
         n == 1' "$1"
}

# Top-level frontmatter keys, one per line, in file order. Derived from
# frontmatter_only so exactly one place decides where the block ends.
frontmatter_keys() {
    frontmatter_only "$1" | awk '/^[A-Za-z][A-Za-z0-9_-]*:/ { sub(/:.*/, ""); print }'
}

# A key's raw value, trailing whitespace trimmed. Internal whitespace is
# preserved: collapsing it would let `name: back log-loop` satisfy a
# comparison against the directory `backlog-loop`.
frontmatter_value() {
    frontmatter_only "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1 | sed 's/[[:space:]]*$//'
}

list_skills() {
    [ -d "$1" ] || return 0
    for d in "$1"/*; do
        [ -d "$d" ] || continue
        basename "$d"
    done
}

# Every file in a skill directory, relative and sorted.
list_files() {
    ( CDPATH= cd -- "$1" && find . -type f | LC_ALL=C sort )
}

# Union of both host trees, so a skill added to only one host is reported
# rather than silently skipped.
skills=$(
    {
        list_skills "$claude_root"
        list_skills "$codex_root"
    } | LC_ALL=C sort -u
)

[ -n "$skills" ] || fail "no skills found under $root/skills"

count=0
# Fed by redirect rather than a pipe so the loop runs in this shell: a pipeline
# would put `fail` and `count` in a subshell. Read line by line so a directory
# name containing whitespace or a glob character stays one token.
while IFS= read -r skill; do
    [ -n "$skill" ] || continue

    claude_dir="$claude_root/$skill"
    codex_dir="$codex_root/$skill"

    [ -d "$claude_dir" ] || fail "$skill: present under skills/codex but missing from skills/claude"
    [ -d "$codex_dir" ] || fail "$skill: present under skills/claude but missing from skills/codex"

    claude_md="$claude_dir/SKILL.md"
    codex_md="$codex_dir/SKILL.md"

    [ -f "$claude_md" ] || fail "$skill: missing skills/claude/$skill/SKILL.md"
    [ -f "$codex_md" ] || fail "$skill: missing skills/codex/$skill/SKILL.md"

    # 1. Both copies carry the same files, apart from the host-only ones.
    list_files "$claude_dir" > "$scratch/claude-files"
    list_files "$codex_dir" | grep -v -x -F "$CODEX_ONLY_FILES" > "$scratch/codex-files" || true
    if ! diff -q "$scratch/claude-files" "$scratch/codex-files" >/dev/null; then
        only_claude=$(comm -23 "$scratch/claude-files" "$scratch/codex-files" | tr '\n' ' ')
        only_codex=$(comm -13 "$scratch/claude-files" "$scratch/codex-files" | tr '\n' ' ')
        fail "$skill: the two host copies hold different files -- only in claude: ${only_claude:-none}; only in codex: ${only_codex:-none}"
    fi

    # 2. Every shared file except SKILL.md is byte-identical. SKILL.md differs
    #    by exactly one frontmatter line and gets the dedicated checks below.
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        if [ "$rel" = "./SKILL.md" ]; then continue; fi
        diff -q "$claude_dir/$rel" "$codex_dir/$rel" >/dev/null ||
            fail "$skill: $rel differs between the two host copies"
    done < "$scratch/claude-files"

    # 3. Frontmatter must actually be frontmatter in both copies.
    frontmatter_is_well_formed "$claude_md" ||
        fail "$skill: skills/claude/$skill/SKILL.md has no well-formed frontmatter block (it must open with '---' on line 1 and close with '---')"
    frontmatter_is_well_formed "$codex_md" ||
        fail "$skill: skills/codex/$skill/SKILL.md has no well-formed frontmatter block (it must open with '---' on line 1 and close with '---')"

    # 4. Bodies must be identical.
    strip_frontmatter "$claude_md" > "$scratch/claude-body"
    strip_frontmatter "$codex_md" > "$scratch/codex-body"
    diff -q "$scratch/claude-body" "$scratch/codex-body" >/dev/null ||
        fail "$skill: the two host copies' SKILL.md bodies differ"

    # 5. Frontmatter must match as a whole block once the Claude-only marker is
    #    removed. Comparing the block rather than one line per key is what
    #    catches drift inside a multi-line or nested value such as `metadata:`.
    frontmatter_only "$claude_md" | grep -v "^$CLAUDE_ONLY_KEY:" > "$scratch/claude-fm" || true
    frontmatter_only "$codex_md" | grep -v "^$CLAUDE_ONLY_KEY:" > "$scratch/codex-fm" || true
    diff -q "$scratch/claude-fm" "$scratch/codex-fm" >/dev/null ||
        fail "$skill: the two host copies' frontmatter differs outside '$CLAUDE_ONLY_KEY'"

    # 6. Keys both hosts need must be present and non-empty in both copies.
    for key in $REQUIRED_KEYS; do
        for md in "$claude_md" "$codex_md"; do
            [ -n "$(frontmatter_value "$md" "$key")" ] ||
                fail "$skill: $md has no non-empty '$key:' in its frontmatter"
        done
    done

    # 6a. No top-level frontmatter key may appear twice. YAML resolution of a
    #     duplicate is implementation-defined, and frontmatter_value reads the
    #     first occurrence -- so a second, conflicting `description:` can be
    #     what a host actually loads while every check here reads the first.
    for md in "$claude_md" "$codex_md"; do
        dup=$(frontmatter_keys "$md" | LC_ALL=C sort | uniq -d | tr '\n' ' ')
        [ -z "$dup" ] ||
            fail "$skill: $md declares duplicate frontmatter key(s): $dup"
    done

    # 6b. Required values must be plain scalars. `description: [a, b]` and
    #     `description: |` are valid YAML that no host reads as the string it
    #     needs, and both satisfy a non-empty check.
    for key in $REQUIRED_KEYS; do
        for md in "$claude_md" "$codex_md"; do
            case "$(frontmatter_value "$md" "$key")" in
                "["*|"{"*|"|"*|">"*|"&"*|"*"*|"!"*)
                    fail "$skill: $md gives '$key:' a non-scalar YAML value; both hosts need a plain string" ;;
            esac
        done
    done

    # 7. The declared name must match the directory and be hyphen-case. Codex's
    #    validator enforces ^[a-z0-9-]+$ with no leading, trailing, or repeated
    #    hyphen; Claude Code accepts more, so the stricter rule applies to both.
    for md in "$claude_md" "$codex_md"; do
        declared=$(frontmatter_value "$md" name)
        [ "$declared" = "$skill" ] ||
            fail "$skill: $md declares 'name: $declared', which does not match its directory"
        case "$declared" in
            *[!a-z0-9-]*) fail "$skill: $md declares 'name: $declared'; Codex requires hyphen-case (lowercase letters, digits, hyphens)" ;;
            -*|*-) fail "$skill: $md declares 'name: $declared'; a name may not start or end with a hyphen" ;;
            *--*) fail "$skill: $md declares 'name: $declared'; a name may not contain consecutive hyphens" ;;
        esac
    done

    # 8. The Claude copy declares explicit-only invocation.
    frontmatter_keys "$claude_md" | grep -q "^$CLAUDE_ONLY_KEY\$" ||
        fail "$skill: skills/claude/$skill/SKILL.md is missing '$CLAUDE_ONLY_KEY'"
    [ "$(frontmatter_value "$claude_md" "$CLAUDE_ONLY_KEY")" = "true" ] ||
        fail "$skill: skills/claude/$skill/SKILL.md must set '$CLAUDE_ONLY_KEY: true'"

    # 9. The Codex copy carries no key Codex would reject.
    for key in $(frontmatter_keys "$codex_md"); do
        case " $CODEX_ALLOWED_KEYS " in
            *" $key "*) ;;
            *) fail "$skill: skills/codex/$skill/SKILL.md carries frontmatter key '$key', which Codex rejects" ;;
        esac
    done

    # 10. The Codex copy declares explicit-only invocation its own way. The key
    #     must be a DIRECT child of the top-level `policy:` block. Accepting it
    #     at any depth below `policy:` is not enough: `policy: { defaults: {
    #     allow_implicit_invocation: false } }` leaves the setting Codex
    #     actually reads unset while the text still appears under `policy`.
    #     Depth is compared against the first key in the block, so any
    #     indentation width works as long as the flag sits at that level.
    codex_yaml="$codex_dir/agents/openai.yaml"
    [ -f "$codex_yaml" ] ||
        fail "$skill: missing skills/codex/$skill/agents/openai.yaml"
    awk '/^policy:[[:space:]]*$/ { in_policy = 1; depth = -1; next }
         /^[^[:space:]#]/ { in_policy = 0 }
         in_policy && /^[[:space:]]+[A-Za-z_][A-Za-z0-9_-]*:/ {
             match($0, /^[[:space:]]+/); indent = RLENGTH
             if (depth < 0) depth = indent
             if (indent == depth && $0 ~ /^[[:space:]]+allow_implicit_invocation:[[:space:]]*false[[:space:]]*$/) found = 1
         }
         END { exit found ? 0 : 1 }' "$codex_yaml" ||
        fail "$skill: skills/codex/$skill/agents/openai.yaml must set 'allow_implicit_invocation: false' as a direct child of the top-level 'policy:' block"

    count=$((count + 1))
done <<SKILL_LIST_END
$skills
SKILL_LIST_END

echo "OK: $count skill(s) in parity across both host trees"
