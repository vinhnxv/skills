# Unit state and restart safety

Read this with the backend reference. It defines the unit state file, the rule that keeps a restart from repeating or skipping an action, and how each kind of action is checked after a restart.

## Files

All state lives under `<git common dir>/codex-lfg/`, where the git common dir is `git rev-parse --git-common-dir`, so every worktree of the repository sees it. Only the coordinator writes it.
- `units/<branch with / replaced by ->.json`: one unit.
- `runs/<Orca Run id>.json`: the Run's message log, Orca only.
- `attempts/<branch slug>/<role>-<attempt>/`: one exec agent attempt, with its brief, log, result, and `started` marker.
- `review/<branch slug>-<round>/`: a clean, detached checkout for one review round or gate, removed when the round ends.

The unit state records:
- **identity:** the inputs, the plan path, the branch, the repository, the default branch, and the backend;
- **pr:** the number, head owner, head ref, and base ref once bound;
- **choices:** worker, model, effort, and reviewer model, each with its source and, after each launch, the effective value the launch reported;
- **orca:** the Run, the parent Task, the worktree identity and path;
- **agents:** each start, with role, attempt, identity, session token, start time, deadline, timer, result path, and status;
- **rounds:** each round, with its kind, head, base, reviewer, result, ledger comment ID, verdict, and findings;
- **handoff:** the pending hand-off, if any;
- **approved:** the approved head and base;
- **gate:** the head it covers, the local result, the check watch, its deadline, and any retrigger;
- **answers:** each question and answer;
- **events:** Orca messages routed to this unit and not yet handled;
- **cleanup:** each resource still to release or remove, and each one kept;
- **intents:** see below;
- **outcome:** `in-flight`, `awaiting-merge`, `merged`, `done`, `failed`, or `parked`.

The session token is this session's scratchpad path. A Claude Code session keeps it through compaction, and a new session gets a new one.

## The intent rule

Every action that changes something outside the coordinator's context is an operation: an Orca mutation, a `gh` or `git push` write, a `bd` write, a merge, a removal, or an agent launch. Before an operation, append an intent to the unit state with a new key, the operation, and its inputs. After it, record its receipt on that intent. For an Orca mutation, the key is also its `--retry-request` value.

On every entry, before anything else, check each intent that has no receipt, using the table below. The check gives one of three answers:
- **done:** record the receipt it found and continue.
- **not done:** run the operation now with the same key.
- **unclear:** set the outcome to `parked`, report the intent and what was observed, and stop. Never start a second agent, send a second message, or make a second commit to get past an unclear intent.

A deliberate second attempt, such as handing the same fixes off again after the worker settled without pushing, is a new operation with a new key.

## Checking an intent after a restart

| Operation | How to check it |
|---|---|
| Any Orca mutation (`run-create`, `run-use`, `task-create`, `worker-start`, `send`, `reply`, `deny`, `worker-release`, `worker-stop`) | Rerun the same command with the same `--retry-request` key. Orca returns the original receipt instead of acting twice: done. If the rerun errors, read `orca orchestration request-show --request <key> --json`. A receipt there means done. An absent receipt is not proof that nothing happened: list the object the operation would have made or changed (`run-current`, `task-list`, `worker-list`, `worker-show`, the Run's message log). If it is there, done. If it is not, and nothing else depends on it, not done. Otherwise unclear |
| Exec agent launch | A result file in the attempt directory means done: the agent finished. Otherwise, for a Codex worker, `pgrep -f "<attempt directory>"` finding a process means it is running: wait for it. With no `started` marker, the agent never began: not done. The coordinator writes the `started` marker, holding the session token, right before the launch; a Codex worker's command line names its attempt directory. A `started` marker with this session's token means the agent is running in this session: wait for its notification, guarded by its timer, which also catches a notification that never comes. A `started` marker from another session means the agent died with that session: the attempt was interrupted, and a new attempt starts without counting as a failure |
| `bd update` of metadata, status, or assignee | `bd show <id> --json` shows the intended value: done. Otherwise not done |
| `bd update --append-notes` | Every note this skill appends ends with `[codex-lfg <key>]`. Its presence in `bd show` means done |
| `bd close` | `bd show` reads `closed`: done |
| `bd create` | Every issue this skill files ends its description with `[codex-lfg <key>]`. `bd list --all --desc-contains "[codex-lfg <key>]" --json` returning it means done |
| `bd update --claim --set-metadata codex_lfg_branch=<branch>` | `bd show` reads `in_progress` with the branch set: done. `in_progress` without the branch, assigned to the assignee an earlier claim of this unit set: finish it with `bd update <id> --set-metadata codex_lfg_branch=<branch>`. Assigned to anyone else: unclear |
| Ledger comment | Every ledger comment carries `<!-- codex-lfg <key> -->`. Search `gh api repos/<owner>/<repo>/issues/<n>/comments --paginate` for that marker on a comment written by the coordinator's login. Found means done, and its ID is the ledger comment's ID |
| Ledger edit, PR body edit | Rerun it: the edit is idempotent |
| `git push` of a coordinator commit | The commit is made locally first and its SHA is in the intent. `git ls-remote origin refs/heads/<branch>` showing that SHA means done. Showing the expected old SHA means not done. Anything else is unclear |
| Merge | `gh pr view <n> --json state,headRefOid` reading `MERGED` means done. `OPEN` with `headRefOid` equal to the approved head means not done. Anything else is unclear |
| Remote branch deletion, worktree removal, local branch deletion | The thing being absent means done. Present means not done |
| `ce-plan` writing a plan | Look for a plan file under the plans directory written after the intent, whose title matches the task or names the issues. One such file means done. None means not done. More than one is unclear |

## The Run's message log

With Orca, every message read from the Run goes into its message log before it is acted on. The log records each message ID and the unit it was routed to, or `unmatched`. Never drop a message ID from the log.

On every entry:
1. Read the history with `orca orchestration inbox --terminal run:<run> --full --limit 200 --json`. Log every message whose ID is not in the log yet. This recovers messages a restart consumed before logging them.
2. Read unread mail without consuming it with `orca orchestration check --run <run> --peek --json`, and log every new message.
3. Consume it with `orca orchestration check --run <run> --json`, log anything it returns that is not in the log yet, and repeat until it returns nothing.

Route each logged message by the Dispatch id or Task id it carries: match it against the agents and Tasks the unit states record, and append it to that unit's `events`. Route the log's `unmatched` messages again after every intent check, because a launch whose receipt was recovered can claim them. A message still unmatched after that is reported to the user. Remove an event from a unit's `events` only after its route has run.

## Backend lock

A unit keeps the backend it started with. When the unit state names a backend and Preflight's probes now point elsewhere, use the recorded one. When it is Orca and Orca is no longer usable, or the arguments force the other backend, set the outcome to `parked` and report the conflict instead of switching.

## Pull request binding

Bind the unit to its pull request once and record its number, head owner, head ref, and base. To find it, run `gh pr list --head <branch> --state all --json number,state,headRefName,headRepositoryOwner,baseRefName,headRefOid,body` and keep only candidates whose head owner is this repository's owner and whose body carries the line `codex-lfg unit: <branch>`. With a recorded number, the candidate must be that number. Without one, bind a single candidate. More than one candidate, or a candidate whose head owner or base differs from the record, is unclear: park the unit.

## Without a unit state

When the unit state file is missing but the branch or PR exists, rebuild only identity and the PR binding. Never take a review approval from the ledger alone: start a fresh review round at the current head.
