---
name: codex-lfg
description: Hand one unit of work, a plan file or one or more Beads issues, to Codex CLI to implement through compound-engineering:lfg up to an open pull request, track the Codex run in the background, then review, fix, and gate the PR with Claude Code; merge only when asked. Claude Code only. Explicit invocation only.
---

Usage: `/codex-lfg <plan-path | bead-id...> [merge]`.

Run one unit of work through Codex and bring it back reviewed. Claude is the primary agent: it plans when needed, judges every result, and owns the merge. Codex CLI is the secondary agent: it only implements a plan and opens a pull request. The user stays in the loop: Codex runs in the background, so the session stays free for other requests while it works. Write English in code, commits, PRs, and tracker fields.

This procedure runs on Claude Code. On any other host, stop before any tracker or git write and tell the user to run it from Claude Code. It needs the `compound-engineering` plugin installed for both Claude Code and Codex, `gh` working, and `codex` on PATH; it needs `bd` working only when the input names Beads issues.

Parameters, overridable by the user:
- `CODEX_MODEL`: empty by default, so `codex exec` uses the `model` from the Codex config (`~/.codex/config.toml`). Set it only when the user names a model.
- `CODEX_EFFORT`: empty by default, so `codex exec` uses the `model_reasoning_effort` from the Codex config. Set it to `xhigh` when the plan has three or more implementation units, touches a contract, migration, or security boundary, or a previous Codex attempt on the same unit failed; otherwise set it only when the user names an effort.
- `MERGE`: off unless the arguments include the word `merge`.

An empty parameter adds no flag to the `codex exec` command, so upgrading the Codex model is a Codex config change, not a skill change.

## Input

Parse the arguments once:
- The word `merge` turns `MERGE` on.
- An argument naming an existing file is the plan. Resolve it to an absolute path. At most one plan is allowed.
- Every other argument must be a Beads issue id that `bd show <id> --json` returns.

With no plan and no issue id, or with an argument that is neither, stop and print the usage line. Refuse an issue that is closed, an epic, or a human gate (`[HUMAN]` title, `human-gate` label, or type `gate`). Refuse an issue that is `in_progress` without `codex_lfg_branch` metadata; another agent owns it.

A plan with issue ids is allowed: the plan is used as written and the issues are claimed and closed with it.

The branch name is fixed by the input so a rerun finds earlier work: `codex-lfg/<plan file name without extension>` when a plan is given, otherwise `codex-lfg/<first issue id>`, lowercased with every character outside `a-z0-9._-` replaced by `-`. When an input issue already carries `codex_lfg_branch`, use that branch instead.

## Preflight

Run `gh auth status`, `codex --version`, and `git status --short`, plus `bd prime` when the input names issues. Resolve the default branch with `gh repo view --json defaultBranchRef`. Stop and report if any probe fails, the local default branch has unpushed commits, or the working tree is dirty; a dirty tree belongs to the user, so never commit or stash it. The one exception is a dirty tree on this unit's own branch, which Resume handles.

## Resume

Look up the branch and its PR with `git ls-remote --heads origin <branch>`, `git branch --list <branch>`, and `gh pr list --head <branch> --state all --json number,state,headRefOid`, then start at the first unfinished step:
- PR `MERGED`: step 7.
- PR `OPEN`: step 5.
- Branch with commits ahead of the default branch but no PR: step 4. Commit leftover changes on it first as `wip: recover interrupted codex-lfg run` and push.
- PR `CLOSED` unmerged: stop and ask the user whether to start over on a fresh branch; a closed PR is a decision someone made.
- Nothing yet: step 1.

Report the step a run resumed at.

## Steps

1. **Plan.** With a plan argument, read the plan and use it as written; when it lacks acceptance criteria or verification commands, state the missing ones in the brief instead of editing the user's file. With issue ids, claim each with `bd update <id> --claim`, record the branch with `bd update <id> --set-metadata codex_lfg_branch=<branch>`, and read it back with `bd show <id> --json`. Without a plan argument, run `/compound-engineering:ce-plan` with the issue ids, titles, bodies, and acceptance criteria; record the absolute path of the plan it writes. The plan must name the bead ids, the acceptance criteria, and the verification commands.
2. **Branch.** `git switch <default> && git pull --ff-only && git switch -c <branch>`, so Codex starts on it.
3. **Delegate (Codex).** Write the brief to a file in the scratchpad and run Codex as a background command, so the session stays free:

   ```sh
   codex exec -C "$REPO" ${CODEX_MODEL:+--model=$CODEX_MODEL} ${CODEX_EFFORT:+--config=model_reasoning_effort=$CODEX_EFFORT} \
     -s danger-full-access -o "$SCRATCH/codex-lfg-<slug>.last.md" - < "$SCRATCH/codex-lfg-<slug>.brief.md" \
     > "$SCRATCH/codex-lfg-<slug>.log" 2>&1
   ```

   The brief says, in English: implement the plan at `<absolute plan path>` with the compound-engineering `lfg` skill on the current branch; end with an open pull request against `<default>` whose body lists the bead ids, if any; do not merge, do not close or edit Beads issues, do not push to `<default>`, do not rewrite history; if blocked, stop and state the blocker in the final message.

   Tell the user the run started, with the branch and the log path. Then wait for the completion notification instead of polling, and handle other requests meanwhile. When the user asks for progress, read the log tail and `git log --oneline <default>..<branch>`, and answer from them. Kill the run (TaskStop) and treat it as failed when it exceeds 90 minutes.
4. **Check the handoff.** Read the `-o` file and the log tail. Find the PR with `gh pr list --head <branch> --json number,headRefOid,state`. If Codex left commits but no PR, open it with `/compound-engineering:ce-commit-push-pr`. If Codex failed with no usable commits, retry once with `CODEX_EFFORT=xhigh` and the failure reason added to the brief; if that also fails, implement the plan yourself with `/compound-engineering:ce-work`.
5. **Review and fix (Claude).** Run `/compound-engineering:ce-code-review` on the PR. Fix every valid finding yourself, including issues review did not flag but the acceptance criteria require. Run the plan's verification commands and the project's test, lint, and type gates locally. Commit and push the fixes. Repeat review until it reports no blocking finding.
6. **Gate, then stop or merge.** Decide whether the PR has checks by reading `gh pr view <n> --json statusCheckRollup`, not by the exit code of `gh pr checks`, which fails when a PR has no checks. Checks can register late, so read it again after two minutes when the first read is empty.
   - **Checks present:** wait with `gh pr checks <n> --watch`; a failing check is fixed and pushed, never bypassed.
   - **Still empty, and no workflow under `.github/workflows/` triggers on `pull_request`:** the repository has no PR CI. Rerun the full local test, lint, and type gates on the exact head commit you reviewed, and treat their pass as the gate.
   - **Still empty, but a `pull_request` workflow exists:** checks are stuck. Push an empty commit once to retrigger them; if they still do not appear, stop and report that cause.

   With `MERGE` off, stop here and report; tell the user that rerunning the same command with `merge` added resumes at this step and merges. With `MERGE` on, never use `--admin` or auto-merge. Merge with `gh pr merge <n> --squash --delete-branch --match-head-commit <reviewed sha>`, confirm `gh pr view <n> --json state` reads `MERGED`, then `git switch <default> && git pull --ff-only`.
7. **Close.** Only after the PR reads `MERGED`, close each issue with `bd close <id> --reason "Merged in #<n>"`, read it back with `bd show <id> --json`, and persist tracker changes the way this repository's Beads setup requires. When the repository uses Beads, file each deferred review finding as a new P2-or-lower `tech-debt` issue that cites the PR; otherwise list it in the report.

## Failure

Take the recommended option on technical choices and record it in the PR body. Ask the user only for a choice that is theirs: a scope change, a change to a contract, permission, or security stance, or starting over after a closed PR. When the unit cannot finish, stop and report the cause, the branch, and the PR. For issues, append the cause and the PR to each with `bd update <id> --append-notes` and release the claim with `bd update <id> --status open --assignee ''`, keeping `codex_lfg_branch` so a rerun resumes the same branch.

## Report

State the input, the plan path, the branch, the Codex model and effort as the log header shows them, the Codex outcome (success, retried, or replaced by Claude), the PR URL, the findings Claude fixed, the reviewed head SHA, the check result, and either the merge SHA or that the PR is open and awaiting `merge`. For issues, give each one's final state.
