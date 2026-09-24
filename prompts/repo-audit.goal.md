Audit this repository against every dimension and criterion in the repo-audit procedure loaded immediately before this goal. The loaded procedure is the execution authority. Save the complete portable report before offering any follow-up action.

Success means:

1. The audit runs without requiring or calling Beads and makes no source-code or tracker changes.
2. Every roster criterion receives a coverage row and verdict; each dimension receives the derived roll-up. An uncovered criterion names the remaining gap. A clean coverage verdict is measured, not inferred from an absence of findings.
3. Every confirmed, refuted, and unevaluable candidate appears in the report with its stable finding ID, evidence snapshot, independent verification result, severity where applicable, and safe redaction state.
4. The `repo-audit-report/v1` report exists at `docs/audits/YYYY-MM-DD-HHMM-<run-id>-audit.md` and can be reviewed from a fresh Codex or Claude Code session without this transcript.
5. After report persistence, recommend one next action with a reason and offer only applicable choices: create Beads work if configured, fix all confirmed actionable findings, fix a chosen severity or ID subset, or stop with the report. Wait for the user's selection before any handoff.

In the final goal turn, provide the report path and VCS status, audited snapshot, coverage summary including uncovered criteria, finding IDs grouped by severity and verification status, redactions or limitations, and the recommended action. Preserve the report even when the user chooses to stop. The fixer and the separate source-to-beads skill own their respective follow-up work and must revalidate source claims against the current tree.
