# Orca backend

Read this when Preflight chose the Orca backend. Load Orca's own guide once per run with `orca skills get orchestration`, and follow it wherever this file is silent. The guide matches the installed Orca version, so it wins on command syntax. This file adds only what `codex-lfg` does differently. Never poll and never run a watch script on Orca mail; Orca wakes this session.

## Run and Task

- With `RUN=<id>` from `codex-delegate`, use that Run. Otherwise create one Run for this invocation with `orca orchestration run-create --objective "codex-lfg <inputs>" --json`, and use only that Run.
- The unit has one parent Task, titled with its branch name. Find it with `orca orchestration task-list --run <run> --json`, or create it with `task-create --run <run> --task-title <branch> --spec-file <brief>`.
- Commands scoped by Run take `--run <run>`: `task-create`, `task-list`, `worker-start`, `worker-list`, `check`, `send`, and `inbox`. Commands that address one agent take its Dispatch id and no `--run`: `worker-show`, `worker-stop`, `worker-release`, and `deny`.
- After this session restarts in the same Orca terminal, rebind with `orca orchestration run-use --id <run>`. Never `run-use` a second Run; that drops the first one's wakes.
- If the coordinator now runs in a different Orca terminal from the one that created the Run, report the live Runs and stop. The operator reruns the command from the original terminal.

## Worker

Start it on the unit's Task in a new child worktree:

```text
orca orchestration worker-start --run <run> --task <task> --worktree new-child --name <branch slug> --agent <codex|claude> [--model <model> [--effort <effort>]] --json
```

- `--agent` is `codex` for a Codex worker and `claude` for a Sonnet worker.
- Pass `--model` only when a model is set. Orca refuses `--effort` without `--model`, so when only an effort is set, also pass the model: the `model` from `~/.codex/config.toml` for Codex, or `sonnet` for Claude.
- From the receipt, record the Dispatch id and the worktree identity. Later steps select that worktree by its identity, never by its name. Orca may add a suffix to the name.
- The worker's tab stays open, because a worker in a new worktree is kept open.
- Send fixes, failing checks, and rebase requests with `orca orchestration send --run <run> --to dispatch:<id> --subject "<topic>" --body "<message>"`. A finished worker receives the message as a follow-up Task and reports with `worker_done`.
- Retry on the same Task with `worker-start --run <run> --task <task> --retry-of <dispatch> --worktree <recorded identity> --agent <agent>`. A retry does not inherit placement. After three failed starts in one chain, Orca's breaker fails the Task: the unit has failed. Never route around the breaker with a new Run or Task.

## Reviewer

Each round starts a fresh reviewer as a child of the unit's Task, on the worker's worktree:

```text
orca orchestration worker-start --run <run> --spec-file <review brief> --parent <task> --worktree <recorded identity> --agent claude --model <REVIEWER_MODEL> --keep-open --json
```

`--keep-open` keeps the reviewer's tab available if the unit fails; a reviewer on an existing worktree is otherwise released when it finishes. After its ledger comment is posted, release the reviewer with `worker-release --dispatch <id>`.

## Wakes and events

On every entry to the skill, and before answering any operator message while a unit is in flight, drain mail first with `orca orchestration check --run <run>`. A wake names a Task or Dispatch, and the Task's title is the unit's branch. When Resume finds a step whose message was already handled but whose result is not in git or the ledger, read the history with `orca orchestration inbox --terminal run:<run> --limit 50`.

| Event | Route |
|---|---|
| `question` the plan or repository answers | `orca orchestration reply --id <message> --body "<answer>"` |
| `question` only the user can answer | The skill's Questions rule. Unattended, reply with the recommended option |
| Permission prompt | Interactive: tell the user and end the turn; the unit waits. Unattended: `orca orchestration deny --dispatch <id> --prompt <approval id> --reason "<why>"`. If deny is refused, the unit has failed |
| `escalation` with `stopReason` | `send` one steer. If it stops again, the unit has failed |
| `worker_done` reporting failure, or `exited`, or `lost` | Retry once at `xhigh` on the same Task, then the coordinator implements with `ce-work` in the recorded worktree |
| `worker-start` fails | Read `failedStage` and load `references/recovery-and-cleanup.md` from the guide. Never rerun the same start |
| Outcome unknown | `orca orchestration request-show --request <id>` from the error. Never start another agent |

## Hang

Past the deadline, read `orca orchestration worker-show --dispatch <id> --json`:
- `observation.agentWait` present and non-null: the agent is waiting on a prompt only a human can answer. Route it as a permission prompt or a question above.
- `observation.agentWait` null while the agent still works: it is hung. Stop it with `worker-stop --dispatch <id>`, then route it as a reported failure. If `worker-stop` returns `stop_unknown`, do not retry: the unit has failed, and every agent and worktree is kept.
- `observation.agentWait` absent: Orca could not verify the agent, which never proves it is stuck, so never stop it. Interactive, tell the user. Unattended, the unit has failed with the agent left running, and the report says so.

## Gate and merge

`worker-show` gives the recorded worktree's path. Local gates, verification commands, and an empty commit to retrigger checks run there. Merge from the coordinator's own checkout without `--delete-branch`, because the worktree still holds the branch:

```sh
gh pr merge <n> --squash --match-head-commit <approved head>
```

## Cleanup after the merge

Once the PR reads `MERGED`:
1. Delete the remote branch with `git push origin --delete <branch>`, but only if `git ls-remote --heads origin <branch>` still shows the approved head.
2. Release each of the unit's agents with `worker-release --dispatch <id>`. A `retained` or `release_pending` receipt goes in the report and is retried on the next entry.
3. Remove the worktree with `orca worktree rm --worktree <recorded identity> --delete-branch`.
4. If the local branch is still there, which a squash merge can leave, delete it with `git branch -D <branch>`. The PR merged at the approved head, so nothing on it is lost.

A unit that failed or awaits `merge` keeps its worktree and every agent.
