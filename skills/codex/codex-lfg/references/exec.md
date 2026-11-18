# Exec backend

Read this when Preflight chose the exec backend. Every agent runs in the background of this session, and its completion arrives as the background-task notification; never poll. The worker gets the brief from step 3 of the skill, and each fix round starts a new run of the same kind of worker with the accepted findings added to that brief.

## Codex worker

The Codex worker uses the coordinator's checkout. Step 2 switches it to the unit's branch with `git switch <default> && git pull --ff-only && git switch -c <branch>`, so Codex starts on it. Run Codex as a background command, with `CODEX_MODEL` and `CODEX_EFFORT` holding `WORKER_MODEL` and `WORKER_EFFORT`:

```sh
codex exec -C "$REPO" ${CODEX_MODEL:+--model=$CODEX_MODEL} ${CODEX_EFFORT:+--config=model_reasoning_effort=$CODEX_EFFORT} \
  -s danger-full-access -o "$SCRATCH/codex-lfg-<slug>.last.md" - < "$SCRATCH/codex-lfg-<slug>.brief.md" \
  > "$SCRATCH/codex-lfg-<slug>.log" 2>&1
```

Tell the user the log path. When the user asks for progress, read the log tail and `git log --oneline <default>..<branch>`, and answer from them. Step 4 reads the `-o` file and the log tail. A retry or fix round is a new `codex exec` run with the same command on the same branch.

## Sonnet worker

The Sonnet worker gets its own git worktree, and the coordinator's checkout stays on the default branch. Create it with `git worktree add "$(git rev-parse --git-common-dir)/codex-lfg/worktrees/<slug>" -b <branch> origin/<default>`. On a resume, attach the existing branch instead, without `-b`.

Start the worker with the `Agent` tool as a fresh general-purpose agent, never a fork. Pass `model` and, when set, `effort`, and set `run_in_background` to true. Its prompt is the brief plus: "Work only in `<worktree path>`." The `Agent` tool takes only model aliases such as `sonnet` or `opus`. Given a full model id, an interactive run stops and says so. Unattended, it uses the alias of the id's family and records the substitution in the report. A retry or fix round starts a new `Agent` in the same worktree.

## Reviewer

The reviewer is a fresh general-purpose `Agent` with `model` set to `REVIEWER_MODEL`, under the same alias rule, run in the background. It reads the pull request through `gh` and needs no workspace.

## Hang

Past the deadline, stop the run with `TaskStop`. Then treat it as a failed run: retry once at `xhigh`, and if that also fails, implement the plan yourself with `/compound-engineering:ce-work` in the workspace that holds the branch.

## Merge and cleanup

- **Codex worker:** `gh pr merge <n> --squash --delete-branch --match-head-commit <approved head>`.
- **Sonnet worker:** the worktree holds the branch, so merge without `--delete-branch`, keeping `--match-head-commit <approved head>`. Once the PR reads `MERGED`, check the worktree first: `git status --short` must be empty and `git rev-parse HEAD` must equal the approved head. If either fails, keep the worktree and the branch and report them. Otherwise:
  1. Remove the worktree with `git worktree remove <worktree path>`.
  2. Delete the local branch with `git branch -D <branch>`.
  3. Delete the remote branch with `git push origin --delete <branch>`, only if it still shows the approved head.

A unit that failed or awaits `merge` keeps its worktree.
