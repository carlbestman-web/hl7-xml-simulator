# Healthcare Integration Workbench

Browser-only GitHub Pages tools for production-style healthcare integration triage.

## Included tools

- Combined OCIS source validation, deduplicated multi-message ADT timeline reconstruction, and eLink checkpoint analysis. It detects missing encounter transitions such as A06 between outpatient/emergency and inpatient states, requires only the HL7 set and latest component, and accepts status/error metrics as optional evidence.
- ESB HL7-to-XML correlation, transformation, routing and timeout analysis.
- ActiveQ consumer, backlog, retry, dead-letter and broker analysis.
- Dependency-guided SLB investigation that stops at the first failed ADT → ORM/RDE → DFT → ORU prerequisite, generates targeted Oracle queries, interprets pasted results, and provides safe replay guidance.
- Phase 4.1 Stage 2.1 interactive test runner for OCIS Cloud → eLink → Mule SIT2 → SLB SIT. It includes realistic happy-path, missing-ADT, cart/missing-DFT, encounter-context mismatch and duplicate scenarios; classifies the first failed dependency; generates SIT Oracle queries; and exports locally saved execution records to CSV.
- ORM/RDE + DFT to SLB charge XML simulator, including multiple FT1 charge rows and confirmed Generic Supplies Scenarios 4, 7 and 11.
- Scenario-specific proposed ZOR mapping sourced from the related ORM OBX fields.

## Generic Supplies XML logic

The DFT is the primary source of charge fields (`FT1-6`, `FT1-7`, `FT1-10`, the FT1 order reference, `MSH-3`, and `MSH-10`). Every FT1 produces a separate charge element. A related ORM supplies proposed ZOR values through Generic Supplies OBX identifiers; an RDE is accepted for medication-charge correlation.

- Scenario 4: `ZOR|compoundOrderId`
- Scenario 7: `ZOR|item|quantity`
- Scenario 11: `ZOR|item|quantity|turnInType|compoundOrderId|itemCode`

The tool verifies Visit Number and Order correlation before producing XML. Detection is automatic and backward-compatible. RDE/pharmacy and non-GENITEM transactions remain existing/default. For correlated ORM GENITEM: turn-in data selects Scenario 11; otherwise a populated `CHRG_SLB_COMPOUND_ID` selects Scenario 4; otherwise ORM `CHRG_Quantity > 1` selects Scenario 7; all other transactions remain existing/default. The enhancement mapping must be approved in the interface specification before production implementation.

## Safety and limitations

- Processing occurs entirely in the browser.
- No backend, Node.js server, database connection or production interface is used.
- Use sanitized or formally approved test data only.
- Predictions are operational hypotheses and do not prove a production database commit.
- Requeue/replay must follow approved production procedures and duplicate-impact review.
- Stage 2.1 evidence and saved test executions stay in the current browser (`localStorage`). The runner does not call OCIS, eLink, Mule, ActiveQ, SLB or Oracle directly.

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
