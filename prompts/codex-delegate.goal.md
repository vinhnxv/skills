Clear every actionable non-epic issue from this repository's Beads tracker, one cycle at a time. Claude is the primary agent: it chooses the work, plans it, judges every result, and owns every merge. Codex CLI is the secondary agent: it only implements a plan Claude wrote and opens a pull request. Run on Claude Code with the `compound-engineering` plugin installed for both Claude Code and Codex, `bd` and `gh` working, and `codex` on PATH.

Parameters (edit before pasting if needed):
- `CODEX_MODEL`: `gpt-6.1-sol`
- `CODEX_EFFORT`: `high` by default; use `xhigh` when the plan has three or more implementation units, touches a contract, migration, or security boundary, or a previous Codex attempt on the same cycle failed.

## Preflight (once)

Run `bd prime`, `bd ready --json`, `gh auth status`, `codex --version`, and `git status --short`. Resolve the default branch with `gh repo view --json defaultBranchRef`. Stop and report if any probe fails or the local default branch has unpushed commits. A dirty working tree stops the run unless the current branch is the `codex_delegate_branch` of an issue found in Recovery below; in that case commit the leftover changes on that branch as `wip: recover interrupted cycle`, push it, and let Recovery resume it.

## Recovery (once, before the first new cycle)

Every issue this loop claims carries `codex_delegate_branch` metadata, so an interrupted run leaves a trail. List it with `bd list --status=in_progress --has-metadata-key codex_delegate_branch --json`, and read each issue with `bd show <id> --json`. Group issues that share a branch and resume each group at the first unfinished step:
- PR for the branch is `MERGED`: run step 7 for it.
- PR is `OPEN`: resume at step 5 (review), then merge as usual.
- Branch exists on `origin` or locally with commits ahead of the default branch but no PR: resume at step 4 (open the PR from those commits).
- No branch and no PR, or the PR is `CLOSED` unmerged: add one to `codex_delegate_attempts`, clear the claim with `bd update <id> --status open --assignee ''`, and let a later cycle pick it again.

Leave `in_progress` issues without `codex_delegate_branch` alone; another agent owns them. Report each recovered issue in the final report. Then switch to the default branch and `git pull --ff-only`.

## One cycle

1. **Pick.** From `bd ready --json`, take the highest-priority non-epic issue that is not a human gate (`[HUMAN]` title, `human-gate` label, or type `gate`). Add other ready issues only when they share its parent epic and the same code area, and keep the set small enough for one reviewable PR. Skip any issue whose `codex_delegate_attempts` metadata is 2 or more. Choose the branch name now (`<type>/<short-slug>`), then claim each issue with `bd update <id> --claim` and record the branch with `bd update <id> --set-metadata codex_delegate_branch=<branch>`, reading it back with `bd show <id> --json`.
2. **Plan (Claude).** Run `/compound-engineering:ce-plan` with the issue ids, titles, bodies, and acceptance criteria. Let it write the plan file; record its absolute path. The plan must name the bead ids, the acceptance criteria, and the verification commands.
3. **Delegate (Codex).** Create the recorded branch yourself (`git switch -c <branch>` from the updated default branch) so Codex starts on it. Write the brief to a file in the scratchpad and run Codex in the background, then wait for its completion notification instead of polling:

   ```sh
   codex exec -C "$REPO" -m "$CODEX_MODEL" -c model_reasoning_effort="$CODEX_EFFORT" \
     -s danger-full-access -o "$SCRATCH/codex-<cycle>.last.md" - < "$SCRATCH/codex-<cycle>.brief.md" \
     > "$SCRATCH/codex-<cycle>.log" 2>&1
   ```

   The brief says, in English: implement the plan at `<absolute plan path>` with the compound-engineering `lfg` skill on the current branch; end with an open pull request against `<default>` whose body lists the bead ids; do not merge, do not close or edit Beads issues, do not push to `<default>`, do not rewrite history; if blocked, stop and state the blocker in the final message.
   Kill the run (TaskStop) and treat it as failed when it exceeds 90 minutes.
4. **Check the handoff.** Read the `-o` file and the log tail. Find the PR with `gh pr list --head <branch> --json number,headRefOid,state`. If Codex left commits but no PR, open it with `/compound-engineering:ce-commit-push-pr`. If Codex failed with no usable commits, retry once with `CODEX_EFFORT=xhigh` and the failure reason added to the brief; if that also fails, implement the plan yourself with `/compound-engineering:ce-work`. Never wait on a human.
5. **Review and fix (Claude).** Run `/compound-engineering:ce-code-review` on the PR. Fix every valid finding yourself, including issues review did not flag but the acceptance criteria require. Run the plan's verification commands and the project's test, lint, and type gates locally. Commit and push the fixes. Repeat review until it reports no blocking finding.
6. **Merge.** Decide whether the PR has checks by reading `gh pr view <n> --json statusCheckRollup`, not by the exit code of `gh pr checks`, which fails when a PR has no checks. Checks can register late, so read it again after two minutes when the first read is empty.
   - **Checks present:** wait with `gh pr checks <n> --watch`; a failing check is fixed and pushed, never bypassed.
   - **Still empty, and no workflow under `.github/workflows/` triggers on `pull_request`:** the repository has no PR CI. Rerun the full local test, lint, and type gates on the exact head commit you reviewed, and treat their pass as the merge gate.
   - **Still empty, but a `pull_request` workflow exists:** checks are stuck. Push an empty commit once to retrigger them; if they still do not appear, block the cycle with that cause.

   Never use `--admin` or auto-merge. Merge with `gh pr merge <n> --squash --delete-branch --match-head-commit <reviewed sha>` and confirm `gh pr view <n> --json state` reads `MERGED`.
7. **Sync and close.** `git switch <default> && git pull --ff-only`. Close each bead with `bd close <id> --reason "Merged in #<n>"`, read it back with `bd show <id> --json`, and persist tracker changes the way this repository's Beads setup requires. File any deferred review finding as a new P2-or-lower `tech-debt` issue that cites the PR.

## Loop and failure rules

Start the next cycle immediately. A cycle that cannot finish adds one to each member's `codex_delegate_attempts` metadata and appends the cause and PR to its notes with `bd update <id> --append-notes`. Below 2 attempts, reopen the issue (`--status open --assignee ''`) so a later cycle retries it; at 2, set it `blocked` and leave it for a person. The loop continues with independent work. The attempt count lives in the tracker, not in context, so it survives compaction and restarts. The Codex retry inside step 4 is part of one attempt. Never ask me for input: take the recommended option and record each decision in the issue notes and the PR body. Work only in English in code, commits, PRs, and tracker fields.

Stop when `bd ready` offers no non-epic issue other than human gates and every issue this run claimed is closed or blocked with a recorded cause, or when trunk is red for a reason no cycle can fix.

## Final report

List each issue Recovery resumed and the step it resumed at. List each cycle: bead ids, plan path, Codex model and effort, Codex outcome (success, retried, or replaced by Claude), PR number, findings fixed by Claude, and merge SHA. Then list every remaining open non-epic issue with the reason it stays, every blocked issue with its cause, and every human gate with the action a person must take.
