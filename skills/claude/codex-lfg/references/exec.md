# Exec backend

Read this when Preflight chose the exec backend. Every agent runs in the background of this session, and its completion arrives as the background-task notification; never poll. Background agents do not outlive the Claude Code session, so the unit state, not memory, says what was started.

Every agent start gets its own attempt number and its own files in the scratchpad, `codex-lfg-<slug>-<role>-<attempt>.brief.md`, `.log`, and `.last.md`, where the role is `worker` or `reviewer`. Record the attempt, its paths, the background task or agent ID, and the start time in the unit state before starting it. A new attempt never reuses an earlier attempt's files.

## Codex worker

The Codex worker uses the coordinator's checkout. Step 2 puts it on the unit's branch: `git switch <default> && git pull --ff-only && git switch -c <branch>` for a new branch, or `git switch <branch>` when the branch exists. Every later Codex run starts from the same switch, so it never runs on another branch. Run Codex as a background command, with `CODEX_MODEL` and `CODEX_EFFORT` holding `WORKER_MODEL` and `WORKER_EFFORT`:

```sh
codex exec -C "$REPO" ${CODEX_MODEL:+--model=$CODEX_MODEL} ${CODEX_EFFORT:+--config=model_reasoning_effort=$CODEX_EFFORT} \
  -s danger-full-access -o "$SCRATCH/codex-lfg-<slug>-worker-<attempt>.last.md" - < "$SCRATCH/codex-lfg-<slug>-worker-<attempt>.brief.md" \
  > "$SCRATCH/codex-lfg-<slug>-worker-<attempt>.log" 2>&1
```

Tell the user the log path. When the user asks for progress, read the log tail and `git log --oneline <default>..<branch>`, and answer from them. The worker's result is the `-o` file plus the log tail. A retry or hand-off is a new attempt with the same command, on the same branch, with the fix or rebase brief.

## Sonnet worker

The Sonnet worker gets its own git worktree, and the coordinator's checkout stays on the default branch. Create it with `git worktree add "$(git rev-parse --git-common-dir)/codex-lfg/worktrees/<slug>" -b <branch> origin/<default>`, or, when the branch exists, attach it without `-b`. Record the path in the unit state.

Start the worker with the `Agent` tool as a fresh general-purpose agent, never a fork. Pass `model` and, when set, `effort`, and set `run_in_background` to true. Its prompt is the brief plus: "Work only in `<worktree path>`. When you finish, write your final message to `<.last.md path>`." The `Agent` tool takes only model aliases such as `sonnet` or `opus`. Given a full model id, an interactive run stops and says so. Unattended, it uses the alias of the id's family and records the substitution in the report. A retry or hand-off starts a new `Agent` in the same worktree.

A background agent cannot ask for a permission it was not already granted, and unattended never asks the user, so a tool the worker needed and was denied shows up in its result. Treat that as a question under the skill's Questions rule.

## Reviewer

The reviewer is a fresh general-purpose `Agent` with `model` set to `REVIEWER_MODEL`, under the same alias rule, run in the background. It reads the pull request through `gh`, needs no workspace, and writes its JSON result to `codex-lfg-<slug>-reviewer-<attempt>.json` in the scratchpad.

## Reattach and hang

On entry, an agent the unit state records as running is still current only when this session started it, or, for a Codex worker, when `pgrep -f "<its .last.md path>"` finds the process. Otherwise it was interrupted when an earlier session ended. Read its result file if one was written and continue from it. Without one, inspect the branch, then rerun the same phase as a new attempt. An interrupted attempt does not count as a failed one.

Past the deadline, stop the run with `TaskStop`. Then treat it as a failed run for its role: a worker retries once at `xhigh`, then the coordinator takes over as step 4 describes; a reviewer retries once, then the unit has failed.

## Merge and cleanup

Merge without `--delete-branch`, for either worker:

```sh
gh pr merge <n> --squash --match-head-commit <approved head>
```

Once the PR reads `MERGED`, check the workspace that held the branch, the coordinator's checkout for Codex or the worktree for Sonnet: `git status --short` must be empty and `git rev-parse <branch>` must equal the approved head. If either fails, keep the workspace and the branch, record them as kept, and report them. Otherwise:
1. Delete the remote branch with `git push --force-with-lease=refs/heads/<branch>:<approved head> origin :refs/heads/<branch>`. When it is already gone, this step is done. A rejected lease means someone pushed after the approval: keep the branch and report it.
2. For Sonnet, remove the worktree with `git worktree remove <worktree path>`. For Codex, the coordinator's checkout is already back on the default branch from step 6.
3. Delete the local branch with `git update-ref -d refs/heads/<branch> <approved head>`, which refuses when the branch points anywhere else.

A unit that failed or awaits `merge` keeps its worktree and branch.
