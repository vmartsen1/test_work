# Reports.v_Economy — Assumptions & Open Questions

Grain: **one row per (Job or AWB) + ChargeType + Currency + Creditor/Debtor** — in the
common case this is 2 rows per Job/Shipment (one COST, one REVENUE), which is what was
requested. It can exceed 2 rows when a single Job/AWB genuinely has more than one currency
or more than one counterparty on the same side (e.g. two different vendors billing cost in
different currencies) — that's correct, not a bug: summing FC amounts across different
currencies, or collapsing two different creditors into one code, would be wrong.

Structure: source-first at the *fine* grain first (one row per underlying charge line —
`TMFF_REVENUE`/`TMFF_COST` row, or `tblAWBInvoiceDetail`/`tblAWBCost` row), with every
lookup (`FMPARTY`, `FMCHARGECODE`/`FMCODE`, `lkpChargeCode`, `lkpCurrency`,
`tblCustomer`/`CALC.v_NORAMOPSDW_Party`) joined **at that fine grain** — every join key is
still a single value at this point, so lookups always match correctly. Only the outermost
`SELECT` aggregates up to the coarse grain, via `sum()` on the amount columns and
`string_agg()` on `ChargeCode`/`ChargeCodeDescription`/`ChargeCodeCategory` (a Job with
several distinct charge codes on the same side shows them comma-separated).

**Bug found and avoided**: an earlier draft pushed `string_agg` for `ChrgCode` into the
per-branch OPS subqueries (grouping before joining to `lkpChargeCode`), which meant
`lkpChargeCode` was joined against an already-concatenated string like `"FRT, THC"` —
that would silently return `NULL` for `ChargeCodeCategory` on any AWB with more than one
charge code. Fixed by keeping every lookup join at the fine grain and aggregating exactly
once, in the outermost `SELECT`, identically on both the TMFF and OPS branches (previously
OPS aggregated twice — once per union branch, once outer — which was both the bug's cause
and pure redundant work).

## Key design decisions

1. **TMFF source tables: `ODS.TMFF_REVENUE` / `ODS.TMFF_COST`, not `JCREVENUE`/`JCCOST`.**
   **CONFIRMED by user:** `JCREVENUE`/`JCCOST` is just another name for the same thing —
   `TMFF_REVENUE`/`TMFF_COST` are the real tables to build on.

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
   **CONFIRMED by user:** keep it exactly as in `InvoiceDetails.sql` for now.

4. **Creditor / Debtor resolution:**
   - TMFF: `FMPARTY.PARTYID`/`FULLNAME`, joined via `BILLING_PARTYID` (revenue→Debtor) /
     `PAYEE_PARTYID` (cost→Creditor), deduped `rn=1 order by SCD_UpdateDate desc` — same
     pattern as `custp` in `v_Shipment`.
   - OPS Debtor (revenue only): `tblAWBInvoice.rowguid_Customer → tblCustomer.CustNo/CustName`.
   - OPS Creditor (cost only): `tblAWBCost.rowguid_Vendor → tblShipmentParty.RowID →
     Party_BK → (latest active tblShipmentParty row for that Party_BK).AccountNo/NameFull`.
     This inlines `CALC.v_NORAMOPSDW_Party`'s own dedup logic directly on ODS tables — no
     `CALC.*` reference in the view — per your instruction that Reports views must not
     depend on CALC objects, only reuse their logic.
   **Open question:** the Excel spec says Creditor should come from `LU_VENDOR.VendorNo/
   VendorName` directly. `lkpVendor` (confirmed via `v_Shipment`'s carrier lookup) only
   has `rowguid_Vendor, VendorNo, VendorName` — no richer info than the tblShipmentParty
   path provides, and the production `v_NORAMOPSDW_dim_Party` view itself resolves AWBCost's
   creditor through `tblShipmentParty` rather than `lkpVendor`. I followed that established
   path — flag if you'd rather use `lkpVendor.VendorNo/VendorName` instead (simpler, but not
   how any existing production view resolves this).

9. **SCD filter must not sit on the intermediate hop of a two-table lookup chain** —
   confirmed as a real, live bug via actual sample output (AWB `01AA8A63-...`), not just a
   theoretical concern. Pattern: `tblAWBCost.rowguid_Vendor`/`tblAWBInvoiceDetail.rowguid_AWBInvoice`
   are FKs captured *at the time that cost/invoice-detail row was recorded* — they point at
   one specific historical row in `tblShipmentParty`/`tblAWBInvoice`. If that specific row has
   since been superseded by a newer SCD version (a very normal occurrence), it is no longer
   `SCD_ActiveFlag=1`. Filtering the *first* hop (`sp`/`ai`) by `SCD_ActiveFlag=1` at that
   point therefore silently drops the join entirely, well before we ever get a chance to
   re-resolve to the business key's current version — producing NULL Creditor/Debtor even
   though the party genuinely exists and is active under a different row. Confirmed correct
   by cross-checking `InvoiceDetails.sql`'s own `ivh` (`tblAWBInvoice`) join, which has **no**
   SCD filter at all — the filter only appears on the *final* lookup (`cust`). Fixed by
   removing the SCD filter from `sp` and `ai` (the intermediate hops); it stays only on the
   terminal lookups (`pty`'s inner dedup subquery, and `cust`).

   **Deliberate deviation from `InvoiceDetails.sql` for TMFF Debtor/Creditor:**
   `InvoiceDetails.sql` resolves TMFF Debtor from `TMFF_IVHDR.PARTYID_CUST`/`CUSTNAME` (the
   invoice *header*, already denormalized). I did **not** copy that here: `TMFF_IVHDR` only
   exists for charge lines that have already been invoiced (via `TMFF_IVDTL.SOURCEUNID/
   SOURCESNO`), so a not-yet-invoiced *estimated* line would get a null Debtor/Creditor if I
   used the invoice-header route. `BILLING_PARTYID`/`PAYEE_PARTYID` are populated directly on
   every `TMFF_REVENUE`/`TMFF_COST` row regardless of invoice status (confirmed via
   `CALC.v_TMFF_RecognitionEvents`, which reads them the same way in every branch), so FMPARTY
   via those columns covers the full grain. Flag if this reasoning is wrong.

5. **`ChargeCodeCategory`** sourced exactly as in your `InvoiceDetails.sql`: TMFF via
   `FMCHARGECODE.CATEGORYSVR → FMCODE.CODE (TYPE='CCT') → DESCRIPTION`; OPS via
   `lkpChargeCode.ReportsCategory`. Neither `CATEGORYSVR` nor `ReportsCategory` appears
   anywhere in the two bulk reference-view dumps, but since your own reference query
   already uses them successfully, I'm treating that as ground truth over the dumps.

6. **`ChargeCodeDescription` (TMFF) switched to `fmcc.CHRGDESC`** (the canonical
   `FMCHARGECODE` lookup value), matching `InvoiceDetails.sql` exactly — previously I was
   using the charge line's own inline `CHRGDESC` copy from `TMFF_REVENUE`/`TMFF_COST`.
   OPS `ChargeCodeDescription` stays as the line's own inline `ChrgDesc` (no lookup),
   matching `InvoiceDetails.sql`'s OPS half, which does *not* use a canonical lookup there.

7. **No credit-note sign flip on TMFF `AMTFC`/`AMTLC`/etc. — reverted.** An earlier version
   of this view added `Multiplier = case when DOCTYPE='CN' then -1 else 1 end` and applied it
   to every monetary column, copying `InvoiceDetails.sql`'s flip. That was wrong: I mis-read
   `CALC.v_TMFF_RecognitionEvents`. Re-checking it — `Multiplier` there is used **only** to
   compute `RECORDAMTLC = RECOGNITIONAMTLC * multiplier - Prev_RECOGNITIONAMTLC * prev_multiplier`
   (a recognition-period *delta*). Every branch of that view (base, changelog, actualized)
   passes `AMTLC`/`AMTFC`/`ACTUALAMTLC`/`ACTUALAMTFC`/`RECOGNITIONAMTLC` straight through
   **unmultiplied**. `InvoiceDetails.sql`'s flip applies to a different table pair
   (`TMFF_IVDTL`/`IVHDR`, the invoice layer) with its own sign convention — it doesn't follow
   that `TMFF_REVENUE`/`TMFF_COST` need the same treatment, and the reference view that
   actually reads those two tables confirms they don't. Reverted to plain passthrough of
   `AMTFC, AMTLC, ACTUALAMTBC, ACTUALAMTLC, ACTUALVATAMTLC, RECOGNITIONAMTLC`, no multiplier.

8. **Not ported over**: `InvoiceDetails.sql`'s two separate currency codes
   (`ChargelineCurrencyCode` vs `InvoiceCurrencyCode`) collapse to Economy's single
   `CurrencyCode`, since the Excel spec for Economy only asks for one currency field per
   row. Also noticed a likely bug in `InvoiceDetails.sql`'s OPS half while reviewing it:
   the `cuh` (header currency) join reads `on cu.rowguid_Currency = ivh.rowguid_Currency` —
   comparing the *line*-currency lookup's key to the header's raw guid, which looks like it
   should be `cuh.rowguid_Currency = ivh.rowguid_Currency`. Doesn't affect `v_Economy` (I
   only use the line-level currency), but flagging in case it matters elsewhere.

**`RecognitionAmountFC`** is computed at the *fine* grain (`RECOGNITIONAMTLC * (AMTFC /
nullif(AMTLC, 0))` per charge line, before aggregation) and then `sum()`'d — summing the
per-line ratios is correct; recomputing the ratio from already-summed `AMTFC`/`AMTLC`
totals would silently give a wrong number whenever lines in the same group have different
FX rates.

**Still open, not resolved**: your "monster" draft set `VATAmountFC = r.ACTUALVATAMTBC` /
`c.ACTUALVATAMTBC` for TMFF — the exact same source column already used for
`VATActualAmountFC`. I did **not** carry that over (kept `VATAmountFC` as `NULL`, unchanged
from before) since I can't tell whether that's the real "booked" FC-VAT column or a
copy-paste duplicate, and you answered "no preference" both times I asked. Still needs a
real answer: is there a distinct booked (non-actual) VAT-in-foreign-currency column on
`TMFF_REVENUE`/`TMFF_COST`, and if so what's it called?

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
