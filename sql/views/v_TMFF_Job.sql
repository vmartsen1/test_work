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
--   * TEU: only ODS.TMFF_SEA.TOTTEU is used; road-shipment TEU (LOADUNITITEM/LOADUNIT) is out of
--     scope per the Excel comment and not computed here.
-- =====================================================================================================
CREATE view [CALC].[v_TMFF_Job]
as
with cte_JobClean as (
			select		  *
						, clean_SHPNO	=	case
											when replace(utilities.ufn_GetCleanGlobalShipmentId(SHPNO),'0','') = '' then null
											else utilities.ufn_GetCleanGlobalShipmentId(SHPNO)
											end
			from		ODS.TMFF_JOB
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			VOIDDATE is null
),
cte_ShipmentId as ( --inlined from CALC.v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company (GlobalShipmentId_BK only)
			select		  JOB_UNID			=	jc.UNID
						, GlobalShipmentId_BK	=	cast(coalesce(gsid.clean_SHPNO, jc.clean_SHPNO, 'TMFF|' + jc.OWNERID + '|' + cast(jc.UNID as varchar)) as varchar(150))
			from		cte_JobClean jc
			left join	(
						select		  gsid.GSHPID
									, clean_SHPNO
									, ix			=	row_number() over (partition by gsid.GSHPID order by case when clean_SHPNO is null then 999 else 1 end asc, jc2.CREATEDATE asc)
						from		(
									select		GSHPID
									from		cte_JobClean
									group by	GSHPID
									having		count(distinct clean_SHPNO) > 1
									) gsid
						join		cte_JobClean jc2
						on			gsid.GSHPID = jc2.GSHPID
						) gsid
			on			gsid.GSHPID = jc.GSHPID
			and			gsid.ix = 1
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
			, TEU						=	isnull(sea.TOTTEU,0)
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
