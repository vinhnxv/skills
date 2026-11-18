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
   `ce-babysit-pr`, `ce-resolve-pr-feedback`, and `ce-debug`. The skill's
   child-skill list was checked against **compound-engineering 3.30.1**; if a later version renames one of these,
   preflight will stop on a skill that no longer exists — that is a bug in this
   repository, not a misconfiguration on your side. A missing plugin → preflight
   stops before any issue is claimed.

### `repo-audit` does not need Beads

It reads a repository and writes a standalone Markdown report. A host that can
spawn subagents audits dimensions in parallel; a host without that capability
audits serially. Neither route calls `bd` or creates tickets. It also does not
need a GitHub remote, `gh`, or the `compound-engineering` plugin.

### `audit-loop` needs `repo-audit` beside it, and no Beads

`audit-loop` loads `repo-audit` as each round's audit, so install both. On
Claude Code it loads it through the Skill tool, which is why `repo-audit`'s
Claude copy is model-invocable; on Codex you invoke both together. It also
needs a GitHub remote
named `origin` with `gh` authenticated, and the `compound-engineering` plugin
providing `ce-work`, `ce-code-review`, and `ce-commit-push-pr`. It never calls
`bd`.

### `source-to-beads` needs Beads

`source-to-beads` creates Beads work for the current repository from an audit
report, brainstorm, implementation plan, document, cited research, or context
accessible in the current session. It runs independently of `repo-audit` and
requires an initialized, working Beads tracker: preflight runs `bd prime` and
`bd ready`, and without a working tracker it writes nothing and returns a draft
that names the missing prerequisite. Run from a linked worktree, it writes to
the root checkout's Beads database, not to a copy in the worktree. It does not
start `backlog-loop`. `repo-audit` itself never needs Beads; only the optional
step of filing its findings does.

### `codex-lfg` runs on Claude Code only

`codex-lfg` hands one plan file, a few Beads issues, or a quoted task to a
worker agent and reviews the result in Claude Code. It needs `gh`
authenticated and the `compound-engineering` plugin on both hosts. It needs
`codex` on PATH only for a Codex worker, and Beads only when you pass issue
ids. Install its Claude copy; the Codex copy exists only to keep the host
trees in parity and stops at preflight. `codex-delegate` runs each cycle
through it, so install both when you use `codex-delegate`.

Orca is optional. Without it, workers run
in the background of the Claude Code session. With it, they run as Orca
agents in their own tabs and worktrees, and `codex-delegate` can run several
cycles at once. That needs Claude Code running inside an Orca terminal with
Orca's Claude Code hooks enabled; anywhere else, both skills fall back to the
background mode.

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

mkdir -p ~/.claude/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.claude/skills --strip-components=3 skills-main/skills/claude/codex-delegate

mkdir -p ~/.claude/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.claude/skills --strip-components=3 skills-main/skills/claude/audit-loop

mkdir -p ~/.claude/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.claude/skills --strip-components=3 skills-main/skills/claude/codex-lfg
```

**Codex**

```sh
mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/backlog-loop

mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/repo-audit

mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/source-to-beads

mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/codex-delegate

mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/audit-loop

mkdir -p ~/.codex/skills && curl -fsSL https://github.com/vinhnxv/skills/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.codex/skills --strip-components=3 skills-main/skills/codex/codex-lfg
```

The `mkdir -p` is not optional: `tar -C` on a directory that does not exist
fails.

**Upgrading.** Delete the installed skill first — `rm -rf
~/.claude/skills/backlog-loop` (or the Codex path, or the other skill's) — then
run its install command again. Extracting over an existing install leaves behind
any file the new version dropped.

**From a clone instead.** If you already have the repository checked out, copy
the directories that match your host:

```sh
mkdir -p ~/.claude/skills && cp -R skills/claude/backlog-loop skills/claude/repo-audit skills/claude/source-to-beads skills/claude/codex-delegate skills/claude/audit-loop skills/claude/codex-lfg ~/.claude/skills/
mkdir -p ~/.codex/skills  && cp -R skills/codex/backlog-loop  skills/codex/repo-audit  skills/codex/source-to-beads  skills/codex/codex-delegate  skills/codex/audit-loop  skills/codex/codex-lfg  ~/.codex/skills/
```

The `mkdir -p` matters here too. With several source directories, as above,
`cp -R` into a target that does not exist fails with a "not a directory" error. With a
single source directory it exits 0 and copies the skill's *contents* into the
target, leaving you with a stray `SKILL.md` and no skill.

CI runs every command in these install blocks as written, with only `curl`
replaced by an archive of the commit under test, on Linux and macOS.

Claude Code also loads skills from a project's `.claude/skills/`, so the same
commands work per project with `<your-repo>/.claude/skills` as the target.

The Codex copy carries `agents/openai.yaml` alongside `SKILL.md` — take the
whole directory, not just the Markdown file.

Every Codex copy is explicit-invocation only. The Claude copies are too, except
the ones listed at the end of [Repository layout](#repository-layout), which a
goal prompt has to load through the Skill tool.

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

**What it decides, files, and reports.** The loop decides on its own every
non-gate `decision` issue by its recommended option, recording the choice in
the issue's design field and the PR body, and a plan that blocks on an open
question gets a recorded decision and one more attempt. It reaps an
`external-wip` claim only through the tracker's own lease (`bd reclaim`), and a
gate killed by its deadline is retried once with a longer deadline before it is
charged as a tool failure. What stays with a person is exactly the human gates
(a credential, access, a paid subscription, a production approval), a change to
a contract, permission, or security stance, and a `needs-human` residual from
PR review. Findings that review leaves unfixed are filed into Beads after the
merge as `tech-debt` issues (never above P2, deduplicated, capped per batch and
per run), so they are done later instead of forgotten. Every census and every
final report ends with an UNBLOCK REPORT: one `unblock <id> | <class> | <action>
| <command>` line per issue the loop is not clearing, ranked by what each act
unlocks, so you read which blocked issues the agent can decide and how to
unblock the rest instead of asking.

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

The report header records the remote default tip, how far the checkout is
behind it, whether the checkout is a linked worktree, and whether HEAD is off
the default branch. When the checkout is behind the tip or off the default
branch, the report opens with a `Warning:` block, because a finding may already
be fixed on the default branch. The audit reads the tip with `git ls-remote`
only; it never fetches and never changes a ref.

The audit can reuse a validated local coverage cache. If the cache is missing
or stale, it audits the full scope. Every skipped criterion and source snapshot
is recorded in the report, so the cache is not needed to review the result.

**Launch it in two steps:** load the skill, then give it
[`prompts/repo-audit.goal.md`](prompts/repo-audit.goal.md). The
[`prompts/repo-audit-readonly.goal.md`](prompts/repo-audit-readonly.goal.md)
companion is retained as a report-only launch alias. Both produce a report and
leave code and tracker changes to the user's next choice.

### `codex-delegate`

Clears a Beads backlog with Claude Code as the coordinator. Each cycle picks a
set of ready issues and runs them through [`codex-lfg`](#codex-lfg) with
`merge unattended`: Claude writes a plan with `ce-plan`, a worker agent
implements it through `lfg` up to an open pull request, a separate reviewer
agent reviews it, and Claude triages the findings, sends the fixes back to the
same worker, waits for checks, merges, pulls the default branch, and closes the
issues. Inside an Orca terminal it runs up to two cycles at once on unrelated
issues (`PARALLEL`); otherwise cycles run one at a time. A failed worker run is
retried once at `xhigh`; after that Claude implements the plan itself.

The worker, its model and effort, and the reviewer model come from the goal's
defaults, can change mid-run when you tell the session (it applies from the
next cycle), and can be pinned per issue with the `codex_lfg_*` metadata keys
`codex-lfg` documents. Each issue it hands over carries
`codex_delegate_branch` and an attempt count in Beads metadata, so a restarted
run resumes interrupted cycles through `codex-lfg` instead of losing them, and
leaves alone the issues an interactive `codex-lfg` run owns.

It runs on Claude Code only. The Codex copy exists so both host trees stay in
parity, and it stops at preflight. It needs `codex-lfg` installed beside it,
Beads, `gh`, the `compound-engineering` plugin on both hosts, and the `codex`
CLI when a cycle runs a Codex worker. Without Orca it runs Codex with
`-s danger-full-access` so Codex can push and open the PR, and it merges
without asking, so point it only at a repository whose default branch you are
comfortable having written to.

**Launch it in two steps:** load the skill, then give it
[`prompts/codex-delegate.goal.md`](prompts/codex-delegate.goal.md) as the goal
or as an ordinary message. The prompt holds only the success condition, so it
fits a goal's 4000-character limit; the procedure lives in the skill.

### `codex-lfg`

Runs one unit of work through a worker agent with you in the loop:

```text
/codex-lfg <plan-path | bead-id... | "task description"> [merge] [unattended]
  [via=auto|orca|exec] [worker=codex|sonnet] [WORKER_MODEL=<model>]
  [WORKER_EFFORT=<effort>] [REVIEWER_MODEL=<model>] [ROUNDS=<n>]
```

Given issue ids or a quoted task, Claude writes the plan with `ce-plan` (and
claims the issues); given a plan file, it uses the plan as written. Claude then
starts the worker, Codex CLI by default or a Claude Sonnet agent with
`worker=sonnet`, to implement the plan through `lfg` up to an open pull
request. The session stays free while it works. When the worker finishes,
Claude checks the handoff (retrying once at `xhigh`, then implementing the plan
itself) and starts a separate reviewer agent (`REVIEWER_MODEL`, Sonnet by
default) that runs `ce-code-review` and only reports. Claude triages each
finding, posts a `codex-lfg review round <n>` ledger comment on the PR, and
sends the accepted findings back to the same worker. Rounds repeat until one
is clean, up to `ROUNDS` (5). It then waits for checks and stops with the PR
open unless you passed `merge`; rerunning the same command with `merge` added
merges the PR at the approved head and closes the issues.

Inside an Orca terminal with Orca's Claude Code hooks enabled, the worker and
reviewer run as Orca agents: the worker in its own worktree and tab, and Orca
wakes the session when either reports. Elsewhere they run in the background:
Codex through `codex exec` in your checkout, Sonnet as a Claude Code subagent
in a worktree under `codex-lfg/worktrees/` in the git common directory. `via=orca` or `via=exec`
forces one backend.

The branch name follows from the input (`codex-lfg/<plan name>` or
`codex-lfg/<first issue id>`), and claimed issues record it as
`codex_lfg_branch` metadata, so rerunning the same command after an interrupted
session resumes the same branch and PR. Progress within a unit (agents started,
review rounds, pending hand-offs, the approved head, and pending cleanup) is
kept in a state file under `codex-lfg/units/` in the git common directory
(`git rev-parse --git-common-dir`), so a restart neither repeats a step nor
skips one; when it cannot tell whether an action took effect, the unit parks
and reports instead of guessing. A repository that merges through a merge
queue is not supported: `merge` stops and reports it. A Codex worker's model and effort come
from `~/.codex/config.toml` unless you pass `WORKER_MODEL=` or `WORKER_EFFORT=`
(`CODEX_MODEL=` and `CODEX_EFFORT=` still work). An issue can pin its own
choices with `codex_lfg_worker`, `codex_lfg_worker_model`,
`codex_lfg_worker_effort`, and `codex_lfg_reviewer_model` metadata. With
`unattended` it never asks you anything: it takes the recommended option,
records it, and starts over on a fresh branch after a closed PR. That is how
`codex-delegate` runs it. It runs on Claude Code only. Its Claude copy is
model-invocable so `codex-delegate` can load it, and its description still says
explicit invocation only.

### `audit-loop`

Repeats audit → fix → merge until the repository converges. Each round runs
the full `repo-audit` procedure on the freshly pulled default branch, fixes
every confirmed actionable finding with `ce-work` (up to 20 per round, highest
severity first), reviews the diff with `ce-code-review`, opens a PR, merges it
through the same CI gate as `codex-delegate`, and pulls. Launching it is your
standing choice of `repo-audit`'s "fix all confirmed, actionable findings"
option for every round; `repo-audit` itself is unchanged and still never
edits code.

A finding whose fix needs a person -- a secret rotation, a change outside the
repository, an unpatched advisory, or a change to a public contract,
permission, or security stance -- is deferred, not fixed. A ledger of finding
IDs at `<git-common-dir>/audit-loop/ledger.json` caps each finding at two
attempts and survives restarts. The loop stops when an audit selects nothing
(converged), when a failed round would only be retried on the same findings
(stalled), after five rounds, or when trunk is red for a reason no round can
fix. It merges without asking, so point it only at a repository whose default
branch you are comfortable having written to.

**Launch it in two steps:** load the skill, then give it
[`prompts/audit-loop.goal.md`](prompts/audit-loop.goal.md) as the goal or as
an ordinary message. On Codex, invoke `$audit-loop $repo-audit` together, then
paste the prompt after `/goal`: Codex keeps `repo-audit` explicit-only, so the
loop can use it only when you invoked it.

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

## Worktree audit workflow

Auditing from a throwaway worktree keeps the audit off your working checkout.
The skills support that flow end to end, and they never remove a worktree for
you.

1. **Create the worktree from the default branch tip.** From the repository,
   run `git fetch origin` and then
   `git worktree add <path> -b <audit-branch> origin/<default>`. This step is
   yours; the skills create no worktree.
2. **Run `repo-audit` in the worktree.** The report is written to
   `docs/audits/` in the worktree and finalized before any choice is offered.
3. **Optionally have a second reviewer check it.** Invoke `repo-audit` on the
   report from another host or model; the review is a companion file beside
   the report and does not replace it.
4. **Run `/source-to-beads <absolute-report-path> <IDs>`** (`$source-to-beads`
   on Codex) to file the findings you choose. It revalidates each finding
   against the default branch tip, not the checked-out branch, and writes to
   the root checkout's Beads database.
5. **Handoff.** In a linked worktree, both skills copy the report and its
   companion review files to the root checkout's `docs/audits/` and compare the
   sha256 of each copy with its source. `source-to-beads` also reads every
   filed issue id back from the root Beads database. A sensitive-detail file
   under `docs/audits/private/` is copied only into a root path that Git
   reports as ignored. The handoff ends with a verdict, `safe to delete` or
   `not safe to delete`, with the blocking reasons.
6. **You decide about cleanup.** Only when the verdict is `safe to delete` does
   the skill print the `git worktree remove <worktree>` command; you run it, or
   you keep the worktree. Neither skill runs `git worktree remove` or
   `git worktree prune`.

**An ignored report is deleted with the worktree unless it was handed off.**
In a repository that ignores `docs/`, a report left only in the worktree is
lost when you remove the worktree. Do not remove the worktree until the
verdict is `safe to delete`, or copy the report out yourself.

**Auditing a non-default branch is allowed.** A detached HEAD, a missing
remote, or a commit off the default branch does not block the audit; the
report records the branch, the base SHA, the remote default tip, and the
off-default state instead. The audit describes the checked-out tree, but filing
always revalidates a finding against the default branch tip. A finding the tip
no longer shows is refused and listed under rejected items, and a finding that
exists only on the audited branch is deferred unless you opted in to file it
as branch-only evidence, in which case the issue body carries a branch note.

## Repository layout

```
skills/claude/<skill-name>/    installable into ~/.claude/skills/
skills/codex/<skill-name>/     installable into ~/.codex/skills/
prompts/                       companion launch prompts
scripts/check-parity.sh        keeps the two host copies from drifting
scripts/check-cross-skill.sh   checks Beads writer and backlog-loop boundaries
scripts/check-backlog-loop.sh  keeps backlog-loop's own internal rules in both copies
scripts/test-*.sh              proves each checker still fails on a broken tree
scripts/fixtures/              model-neutral audit report fixture that test-repo-audit.sh validates
```

Each skill exists twice, once per host, because the two hosts declare
explicit-only invocation differently: Claude Code uses
`disable-model-invocation: true` in frontmatter, which Codex's validator
rejects, and Codex uses `policy.allow_implicit_invocation: false` in
`agents/openai.yaml`. Apart from that one marker the two copies of a skill are
identical, and `scripts/check-parity.sh` fails CI if they ever stop being.
The exceptions are `backlog-loop`, `codex-delegate`, `audit-loop`,
`repo-audit`, and `codex-lfg`: their Claude copies omit the marker so a goal
prompt, `audit-loop` for `repo-audit`, or `codex-delegate` for `codex-lfg`, can
load them through the Skill tool, while
their Codex copies stay explicit-only.

## License

MIT — see [LICENSE](LICENSE).
