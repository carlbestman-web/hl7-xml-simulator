# Healthcare Integration Workbench

Browser-only GitHub Pages tools for production-style healthcare integration triage.

## Included tools

- OCIS source-data completeness checks for ADT, ORM/RDE, DFT and ORU.
- ESB HL7-to-XML correlation, transformation, routing and timeout analysis.
- ActiveQ consumer, backlog, retry, dead-letter and broker analysis.
- SLB delivery, prerequisite, reference-data, invalid transaction and accepted-but-not-posted analysis.
- Separate DFT/HL7 to SLB XML simulator, preserving the repository's original conversion capability.

## Safety and limitations

- Processing occurs entirely in the browser.
- No backend, Node.js server, database connection or production interface is used.
- Use sanitized or formally approved test data only.
- Predictions are operational hypotheses and do not prove a production database commit.
- Requeue/replay must follow approved production procedures and duplicate-impact review.

## GitHub Pages

The site is deployed from `main` and the repository root:

`https://carlbestman-web.github.io/hl7-xml-simulator/`

GitHub Pages uses HTTPS on TCP 443. The application is static HTML, CSS and JavaScript.

## Workflow

1. Validate OCIS/source data.
2. Confirm eLink acceptance outside the tool.
3. Verify ESB receipt, transformation and routing.
4. Verify ActiveQ publication and consumption when applicable.
5. Verify SLB receipt, response and final business posting.

Do not proceed downstream until the previous checkpoint is confirmed.
