# HL7 + DataWeave Troubleshooting Analyzer v2

Static GitHub Pages tool for tracing HL7 values through six selected MuleSoft DataWeave mappings:

- `patientTransferMapping.dwl` — ADT transfer/location processing
- `billingNewOrderMapping.dwl` — ORM new order (`ORC-1=NW`)
- `officialResultMapping.dwl` — ORU official result
- `finalChargesMapping.dwl` — DFT final charges
- `billingAdjustedOrderMapping.dwl` — ORM adjustment (`ORC-1=XO`)
- `billingCancelOrderMapping.dwl` — ORM cancellation (`ORC-1=CA`)

## What changed from the old simulator

The old browser simulator manually transformed a few HL7 fields. This version is mapping-aware: it identifies the relevant `.dwl`, traces source fields to DataWeave variables/output fields, reconstructs key expected values, and produces findings tied to the actual mapping logic.

## GitHub Pages

Upload the contents of this folder to a repository root and enable GitHub Pages from the `main` branch/root folder. No server is required.

## Important limitation

This is not a DataWeave runtime. It reproduces mapping rules that can be derived from the supplied `.dwl` files in browser JavaScript. Mule variables such as `vars.serviceCode`, prerequisite/reference API responses, cache contents, private environment properties, and SLB database state cannot be reconstructed from HL7 alone. The tool explicitly marks these as context-dependent instead of guessing.

Use synthetic or approved test HL7 only.
