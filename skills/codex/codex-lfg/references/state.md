# Unit state and restart safety

Read this with the backend reference. It defines the unit state file, the rule that keeps a restart from repeating or skipping an action, and how each kind of action is checked after a restart. When a check cannot tell what happened, the unit parks: it stops and reports exactly what a person must settle. Parking is the intended answer to a gap that more machinery would only narrow.

## Files

All state lives under the state directory, `<git common dir>/codex-lfg/`, where the git common dir is `git rev-parse --path-format=absolute --git-common-dir`, so every worktree of the repository sees the same path. Only the coordinator writes the unit, planning, repository, and Run files; an agent writes only the result file its brief names inside its attempt directory or review checkout's result path.
- `units/<branch with / replaced by ->.json`: one unit.
- `units/text-<hash>.json`: the planning record of a task description or issue set, before it has a branch.
- `repo.json`: decisions about the repository that outlive one unit, such as whether it has CI.
- `runs/<Orca Run id>.json`: the Run's message log, Orca only.
- `attempts/<branch slug>/<role>-<attempt>/`: one exec agent attempt, with its brief, log, result, and `started` marker.
- `review/<branch slug>-<round>/` and `review/<branch slug>-gate/`: clean, detached checkouts for one review round or gate, removed when it ends.

The unit state records:
- **identity:** the inputs, their hash, the plan path, the branch, the repository, the default branch, the backend, and `replaced_by` once a closed PR's unit is replaced;
- **pr:** the number, head repository, head ref, and base ref once bound;
- **choices:** worker, model, effort, and reviewer model, each with its source and, after each launch, the effective value the launch reported or `inherited`;
- **orca:** the Run, the parent Task, the worktree identity and path;
- **agents:** each start, with role, attempt, Dispatch or task ID, follow-up Task, session token, start time, deadline, timer, result path, and status; the current attempt for each role;
- **checkout_owner:** for an exec Codex worker, the attempt that may still write in the coordinator's checkout;
- **rounds:** each round, with its head, base, next substep, reviewer, result, ledger comment ID, verdict, and findings;
- **handoff:** the pending hand-off, if any;
- **approved:** the approved head and base;
- **gate:** the head it covers, the local result, the check watch and its task ID, its deadline, and any retrigger;
- **answers:** each question, its answer, and how often it was asked;
- **events:** Orca message IDs routed to this unit and not yet handled;
- **parked:** when the outcome is `parked`, its cause: an intent, an agent, `ci-unknown`, a dirty workspace, or an adoption, with the evidence;
- **cleanup:** each resource still to release or remove, and each one kept;
- **intents:** see below;
- **outcome:** `in-flight`, `awaiting-merge`, `merged`, `done`, `failed`, or `parked`, with the cause.

The session token is this session's scratchpad path. A Claude Code session keeps it through compaction, and a new session gets a new one.

## Entry order

On every entry: load the unit state; follow `replaced_by` to the current unit; confirm the recorded inputs match this invocation; re-read the bound PR by its number and park if its head repository, head ref, or base changed; then check open intents; then, with Orca, read the Run's mail; then continue the phase.

## The intent rule

Every action that changes something outside the coordinator's context is an operation: an Orca mutation, a `gh` or `git push` write, a `bd` write, a merge, a removal, or an agent launch. Before an operation, append an intent to the unit state with a new key, the operation, its inputs, and, when it answers an Orca message, that message's ID. After it, record its receipt on that intent. Keys are lowercase UUIDs from `uuidgen`; for an Orca mutation, the key is also its `--retry-request` value, which Orca accepts only in UUID form.

Check each intent that has no receipt, using the table below. The check gives one of three answers:
- **done:** record the receipt it found and continue.
- **not done:** return to the step that issued the operation. That step checks its preconditions again before acting, and acts with the same key.
- **unclear:** park the unit with the intent and what was observed. Never start a second agent, send a second message, or make a second commit to get past an unclear intent.

A deliberate second attempt, such as handing the same fixes off again after the worker settled without pushing, is a new operation with a new key. Before handling an Orca message, look for an intent that names its message ID; when one exists, check that intent instead of acting again.

## Checking an intent

| Operation | How to check it |
|---|---|
| Orca mutation (`run-create`, `run-use`, `task-create`, `worker-start`, `send`, `reply`, `deny`, `worker-release`, `worker-stop`) | Read `orca orchestration request-show --request <key> --json` first. `completed`: rerun the same command with the same key to get its full result, which Orca replays instead of acting again, and classify that result as the step that issued it does. `pending`: the operation is still running; follow what `request-show` says, and park if it stays pending. `absent` is not proof that nothing happened: it is done only when the object the operation would have made or changed is found by its exact identity (for a start, a Dispatch on the recorded Task with the recorded name and role; for a send or reply, a message in the Run log that names the intent's message), and otherwise unclear |
| Exec agent launch | See `references/exec.md`, which owns this check |
| `bd update` of metadata, status, or assignee | `bd show <id> --json` shows the intended value: done. Otherwise not done |
| `bd update --claim --set-metadata codex_lfg_branch=<branch>` | `bd show` reads `in_progress` with the branch set: done. Open and unassigned: not done. Assigned to anyone else: unclear |
| `bd update --append-notes`, `bd create` | Every note and description this skill writes ends with `[codex-lfg <key>]`. Its presence in `bd show`, or `bd list --all --desc-contains "[codex-lfg <key>]" --json` returning an issue, means done |
| `bd close` | `bd show` reads `closed`: done |
| Ledger comment | Every ledger comment carries `<!-- codex-lfg <key> -->`. Search `gh api repos/<owner>/<repo>/issues/<n>/comments --paginate` for that marker on a comment written by the coordinator's login. Found means done, and its ID is the ledger comment's ID |
| Ledger edit, PR body edit | Rerun it: the edit is idempotent. A ledger edit always targets the recorded comment ID with `gh api -X PATCH repos/<owner>/<repo>/issues/comments/<id> -F body=@<file>` |
| `git push` of a coordinator commit | The commit is made locally first and its SHA is in the intent. `git ls-remote origin refs/heads/<branch>` showing that SHA means done. Showing the expected old SHA means not done. Anything else is unclear |
| Merge | `gh pr view <n> --json state,headRefOid,mergeCommit` reading `MERGED` at the approved head means done. `OPEN` means not done, and step 6 runs every pre-merge check again before merging. Anything else is unclear |
| Remote branch deletion, worktree removal, local branch deletion | The thing being absent means done. Present means not done |
| `ce-plan` writing a plan | The plan path ce-plan returned, recorded on the intent, means done once the file exists. Without a recorded path, a plan file written after the intent whose title matches the task or names the issues means done when there is exactly one. None means not done. More than one is unclear |

## The Run's message log

With Orca, every message read from the Run goes into its message log, keyed by message ID, before it is acted on. The log records, for each message, the unit it was routed to and whether it is handled. Never drop a message ID from the log.

Reading mail:
1. When the log records a consuming check with no saved response, run it again with its recorded key: `orca orchestration check --run <run> --retry-request <key> --json` returns the same batch.
2. Otherwise record a new key in the log, then run `orca orchestration check --run <run> --retry-request <key> --json`.
3. Save the whole response in the log, log each message by ID, and repeat from step 2 until a check returns nothing.

The consuming checks belong to the coordinator's mailbox, which `orca orchestration inbox --terminal run:<run> --full --limit 200 --json` lists. When a step waits on a message the log lacks, read that list and log what is missing. `inbox --run <run>` lists every mailbox in the Run, workers' included, and is not used for this.

Route each logged message that is not handled by the Dispatch id or Task id it carries: match it against the agents and Tasks the unit states record, and add its ID to that unit's `events` unless it is already there. Route unmatched messages again after every intent check, because a launch whose receipt was recovered can claim them. A message for an agent that is not its role's current attempt is marked handled and reported, never acted on. A message still unmatched is reported to the user. Mark a message handled, and remove it from the unit's `events`, only once its route's phase change or action intent has landed.

When a step waits on a report from an agent that has settled and neither the log nor the coordinator mailbox has it, read the Dispatch's `lastReport` with `orca orchestration worker-show --dispatch <id> --full --json`. Without one, park with the Dispatch id.

## Backend lock

A unit keeps the backend it started with. Preflight looks up the unit state read-only before its worker-dependent probes. When the unit state names a backend, read that backend's reference, use its recorded choices, and run the probes they need, such as `codex --version` for a recorded Codex worker. When it is Orca and Orca is no longer usable, or the arguments force the other backend, park and report the conflict instead of switching.

## Pull request binding

Bind the unit to its pull request once and record it. The PR body carries the line `codex-lfg unit: <branch> <inputs hash>`, where the inputs hash is the first 12 hex digits of the SHA-256 of the sorted inputs. To find it, run `gh pr list --head <branch> --state all --json number,state,headRefName,headRepository,headRepositoryOwner,baseRefName,headRefOid,body`. Keep only candidates whose head repository is this repository (owner and name), whose head ref is the branch, whose base is the default branch, and whose body carries the unit line with this unit's hash. Bind a single candidate. More than one, or none while the branch has a PR, is unclear. Once bound, always read the PR by its number.

## Without a unit state

When the unit state file is missing but the branch or PR exists, the earlier run's workers, Tasks, and workspaces are unknown. Interactive, ask the user before adopting it; unattended, park. An adopted unit rebuilds identity and the PR binding only, never takes a review approval from the ledger, and starts a fresh review round at the current head. It needs a workspace it owns for any hand-off: on exec, the coordinator's checkout for a Codex worker, or a new worktree for a Sonnet worker when no worktree holds the branch; on Orca, nothing it can prove it owns, so park the adoption. Never remove a workspace the unit did not create.
