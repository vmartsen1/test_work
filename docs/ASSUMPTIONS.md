# Reports.v_Job — assumptions and open items

This pass was done with these inputs only:
- `docs/HANDOFF_SUMMARY.md` (summary from the previous chat session)
- `docs/UP_Data_Model_2907__copy.xlsx` (Job tab only — 145 rows)
- `sql/reference/TMFF_views.sql`, `sql/reference/OPS_views.sql` (current production view definitions)

**Not re-uploaded this session** (the handoff explicitly listed these as "files the user will
attach again"): `TMFF_OPS.sql` (raw DDL — the actual source-of-truth for column names/existence),
the previous `v_Job_views.sql` / `v_Job_views_ODS_only.sql` drafts, and `consignee_block_fix.sql`.
Because of that, `sql/views/v_Job.sql` (`Reports.v_Job`, one UNION ALL of a TMFF branch and an OPS
branch, one row per JOB/AWB) was written from scratch against the reference views + Excel + handoff
notes, not as a patch on top of the earlier draft. It started as two separate views
(`CALC.v_TMFF_Job` / `CALC.v_NORAMOPSDW_Job`), which the user then merged into one `Reports.v_Job`
and reworked (no more CTEs for single-use subqueries, only for the two genuinely reused pieces:
`cte_ShipmentId` and `cte_TEU`). Everything below is either directly confirmed by a real, working
reference view, or - where flagged - taken from the Excel mapping / handoff text without
independent DDL confirmation.

## Confirmed directly from the reference views (high confidence)

- TMFF: all of `ODS.TMFF_JOB` / `TMFF_JOBOTHER` fields used (CSGNADDR1-4, CSGNCTRYCODE,
  CSGNPOSTALCODE, CSGNSTATEPROV, CSGNONWBCITYNAME, SHPRADDR1-4 etc.) come straight from the
  handoff's own verified findings plus `v_TMFF_Shipment`'s actual (buggy-labeled) usage of the
  same source columns.
- TMFF: `ODS.TMFF_FMPARTY` (PARTYID, FULLNAME, UNID, SCD_UpdateDate) and `ODS.TMFF_FMPARTYADDR`
  (FMPARTY_UNID, ADDR1, POSTALCODE, CITYCODE, CTRYCODE) confirmed via `DW.v_TMFF_dim_Party`.
  ADDR2-4 specifically are not used by that view, but the ADDR1-4 pattern is confirmed
  independently via `ODS.TMFF_JOBPARTY` (used the same way in `v_TMFF_Shipment`'s
  `TMFF_JOBPARTY` CTE), so treated as safe.
- TMFF: `ODS.TMFF_FMCITY` (CITYCODE, CTRYCODE, Description, STATEPROV) confirmed via
  `DW.v_TMFF_dim_Party` — used for CustomerCity/CustomerState instead of a direct
  city/state column on FMPARTYADDR, matching that proven pattern.
- TMFF: `CALC.v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company` and `CALC.v_TMFF_JOBPARTY`
  (pivot) fully read and inlined per the handoff's own CALC-replacement table.
- TMFF: `ODS.TMFF_CONTAINER` (TEU, CONTTYPE), `ODS.TMFF_LOADUNIT` (UNITTYPE), `ODS.TMFF_SEA`
  (CTNQTY1-4, CTNTYPE1-4, ISPARTOF1-4, LOADTERM), `ODS.TMFF_ROAD` (VEHICLEQTY1-4, VEHICLETYPE1-4,
  LOADTERM) confirmed via `CALC.v_TMFF_AllItemsWithTEUAllocation` / `CALC.v_TMFF_AllItems`
  (the TEU-allocation logic those two views implement at item grain is reconstructed at job grain
  in `v_TMFF_Job`'s TEU CTEs).
- OPS: `ODS.NORAMOPSDW_tblAWB`, `tblMAWB`, `tblMAWBOcean`, `xrfMAWBAWB`, `tblAWBPieces`,
  `tblAWBCalcValues`, `tblAWBInternational`, `tblICO`, `lkpDepartment` (DeptName, TransportMode_BK,
  ImpExp), `lkpVendor` (VendorNo), `tblCustomer` (Address1-3, City, Country, Zip, State, CustName,
  CustNo) all confirmed via `CALC.v_NORAMOPSDW_Shipment` / `v_NORAMOPSDW_MAWB` / `v_NORAMOPSDW_MAWBOcean`
  / `v_NORAMOPSDW_AWB_SlavesAndMasters`.

## Taken from the Excel mapping as-is, NOT independently confirmed (verify against DDL)

| Field(s) | Assumed source | Why unconfirmed |
|---|---|---|
| TMFF ClosingDate | `ODS.TMFF_JOBINTFEXPDTL.STATUSDATE`, filter `REFNO1='OPSTATUS_CLOSE'` | This table isn't referenced anywhere in the supplied reference views. |
| TMFF FlightNumber | `ODS.TMFF_AIR.BY1FLTNO` | TMFF_AIR only appears in reference code via `SCD_UpdateDate`. |
| TMFF Master (MBLNO) | `ODS.TMFF_SEA.MBLNO` | Confirmed (used in `v_TMFF_Shipment`). |
| OPS ClosingDate | `ODS.NORAMOPSDW_tblAWBRecap.EntryDate` | Only `tblAWBRecap.WeekEnding` is confirmed elsewhere. |
| OPS CustomerID/Contact/Phone | `tblCustomer.SlsPsnID/Contact/Phone` | Not used in any reference view. `SlsPsnID` → CustomerID looks like it might actually be a **salesperson** ID, not a customer ID — worth a business sanity check regardless of DDL. |
| OPS Consignee/Shipper Name/Address/City/State/Zip/Country | `tblAWBConsignee` / `tblAWBShipper` | Only the `*ID` columns of these two tables (AwbConsigneeID/AwbShipperID) are used anywhere in the reference views; the Name/Address columns are taken from Excel verbatim. |
| OPS CarrierName | `lkpVendor.VendorName` | Only `VendorNo` is confirmed in reference code. |
| OPS VesselName/VoyageNo/FlightNumber/CarrierService/ETADate/PlDelv/PTLOAD | `ODS.NORAMOPSDW_tblMAWB` | Only MAWB/OriginCityCode/DestCityCode/DepartureDate/rowguid_CarrierVendor are confirmed via `CALC.v_NORAMOPSDW_MAWB`. |
| OPS PlAccept/PtLoad/PtDisch/PlDelv (name variants) | `ODS.NORAMOPSDW_tblMAWBOcean` | Only the `*Code` variants are confirmed via `CALC.v_NORAMOPSDW_MAWBOcean`; Excel lists both a name and a code column per field, matching the Code/Name pairing convention seen elsewhere in this system. |

## My own design decisions (flagged, not from the handoff)

- **TMFF `Master`**: Excel gives no logic for this field ("Multiple", no formula). Reused the
  `MasterCode` logic from `v_TMFF_Shipment` (SEA.MBLNO / CONSOLNO / JOBROUTE.MAWBNO, with a
  SHPTYPE='D' branch) since the field is semantically the same thing.
- **OPS `POD`/`POL`/`POR`/`Delivery`/`FinalDestination`**: Excel lists multiple candidate source
  columns per field with no stated priority. Reused the exact COALESCE hierarchy already used for
  the analogous Pre/Main/Post-transport location fields in `v_NORAMOPSDW_Shipment` (which
  prioritizes the dedicated Code columns), per the handoff's own guidance ("priorytet dla
  dedykowanych kodów PtDischCode/PtLoadCode"). The handoff already flagged its own version of this
  same hierarchy as "moja interpretacja, warto zweryfikować na danych" — same caveat applies here.
- **OPS date-scope filter**: `v_NORAMOPSDW_Shipment` re-checks the 2019-01-01 cutoff a second time,
  direction-aware (Import vs. other), which requires resolving country via `CALC.NORAMOPSDW_Location`.
  Not inlined here — only the direction-agnostic base filter is applied. Affects only rows right at
  the cutoff boundary.
- **TSP** and **TMFF CarrierName**: no source in Excel or the reference views on either system →
  left `NULL`, per the handoff's own note that no source was found.
- **TEU (TMFF)**: reconstructed at job grain from the real `CALC.v_TMFF_AllItemsWithTEUAllocation` /
  `CALC.v_TMFF_AllItems` logic (both fully confirmed, not the earlier `TMFF_SEA.TOTTEU` guess), via
  the `cte_SeaContainerItems`/`cte_Container`/`cte_SeaContainerTEU(ByJob)`,
  `cte_LoadUnitItems`/`cte_LoadUnit`/`cte_LoadUnitTEU(ByJob)`, `cte_SeaVirtualTEU` and
  `cte_RoadVirtualTEU` CTEs in the view. One deliberate simplification: a container/load unit shared
  across jobs (consolidations) has its TEU split by `CONTAINER_UNID`/`UNITUNID` alone, whereas the
  original also partitions by `Company_BK` (resolved through `CALC.TMFF_AllItems` →
  `CALC.TMFF_OwnerIdCompany`) - only matters if the same numeric container/load-unit id is reused
  across different companies, which seems unlikely for a physical container/unit key but wasn't
  verified.

## Not carried over from CALC (per handoff), plus one reintroduced on purpose

- `CALC.BiRef_AirLineMapping` (IATA→carrier fallback, TMFF `CarrierCode`) **was reintroduced by the
  user** in the merged `Reports.v_Job` (`left join CALC.BiRef_AirLineMapping airm ...`) - this is
  the one remaining CALC dependency in the view, flagged in-line with `-- should we remove that
  table??`. Pending a decision; everything else in the view stays ODS-only.
- `CALC.TMFF_OwnerIdCompany` is not reintroduced — the rare `ShipmentID` fallback branch uses
  `OWNERID` directly instead of a resolved `Company_BK`.
- `utilities.ufn_GetCleanGlobalShipmentId` / `utilities.ufn_GetHashedUID` are used unchanged as
  black boxes (schema `utilities`, not `CALC`).

## Cross-branch consistency note (only matters now that both systems are UNION ALL'd together)

- **`ModeOfTransport`**: TMFF yields `AIR`/`SEA`/`ROAD`/`COU`/`OTH` (or whatever free text sits in
  `JOBOTHER.TPTTYPE`, e.g. `Rail`) while OPS yields `Air`/`Sea`/`Surface`/`Warehouse`/`Other` (from
  `lkpDepartment.TransportMode_BK`) - different casing and partly different vocabulary. Not a bug
  under the database's default case-insensitive collation (`WHERE ModeOfTransport = 'Air'` matches
  `'AIR'` too), but worth knowing if this ever runs under a case-sensitive collation or gets
  consumed by something doing exact string matching outside SQL.
- **Slave-AWB exclusion** (`sam` derived table, OPS branch): inlined from
  `CALC.v_NORAMOPSDW_AWB_SlavesAndMasters` (COBI-7158 - NORAMOPSDW duplicates some AWB rows under a
  suffixed HWB, e.g. `12345-67890A` is a "slave" duplicate of master `12345-67890`). Without this
  join + the `sam.Slave_RowGuid_AWB is null` filter, the OPS branch returns duplicate rows for those
  AWBs. This is existing production logic, not something new - see the in-line comment at that join
  in `sql/views/v_Job.sql`.

## Performance pass (~20 min runtime for ~4M rows)

Two redundant full scans removed - both were "the same filtered pool of a big table, scanned twice
for a self-join" (the same anti-pattern, once per branch):

- **TMFF**: `cte_ShipmentId` used to scan `ODS.TMFF_JOB` a second time (with its own
  `utilities.ufn_GetCleanGlobalShipmentId` call per row) just to compute `GlobalShipmentId_BK`, then
  joined that back to the main query's own scan of the same table. Folded directly into the main
  query instead: the UDF call becomes an `OUTER APPLY` right after `from ODS.TMFF_JOB j`, and the
  `MIN`/`MAX`/`FIRST_VALUE` windows that used to live in `cte_ShipmentId` are now computed straight
  in the `ShipmentID` column of the final `SELECT` (window functions can reference any join/apply
  alias already in scope - they don't need their own CTE). `ODS.TMFF_JOB` is now read once, not
  twice, and the whole CTE is gone.
- **OPS**: the `sam` slave-AWB detection used a self-join (`slv` join `mst`) that scanned the
  filtered `TGOPSINTL` + HWB-pattern pool of `ODS.NORAMOPSDW_tblAWB` twice. Rewritten as a single
  scan: each row gets a `MasterKey` (its own HWB if master-shaped, or the HWB it would be a slave of
  if slave-shaped), then `MAX(...) OVER (PARTITION BY MasterKey)` checks whether a live master with
  that key exists anywhere in the pool - same result, one scan instead of two. Worth calling out:
  `HWB LIKE '[0-9][0-9]...'` (a character-class pattern) can't use an index seek in SQL Server, so
  every scan of this filtered pool was already a full scan - halving the scan count here is a real win.

**Most likely remaining dominant cost, not fixed here**: `utilities.ufn_GetCleanGlobalShipmentId`
(OPS `ShipmentID`) and `utilities.ufn_GetHashedUID` (`UniqueRecordKey`, both branches) are scalar
UDFs called once per *final output row* - at ~4M rows that's ~4-8M scalar function calls, and scalar
UDFs in SQL Server normally execute row-by-row with no parallelism (unless SQL Server 2019+'s Scalar
UDF Inlining kicks in, which requires database compatibility level ≥ 150 and a function body simple
enough to qualify - no cursors, no multiple statements with branching, etc.). Worth checking:
1. The database's compatibility level (`SELECT compatibility_level FROM sys.databases WHERE name = 'SGLBI'`).
2. Whether these two functions currently qualify for inlining - the query plan will show them as a
   separate "Scalar Function" / UDX operator with high cost if not inlined, versus disappearing into
   the plan if they are.
Since these are treated as black boxes here (no visibility into their bodies, and deliberately not
touched to avoid silently changing ID values), this can't be fixed from the view side - it would need
looking at the functions themselves.

## Bugs found and fixed in final review

- **TMFF branch had no row filter at all** on `ODS.TMFF_JOB` (no `WHERE` before the `union all`) -
  it would have returned every historical SCD version plus voided/deleted jobs. Added
  `where j.SCD_ActiveFlag = 1 and j.SCD_IsDeleted = 0 and j.VOIDDATE is null` back.
- **OPS branch's ICO active/deleted filter was on the wrong join** - `i.SCD_ActiveFlag = 1 and
  i.SCD_IsDeleted = 0` had ended up attached to the `vnd` (vendor) `LEFT JOIN`'s `ON` clause instead
  of the `i` (`tblICO`) join's own `ON` clause. Since `vnd` is a `LEFT JOIN`, that condition only
  affected whether vendor columns resolved - it did not actually exclude inactive/deleted ICOs from
  the result, unlike the original `v_NORAMOPSDW_Shipment`. Moved back onto `i`'s own join.
- Confirmed the OPS slave-AWB exclusion (`sam`, self-join subquery) is functionally identical to the
  original 4-CTE version it replaced: `row_number() over (partition by RowGuid_AWB order by ...)` is
  deterministic per physical row regardless of whether it's computed once over a shared pool (the
  original) or twice over two separately-filtered copies of the same pool (this version) - master and
  slave rows never share a `RowGuid_AWB`, so splitting before vs. after computing `ix` gives the same
  result either way.

## Scope filters adopted from InvoiceDetails.sql

The client-authored `sql/reference/InvoiceDetails.sql` (reviewed for the Shipment task) restricts its
TMFF branch to US-company jobs (`join ODS.TMFF_SYCOMPANY syc on syc.OWNERID = j.OWNERID and
syc.CTRYCODE = 'US'`) and its OPS branch to `NORAMOPSDW_tblAWB.LinkServer = 'TGOPSINTL'`. Neither filter
was previously applied in `Reports.v_Job` (the OPS slave-AWB-detection subquery already had the
`LinkServer` filter, but only inside that subquery, not on the main driving row). Added both filters -
TMFF: `join ODS.TMFF_SYCOMPANY syc on syc.OWNERID = j.OWNERID and syc.CTRYCODE = 'US'`; OPS: `LinkServer
= 'TGOPSINTL'` added to the main `ODS.NORAMOPSDW_tblAWB` driving subquery's `WHERE` - so `Reports.v_Job`
now scopes to the same US/TGOPSINTL population as invoicing. Same two filters were added to
`Reports.v_Shipment`'s `cte_Candidates` (see `docs/ASSUMPTIONS_Shipment.md`).

## Suggested next step

Re-upload `TMFF_OPS.sql` (or just the DDL for `TMFF_JOBINTFEXPDTL`, `NORAMOPSDW_tblAWBConsignee`,
`NORAMOPSDW_tblAWBShipper`, `NORAMOPSDW_tblAWBRecap`, `NORAMOPSDW_tblCustomer`, `NORAMOPSDW_tblMAWB`)
so the flagged column names above can be checked mechanically rather than by inference from Excel.
