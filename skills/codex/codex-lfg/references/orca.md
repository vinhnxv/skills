# Orca backend

Read this when Preflight chose the Orca backend, together with `references/state.md`. Load Orca's own guide once per run with `orca skills get orchestration`, and follow it wherever this file is silent. The guide matches the installed Orca version, so it wins on command syntax. This file adds only what `codex-lfg` does differently. Never poll and never run a watch script on Orca mail; Orca wakes this session.

Every `orca orchestration` command below that changes something takes `--retry-request <intent key>`, with the key, a UUID, recorded in the unit state before the call, as `references/state.md` requires.

## Run and Task

- **On entry.** Read `orca orchestration run-current --json`. With `RUN=<id>` from `codex-delegate`, or a Run the unit state records, that is the unit's Run. When this session is bound to no Run, bind it with `orca orchestration run-use --id <run>`. When it is bound to a different Run, report both and stop: rebinding would drop the other Run's wakes. When the Run belongs to a different Orca terminal, report the live Runs and stop; the operator reruns the command from the original terminal. With no Run yet, entry does nothing more: the Run is created only when step 3 is about to start the worker.
- **A recorded Run that is gone.** When `orca orchestration run-show --id <run> --json` reports the Run not found, and the unit state records no running agent, clear the Run, its Task, and its agent records, and continue on a new Run from step 3's creation. Any other `run-show` error parks the unit.
- **At step 3.** With no Run, create one with `orca orchestration run-create --objective "codex-lfg <branch>" --json` and bind it. With no parent Task, create it after the build brief is written, with `orca orchestration task-create --run <run> --task-title <branch> --spec-file <build brief> --json`. Record both.
- Commands scoped by Run take `--run <run>`: `task-create`, `task-list`, `worker-start`, `worker-list`, `check`, and `send`. The coordinator reads its own mailbox with `inbox --terminal run:<run>`. Commands that address one agent take its Dispatch id and no `--run`: `worker-show`, `worker-stop`, `worker-release`, and `deny`.

## Entry: the Run's mail

After binding, read the Run's mail into its message log and route every message, as `references/state.md` describes, before handling this unit's events. `codex-delegate` invokes this skill for each other unit with pending events.

## Worker

Start it on the unit's Task in a new child worktree:

```text
orca orchestration worker-start --run <run> --task <task> --worktree new-child --name <branch slug> --agent <codex|claude> [--model <model> [--effort <effort>]] --json
```

- `--agent` is `codex` for a Codex worker and `claude` for a Sonnet worker. A Sonnet worker always gets `--model <WORKER_MODEL>`, which is `sonnet` unless another model was chosen. A Codex worker gets `--model` only when a model is set. Orca refuses `--effort` without `--model`, so when only an effort is set, also pass the `model` from `~/.codex/config.toml`; when the config names none, start without `--effort` and record that the effort could not be applied.
- From the receipt, record the Dispatch id, its `state`, and its `workspace`. Resolve the worktree with `orca worktree show --worktree id:<workspace> --json` and record its path and selector `id:<workspace>`. Later steps select that worktree by this selector, never by its name; Orca may add a suffix to the name. Record the receipt's `model` and `effort` as the effective choices; when it omits them, the launch inherited Codex's defaults, and the choice is recorded as `inherited`.
- Classify every start receipt before acting on it. `ready`: started. `outcome_unknown` with a `next` instruction to wait: started but not yet observed; follow `next` and never start the agent again. `not_kept_open`: the agent started without its keep-open hold; it is live, so record it as started and wait. Any other failure that returns a Dispatch id: read `worker-show --dispatch <id> --full --json`; a settled failure takes the failure route, and anything still live or unknown parks the unit. A failure with no Dispatch id takes the `worker-start` failure route below.
- The worker's tab stays open, because a worker in a new worktree is kept open.
- A worker whose agent runs with permission prompts needs `orca orchestration` commands allowed: its `ask` and `worker_done` are shell commands too, and each would otherwise wait on a prompt.
- Send a hand-off with `orca orchestration send --run <run> --to dispatch:<id> --subject "<topic>" --body "$(cat <brief>)" --json`, only to a worker whose Dispatch has settled. A settled worker receives the message as a follow-up Task with its own Dispatch; record both from the receipt. That Dispatch becomes the worker's current attempt, with its own deadline, and joins cleanup. A receipt without a follow-up Task and Dispatch means no new attempt started: park the unit with the receipt.
- Retry on the same Task with `worker-start --run <run> --task <task> --retry-of <dispatch> --worktree <recorded selector> --agent <agent> [--model <model> --effort xhigh] --keep-open --json`. A retry does not inherit placement, model, or keep-open, so pass them. Pass `--model` with the effective model the first launch reported, and `--effort xhigh` with it. When the first launch's model was `inherited`, pass neither, and record that the retry could not escalate its effort. When Orca refuses `xhigh` for the model before starting anything, start the retry without `--effort` and record it. After three failed starts in one chain, Orca's breaker fails the Task: the unit has failed. Never route around the breaker with a new Run or Task.

## Reviewer

Each round starts a fresh reviewer as a child of the unit's Task, in the worker's worktree; its brief sends it to the round's review checkout:

```text
orca orchestration worker-start --run <run> --spec-file <review brief> --parent <task> --worktree <recorded selector> --agent claude --model <REVIEWER_MODEL> --keep-open --json
```

Record its Dispatch id and its child Task id. `--keep-open` keeps the reviewer's tab after it finishes, and a reviewer retry passes it too. Keep every reviewer until the unit's cleanup releases it.

## Events

| Event | Route |
|---|---|
| `question` the plan or repository answers | `orca orchestration reply --id <message> --body "<answer>"` |
| `question` only the user can answer | The skill's Questions rule. Unattended, reply with the recommended option |
| Permission prompt: an `escalation` with `stopReason` `needs-input` whose payload carries `approval` | Never message the worker while it waits. Interactive: tell the user what the worker asks to run and end the turn; the unit waits for the approval's `status` message. Unattended: `orca orchestration deny --dispatch <id> --prompt <payload approval.approvalId> --reason "<why>"`. The reason only says why the action is refused and that the worker should continue without it; a reason that hands the worker new work reads to it as injected instructions, and it may stop. If deny is refused, park the unit |
| `status` about an approval (`Worker approval answered` or `closed`) | Mark it handled. A later `worker_done`, question, or escalation from the same Dispatch carries on the unit |
| Any other `escalation` with `stopReason` | `send` one steer. If it stops again, the unit has failed |
| Worker `worker_done` | Step 4 for a build, or the hand-off check in step 5 for a fix, check, verify, or rebase hand-off. An `answer` hand-off is checked as the phase it continues |
| Reviewer `worker_done` | Step 5's acceptance check on the reviewer's result file |
| Worker reports failure, or `exited`, or `lost` | Retry once at `xhigh` on the same Task, then the coordinator takes over as step 4 describes |
| Reviewer reports failure, or `exited`, or `lost` | Retry the reviewer once as step 5 describes, then park the unit |
| `worker-start` fails | Read `failedStage` and load `references/recovery-and-cleanup.md` from the guide. Never rerun the same start under a new key |

## Reattach and hang

An agent the unit state records as running is still current when `orca orchestration worker-show --dispatch <id> --full --json` shows it unsettled; wait for its event. A settled agent whose event is not in the Run's message log is handled from the coordinator mailbox listing or its `lastReport`, as `references/state.md` describes.

Past the deadline, read `worker-show --full --json` again; the concise view omits `observation`:
- `observation.agentWait` present and non-null: the agent is waiting on a prompt only a human can answer. Route it as a permission prompt or a question above.
- `observation.agentWait` null while the agent still works: it is hung. Stop it with `worker-stop --dispatch <id>`, then route it as a reported failure for its role. If `worker-stop` returns `stop_unknown` or `helper_stop_unknown`, do not retry: park the unit, since the agent or its helper may still write.
- `observation.agentWait` absent: Orca could not verify the agent, which never proves it is stuck, so never stop it. Interactive, tell the user. Unattended, park the unit with the agent left running, and report it.

## Gate and merge

The recorded worktree path holds the branch; an empty commit to retrigger checks is made there. Review and gate checkouts are separate detached worktrees under the state directory. Merge from the coordinator's own checkout with GitHub's direct merge call, which never queues, never enables auto-merge, and refuses when the PR head is not the approved head:

```sh
gh api -X PUT repos/<owner>/<repo>/pulls/<n>/merge -f merge_method=squash -f sha=<approved head>
```

## Cleanup after the merge

Each step is an operation with its own intent; a resource found already gone counts as done, and cleanup continues with the next step.
1. Check the recorded worktree, unless an earlier entry already removed it: `git status --short` must be empty and `git rev-parse HEAD` must equal the approved head. If either check fails, the worktree holds work the merge did not include: keep the worktree, the branch, and every agent, record them as kept, report them, and stop here.
2. Delete the remote branch with `git push --force-with-lease=refs/heads/<branch>:<approved head> origin :refs/heads/<branch>`. A rejected lease means someone pushed after the approval: keep the branch and report it.
3. Release each agent the unit state records, follow-up Dispatches included, with `worker-release --dispatch <id> --json`, and record each receipt. `already_released` is done. `release_pending` stays pending and is retried on the next entry. `retained` with reason `ownership_transferred` means a later Dispatch of this unit took over the same terminal; it is settled once that later Dispatch is released. Any other `retained` means the agent's terminal is kept on purpose, by the operator or by Orca: record it as kept, do not retry it, and report it. `release_unknown` parks the cleanup.
4. Only when every agent is released, remove the worktree with `orca worktree rm --worktree <recorded selector>`, without `--delete-branch`. With an agent kept, keep the worktree and report it.
5. When no worktree has the branch checked out (`git worktree list --porcelain`), delete the local branch with `git update-ref -d refs/heads/<branch> <approved head>`, which refuses when the branch points anywhere else.

A unit that failed, parked, or awaits `merge` keeps its worktree and every agent.
