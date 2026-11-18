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

The Sonnet worker gets its own git worktree, and the coordinator's checkout stays on the default branch. Create it with `git worktree add "<state dir>/worktrees/<branch slug>" -b <branch> origin/<default>`, or, when the branch exists, attach it without `-b`. Record the path in the unit state. Only an interactive unit runs a Sonnet worker on exec; Preflight refuses an unattended one.

Start the worker with the `Agent` tool as a fresh general-purpose agent, never a fork. Pass `model` and, when set, `effort`, and set `run_in_background` to true. Its prompt is the brief plus: "Work only in `<worktree path>`. When you finish, write your final message to `<attempt directory>/result.md`." The `Agent` tool takes only model aliases such as `sonnet` or `opus`. Given a full model id, the unit stops and says so. A retry or hand-off starts a new `Agent` in the same worktree.

A background agent that needs a permission it does not have either gets the tool call denied, which shows in its result and is handled as a question under the skill's Questions rule, or raises a prompt in this session, which the user answers.

## Reviewer

The reviewer is a fresh general-purpose `Agent` with `model` set to `REVIEWER_MODEL`, under the same alias rule, run in the background. Its brief is step 5's review brief, which sends it to the round's review checkout and names `<attempt directory>/result.json` as its result path. An unattended reviewer stopped by a permission prompt nobody answers runs into its deadline and is handled by the hang rule below.

## Checking an exec launch

This is the check `references/state.md` defers to, run on every entry for each attempt the unit state records as running:
1. A result file in the attempt directory: the attempt finished. Read it.
2. A Codex worker whose process is alive, found with `pgrep -f "<attempt directory>"` because its command line names that directory: it is running. Wait for it, guarded by its deadline.
3. A Codex worker with no live process and a `started` marker: it died without a result. The attempt was interrupted.
4. A Sonnet worker or reviewer whose `started` marker holds another session's token: it ended with that session. The attempt was interrupted.
5. A Sonnet worker or reviewer whose marker holds this session's token and whose agent ID is recorded: it is running. Wait for its notification, guarded by its deadline.
6. A Sonnet worker or reviewer whose marker holds this session's token but has no recorded agent ID: it may be running and cannot be watched or stopped. Park the unit.
7. No `started` marker: the attempt never began. Launch it.

An interrupted attempt does not count as a failed one: start the same phase again as a new attempt, after reading what the branch already holds. A notification that reports an agent finished without writing its result file is a failed run for its role. A Codex attempt's `checkout_owner` is cleared in cases 1, 3, and 7, and once a stopped process is gone.

## Hang

Past the deadline, stop the attempt. For an agent or command this session started, use `TaskStop` with its recorded ID. For a Codex process from an earlier session, `kill` the process `pgrep -f "<attempt directory>"` names, and confirm it is gone. Then treat it as a failed run for its role: a worker retries once at `xhigh`, then the coordinator takes over as step 4 describes; a reviewer retries once, then the unit parks. When the process cannot be stopped, park the unit and keep the `checkout_owner`.

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
