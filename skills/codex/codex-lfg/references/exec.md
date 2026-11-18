# Exec backend

Read this when Preflight chose the exec backend, together with `references/state.md`. Every agent runs in the background of this session, and its completion arrives as the background-task notification; never poll. An `Agent` does not outlive the Claude Code session that started it, so the unit state, not memory, says what was started.

Every agent start gets its own attempt directory, `<state dir>/attempts/<branch slug>/<role>-<attempt>/`, where the role is `worker` or `reviewer`. It holds `brief.md`, `log`, `result.md` (`result.json` for a reviewer), and the `started` marker. Record the attempt in the unit state, write `started` with the session token, then launch, then record the background task or agent ID the launch returns. A new attempt never reuses an earlier attempt's directory.

## Codex worker

The Codex worker uses the coordinator's checkout. Step 2 puts it on the unit's branch: `git switch <default> && git pull --ff-only && git switch -c <branch>` for a new branch, or `git switch <branch>` when the branch exists. Every later Codex run starts from the same switch, so it never runs on another branch. Before each launch, record the attempt as the unit's `checkout_owner`; it is cleared only when the attempt has settled, as the check below decides. While any unit has a `checkout_owner`, nothing else switches or writes in the coordinator's checkout. Run Codex as a background command, with `CODEX_MODEL` and `CODEX_EFFORT` holding `WORKER_MODEL` and `WORKER_EFFORT` and `$ATTEMPT` the attempt directory:

```sh
codex exec -C "$REPO" ${CODEX_MODEL:+--model=$CODEX_MODEL} ${CODEX_EFFORT:+--config=model_reasoning_effort=$CODEX_EFFORT} \
  -s danger-full-access -o "$ATTEMPT/result.md" - < "$ATTEMPT/brief.md" \
  > "$ATTEMPT/log" 2>&1
```

Tell the user the log path. When the user asks for progress, read the log tail and `git log --oneline <default>..<branch>`, and answer from them. The worker's result is `result.md` plus the log tail. A retry or hand-off is a new attempt with the same command, on the same branch, with the fix or rebase brief.

## Sonnet worker

The Sonnet worker gets its own git worktree, and the coordinator's checkout stays on the default branch. Create it with `git worktree add "<state dir>/worktrees/<branch slug>" -b <branch> origin/<default>`, or, when the branch exists, attach it without `-b`. Record the path in the unit state.

Start the worker with the `Agent` tool as a fresh general-purpose agent, never a fork. Pass `model` and, when set, `effort`, and set `run_in_background` to true. Its prompt is the brief plus: "Work only in `<worktree path>`, using absolute paths and setting the working directory in every shell command, since a `cd` does not carry over between commands. When you finish, write your final message to `<attempt directory>/result.md`." The `Agent` tool takes only model aliases such as `sonnet` or `opus`. Given a full model id, the unit stops and says so. A retry or hand-off starts a new `Agent` in the same worktree.

A background agent that needs a permission it does not have either gets the tool call denied, which shows in its result and is handled as a question under the skill's Questions rule, or raises a prompt in this session. Interactive, the user answers it. Unattended, nobody does: the agent runs into its deadline, and the hang rule parks the unit, naming the agent and the likely permission. Allowing the plan's verification commands in the project's permission settings before an unattended run avoids this.

## Reviewer

The reviewer is a fresh general-purpose `Agent` with `model` set to `REVIEWER_MODEL`, under the same alias rule, run in the background. Its brief is step 5's review brief, which sends it to the round's review checkout and names `<attempt directory>/result.json` as its result path. An unattended reviewer stopped by a permission prompt nobody answers is handled the same way.

## Checking an exec launch

This is the check `references/state.md` defers to, run on every entry for each attempt the unit state records as running. The first rule that applies decides:
1. This session holds the attempt's task or agent ID: its completion notification, or the task's status, decides. Finished with a result file: read it. Finished without one: a failed run for its role. Still running: wait, guarded by its deadline. A missing result file or a missing process never overrides this.
2. A result file in the attempt directory: the attempt finished. Read it.
3. A Codex worker whose process is alive, found with `pgrep -f "<attempt directory>"` because its command line names that directory, which no other process shares: it is running, but this session cannot stop it. Wait until its deadline; past it, park the unit and keep the `checkout_owner`.
4. A Codex worker with no live process and a `started` marker from another session: it died without a result. The attempt was interrupted.
5. A Sonnet worker or reviewer whose `started` marker holds another session's token: it ended with that session. The attempt was interrupted.
6. A `started` marker that holds this session's token with no recorded ID: the launch may have happened and cannot be watched or stopped. Park the unit and keep any `checkout_owner`.
7. No `started` marker: the attempt never began. Launch it.

An interrupted attempt does not count as a failed one: start the same phase again as a new attempt, after reading what the branch already holds. A second interrupted attempt in a row for the same phase parks the unit. A Codex attempt's `checkout_owner` is cleared only in cases 1 and 2 once the run has finished, and in cases 4 and 7.

## Hang

Past the deadline, stop an agent or command this session started with `TaskStop` and its recorded ID, then confirm with its notification or status that it ended. Then treat it as a failed run for its role: a worker retries once at `xhigh`, then the coordinator takes over as step 4 describes; a reviewer retries once, then the unit parks. The exception is an unattended `Agent`, worker or reviewer, which past its deadline is most often waiting on a permission prompt nobody will answer: park the unit instead, naming the agent. Never stop a process this session did not start: park, keep the `checkout_owner`, and name the process for the operator.

## Merge and cleanup

Merge from the coordinator's checkout with GitHub's direct merge call, for either worker. It never queues, never enables auto-merge, and refuses when the PR head is not the approved head:

```sh
gh api -X PUT repos/<owner>/<repo>/pulls/<n>/merge -f merge_method=squash -f sha=<approved head>
```

Each cleanup step is an operation with its own intent; a resource found already gone counts as done, and cleanup continues with the next step. First, unless an earlier entry already removed it, check the workspace that held the branch, the coordinator's checkout for Codex or the worktree for Sonnet: `git status --short` must be empty and `git rev-parse <branch>` must equal the approved head. If either fails, keep the workspace and the branch, record them as kept, and report them. Otherwise:
1. Delete the remote branch with `git push --force-with-lease=refs/heads/<branch>:<approved head> origin :refs/heads/<branch>`. A rejected lease means someone pushed after the approval: keep the branch and report it.
2. For Sonnet, remove the worktree with `git worktree remove <worktree path>`. For Codex, the coordinator's checkout is already back on the default branch from step 6.
3. When no worktree has the branch checked out (`git worktree list --porcelain`), delete the local branch with `git update-ref -d refs/heads/<branch> <approved head>`, which refuses when the branch points anywhere else.

A unit that failed, parked, or awaits `merge` keeps its worktree and branch.
