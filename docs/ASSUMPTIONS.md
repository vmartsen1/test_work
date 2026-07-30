# v_TMFF_Job / v_NORAMOPSDW_Job — assumptions and open items

This pass was done with these inputs only:
- `docs/HANDOFF_SUMMARY.md` (summary from the previous chat session)
- `docs/UP_Data_Model_2907__copy.xlsx` (Job tab only — 145 rows)
- `sql/reference/TMFF_views.sql`, `sql/reference/OPS_views.sql` (current production view definitions)

**Not re-uploaded this session** (the handoff explicitly listed these as "files the user will
attach again"): `TMFF_OPS.sql` (raw DDL — the actual source-of-truth for column names/existence),
the previous `v_Job_views.sql` / `v_Job_views_ODS_only.sql` drafts, and `consignee_block_fix.sql`.
Because of that, `sql/views/v_TMFF_Job.sql` and `sql/views/v_NORAMOPSDW_Job.sql` were written from
scratch against the reference views + Excel + handoff notes, not as a patch on top of the earlier
draft. Everything below is either directly confirmed by a real, working reference view, or -
where flagged - taken from the Excel mapping / handoff text without independent DDL confirmation.

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

## Not carried over from CALC (per handoff, unchanged)

- `CALC.BiRef_AirLineMapping` (IATA→carrier fallback) is not reintroduced — `CarrierCode` can be
  `NULL` in the rare case there's no `CARRIERCODE`/`CARRIERID` (TMFF) or vendor match (OPS).
- `CALC.TMFF_OwnerIdCompany` is not reintroduced — the rare `ShipmentID` fallback branch uses
  `OWNERID` directly instead of a resolved `Company_BK`.
- `utilities.ufn_GetCleanGlobalShipmentId` / `utilities.ufn_GetHashedUID` are used unchanged as
  black boxes (schema `utilities`, not `CALC`).

## Suggested next step

Re-upload `TMFF_OPS.sql` (or just the DDL for `TMFF_JOBINTFEXPDTL`, `NORAMOPSDW_tblAWBConsignee`,
`NORAMOPSDW_tblAWBShipper`, `NORAMOPSDW_tblAWBRecap`, `NORAMOPSDW_tblCustomer`, `NORAMOPSDW_tblMAWB`)
so the flagged column names above can be checked mechanically rather than by inference from Excel.
