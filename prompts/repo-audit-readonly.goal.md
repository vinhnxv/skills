Audit this repository against every dimension and criterion in the repo-audit procedure loaded immediately before this goal, and save a standalone diagnostic report. The loaded procedure is the execution authority.

This diagnostic run reads source, may use read-only subagents, and writes only its report artifacts. It requires no Beads installation and makes no Beads calls or tracker changes. Do not fix findings or invoke a downstream workflow during this goal.

Success means:

1. The report uses `repo-audit-report/v1` at `docs/audits/YYYY-MM-DD-HHMM-<run-id>-audit.md` and records the audited commit plus any working-tree evidence snapshot.
2. Every roster criterion and dimension has its own coverage row, counts, verdict, and stated gap if uncovered.
3. Every confirmed, refuted, and unevaluable candidate has a stable ID, evidence, independent verification result, and redaction state sufficient for cross-model review.
4. The report states that the audit made no source fix or tracker write. It preserves sensitive detail only in a verified ignored path, if one exists.

In the final goal turn, provide the report path and VCS status, coverage summary, finding IDs with severity and verification status, and limitations. Recommend a next action and present the applicable post-report choices required by the procedure; wait for the user's selection. No recommendation alone authorizes fixing or ticket creation.
