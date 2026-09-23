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
   `ce-test-browser`, `ce-doc-review`, `ce-commit-push-pr`,
   `ce-babysit-pr`, and `ce-resolve-pr-feedback`. The skill's child-skill list
   was checked against **compound-engineering 3.28.2**; if a later version renames one of these,
   preflight will stop on a skill that no longer exists — that is a bug in this
   repository, not a misconfiguration on your side. A missing plugin → preflight
   stops before any issue is claimed.

### `repo-audit` does not need Beads

It reads a repository and writes a standalone Markdown report. A host that can
spawn subagents audits dimensions in parallel; a host without that capability
audits serially. Neither route calls `bd` or creates tickets. It also does not
need a GitHub remote, `gh`, or the `compound-engineering` plugin.

### `source-to-beads` needs Beads

`source-to-beads` creates Beads work for the current repository from an audit
report, brainstorm, implementation plan, document, cited research, or context
accessible in the current session. It runs independently of `repo-audit` and
requires an initialized, working Beads tracker. It does not start
`backlog-loop`.

**Also know what you are starting.** `backlog-loop` is autonomous. It claims
issues, opens branches and pull requests, and **merges its own PRs** without
asking. It refuses `--admin` and GitHub auto-merge, pins each merge to the exact
commit it reviewed, proves the PR reached `MERGED` before closing anything, runs
every merge-authorizing gate in a clean throwaway worktree rather than beside
your uncommitted files, stops when your local default branch holds unpushed
commits, and stops after repeated failures — but do not point it at a repository
whose main branch you are not comfortable having written to.

It probes trunk health and PR checks separately. A green workflow that runs
only on `main` keeps trunk healthy but does not count as a PR check; that PR
uses exact-commit local gates before and after merge and a bounded review
watch. A required or observed PR check must pass before merge.

After an audit, the agent saves the full report and recommends what to do next.
You choose whether to stop with that report, fix all or selected findings, or
create Beads issues when Beads is configured. Creating issues is a separate
action; running `backlog-loop` is another separate action.

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

mkdir -p ~/.claude/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.claude/skills --strip-components=3 skills-main/skills/claude/source-to-beads
```

**Codex**

```sh
mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/backlog-loop

mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/repo-audit

mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/source-to-beads
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
mkdir -p ~/.claude/skills && cp -R skills/claude/backlog-loop skills/claude/repo-audit skills/claude/source-to-beads ~/.claude/skills/
mkdir -p ~/.codex/skills  && cp -R skills/codex/backlog-loop  skills/codex/repo-audit  skills/codex/source-to-beads  ~/.codex/skills/
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

Audits a repository against a fixed roster of nine dimensions and writes a
report with a versioned schema under `docs/audits/`. Each dimension names
criteria whose coverage and findings are recorded. A report includes stable
finding IDs, evidence, source snapshot, verification result, and coverage limits, so another
person, Codex session, or Claude Code session can review it without the original
chat. The audit does not require or write to Beads.

The audit can reuse a validated local coverage cache. If the cache is missing
or stale, it audits the full scope. Every skipped criterion and source snapshot
is recorded in the report, so the cache is not needed to review the result.

**Launch it in two steps:** load the skill, then give it
[`prompts/repo-audit.goal.md`](prompts/repo-audit.goal.md). The
[`prompts/repo-audit-readonly.goal.md`](prompts/repo-audit-readonly.goal.md)
companion is retained as a report-only launch alias. Both produce a report and
leave code and tracker changes to the user's next choice.

### `source-to-beads`

Extracts actionable work into Beads from any accessible source. An audit report
is one supported input, alongside a brainstorm, an implementation-ready plan,
another document, cited research, or the current host's available session
context. Brainstorm questions remain decision or discovery work; plan units
become executable issues with justified dependencies. Every issue cites its
source, and repeated runs check the tracker before creating duplicates.

Invoke it directly with the source and the instruction to update the current
repository's Beads backlog. It reports created, reused, and deferred work. It
does not claim to read a different host's private transcript unless that
transcript was supplied, and it does not run `backlog-loop`.

## Repository layout

```
skills/claude/<skill-name>/    installable into ~/.claude/skills/
skills/codex/<skill-name>/     installable into ~/.codex/skills/
prompts/                       companion launch prompts
scripts/check-parity.sh        keeps the two host copies from drifting
scripts/check-cross-skill.sh   checks Beads writer and backlog-loop boundaries
scripts/check-backlog-loop.sh  keeps backlog-loop's own internal rules in both copies
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
