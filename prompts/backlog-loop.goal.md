Clear every actionable non-epic issue from the Beads tracker by following the backlog-loop procedure explicitly loaded immediately before this goal.

The loaded backlog-loop procedure is the sole execution authority for every batch. If this prompt conflicts with that procedure, the procedure wins. Do not improvise around it or substitute another workflow.

Success means all three:
1. `bd ready --json --exclude-type=epic` returns no actionable issue.
2. No non-epic issue remains in progress, except one explicitly identified as externally owned and reported as a blocker under the backlog-loop procedure.
3. The backlog-loop census leaves **no** non-closed non-epic issue in a category the loop is responsible for, and names every remaining issue with the reason it stays.

Condition 3 is not redundant, and it is the only one of the three that can tell a finished backlog from a stuck one. `bd ready` excludes blocked, deferred, hooked, and in-progress issues, and backlog-loop marks a failed batch's members `blocked`, so conditions 1 and 2 alone are both satisfied by a run in which every issue failed and nothing merged.

It is stated as a census result rather than as "no blocked issue carries a run marker" because the procedure deliberately leaves some blocked issues alone. A post-merge verification failure, or a cause that has reached its attempt ceiling, is work a person must pick up, and no later run may reopen it. A condition demanding that no such issue exist becomes unmeetable the first time one appears -- which would rebuild the trap this condition exists to close. The census separates the two: an issue the loop is responsible for is unfinished work, and an issue it is not responsible for is accounted for.

The census covers **every** marker, not only this run's. Every invocation picks a fresh run id, and blocked issues are neither ready nor in progress, so a restart after a failed run sees an empty ready list, nothing in progress, and no blocked issue bearing its own new id -- and would declare the backlog cleared over work the previous run failed to land.

In the final goal turn:
- Paste the output of `bd ready --json --exclude-type=epic`.
- Paste the relevant non-epic result from `bd list --status=in_progress --json`.
- Paste the census lines, one per non-closed non-epic issue.
- Paste the blocked issues carrying any run marker, not only this run's, each with its recorded cause.
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
