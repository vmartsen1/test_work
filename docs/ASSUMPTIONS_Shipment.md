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

## Pick-winners-first restructuring (performance)

The original single-view shape built every output column for every JOB/AWB (the full detail-join
fan-out: `JOBOTHER`, the `FMPARTY`/`FMPARTYADDR` chain, `AIR`/`SEA`/`JOBROUTE`, `TEU` on TMFF; vendor,
pieces, consignee, customer, `tblMAWBOcean`/`tblMAWB`, department, shipper, etc. on OPS) and only
*then* deduplicated down to unique shipments - meaning most of that join work ran for rows that got
thrown away by the dedup a moment later.

`v_Shipment.sql` now picks the winning `JOB_UNID` per unique shipment *first*, cheaply, and only runs
the detail joins for the winners:
- `cte_Candidates`: just `House`/`CreateDate`/`JOB_UNID`/`System_BK` - all sit directly on the driving
  row (`TMFF_JOB.SHPNO`/`CREATEDATE`/`UNID`, `tblAWB.HWB`/`EntryDate`/`rowguid_AWB`), plus whatever's
  needed to know a row qualifies at all (the ICOID business-rule filter and the slave-AWB exclusion on
  the OPS side - both moved here, so they now run once instead of once per detail join).
- `cte_Winners`: the same `ROW_NUMBER() OVER (PARTITION BY System_BK, COALESCE(House, JOB_UNID) ORDER BY
  CreateDate ASC, JOB_UNID ASC) = 1` dedup as before, but computed over the cheap candidate rows.
- The two detail branches (TMFF/OPS) `JOIN` onto `cte_Winners` on `System_BK` + `JOB_UNID`, so the full
  join fan-out only executes for the rows that actually survive to the output.

**One exception**: TMFF's `ShipmentID` is computed by a window function (`MIN`/`MAX`/`FIRST_VALUE`)
partitioned by `GSHPID` across *every* active `TMFF_JOB` row sharing that group, to pick a canonical
clean `SHPNO` value - not just the rows that happen to win the House-dedup. Restricting to winners before
computing it could hide a sibling row the window needs to see and change the result. So it's computed
once, up front, over the full active population in `cte_TMFF_ShipmentId` (same cost as before - this was
always the expensive part, per the earlier UDF/scalar-function performance work) and looked up by
`JOB_UNID` for the winners. OPS's `ShipmentID` has no such cross-row dependency (pure function of that
AWB's own joined fields), so it stays computed inline in the OPS detail branch.

Net effect: the detail join fan-out, and the non-seekable `LIKE`-based OPS slave-AWB scan, now run once
per unique shipment instead of once per underlying JOB/AWB.

## Scope filters adopted from InvoiceDetails.sql

Same two filters as added to `Reports.v_Job` (see `docs/ASSUMPTIONS.md`), applied in `cte_Candidates`
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
