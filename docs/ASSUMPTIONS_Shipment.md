# Reports.v_Shipment — assumptions and open items

`sql/views/v_Shipment.sql` was built from `docs/UP_Data_Model_1108.xlsx` (Shipment tab, 137 rows).

## Why this is a structural clone of Reports.v_Job

Compared the Shipment tab's 68 field names against the Job tab in the same workbook field-by-field:
zero difference either way. Same source entities/columns are listed for every field, and the wording on
the trickier ones matches too - e.g. CarrierCode's note ("COALESCE(JOB.CARRIERCODE, JOB.CARRIERID);
fallback IATA (Air) / MasterCode (Sea)") is close to verbatim what `v_Job.sql`'s CarrierCode expression
already does. So rather than re-deriving everything, `v_Shipment.sql` reuses `v_Job.sql`'s logic as-is:

- Consignee/Shipper via the JOB/JOBOTHER snapshot fields (TMFF), not FMPARTY - same fix as v_Job, for
  the same reason (see docs/HANDOFF_SUMMARY.md - v_TMFF_Shipment's mislabeled-column bug). Customer
  stays on FMPARTY/FMPARTYADDR (no snapshot exists for it).
- OPS Consignee/Shipper via tblAWBConsignee/tblAWBShipper directly.
- ShipmentID / TEU / OPS slave-AWB exclusion: identical window-function-based logic as v_Job (no
  self-joins, no CTE re-scanning the driving table - see v_Job's commit history for why).
- CALC.BiRef_AirLineMapping fallback for TMFF CarrierCode: kept, same open question as in v_Job
  ("should we remove that table??").
- Every join key / id column cast to varchar for the same UNID (numeric) vs rowguid_AWB
  (uniqueidentifier) reason as v_Job.

Column-by-column parity between the two UNION ALL branches was verified mechanically (70 output columns,
same names, same order on both sides) before committing.

## The only actual difference from v_Job

Two fields are renamed in this (newer) workbook vs. the one `v_Job.sql` was built from
(`UP_Data_Model_2907__copy.xlsx`): `Delivery` -> `DeliveryLocationCode`, `FinalDestination` ->
`FinalDestinationLocationCode`. Same source columns, just renamed output - applied that renaming here.

**Open question for the user**: the Job tab in this newer workbook already uses the same renamed
`DeliveryLocationCode`/`FinalDestinationLocationCode` names too. `v_Job.sql` currently still outputs
`Delivery`/`FinalDestination` (built from the older workbook). Worth deciding whether to rename those
two columns in `v_Job.sql` to match, for consistency between the two views.

## Unique-shipment dedup (merged into this same view)

Business requirement changed mid-task: `Reports.v_Shipment` should expose 1 row per *unique* shipment,
deduplicated by House number - when several JOB/AWB rows share a House, the one with the earliest
`CreateDate` wins and all of its columns are carried through as-is (representative-row pick, not
aggregation across the group).

This was first built as a second wrapper view (`Reports.v_Shipment_Unique`, selecting from
`Reports.v_Shipment`), then merged into one self-contained view (`cte_TEU` -> `cte_AllRows` -> outer
dedup), matching how `Reports.v_Job` is structured. It was then restructured again for performance (see
next section) - the dedup now happens *before* the detail joins instead of after.

Two design decisions were confirmed with the user rather than assumed:
- **Dedup scope**: within each source system separately (TMFF `SHPNO` vs OPS `HWB` are two unrelated
  numbering schemes - a text coincidence between them should not merge two unrelated shipments). This
  needed a `System_BK` column (`'TMFF'` / `'NORAMOPSDW'`, same convention as the real
  `v_TMFF_Shipment`/`v_NORAMOPSDW_Shipment`).
- **"First job" tie-break**: earliest `CreateDate`, with `JOB_UNID` as a deterministic secondary
  tie-break for same-timestamp rows.

Rows with a `NULL` House are not collapsed into each other - the partition key falls back to `JOB_UNID`
(always unique) for those, so a `NULL` House doesn't accidentally bucket unrelated shipments together
(the naive `PARTITION BY House` would have put every `NULL`-House row in one shared group, since
`ROW_NUMBER() OVER (PARTITION BY ...)` treats `NULL` as a single group like `GROUP BY` does).

## Source-first restructuring (performance and shape)

The original single-view shape built every output column for every JOB/AWB (the full detail-join
fan-out: `JOBOTHER`, the `FMPARTY`/`FMPARTYADDR` chain, `AIR`/`SEA`/`JOBROUTE`, `TEU` on TMFF; vendor,
pieces, consignee, customer, `tblMAWBOcean`/`tblMAWB`, department, shipper, etc. on OPS) and only *then*
deduplicated down to unique shipments - meaning most of that join work ran for rows that got thrown
away by the dedup a moment later. An intermediate version picked the winning `JOB_UNID` first via a
separate lookup derived table joined back onto a second scan of the driving table.

Per explicit direction, the view is now shaped source-first instead: each branch builds one SOURCE
derived table that already *is* the final grain for that system (1 row per unique shipment,
business-rule filters applied, `ShipmentID` attached where cheap to do so), and every detail join
(`JOBOTHER`, `FMPARTY` chain, `AIR`/`SEA`/`JOBROUTE`, `TEU`, vendor, pieces, consignee, customer, mawb,
department, shipper, ...) `LEFT JOIN`s onto that one source by `JOB_UNID`. Nothing is computed broadly
and then filtered or split apart afterwards - each source scans its driving table exactly once:
- **TMFF**: `ODS.TMFF_JOB` is scanned once, filtered to US-company jobs immediately (`JOIN
  ODS.TMFF_SYCOMPANY ... CTRYCODE = 'US'`) before anything else runs, deduplicated to 1 row per House
  (`SHPNO`) via `ROW_NUMBER() OVER (PARTITION BY COALESCE(SHPNO, OWNERID+UNID) ORDER BY CreateDate ASC,
  UNID ASC) = 1`, and `ShipmentID` is computed in the same source (see below) instead of a separate
  lookup joined back in afterwards.
- **OPS**: `ODS.NORAMOPSDW_tblAWB` is scanned once, filtered to `LinkServer = 'TGOPSINTL'` immediately,
  deduplicated to the current SCD version per physical AWB (`rnv`), then joined to `tblICO` (its `ICOId`
  carried through in the source so the detail portion never needs to rejoin `tblICO`) and the slave-AWB
  exclusion, then deduplicated to 1 row per House (`HWB`) the same way as TMFF. `ShipmentID` still needs
  the department/MAWB joins (`calc`/`precalc`), so it stays a detail-join field for OPS, same as before.

The dedup is scoped per source system by design anyway (TMFF `SHPNO` and OPS `HWB` are two unrelated
numbering schemes, and each source only ever contains its own system's rows), so there's no `System_BK`
in either ranking and no `UNION ALL` of the two systems' candidates anywhere - each source is entirely
self-contained.

**TMFF's `ShipmentID`**: it's a window function (`MIN`/`MAX`/`FIRST_VALUE`) partitioned by `GSHPID`
across every row sharing that group, to pick a canonical clean `SHPNO`. It turns out this can be
computed from the *same* rows the House-dedup already ranks, not the full undeduped population: the
House-dedup only ever discards *duplicate* rows sharing an identical `SHPNO` (never a distinct `SHPNO`
value - every `SHPNO` that appears keeps at least its earliest row), and `ShipmentID`'s GSHPID window
only cares about which *distinct* `clean_SHPNO` values exist within a group - a value it never loses by
running after the House-dedup instead of before. So `ShipmentID` now rides along in the TMFF source for
free, instead of a separate CTE/derived table scanning `TMFF_JOB` a second time.

This also fixed a real bug from the intermediate version: `ShipmentID`'s lookup there was missing the
`TMFF_SYCOMPANY` US-company filter entirely, so its `GSHPID` window ran over a broader (non-US-filtered)
population than the rest of the view - now that it's computed in the already-US-filtered source, that
gap is closed.

No named CTEs remain except `cte_TEU`, kept by explicit request even though it's referenced only once
(from the TMFF branch) - everything else (each branch's source, both slave-AWB-exclusion subqueries) is
an inline derived table at its one use site.

## Scope filters adopted from InvoiceDetails.sql

Same two filters as added to `Reports.v_Job` (see `docs/ASSUMPTIONS.md`), applied in the candidate pool
since they decide whether a row qualifies at all (same place the ICOID/slave-AWB filters already live):
- TMFF: `join ODS.TMFF_SYCOMPANY syc on syc.OWNERID = j.OWNERID and syc.CTRYCODE = 'US'` - restricts to
  US-company jobs.
- OPS: `LinkServer = 'TGOPSINTL'` added to the main `ODS.NORAMOPSDW_tblAWB` driving subquery's `WHERE`
  (the slave-AWB-detection subquery already had this filter, but only for itself, not for the main
  driving row).

## Not used for this task, but reviewed (per the user's request)

- `sql/reference/InvoiceDetails.sql` (uploaded alongside this task) - a client-authored view unioning
  TMFF (`ODS.TMFF_IVDTL`/`IVHDR`/`IVJOB`, filtered to `SOURCETYPE='JB'` and US-company `TMFF_SYCOMPANY`)
  and OPS (`ODS.NORAMOPSDW_tblAWBInvoiceDetail`/`tblAWBInvoice`) invoice line detail. Notable patterns,
  not yet used anywhere: `ChargeCodeCategory` resolved via `TMFF_FMCHARGECODE.CATEGORYSVR` ->
  `TMFF_FMCODE` (`TYPE='CCT'`) lookup; OPS `AmountChargelineCurrency` = `COALESCE(ForeignAmt, Amount)`;
  currency resolved via `lkpCurrency.rowguid_Currency`, filtered `LinkServer='TGOPSINTL'`.
- `UP_Data_Model_1108.xlsx`'s `InvoiceDetail` tab (34 rows) - not read in detail this pass; flagged here
  in case an Invoice/InvoiceDetail view is the next task, since the field list would likely map closely
  to `InvoiceDetails.sql` above.
