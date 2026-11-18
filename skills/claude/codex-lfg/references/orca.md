# Orca backend

Read this when Preflight chose the Orca backend. Load Orca's own guide once per run with `orca skills get orchestration`, and follow it wherever this file is silent. The guide matches the installed Orca version, so it wins on command syntax. This file adds only what `codex-lfg` does differently. Never poll and never run a watch script on Orca mail; Orca wakes this session.

## Run and Task

- With `RUN=<id>` from `codex-delegate`, use that Run. Otherwise use the Run the unit state records. When it records none, or `orca orchestration run-show --id <run>` no longer finds it, create one with `orca orchestration run-create --objective "codex-lfg <branch>" --json` and record it before anything else.
- Before using a Run, read `orca orchestration run-current --json`. When this session is bound to no Run, bind it with `orca orchestration run-use --id <run>`. When it is bound to a different Run, report both and stop: rebinding would drop the other Run's wakes. When the Run belongs to a different Orca terminal, report the live Runs and stop; the operator reruns the command from the original terminal.
- The unit has one parent Task, titled with its branch name and recorded in the unit state. Find it with `orca orchestration task-list --run <run> --json`, or create it with `task-create --run <run> --task-title <branch> --spec-file <brief> --json`.
- Commands scoped by Run take `--run <run>`: `task-create`, `task-list`, `worker-start`, `worker-list`, `check`, `send`, and `inbox`. Commands that address one agent take its Dispatch id and no `--run`: `worker-show`, `worker-stop`, `worker-release`, and `deny`.

## Entry: route every event first

On every entry to the skill, and before answering any operator message while a unit is in flight, drain the Run's mail with `orca orchestration check --run <run> --json` until it returns nothing. Each call marks its whole batch handled, and a batch can hold events for several units. Route every message before acting on any: match the Dispatch id or Task id it carries against the agents and Tasks recorded in each unit state under `<git common dir>/codex-lfg/units/`, and append the message, with its ID, to the `events` of the unit it belongs to. Report a message that matches no unit to the user. Then handle the events of this unit; `codex-delegate` invokes this skill for each other unit with pending events. Remove an event from the unit state only after its route below has run.

When the unit state shows a step waiting on a message that never arrived, read the Run's history with `orca orchestration inbox --terminal run:<run> --limit 50 --json` and route the matching message by its ID.

## Worker

Start it on the unit's Task in a new child worktree:

```text
orca orchestration worker-start --run <run> --task <task> --worktree new-child --name <branch slug> --agent <codex|claude> [--model <model> [--effort <effort>]] --json
```

- `--agent` is `codex` for a Codex worker and `claude` for a Sonnet worker. A Sonnet worker always gets `--model <WORKER_MODEL>`, which is `sonnet` unless another model was chosen. A Codex worker gets `--model` only when a model is set. Orca refuses `--effort` without `--model`, so when only an effort is set, also pass the `model` from `~/.codex/config.toml`.
- From the receipt, record the Dispatch id, the worktree identity, and the worktree path in the unit state. Later steps select that worktree by its identity, never by its name; Orca may add a suffix to the name.
- The worker's tab stays open, because a worker in a new worktree is kept open.
- Send a hand-off with `orca orchestration send --run <run> --to dispatch:<id> --subject "<topic>" --body "$(cat <brief>)" --retry-request <request id> --json`, using the request ID the unit state recorded. Repeating the call with the same request ID does not send twice. A finished worker receives the message as a follow-up Task and reports with `worker_done`; record that Task's id so its events route to this unit.
- Retry on the same Task with `worker-start --run <run> --task <task> --retry-of <dispatch> --worktree <recorded identity> --agent <agent> --model <model> --effort xhigh --json`. Pass the model and effort explicitly, because a retry does not inherit placement or model. After three failed starts in one chain, Orca's breaker fails the Task: the unit has failed. Never route around the breaker with a new Run or Task.

## Reviewer

Each round starts a fresh reviewer as a child of the unit's Task, on the worker's worktree:

```text
orca orchestration worker-start --run <run> --spec-file <review brief> --parent <task> --worktree <recorded identity> --agent claude --model <REVIEWER_MODEL> --keep-open --json
```

Record its Dispatch id and its child Task id. `--keep-open` keeps the reviewer's tab after it finishes. Keep every reviewer until the unit's cleanup releases it.

## Events

| Event | Route |
|---|---|
| `question` the plan or repository answers | `orca orchestration reply --id <message> --body "<answer>"` |
| `question` only the user can answer | The skill's Questions rule. Unattended, reply with the recommended option |
| Permission prompt | Interactive: tell the user and end the turn; the unit waits. Unattended: `orca orchestration deny --dispatch <id> --prompt <approval id> --reason "<why>"`. If deny is refused, the unit has failed |
| `escalation` with `stopReason` | `send` one steer. If it stops again, the unit has failed |
| Worker `worker_done` | Step 4 for a build, or the hand-off check in step 5 for a fix or rebase |
| Reviewer `worker_done` | Step 5's acceptance check on the reviewer's result file |
| Worker reports failure, or `exited`, or `lost` | Retry once at `xhigh` on the same Task, then the coordinator takes over as step 4 describes |
| Reviewer reports failure, or `exited`, or `lost` | Retry the reviewer once as step 5 describes, then the unit has failed |
| `worker-start` fails | Read `failedStage` and load `references/recovery-and-cleanup.md` from the guide. Never rerun the same start |
| Outcome unknown | `orca orchestration request-show --request <id>` from the error. Never start another agent |

## Reattach and hang

An agent the unit state records as running is still current when `orca orchestration worker-show --dispatch <id> --json` shows it unsettled; wait for its event. A settled agent whose event was never routed is handled from the `inbox` history above.

Past the deadline, read `worker-show` again:
- `observation.agentWait` present and non-null: the agent is waiting on a prompt only a human can answer. Route it as a permission prompt or a question above.
- `observation.agentWait` null while the agent still works: it is hung. Stop it with `worker-stop --dispatch <id>`, then route it as a reported failure for its role. If `worker-stop` returns `stop_unknown`, do not retry: the unit has failed, and every agent and worktree is kept.
- `observation.agentWait` absent: Orca could not verify the agent, which never proves it is stuck, so never stop it. Interactive, tell the user. Unattended, the unit has failed with the agent left running, and the report says so.

## Gate and merge

The recorded worktree path holds the branch. Local gates, verification commands, and an empty commit to retrigger checks run there. Merge from the coordinator's own checkout, without `--delete-branch`:

```sh
gh pr merge <n> --squash --match-head-commit <approved head>
```

## Cleanup after the merge

1. Check the recorded worktree: `git status --short` must be empty and `git rev-parse HEAD` must equal the approved head. If either check fails, the worktree holds work the merge did not include: keep the worktree, the branch, and every agent, record them as kept, report them, and stop here.
2. Delete the remote branch with `git push --force-with-lease=refs/heads/<branch>:<approved head> origin :refs/heads/<branch>`. When the remote branch is already gone, as a repository that deletes merged branches leaves it, this step is done. A rejected lease means someone pushed after the approval: keep the branch and report it.
3. Release each agent the unit state records with `worker-release --dispatch <id> --json`, and record each receipt. A `retained` or `release_pending` receipt stays pending in the unit state and is retried on the next entry.
4. Only when every release is settled, remove the worktree with `orca worktree rm --worktree <recorded identity>`, without `--delete-branch`.
5. Delete the local branch with `git update-ref -d refs/heads/<branch> <approved head>`, which refuses when the branch points anywhere else.

A unit that failed or awaits `merge` keeps its worktree and every agent.
