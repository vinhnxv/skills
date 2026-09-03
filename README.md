# skills

Agent skills that install on both **Claude Code** and **Codex**, one directory
per host. Installing is one command that drops the directory for your host into
its skills folder — there is no build step, no generator, no package to add,
and nothing to edit afterwards.

## Before you install

These skills are not general-purpose. `backlog-loop` needs all three of the
following:

1. **[Beads](https://github.com/steveyegge/beads) (`bd`)** as the repository's
   issue tracker, initialized and working — preflight runs `bd prime` and
   `bd ready` and stops if either fails. There is no fallback onto another
   tracker: every step issues literal `bd` commands, so a partial mapping
   would strand tracker state at the first unmapped operation.
2. **A GitHub remote**, with [`gh`](https://cli.github.com) installed and
   authenticated for it. Not GitHub → preflight stops. The remote may carry any
   name; preflight resolves the one whose URL matches the repository `gh`
   reports, and stops if none or several do. Your default branch must **not**
   require a merge queue: on such a branch `gh pr merge` enqueues the PR
   instead of merging it, and the loop refuses a merge it cannot verify.
3. **The `compound-engineering` plugin** for your host, providing `lfg`,
   `ce-plan`, `ce-work`, `ce-simplify-code`, `ce-code-review`,
   `ce-test-browser`, `ce-doc-review`, `ce-commit-push-pr`, and
   `ce-babysit-pr`. The skill's child-skill list was written against
   **compound-engineering 3.24.0**; if a later version renames one of these,
   preflight will stop on a skill that no longer exists — that is a bug in this
   repository, not a misconfiguration on your side. A missing plugin → preflight
   stops before any issue is claimed.

**Also know what you are starting.** `backlog-loop` is autonomous. It claims
issues, opens branches and pull requests, and **merges its own PRs** without
asking. It refuses `--admin` and GitHub auto-merge, pins each merge to the exact
commit it reviewed, proves the PR reached `MERGED` before closing anything, runs
every merge-authorizing gate in a clean throwaway worktree rather than beside
your uncommitted files, stops when your local default branch holds unpushed
commits, and stops after repeated failures — but do not point it at a repository
whose main branch you are not comfortable having written to.

## Install

One command per host. It downloads the repository archive and extracts just the
one skill directory — no clone, no Node, no script of ours to trust.

**Claude Code**

```sh
mkdir -p ~/.claude/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.claude/skills --strip-components=3 skills-main/skills/claude/backlog-loop
```

**Codex**

```sh
mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/backlog-loop
```

The `mkdir -p` is not optional: `tar -C` on a directory that does not exist
fails, and on the `cp -R` path below it silently mis-installs instead.

**Upgrading.** Delete the installed skill first — `rm -rf
~/.claude/skills/backlog-loop` (or the Codex path) — then run the install
command again. Extracting over an existing install leaves behind any file the
new version dropped.

**From a clone instead.** If you already have the repository checked out, copy
the one directory that matches your host:

```sh
mkdir -p ~/.claude/skills && cp -R skills/claude/backlog-loop ~/.claude/skills/
mkdir -p ~/.codex/skills  && cp -R skills/codex/backlog-loop  ~/.codex/skills/
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

**Launch it in two steps.** Load the skill first, then give it the companion
prompt in [`prompts/backlog-loop.goal.md`](prompts/backlog-loop.goal.md). The
second step differs by host:

- **Codex** — `/goal` is a built-in command. Paste the prompt file's contents
  after `/goal`.
- **Claude Code** — there is no `/goal` command. Paste the prompt file's
  contents as an ordinary message, immediately after loading the skill.

**Tracker support.** Beads only. The procedure issues literal `bd` commands
for claims, estimates, metadata, notes, and closure, and preflight stops when
`bd` does not work rather than improvising a mapping onto another tracker. If
you do not use Beads, this skill is not for you.

## Repository layout

```
skills/claude/<skill-name>/    installable into ~/.claude/skills/
skills/codex/<skill-name>/     installable into ~/.codex/skills/
prompts/                       companion launch prompts
scripts/check-parity.sh        keeps the two host copies from drifting
```

Each skill exists twice, once per host, because the two hosts declare
explicit-only invocation differently: Claude Code uses
`disable-model-invocation: true` in frontmatter, which Codex's validator
rejects, and Codex uses `policy.allow_implicit_invocation: false` in
`agents/openai.yaml`. Apart from that one marker the two copies of a skill are
identical, and `scripts/check-parity.sh` fails CI if they ever stop being.

## License

MIT — see [LICENSE](LICENSE).
