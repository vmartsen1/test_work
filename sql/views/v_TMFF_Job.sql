USE [SGLBI]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =====================================================================================================
-- View:    CALC.v_TMFF_Job
-- Purpose: 1 row = 1 JOB (ODS.TMFF_JOB), covering the "Job" tab of UP_Data_Model.
--          Built directly on ODS.* tables only (no CALC.* views), per the decision to stop
--          layering CALC shortcuts that could silently carry over simplifications/bugs.
--
-- Key corrections vs. the existing v_TMFF_Shipment pattern (see docs/HANDOFF_SUMMARY.md):
--   * Consignee/Shipper name+address come from the snapshot fields stored directly on
--     JOB/JOBOTHER (CSGNNAME/SHPRNAME, CSGNADDR1-4/SHPRADDR1-4, CSGNCTRYCODE/SHPRCTRYCODE,
--     CSGNPOSTALCODE/SHPRPOSTALCODE, CSGNSTATEPROV/SHPRSTATEPROV, CSGNONWBCITYNAME/SHPRCITYNAME).
--     v_TMFF_Shipment reads these same source columns but writes them into mislabeled output
--     columns (its "ADDR2/3/4" are actually PostalCode/City/Country) and never exposes
--     STATEPROV at all. This view uses the real columns directly, correctly labeled.
--   * Customer is the one party that has NO address snapshot on JOB/JOBOTHER, so it is the
--     only field group still resolved via ODS.TMFF_FMPARTY / ODS.TMFF_FMPARTYADDR (through
--     PARTYID_CUST, falling back on jobparty type CONTROLPARTY).
--   * ShipmentID (GlobalShipmentId_BK) reuses the SHPNO-cleaning + GSHPID-dedup logic that
--     lives in CALC.v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company, inlined below as a CTE.
--     The Company_BK fallback branch of that view (via CALC.TMFF_OwnerIdCompany) was dropped;
--     the rare fallback here uses OWNERID directly (see handoff item on CALC.TMFF_OwnerIdCompany).
--   * utilities.ufn_GetCleanGlobalShipmentId / utilities.ufn_GetHashedUID are treated as black
--     boxes (schema `utilities`, not CALC) and used as-is, unchanged.
--
-- Open items / assumptions that could NOT be verified against raw DDL this session
-- (TMFF_OPS.sql was not part of this upload batch - see docs/ASSUMPTIONS.md for the full list):
--   * CarrierName: no source column found on ODS.TMFF_JOB (only CARRIERCODE/CARRIERID) -> NULL.
--   * ClosingDate: ODS.TMFF_JOBINTFEXPDTL.STATUSDATE / REFNO1 = 'OPSTATUS_CLOSE' taken from the
--     Excel mapping as-is; this table isn't referenced anywhere in the existing reference views.
--   * TSP: Excel gives no source/logic for either system -> NULL.
--   * TEU: reconstructed from CALC.v_TMFF_AllItemsWithTEUAllocation's real allocation logic (see the
--     cte_*TEU* CTEs below), confirmed against that view's own definition. One simplification vs. the
--     original: a shared container/load unit's TEU is split across jobs by CONTAINER_UNID/UNITUNID alone;
--     the original also groups by Company_BK (via CALC.TMFF_AllItems/TMFF_OwnerIdCompany), which only
--     matters if the same numeric CONTAINER_UNID/UNITUNID is reused across different companies.
-- =====================================================================================================
CREATE view [CALC].[v_TMFF_Job]
as
with cte_JobClean as (
			select		  UNID
						, OWNERID
						, GSHPID
						, CREATEDATE
						, clean_SHPNO	=	case when replace(shpno.CleanRaw,'0','') = '' then null else shpno.CleanRaw end
			from		ODS.TMFF_JOB j
			outer apply	(select CleanRaw = utilities.ufn_GetCleanGlobalShipmentId(j.SHPNO)) shpno
			where		j.SCD_ActiveFlag = 1
			and			j.SCD_IsDeleted = 0
			and			j.VOIDDATE is null
),
cte_ShipmentId as ( --same GlobalShipmentId_BK logic as CALC.v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company, rewritten
					--as a single window-function pass instead of a self-join. The self-join version forced 3 scans
					--of ODS.TMFF_JOB and 2 scalar-UDF calls per row (scalar UDFs run row-by-row and block
					--parallelism, so with ~550k rows in TMFF_JOB that dominated the whole view's runtime); this
					--version does exactly 1 scan and 1 UDF call per row, and gives the same result: MinClean <>
					--MaxClean within a GSHPID group is equivalent to the original's "count(distinct clean_SHPNO) > 1"
					--(ambiguous group -> override with the group's cleanest value), while a non-ambiguous group
					--(or a lone job) still falls through to its own clean_SHPNO, exactly as before.
			select		  JOB_UNID				=	UNID
						, GlobalShipmentId_BK	=	cast(coalesce(
														case when MinClean <> MaxClean then BestClean end
													, clean_SHPNO
													, 'TMFF|' + OWNERID + '|' + cast(UNID as varchar)
													) as varchar(150))
			from		(
						select		  *
									, MinClean	=	min(clean_SHPNO) over (partition by GSHPID)
									, MaxClean	=	max(clean_SHPNO) over (partition by GSHPID)
									, BestClean	=	first_value(clean_SHPNO) over (partition by GSHPID order by case when clean_SHPNO is null then 999 else 1 end asc, CREATEDATE asc)
						from		cte_JobClean
						) x
),
cte_ClosingDate as (
			select		  JOB_UNID
						, ClosingDate	=	min(STATUSDATE)
			from		ODS.TMFF_JOBINTFEXPDTL
			where		REFNO1 = 'OPSTATUS_CLOSE'
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			group by	JOB_UNID
),
cte_JobParty as ( --inlined subset of CALC.TMFF_JOBPARTY pivot: only the party types this view needs
			select		  JOB_UNID
						, REALCSGN		=	max(case when PARTYTYPE = 'REALCSGN'		then PARTYID end)
						, CONTROLPARTY	=	max(case when PARTYTYPE = 'CONTROLPARTY'	then PARTYID end)
			from		ODS.TMFF_JOBPARTY
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			JOB_UNID is not null
			group by	JOB_UNID
),
cte_FMParty as (
			select		  *
						, rn	=	row_number() over (partition by PARTYID order by SCD_UpdateDate desc)
			from		ODS.TMFF_FMPARTY
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
),
cte_FMPartyAddr as (
			select		  *
						, rn	=	row_number() over (partition by FMPARTY_UNID order by SCD_UpdateDate desc)
			from		ODS.TMFF_FMPARTYADDR
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
),
cte_JobRoute as (
			select		  JOB_UNID
						, MAWBNO	=	max(MAWBNO)
			from		ODS.TMFF_JOBROUTE
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			MAWBNO is not null
			group by	JOB_UNID
),
-- TEU, reconstructed at job grain from CALC.v_TMFF_AllItemsWithTEUAllocation's item-level allocation logic,
-- instead of item-level CALC.TMFF_AllItems (which itself needs CALC.TMFF_Shipment for Company_BK/TransportMode_BK/
-- ShipmentType_BK). A physical container/load unit can be shared by several jobs (consolidations), so its TEU
-- is split across them by cargo-volume share (falling back to an even split by item count when volume is 0/null,
-- same fallback the original uses) - that's cte_SeaContainerTEU / cte_LoadUnitTEU below. On top of that, TMFF_SEA
-- and TMFF_ROAD can imply containers/vehicles that never got a real SEACONTITEM/LOADUNITITEM row yet - those are
-- cte_SeaVirtualTEU / cte_RoadVirtualTEU, using CTNQTY1-4/CTNTYPE1-4/ISPARTOF1-4 and VEHICLEQTY1-4/VEHICLETYPE1-4
-- directly (only when the job doesn't already have real container/load-unit rows, same as the original's
-- "left join ... where ...JOB_UNID is null" exclusion). The ROAD branch's original eligibility check
-- (s.TransportMode_BK='Rail' and s.ShipmentType_BK='FCL', both CALC.v_TMFF_Shipment-derived) reduces to
-- jo.TPTTYPE='Rail' and road.LOADTERM='FTL' (with SERVICELEVEL not 'BCN') once you trace through
-- v_TMFF_Shipment's own TransportMode_BK/ShipmentType_BK CASE expressions for a road-sourced job.
cte_SeaContainerItems as (
			select		  JOB_UNID			=	sci.JOB_UNID
						, CONTAINER_UNID	=	sci.CONTAINER_UNID
						, ItemVolume		=	sum(sci.TOTVOL)
			from		ODS.TMFF_SEACONTITEM sci
			where		sci.SCD_ActiveFlag = 1
			and			sci.SCD_IsDeleted = 0
			group by	sci.JOB_UNID, sci.CONTAINER_UNID
),
cte_Container as (
			select		  UNID
						, CalculatedTEU	=	case	when TEU is not null then cast(TEU as decimal(19,2))
												when CONTTYPE like '%10%' then 0.50
												when CONTTYPE like '%20%' then 1.00
												when CONTTYPE like '%40%' then 2.00
												when CONTTYPE like '%45%' then 2.25
												else 0
											end
			from		ODS.TMFF_CONTAINER
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
),
cte_SeaContainerTEU as ( --row-level AllocatedTEU per (JOB_UNID, CONTAINER_UNID); needs its own step because
						 --the window functions below must see the un-grouped rows, before cte_SeaContainerTEUByJob's GROUP BY
			select		  sci.JOB_UNID
						, AllocatedTEU	=	coalesce(
												sci.ItemVolume / nullif(sum(sci.ItemVolume) over (partition by sci.CONTAINER_UNID), 0) * cnt.CalculatedTEU
											, 1.0 / nullif(count(*) over (partition by sci.CONTAINER_UNID), 0) * cnt.CalculatedTEU
											)
			from		cte_SeaContainerItems sci
			join		cte_Container cnt
			on			cnt.UNID = sci.CONTAINER_UNID
),
cte_SeaContainerTEUByJob as (
			select		  JOB_UNID
						, TEU	=	sum(AllocatedTEU)
			from		cte_SeaContainerTEU
			group by	JOB_UNID
),
cte_LoadUnitItems as (
			select		  JOB_UNID	=	lui.JOB_UNID
						, UNITUNID	=	lui.UNITUNID
						, ItemVolume	=	sum(lui.TOTVOL)
			from		ODS.TMFF_LOADUNITITEM lui
			where		lui.SCD_ActiveFlag = 1
			and			lui.SCD_IsDeleted = 0
			and			lui.JOB_UNID is not null
			group by	lui.JOB_UNID, lui.UNITUNID
),
cte_LoadUnit as (
			select		  UNID
						, CalculatedTEU	=	case	when UNITTYPE like '%10%' then 0.50
												when UNITTYPE like '%20%' then 1.00
												when UNITTYPE like '%40%' then 2.00
												when UNITTYPE like '%45%' then 2.25
											end	--no ELSE here, matching the original (unlike containers, an unrecognized UNITTYPE yields NULL, not 0)
			from		ODS.TMFF_LOADUNIT
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
),
cte_LoadUnitTEU as ( --row-level AllocatedTEU per (JOB_UNID, UNITUNID); same reason as cte_SeaContainerTEU above
			select		  lui.JOB_UNID
						, AllocatedTEU	=	coalesce(
												lui.ItemVolume / nullif(sum(lui.ItemVolume) over (partition by lui.UNITUNID), 0) * lu.CalculatedTEU
											, 1.0 / nullif(count(*) over (partition by lui.UNITUNID), 0) * lu.CalculatedTEU
											)
			from		cte_LoadUnitItems lui
			join		cte_LoadUnit lu
			on			lu.UNID = lui.UNITUNID
),
cte_LoadUnitTEUByJob as (
			select		  JOB_UNID
						, TEU	=	sum(AllocatedTEU)
			from		cte_LoadUnitTEU
			group by	JOB_UNID
),
cte_SeaVirtualTEU as (
			select		  JOB_UNID	=	sea.JOB_UNID
						, TEU		=	sum(v.qty * case	when v.typ like '%10%' then 0.50
														when v.typ like '%20%' then 1.00
														when v.typ like '%40%' then 2.00
														when v.typ like '%45%' then 2.25
														else 0
													end)
			from		ODS.TMFF_SEA sea
			cross apply	(values	  (sea.CTNQTY1, sea.CTNTYPE1, sea.ISPARTOF1)
									, (sea.CTNQTY2, sea.CTNTYPE2, sea.ISPARTOF2)
									, (sea.CTNQTY3, sea.CTNTYPE3, sea.ISPARTOF3)
									, (sea.CTNQTY4, sea.CTNTYPE4, sea.ISPARTOF4)
						) v(qty, typ, ispart)
			left join	(select distinct JOB_UNID from ODS.TMFF_SEACONTITEM where SCD_ActiveFlag = 1 and SCD_IsDeleted = 0) sci
			on			sci.JOB_UNID = sea.JOB_UNID
			where		sea.SCD_ActiveFlag = 1
			and			sea.SCD_IsDeleted = 0
			and			coalesce(sea.CTNQTY1, sea.CTNQTY2, sea.CTNQTY3, sea.CTNQTY4) > 0
			and			sea.LOADTERM in ('FCL','CONS')
			and			sci.JOB_UNID is null	--exclude jobs that already have real SEACONTITEM rows (those are covered by cte_SeaContainerTEUByJob)
			and			v.qty > 0
			and			v.ispart = 0
			group by	sea.JOB_UNID
),
cte_RoadVirtualTEU as (
			select		  JOB_UNID	=	road.JOB_UNID
						, TEU		=	sum(v.qty * case	when v.typ like '%10%' then 0.50
														when v.typ like '%20%' then 1.00
														when v.typ like '%40%' then 2.00
														when v.typ like '%45%' then 2.25
														else 0
													end)
			from		ODS.TMFF_ROAD road
			join		ODS.TMFF_JOBOTHER jo
			on			jo.JOB_UNID = road.JOB_UNID
			and			jo.SCD_ActiveFlag = 1
			and			jo.SCD_IsDeleted = 0
			cross apply	(values	  (road.VEHICLEQTY1, road.VEHICLETYPE1)
									, (road.VEHICLEQTY2, road.VEHICLETYPE2)
									, (road.VEHICLEQTY3, road.VEHICLETYPE3)
									, (road.VEHICLEQTY4, road.VEHICLETYPE4)
						) v(qty, typ)
			left join	(select distinct JOB_UNID from ODS.TMFF_LOADUNITITEM where SCD_ActiveFlag = 1 and SCD_IsDeleted = 0) lui
			on			lui.JOB_UNID = road.JOB_UNID
			where		road.SCD_ActiveFlag = 1
			and			road.SCD_IsDeleted = 0
			and			coalesce(road.VEHICLEQTY1, road.VEHICLEQTY2, road.VEHICLEQTY3, road.VEHICLEQTY4) > 0
			and			jo.TPTTYPE = 'Rail'
			and			isnull(jo.SERVICELEVEL,'') <> 'BCN'
			and			road.LOADTERM = 'FTL'
			and			lui.JOB_UNID is null	--exclude jobs that already have real LOADUNITITEM rows (those are covered by cte_LoadUnitTEUByJob)
			and			v.qty > 0
			group by	road.JOB_UNID
)
select		  JOB_UNID					=	j.UNID
			, Branch					=	cast(j.OWNERID													as varchar(50))
			, CarrierCode				=	cast(coalesce(j.CARRIERCODE, j.CARRIERID)						as varchar(50))
			, CarrierName				=	cast(null														as varchar(100))	--no source found on ODS.TMFF_JOB
			, ChargeableWeight			=	isnull(j.TOTCWGT,0)
			, ClosingDate				=	cd.ClosingDate
			, ConsigneeID				=	cast(coalesce(jp.REALCSGN, jo.PARTYID_CSGNONWB, j.PARTYID_CSGN)	as varchar(50))
			, ConsigneeName				=	cast(coalesce(j.CSGNNAME, jo.CSGNNAMEONWB)						as varchar(100))
			, ConsigneeAddress1			=	cast(jo.CSGNADDR1												as varchar(50))
			, ConsigneeAddress2			=	cast(jo.CSGNADDR2												as varchar(50))
			, ConsigneeAddress3			=	cast(jo.CSGNADDR3												as varchar(50))
			, ConsigneeAddress4			=	cast(jo.CSGNADDR4												as varchar(50))
			, ConsigneeCity				=	cast(jo.CSGNONWBCITYNAME										as varchar(50))
			, ConsigneeState			=	cast(jo.CSGNSTATEPROV											as varchar(50))
			, ConsigneePostalCode		=	cast(jo.CSGNPOSTALCODE											as varchar(50))
			, ConsigneeCountryCode		=	cast(jo.CSGNCTRYCODE											as varchar(50))
			, CustomerID				=	cast(coalesce(jp.CONTROLPARTY, j.PARTYID_CUST)					as varchar(50))
			, CustomerName				=	cast(custp.FULLNAME											as varchar(150))
			, CustomerCode				=	cast(null														as varchar(50))		--no TMFF source (Excel: none)
			, CustomerContact			=	cast(null														as varchar(50))		--no TMFF source (Excel: none)
			, CustomerPhone				=	cast(null														as varchar(50))		--no TMFF source (Excel: none)
			, CustomerAddress1			=	cast(custpa.ADDR1												as varchar(100))
			, CustomerAddress2			=	cast(custpa.ADDR2												as varchar(100))
			, CustomerAddress3			=	cast(custpa.ADDR3												as varchar(100))
			, CustomerAddress4			=	cast(custpa.ADDR4												as varchar(100))
			, CustomerCity				=	cast(custci.[Description]										as varchar(50))
			, CustomerState				=	cast(custci.STATEPROV											as varchar(50))
			, CustomerPostalCode		=	cast(custpa.POSTALCODE											as varchar(50))
			, CustomerCountryCode		=	cast(custpa.CTRYCODE											as varchar(50))
			, CreateDate				=	j.CREATEDATE
			, Delivery					=	cast(j.DEVRYCTRY + j.DEVRYCITY									as varchar(50))
			, Department				=	cast(jo.BIZSCOPE												as varchar(50))
			, FinalDestination			=	cast(j.DESTCTRY + j.DESTCITY									as varchar(50))
			, FinalDestinationDate		=	j.FINALDESTETADATE
			, FlightNumber				=	cast(air.BY1FLTNO												as varchar(50))
			, FreightDescription		=	cast(jo.COMMLOCALDESC											as varchar(500))
			, House						=	cast(j.SHPNO													as varchar(50))
			, JobNo						=	cast(j.JOBNO													as varchar(50))
			, Master					=	cast(mc.MasterCode												as varchar(50))
			, ModeOfTransport			=	cast(j.BIZTYPE													as varchar(50))
			, Pieces					=	j.TOTPCS
			, POD						=	cast(j.PODCTRY + j.PODCITY										as varchar(50))
			, PODETADate				=	j.PODETADATE
			, POL						=	cast(j.POLCTRY + j.POLCITY										as varchar(50))
			, POLETDDate				=	j.POLETDDATE
			, POR						=	cast(j.PORCTRY + j.PORCITY										as varchar(50))
			, PORETDDate				=	j.PORETDDATE
			, ServiceLevel				=	cast(jo.SERVICELEVEL											as varchar(50))
			, ServiceType				=	cast(jo.SERVICETYPE											as varchar(50))
			, ShipmentID				=	cast(sid.GlobalShipmentId_BK									as varchar(150))
			, ShipperID					=	cast(j.PARTYID_SHPR												as varchar(50))
			, ShipperName				=	cast(j.SHPRNAME													as varchar(100))
			, ShipperAddress1			=	cast(jo.SHPRADDR1												as varchar(50))
			, ShipperAddress2			=	cast(jo.SHPRADDR2												as varchar(50))
			, ShipperAddress3			=	cast(jo.SHPRADDR3												as varchar(50))
			, ShipperAddress4			=	cast(jo.SHPRADDR4												as varchar(50))
			, ShipperCity				=	cast(jo.SHPRCITYNAME											as varchar(50))
			, ShipperState				=	cast(jo.SHPRSTATEPROV											as varchar(50))
			, ShipperPostalCode			=	cast(jo.SHPRPOSTALCODE											as varchar(50))
			, ShipperCountryCode		=	cast(jo.SHPRCTRYCODE											as varchar(50))
			, TEU						=	isnull(cntTEU.TEU,0) + isnull(luTEU.TEU,0) + isnull(seaV.TEU,0) + isnull(roadV.TEU,0)
			, TSP						=	cast(null														as varchar(50))		--Excel gives no source/logic for TSP
			, VesselName				=	cast(mo.VESSELNAME												as varchar(50))
			, VIA						=	cast(j.VIACTRY + j.VIACITY										as varchar(50))
			, Volume					=	j.TOTVOL
			, VoyageNo					=	cast(mo.VOYAGE													as varchar(50))
			, Weight					=	j.TOTGWGT
			, Weight_UT					=	cast(j.TOTGWGT_UT												as varchar(50))
			, UniqueRecordKey			=	utilities.ufn_GetHashedUID('TMFF', cast(j.UNID as varchar), default, default, default)
			, DataAgeHOT				=	jo.SCD_UpdateDate
			, DataAgeCOLD				=	(select max(v) from (values (j.SCD_UpdateDate), (jo.SCD_UpdateDate), (custp.SCD_UpdateDate), (custpa.SCD_UpdateDate)) x(v))
			, RecordChangeDateTime		=	getdate()
from		ODS.TMFF_JOB j
join		ODS.TMFF_JOBOTHER jo
on			jo.JOB_UNID = j.UNID
and			jo.SCD_ActiveFlag = 1
and			jo.SCD_IsDeleted = 0
left join	cte_JobParty jp
on			jp.JOB_UNID = j.UNID
left join	cte_ClosingDate cd
on			cd.JOB_UNID = j.UNID
left join	cte_ShipmentId sid
on			sid.JOB_UNID = j.UNID
left join	cte_FMParty custp
on			custp.PARTYID = coalesce(jp.CONTROLPARTY, j.PARTYID_CUST)
and			custp.rn = 1
left join	cte_FMPartyAddr custpa
on			custpa.FMPARTY_UNID = custp.UNID
and			custpa.rn = 1
left join	ODS.TMFF_FMCITY custci
on			custci.CITYCODE = custpa.CITYCODE
and			custci.CTRYCODE = custpa.CTRYCODE
and			custci.SCD_ActiveFlag = 1
and			custci.SCD_IsDeleted = 0
left join	ODS.TMFF_AIR air
on			air.JOB_UNID = j.UNID
and			air.SCD_ActiveFlag = 1
and			air.SCD_IsDeleted = 0
left join	ODS.TMFF_SEA sea
on			sea.JOB_UNID = j.UNID
and			sea.SCD_ActiveFlag = 1
and			sea.SCD_IsDeleted = 0
left join	ODS.TMFF_VEWMOTHERVESSEL mo
on			mo.JOBUNID = j.UNID
and			mo.SCD_ActiveFlag = 1
and			mo.SCD_IsDeleted = 0
left join	cte_JobRoute jro
on			jro.JOB_UNID = j.UNID
left join	cte_SeaContainerTEUByJob cntTEU
on			cntTEU.JOB_UNID = j.UNID
left join	cte_LoadUnitTEUByJob luTEU
on			luTEU.JOB_UNID = j.UNID
left join	cte_SeaVirtualTEU seaV
on			seaV.JOB_UNID = j.UNID
left join	cte_RoadVirtualTEU roadV
on			roadV.JOB_UNID = j.UNID
outer apply	(
			select		MasterCode	=	case	when j.SHPTYPE = 'D'
												then coalesce(sea.MBLNO, j.SHPNO)
												else coalesce(sea.MBLNO, j.CONSOLNO, jro.MAWBNO)
										end
			) mc
where		j.SCD_ActiveFlag = 1
and			j.SCD_IsDeleted = 0
and			j.VOIDDATE is null
GO
