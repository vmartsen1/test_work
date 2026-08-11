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

Column-by-column parity between the two UNION ALL branches was verified mechanically (72 output columns,
same names, same order on both sides) before committing.

## The only actual difference from v_Job

Two fields are renamed in this (newer) workbook vs. the one `v_Job.sql` was built from
(`UP_Data_Model_2907__copy.xlsx`): `Delivery` -> `DeliveryLocationCode`, `FinalDestination` ->
`FinalDestinationLocationCode`. Same source columns, just renamed output - applied that renaming here.

**Open question for the user**: the Job tab in this newer workbook already uses the same renamed
`DeliveryLocationCode`/`FinalDestinationLocationCode` names too. `v_Job.sql` currently still outputs
`Delivery`/`FinalDestination` (built from the older workbook). Worth deciding whether to rename those
two columns in `v_Job.sql` to match, for consistency between the two views.

## Reports.v_Shipment_Unique (new requirement, separate view)

Business requirement changed mid-task: `Reports.v_Shipment` should stay 1 row per JOB/AWB, but a
**separate** view should expose 1 row per *unique* shipment, deduplicated by House number - when
several JOB/AWB rows share a House, the one with the earliest `CreateDate` wins and all of its columns
are carried through as-is (representative-row pick, not aggregation across the group).

Two design decisions were confirmed with the user rather than assumed:
- **Dedup scope**: within each source system separately (TMFF `SHPNO` vs OPS `HWB` are two unrelated
  numbering schemes - a text coincidence between them should not merge two unrelated shipments). This
  needed a `System_BK` column (`'TMFF'` / `'NORAMOPSDW'`, same convention as the real
  `v_TMFF_Shipment`/`v_NORAMOPSDW_Shipment`) added to `v_Shipment.sql` itself, since it didn't
  previously expose which branch a row came from.
- **"First job" tie-break**: earliest `CreateDate`, with `JOB_UNID` as a deterministic secondary
  tie-break for same-timestamp rows.

Rows with a `NULL` House are not collapsed into each other - the partition key falls back to `JOB_UNID`
(always unique) for those, so a `NULL` House doesn't accidentally bucket unrelated shipments together
(the naive `PARTITION BY House` would have put every `NULL`-House row in one shared group, since
`ROW_NUMBER() OVER (PARTITION BY ...)` treats `NULL` as a single group like `GROUP BY` does).

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
