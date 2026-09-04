# skills

Agent skills that install on both **Claude Code** and **Codex**, one directory
per host. Installing is one command that drops the directory for your host into
its skills folder — there is no build step, no generator, no package to add,
and nothing to edit afterwards.

## Before you install

These skills are not general-purpose.

### `backlog-loop` needs all three of the following

1. **[Beads](https://github.com/steveyegge/beads) (`bd`)** as the repository's
   issue tracker, initialized and working — preflight runs `bd prime` and
   `bd ready` and stops if either fails. There is no fallback onto another
   tracker: every step issues literal `bd` commands, so a partial mapping
   would strand tracker state at the first unmapped operation.
2. **A GitHub remote**, with [`gh`](https://cli.github.com) installed and
   authenticated for it. Not GitHub → preflight stops. The remote must be
   named `origin`: preflight resolves the remote whose URL matches the
   repository `gh` reports and stops if it is absent, ambiguous, or named
   anything else, because the pinned `ce-commit-push-pr` contract pushes to a
   literal `origin`. Your default branch must **not**
   require a merge queue: on such a branch `gh pr merge` enqueues the PR
   instead of merging it, and the loop refuses a merge it cannot verify. A
   private repository on a free plan cannot have one — branch protection and
   rulesets are both unavailable there, and preflight reads that plan's 403 as
   an unprotected branch rather than stopping on it.
3. **The `compound-engineering` plugin** for your host, providing `lfg`,
   `ce-plan`, `ce-work`, `ce-simplify-code`, `ce-code-review`,
   `ce-test-browser`, `ce-doc-review`, `ce-commit-push-pr`, and
   `ce-babysit-pr`. The skill's child-skill list was written against
   **compound-engineering 3.24.0**; if a later version renames one of these,
   preflight will stop on a skill that no longer exists — that is a bug in this
   repository, not a misconfiguration on your side. A missing plugin → preflight
   stops before any issue is claimed.

### `repo-audit` needs two things

1. **Beads (`bd`)**, exactly as above and for the same reason: every write it
   makes is a literal `bd` command, and preflight stops on Beads before it
   reads a single repository file.
2. **A host that can spawn subagents.** `repo-audit` shards its roster one
   dimension per subagent, and it does not stop when the host cannot: a host
   with no spawn primitive, and a host that refuses the first spawn, both fall
   back to auditing the roster serially in one context — and a serial run is
   **read-only**. It reports everything it found and files none of it, because
   the party doing the searching would otherwise be the party measuring its own
   coverage. So on such a host the skill still works and still never writes.

It does **not** need a GitHub remote, `gh`, or the `compound-engineering`
plugin. It reads the repository and writes to the tracker; it opens nothing.

**Also know what you are starting.** `backlog-loop` is autonomous. It claims
issues, opens branches and pull requests, and **merges its own PRs** without
asking. It refuses `--admin` and GitHub auto-merge, pins each merge to the exact
commit it reviewed, proves the PR reached `MERGED` before closing anything, runs
every merge-authorizing gate in a clean throwaway worktree rather than beside
your uncommitted files, stops when your local default branch holds unpushed
commits, and stops after repeated failures — but do not point it at a repository
whose main branch you are not comfortable having written to.

**And know what the two of them are together.** `repo-audit` fills the backlog
that `backlog-loop` clears, and every finding it files enters `bd ready` with no
human gate in front of it. Install both and point them at the same repository
and you have a closed loop: the audit files, the loop plans, builds, opens a
pull request, and merges it. Nobody stands between the two. That is the design,
not a side effect — but it is worth knowing before the first run rather than
after it. `repo-audit` bounds its own half: a first run against a repository
files **nothing at all**, whichever prompt invoked it, so you get a full report
of what it would have filed before anything reaches the tracker. Every run also
prints the exact commands that would close everything it just filed.

## Install

One command per skill per host. Each downloads the repository archive and
extracts just that one skill directory — no clone, no Node, no script of ours
to trust. Install only the skills you want; they are independent.

**Claude Code**

```sh
mkdir -p ~/.claude/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.claude/skills --strip-components=3 skills-main/skills/claude/backlog-loop

mkdir -p ~/.claude/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.claude/skills --strip-components=3 skills-main/skills/claude/repo-audit
```

**Codex**

```sh
mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/backlog-loop

mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/repo-audit
```

The `mkdir -p` is not optional: `tar -C` on a directory that does not exist
fails, and on the `cp -R` path below it silently mis-installs instead.

**Upgrading.** Delete the installed skill first — `rm -rf
~/.claude/skills/backlog-loop` (or the Codex path, or the other skill's) — then
run its install command again. Extracting over an existing install leaves behind
any file the new version dropped.

**From a clone instead.** If you already have the repository checked out, copy
the directories that match your host:

```sh
mkdir -p ~/.claude/skills && cp -R skills/claude/backlog-loop skills/claude/repo-audit ~/.claude/skills/
mkdir -p ~/.codex/skills  && cp -R skills/codex/backlog-loop  skills/codex/repo-audit  ~/.codex/skills/
```

`cp -R` into a directory that does not exist exits 0 and copies the skill's
*contents* there, leaving you with a stray `SKILL.md` and no skill — hence the
`mkdir -p`.

Claude Code also loads skills from a project's `.claude/skills/`, so the same
commands work per project with `<your-repo>/.claude/skills` as the target.

The Codex copy carries `agents/openai.yaml` alongside `SKILL.md` — take the
whole directory, not just the Markdown file.

Both copies are explicit-invocation only: neither host will decide to run one
on its own.

## Skills

### `backlog-loop`

Clears a repository's issue backlog autonomously, one batch at a time, until
the tracker has no actionable non-epic issue left. Work comes from **Beads**:
it reads ready issues with `bd`, groups them into batches sized against a
complexity budget, and drives one plan → branch → PR → merge cycle per batch,
adapting its quality gates depending on whether CI is available.

**Launch it in two steps.** Load the skill first, then give it one of the two
companion prompts. Use
[`prompts/backlog-loop.goal.md`](prompts/backlog-loop.goal.md) to clear the
backlog, and
[`prompts/backlog-census.goal.md`](prompts/backlog-census.goal.md) to find out
why it is stuck without changing anything -- the census prompt runs read-only,
reports every gate, block, and repair it would make, and merges nothing. The
second step differs by host:

- **Codex** — `/goal` is a built-in command. Paste the prompt file's contents
  after `/goal`.
- **Claude Code** — there is no `/goal` command. Paste the prompt file's
  contents as an ordinary message, immediately after loading the skill.

**Tracker support.** Beads only. The procedure issues literal `bd` commands
for claims, estimates, metadata, notes, and closure, and preflight stops when
`bd` does not work rather than improvising a mapping onto another tracker. If
you do not use Beads, this skill is not for you.

### `repo-audit`

Audits a repository against a fixed roster of nine dimensions — one subagent
per dimension, in waves — and files what survives verification into **Beads**
as ready work. It derives its rules from the target repository each run rather
than shipping a pattern library, measures per-dimension coverage against a
population the orchestrator counts itself, and files nothing it did not confirm
against the audited commit.

**It is incremental across runs.** A coverage ledger records what each
dimension proved clean and at which commit, so a later run audits the files
that changed since — plus their reverse-dependency closure — instead of the
whole tree. Dimensions whose defects are not file-local are never cached, and
every skip it takes is enumerated in the report.

**It closes what it opened.** A run's first write is a sweep over its own
previously filed issues: each one's recorded detection recipe is re-evaluated
at the current commit, and only the ones that provably no longer reproduce are
closed. It has no authority over anyone else's issues, and it never closes on a
recipe it could not evaluate.

**Launch it in two steps**, the same way — load the skill, then give it one of
the two companion prompts. Use
[`prompts/repo-audit.goal.md`](prompts/repo-audit.goal.md) for a writing run,
and [`prompts/repo-audit-readonly.goal.md`](prompts/repo-audit-readonly.goal.md)
to see everything it would file without letting it file any of it — that prompt
runs every `bd` command under `--readonly`, so a write is refused by the tracker
rather than merely avoided. The per-host second step is identical to
`backlog-loop`'s above.

**Suppressing a finding is your act, not its.** Close the issue and label it
`audit-suppressed`; the audit re-derives its suppression list from those labels
on every run and never writes that label itself. Remove the label or reopen the
issue and the suppression is gone on the next run.

**Tracker support.** Beads only, for the same reason.

## Repository layout

```
skills/claude/<skill-name>/    installable into ~/.claude/skills/
skills/codex/<skill-name>/     installable into ~/.codex/skills/
prompts/                       companion launch prompts
scripts/check-parity.sh        keeps the two host copies from drifting
scripts/check-cross-skill.sh   keeps the two skills' shared assumptions true
scripts/test-*.sh              proves each checker still fails on a broken tree
```

Each skill exists twice, once per host, because the two hosts declare
explicit-only invocation differently: Claude Code uses
`disable-model-invocation: true` in frontmatter, which Codex's validator
rejects, and Codex uses `policy.allow_implicit_invocation: false` in
`agents/openai.yaml`. Apart from that one marker the two copies of a skill are
identical, and `scripts/check-parity.sh` fails CI if they ever stop being.

## License

MIT — see [LICENSE](LICENSE).
