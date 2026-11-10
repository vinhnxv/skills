---
name: audit-loop
description: Repeatedly audit a repository with the repo-audit procedure, fix every confirmed actionable finding, and land each round through a reviewed, CI-gated pull request until an audit finds nothing left to fix. Explicit invocation only; run before the matching long-running goal.
---

Repeat one round until the repository converges: audit with the `repo-audit` procedure, fix every confirmed actionable finding, review the fix, open a pull request, merge it, and pull the default branch. Never ask the user anything; when a choice arises take your recommended option and record it in the PR body. Write English in code, commits, PRs, and reports.

Invoking this skill is the user's standing selection of `repo-audit`'s "Fix all confirmed, actionable findings" choice for every round. It authorizes nothing else: it never creates tracker work, never runs `source-to-beads` or `backlog-loop`, and never changes the audit procedure.

Requirements: the `repo-audit` skill installed beside this one, a GitHub remote named `origin` with `gh` authenticated, and the `compound-engineering` plugin providing `ce-work`, `ce-code-review`, and `ce-commit-push-pr`. Beads is not required, and this procedure never calls `bd`.

Parameters, overridable by the goal or the user:
- `LOOP_ROUND_LIMIT`: `5` rounds.
- `MAX_FIXES_PER_ROUND`: `20` findings. Over the cap, fix in severity order (P0 first) and leave the rest to the next round's audit.
- `FIX_SCOPE`: every confirmed actionable finding, P0 through P4.

## Preflight (once)

1. Read `../repo-audit/SKILL.md`, resolved against this skill's own directory. If it is absent, stop and tell the user to install `repo-audit` beside this skill. That file is the audit procedure for every round.
2. Run `gh auth status` and `git status --short`, and resolve the default branch with `gh repo view --json defaultBranchRef`. Stop when a probe fails, the local default branch has unpushed commits, or the tree is dirty outside `docs/audits/`. Untracked report files under `docs/audits/` never block a round.
3. Switch to the default branch and `git pull --ff-only`.
4. Open the ledger at `<git-common-dir>/audit-loop/ledger.json`, where `<git-common-dir>` is `git rev-parse --path-format=absolute --git-common-dir`. Create it as `{}` when absent. It lives outside the work tree, so it never dirties a round, and it survives restarts. Each key is a stable finding ID; each value records `attempts`, `status` (`fixed`, `deferred`, or `exhausted`), the PR number, and the reason.

## One round

1. **Audit.** Run the `repo-audit` procedure in full on the freshly pulled default branch, passing the previous round's report as `previous-report:` when one exists. Save the report and run its worktree handoff exactly as it requires. Stop at its "Recommendation and user choice" step: do not present choices or wait; the selection is this skill's invocation.
2. **Select.** From the report, take every finding that is `confirmed` and actionable within `FIX_SCOPE`. Drop each finding the ledger marks `deferred` or `exhausted`. Defer, with a reason recorded in the ledger and later in the PR body, a finding whose fix needs a person: a credential or secret rotation, a change outside the repository, an unpatched advisory with no fixed version, or a change to a public contract, permission, or security stance. A finding the ledger marks `fixed` that the audit reports again counts as a new attempt. If nothing is selected, the repository has converged: go to the final report.
3. **Fix.** Create `fix/audit-<run-id>` from the default branch. Run `compound-engineering:ce-work` with the absolute report path and the exact selected IDs, telling it to recheck each finding against the current tree before editing, to fix the root cause, to add a regression test where the project has tests, and to skip a finding the recheck refutes. A redacted finding's location comes from its ignored detail file; never copy sensitive detail into code, commits, or the PR.
4. **Review.** Run `compound-engineering:ce-code-review` on the branch diff. Fix every valid finding. Run the project's test, lint, and type gates locally. Repeat until review reports no blocking finding.
5. **Open the PR.** Commit the report with the fix only when the repository already tracks a report under `docs/audits/`; otherwise leave it untracked. Open the PR with `compound-engineering:ce-commit-push-pr`. Its body lists the report path and run ID, every fixed ID, every ID the recheck refuted, and every deferred ID with its reason.
6. **Merge.** Decide whether the PR has checks by reading `gh pr view <n> --json statusCheckRollup`, not by the exit code of `gh pr checks`, which fails when a PR has no checks. Read it again after two minutes when the first read is empty.
   - **Checks present:** wait with `gh pr checks <n> --watch`; a failing check is fixed and pushed, never bypassed.
   - **Still empty, and no workflow under `.github/workflows/` triggers on `pull_request`:** rerun the full local gates on the exact head commit you reviewed and treat their pass as the merge gate.
   - **Still empty, but a `pull_request` workflow exists:** push an empty commit once to retrigger; if checks still do not appear, abandon the round with that cause.

   Never use `--admin` or auto-merge. Merge with `gh pr merge <n> --squash --delete-branch --match-head-commit <reviewed sha>` and confirm `gh pr view <n> --json state` reads `MERGED`.
7. **Record and sync.** Mark every fixed ID `fixed` with the PR number in the ledger. `git switch <default> && git pull --ff-only`, then start the next round.

## Convergence and failure rules

A round that cannot merge closes its PR with the cause as a comment, deletes the branch, switches back to the default branch, and adds one to `attempts` for every selected ID. An ID at 2 attempts becomes `exhausted` and is left for a person; that includes a finding that resurfaces after a merged fix.

Stop when any of these holds, and say which:
- **Converged:** an audit selects nothing.
- **Stalled:** a round merged no fix, and the next audit selects only IDs that round already attempted.
- **Limit:** `LOOP_ROUND_LIMIT` rounds have run.
- **Trunk red:** the default branch fails its gates for a reason no round can fix.

## Final report

List each round: report path, run ID, confirmed and selected counts, fixed IDs, refuted IDs, deferred IDs with reasons, PR number, and merge SHA. Then name the stop condition, every finding still open with its severity and the reason it stays (deferred to a person, exhausted, or over the round limit), the coverage gaps the last audit recorded, and the ledger path.
