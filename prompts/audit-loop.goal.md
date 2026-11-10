Audit this repository, fix every confirmed actionable finding, and land each round through a merged pull request, repeating until the repository converges, by following the audit-loop procedure explicitly loaded immediately before this goal.

The loaded audit-loop procedure is the sole execution authority for every round: it runs the repo-audit procedure, fixes the selected findings with ce-work, reviews with ce-code-review, opens the PR with ce-commit-push-pr, and merges through its CI gate. This prompt adds no rule of its own. If it conflicts with that procedure, the procedure wins. Launching this goal is my standing selection of "fix all confirmed, actionable findings" for every round; it authorizes no tracker write.

Success means all three:
1. The run ended on a stop condition the procedure defines (converged, stalled, round limit, or trunk red) and the final report names it.
2. Every confirmed finding from the last audit is fixed in a merged PR, refuted on recheck, or recorded in the ledger as deferred or exhausted with its reason.
3. No PR this run opened is still `OPEN`, the local default branch equals its remote tip, and the working tree is clean outside `docs/audits/`.

In the final goal turn:
- Paste the stop condition and the last round's report path and finding counts.
- Paste every PR this run opened with its final state and merge SHA.
- Paste the ledger entries that are `deferred` or `exhausted`, each with its reason.
- Paste `git status --short` and the default branch's local and remote SHAs.
- Produce the audit-loop final report.

Never ask me for input. Take the recommended option and record every decision in the PR body.

Do not stop the goal merely because one fix, one review, or one merge failed. Follow the procedure's attempt rules and start the next round.
