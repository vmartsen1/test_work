# Reports.v_Economy — Assumptions & Open Questions

Draft grain: **one row per revenue-or-cost charge line** (TMFF: `TMFF_REVENUE`/`TMFF_COST`
row; OPS: `tblAWBInvoiceDetail`/`tblAWBCost` row), unioned across the two systems.
Source-first pattern, same style as `v_Job`/`v_Shipment`: one filtered/joined derived
table per branch (already at the final grain — no fan-out risk here since neither
system's charge-line tables can multiply against their parent Job/AWB), then lookups
attached via `left join` afterward.

## Key design decisions

1. **TMFF source tables: `ODS.TMFF_REVENUE` / `ODS.TMFF_COST`, not `JCREVENUE`/`JCCOST`.**
   The Excel tab names `JCREVENUE`/`JCCOST` as the TMFF entities, but neither table has
   `RECOGNITIONAMTLC`, a party/counterparty column, or any VAT column anywhere in the
   reference view dump — they only carry `JOB_UNID, SNO, SOURCEUNID, SOURCESNO,
   SOURCETYPE, CHRGCODE, CHRGDESC, AMTFC, AMTLC, ACTUALAMTBC, ACTUALAMTLC, CURRCODE,
   ACTUALCURRCODE`, and are used in exactly one place (`v_TMFF_dim_File`) purely as a
   bridge to look up the latest recognition `CreateDate` for a Job.
   `ODS.TMFF_REVENUE`/`TMFF_COST` — the tables `CALC.v_TMFF_RecognitionEvents` itself is
   built from — carry every field Economy needs (`RECOGNITIONAMTLC`, `ACTUALVATAMTLC`,
   `BILLING_PARTYID`/`PAYEE_PARTYID`, `INVSTS`, `DOCTYPE`, plus the same amount columns).
   **Open question:** please confirm `TMFF_REVENUE`/`TMFF_COST` are in fact the real
   current-state charge-line tables (my working hypothesis is `JCREVENUE`/`JCCOST` are a
   legacy/alternate name for the same underlying source-system concept, or a narrower
   bridge table) — or point me to `JCREVENUE`/`JCCOST`'s real DDL if they're genuinely
   different and richer than what's in the reference dump.

2. **Row filter**: `SCD_ActiveFlag=1, SCD_IsDeleted=0, isnull(INVSTS,'') not in ('C','V')`
   on both `TMFF_REVENUE` and `TMFF_COST` — matches the "current state" (non-changelog)
   branches of `CALC.v_TMFF_RecognitionEvents`, which exclude voided/credited estimate
   lines the same way on both revenue and cost. Not applying the changelog/event-history
   machinery from that view since Economy's grain is "current charge line", not
   "recognition event over time".

3. **ShipmentID kept simple**, per your own `InvoiceDetails.sql` reference:
   TMFF = `JOB.GSHPID` (direct column), OPS = `LEFT(AWB.HWB, 11)`. This is *not* the
   fuller fallback chain (`HouseNoForGlobalShipment`/`MasterNoForGlobalShipment`/
   `UniqueBookingIdentifier`) built for `Reports.v_Shipment`.
   **Open question:** should Economy's `ShipmentID` align exactly with `v_Shipment`'s
   (so charge lines join cleanly to the Shipment dimension), or is the simple version
   (matching your already-built `InvoiceDetails.sql`) intentional here?

4. **Creditor / Debtor resolution:**
   - TMFF: `FMPARTY.PARTYID`/`FULLNAME`, joined via `BILLING_PARTYID` (revenue→Debtor) /
     `PAYEE_PARTYID` (cost→Creditor), deduped `rn=1 order by SCD_UpdateDate desc` — same
     pattern as `custp` in `v_Shipment`.
   - OPS Debtor (revenue only): `tblAWBInvoice.rowguid_Customer → tblCustomer.CustNo/CustName`.
   - OPS Creditor (cost only): `tblAWBCost.rowguid_Vendor → tblShipmentParty.RowID →
     Party_BK → CALC.v_NORAMOPSDW_Party.AccountNo/NameFull` — using the CALC-layer party
     resolution (as instructed, richer than a raw lookup) instead of `lkpVendor` directly.
   **Open question:** the Excel spec says Creditor should come from `LU_VENDOR.VendorNo/
   VendorName` directly. `lkpVendor` (confirmed via `v_Shipment`'s carrier lookup) only
   has `rowguid_Vendor, VendorNo, VendorName` — no richer info than `CALC.v_NORAMOPSDW_Party`
   provides, and the production `v_NORAMOPSDW_dim_Party` view itself resolves AWBCost's
   creditor through `tblShipmentParty`/`CALC` rather than `lkpVendor`. I followed that
   established path — flag if you'd rather I use `lkpVendor.VendorNo/VendorName` instead
   (simpler, but not how any existing production view resolves this).

5. **`ChargeCodeCategory`** sourced exactly as in your `InvoiceDetails.sql`: TMFF via
   `FMCHARGECODE.CATEGORYSVR → FMCODE.CODE (TYPE='CCT') → DESCRIPTION`; OPS via
   `lkpChargeCode.ReportsCategory`. Neither `CATEGORYSVR` nor `ReportsCategory` appears
   anywhere in the two bulk reference-view dumps, but since your own reference query
   already uses them successfully, I'm treating that as ground truth over the dumps.

## Fields with no confirmed source (nulled + commented inline in the view)

- **`VendorType`** — no column found anywhere (TMFF or OPS) for this.
- **`VATAmountFC` / `VATActualAmountFC`** (both systems) — only local-currency VAT columns
  are confirmed to exist anywhere (`TMFF.ACTUALVATAMTLC`, `OPS.TaxAndDutyAmountTransaction_BI`).
  No foreign-currency VAT column was found for either system.
- **OPS `VATAmountLC` on cost lines** — `tblAWBCost`'s real DDL (which you provided) has
  no VAT/tax column at all; only `tblAWBInvoiceDetail` (revenue) has
  `TaxAndDutyAmountTransaction_BI`.
- **OPS `ActualAmountFC`/`ActualAmountLC`** and **`RecognitionAmountFC`/`LC`** — OPS has no
  booked-vs-actual split or revenue-recognition concept in these tables (matches the
  Excel tab itself, which marks these OPS rows as not sourced).
- **`RecognitionVATAmountFC`/`LC`** — dropped entirely (not just nulled), since the Excel
  tab marks these as unsourced for both systems.

## Not yet reviewed by you

This is a first draft, same as the early rounds on `v_Job`/`v_Shipment` — please review
before I treat anything here as final.
