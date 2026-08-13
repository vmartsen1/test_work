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
  needed a `System_BK` column (`'TMFF'` / `'OPS'` - aligned to the same literal `Reports.v_Job` uses,
  after that view's own final revision moved away from `'NORAMOPSDW'`).
- **"First job" tie-break**: earliest `CreateDate`, with `JOB_UNID` as a deterministic secondary
  tie-break for same-timestamp rows.

**Clarification on "based on House"**: the dedup key isn't a change of business logic away from House -
the point is simply that `Reports.v_Job` is split by JOB, `Reports.v_Shipment` must be split by
*shipment*, and a shipment is, in practice, identified by its House number. For TMFF that's literally
`SHPNO`. For OPS, the view dedups by `ShipmentID` rather than raw `HWB` - `ShipmentID` is the same
canonicalized House/Master identifier (`ufn_GetCleanGlobalShipmentId` over
`HouseNoForGlobalShipment`/`MasterNoForGlobalShipment`, falling back to a per-AWB
`UniqueBookingIdentifier`) already used everywhere else in this codebase as *the* cross-system shipment
identifier, so using it as the OPS dedup key too keeps "unique shipment" consistent with what
`ShipmentID` already means elsewhere, rather than dedupping on the raw, unnormalized `HWB` string.

One consequence worth knowing: when both `HouseNoForGlobalShipment` and `MasterNoForGlobalShipment` are
null/invalid (short or non-numeric), `ShipmentID` falls back to `UniqueBookingIdentifier`, which embeds
`AWBID` and is therefore unique per physical AWB row - in that fallback tier, dedup is effectively a
no-op (each such row is its own "unique shipment"). This isn't a new risk introduced by choosing
`ShipmentID` over `HWB`: the earlier `HWB`-based dedup had the identical property (`COALESCE(HWB,
rowguid_AWB)` also falls back to a per-row-unique value when `HWB` is unusable). It's an inherent limit
of any dedup-by-fallback-key, not a bug - you can't group rows that don't share a usable key. The SQL
mechanics still guarantee the *output* itself is unique per `ShipmentID` (`ROW_NUMBER() OVER (PARTITION
BY ShipmentID ...) = 1` can never emit two rows with the same value) - what can vary is only how many
distinct groups a batch of AWBs collapses into upstream of that.

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
  deduplicated to the current SCD version per physical AWB (`rnv` - named distinctly from the outer
  dedup's `rn` to avoid a column-name collision once both are exposed on the same derived table), then
  joined to `tblICO` (its `ICOId` carried through so the detail portion never needs to rejoin `tblICO`)
  and `lkpDepartment` (`DeptName`/`TransportMode_BK` - a cheap dimension lookup, no window functions, so
  no reason not to have it live in the source and cover both `ShipmentID`'s needs and the `Department`/
  `ModeOfTransport` output fields at once). `ShipmentID` is computed here too, via `calc`/`precalc`,
  which needs the MAWB number - but *only* the MAWB number, not any of MAWB's other fields. So the
  source joins a **minimal** MAWB lookup (`mawmin`: just `rowguid_AWB`, `MAWB`) rather than the full
  11-column, `first_value()`-window-function-heavy MAWB derived table. The rest of MAWB's fields
  (vessel, voyage, flight, ports, dates, carrier service) are looked up a *second* time, by the same
  derived-table shape, but as a plain external detail join against the already-deduped winners - so that
  heavier lookup runs once per unique shipment, not once per candidate AWB. The OPS dedup itself ranks
  by `ShipmentID` rather than raw `HWB` (see "Clarification on 'based on House'" above) -
  `ROW_NUMBER() OVER (PARTITION BY ShipmentID ORDER BY EntryDate ASC, rowguid_AWB ASC) = 1`.

  This two-tier MAWB lookup (minimal inside the source, full as an external detail join) replaced an
  earlier version that pulled the *entire* rich MAWB derived table into the source just to get at its
  `MAWB` column - which meant every one of its `first_value()` columns, and the join fan-out to compute
  them, ran once per *candidate* AWB rather than once per *winning* shipment. Given `ShipmentID`
  unavoidably needs to run before the dedup can happen (it *is* the dedup key), the goal here isn't to
  avoid touching MAWB/department before dedup entirely - that's not possible - it's to make what runs
  pre-dedup as cheap as it can be, and defer everything that isn't strictly needed for the dedup key
  itself to post-dedup, same principle as the TMFF side.

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

**Bugs caught and fixed across the source-first rewrites** (mechanical review, not logic changes):
- An `iw` alias referenced in a `WHERE` clause that no longer existed after a rename to `i` - would have
  failed to compile ("invalid column name").
- An outer-scope alias (`a`) referenced inside a derived table where only its own inner alias (`x`) was
  in scope - `ORDER BY` clauses need to reference the alias actually visible at that nesting level.
- Column-name collisions from pulling MAWB-lookup columns into the TMFF/OPS sources without renaming
  them: `ETADate`, `DestCityCode`, `OriginCityCode` (and similar) exist as both a native `tblAWB` column
  and a same-named MAWB-lookup column: `SELECT a.*, ..., maw.ETADate, ...` produces two columns both
  named `ETADate`, which raises "ambiguous column name" the moment anything downstream references it
  unqualified - fixed by explicitly prefixing the MAWB-derived versions (`maw_ETADate`, etc.).
- A duplicate column (`SHPNO` listed twice) in the TMFF source's explicit column list, and a `rn`/`rnv`
  collision in the OPS source (the physical-SCD-version-pick window function and the outer House/
  ShipmentID dedup window function ended up with the same column name once both were exposed on the
  same derived table) - both are the same underlying lesson: give every window-function or lookup
  column that lands in the same projection a name that's unique across the whole projection, not just
  locally unique at the level it was computed.

(The `maw_*`-prefixed columns from that fix no longer exist in the current version - the follow-up pass
described above moved MAWB's detail fields back out of the source entirely, keeping only the minimal
`mawmin.MAWB` lookup pre-dedup, so there's nothing left to collide with.)

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
