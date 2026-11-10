Clear every actionable non-epic issue from the Beads tracker by following the codex-delegate procedure explicitly loaded immediately before this goal.

The loaded codex-delegate procedure is the sole execution authority for every cycle: Claude plans with ce-plan, Codex CLI implements through lfg up to an open pull request, and Claude reviews, fixes, merges, pulls, and closes the issues. This prompt adds no rule of its own. If it conflicts with that procedure, the procedure wins.

Success means all three:
1. `bd ready` offers no non-epic issue other than human gates (a `[HUMAN]` title, the `human-gate` label, or type `gate`).
2. No non-epic issue carrying `codex_delegate_branch` metadata remains `in_progress`: each one this loop claimed is closed after a verified `MERGED` pull request, reopened below the attempt ceiling and then cleared, or `blocked` at the ceiling with its recorded cause.
3. The local default branch equals its remote tip and the working tree is clean.

In the final goal turn:
- Paste the result of `bd ready --json` filtered to non-epic issues.
- Paste `bd list --status=in_progress --has-metadata-key codex_delegate_branch --json`.
- Paste every blocked issue carrying `codex_delegate_attempts`, each with its recorded cause.
- Paste `git status --short` and the default branch's local and remote SHAs.
- Produce the codex-delegate final report.

Never ask me for input. Take the recommended option and record every decision.

Do not stop the goal merely because one Codex run, one cycle, or one merge failed. Follow the procedure's retry and attempt rules, park only the issues that cannot complete, and continue every independent agent-executable issue.

Stop the goal early only when no agent-executable issue remains or trunk is red for a reason no cycle can fix. The final report must then name the human action, external owner, or unavailable capability required, and why it blocks every remaining issue.
