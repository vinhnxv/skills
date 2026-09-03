Clear every actionable non-epic issue from the Beads tracker by following the backlog-loop procedure explicitly loaded immediately before this goal.

The loaded backlog-loop procedure is the sole execution authority for every batch. If this prompt conflicts with that procedure, the procedure wins. Do not improvise around it or substitute another workflow.

Success means all three:
1. `bd ready --json --exclude-type=epic` returns no actionable issue.
2. No non-epic issue remains in progress, except one explicitly identified as externally owned and reported as a blocker under the backlog-loop procedure.
3. No non-epic issue carrying this run's `backlog_loop_run` marker is in `blocked` status.

Condition 3 is not redundant. `bd ready` excludes blocked issues, and backlog-loop marks a failed batch's members `blocked`, so conditions 1 and 2 alone are both satisfied by a run in which every issue failed and nothing merged. A run that ends with blocked members is a terminal failure to report, never a cleared backlog.

In the final goal turn:
- Paste the output of `bd ready --json --exclude-type=epic`.
- Paste the relevant non-epic result from `bd list --status=in_progress --json`.
- Paste `bd list --all --limit 0 --status=blocked --metadata-field backlog_loop_run=<run-id> --json`.
- Produce the backlog-loop final report from tracker state.

Never ask me for input. Take the recommended option and record every decision.

For every batch, follow the CI state selected by backlog-loop:
- When CI is available, use its documented bounded babysitter and require a mergeable CI decision.
- When CI is unavailable, use the documented local pre-merge and post-merge quality gates without waiting for nonexistent CI.

The applicable documented quality gates must be green before every PR. Merge each eligible completed batch using the backlog-loop merge procedure, normally:
`gh pr merge <url> --squash --delete-branch`

Never use `--admin` or GitHub auto-merge. Honor any documented exception that requires retaining the branch.

Stop the goal early and report the exact state if:
- trunk health fails;
- three consecutive batches are blocked or failed;
- the same issue ID is attempted twice;
- two consecutive merges fail;
- backlog-loop encounters another documented terminal blocker.
