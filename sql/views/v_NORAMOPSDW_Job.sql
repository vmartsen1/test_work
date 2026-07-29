USE [SGLBI]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =====================================================================================================
-- View:    CALC.v_NORAMOPSDW_Job
-- Purpose: 1 row = 1 AWB (ODS.NORAMOPSDW_tblAWB), covering the "Job" tab of UP_Data_Model.
--          Built directly on ODS.* tables only (no CALC.* views), mirroring the row-selection /
--          dedup logic already proven in CALC.v_NORAMOPSDW_Shipment, CALC.v_NORAMOPSDW_MAWB,
--          CALC.v_NORAMOPSDW_MAWBOcean and CALC.v_NORAMOPSDW_AWB_SlavesAndMasters (all inlined below).
--
-- Consignee/Shipper check (handoff item 2): unlike TMFF, OPS does NOT go through a party-master
-- table here - Name/Address come straight from the dedicated per-AWB tables
-- ODS.NORAMOPSDW_tblAWBConsignee / tblAWBShipper (1:1 on rowguid_AWB), so there is no "party
-- master shortcut" bug to fix on this side. ConsigneeID/ShipperID are left NULL: the Excel Job
-- tab has no OPS source for a Consignee/Shipper business key (AwbConsigneeID/AwbShipperID are
-- internal surrogate keys only used to build CALC.NORAMOPSDW_Party's Party_BK, not exposed here).
--
-- ShipmentID reuses the HouseNo/MasterNo/UniqueBookingIdentifier cleaning cross-applies from
-- CALC.v_NORAMOPSDW_Shipment verbatim (utilities.ufn_GetCleanGlobalShipmentId is treated as a
-- black box, per handoff).
--
-- Simplification vs. v_NORAMOPSDW_Shipment (flagged for review):
--   * The outer date filter here only keeps the CTE-level, direction-agnostic check
--     (coalesce(ETADate,DateShip,EntryDate) or coalesce(DateShip,EntryDate) >= 2019-01-01).
--     v_NORAMOPSDW_Shipment additionally re-checks this per ShipmentDirection (Import vs.
--     other), which requires resolving Origin/Destination country via CALC.NORAMOPSDW_Location.
--     That second, direction-aware check was NOT inlined here to avoid dragging in the whole
--     location-dimension resolution just for a boundary-date edge case; it only affects rows
--     right at the 2019-01-01 cutoff.
--
-- Open items / assumptions that could NOT be verified against raw DDL this session
-- (TMFF_OPS.sql was not part of this upload batch - see docs/ASSUMPTIONS.md for the full list):
--   * ClosingDate: ODS.NORAMOPSDW_tblAWBRecap.EntryDate taken from the Excel mapping as-is;
--     only tblAWBRecap.WeekEnding is confirmed elsewhere in the existing views.
--   * CustomerID/Contact/Phone: ODS.NORAMOPSDW_tblCustomer.SlsPsnID/Contact/Phone taken from the
--     Excel mapping as-is (SlsPsnID mapped to CustomerID looks like it may actually be a
--     salesperson id rather than a customer id - worth a business sanity check).
--   * ConsigneeAddress1-3/City/State/Zip/Country and Shipper equivalents: column names taken
--     from the Excel mapping (tblAWBConsignee/tblAWBShipper), not independently confirmed - no
--     other existing view reads more than the *ID column off these two tables.
--   * lkpVendor.VendorName, tblMAWB.VesselName/VoyageNo/FlightNumber/CarrierService/ETADate/PlDelv/
--     PTLOAD: taken from the Excel mapping as-is; only tblMAWB.MAWB/OriginCityCode/DestCityCode/
--     DepartureDate/rowguid_CarrierVendor are confirmed via the existing CALC.v_NORAMOPSDW_MAWB.
--   * POD/POL/POR/Delivery/FinalDestination coalesce hierarchies are this view's own
--     interpretation (reusing the location-fallback order already used for the analogous
--     Pre/Main/Post transport location fields in v_NORAMOPSDW_Shipment) - handoff flagged this
--     as needing validation against real data either way.
-- =====================================================================================================
CREATE view [CALC].[v_NORAMOPSDW_Job]
as
with cte_AWB as (
			select		  *
						, rn	=	row_number() over (partition by rowguid_AWB order by LastEdit desc)
			from		ODS.NORAMOPSDW_tblAWB
			where		AWBID is not null
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			(	coalesce(cast(ETADate as date), cast(DateShip as date), cast(EntryDate as date)) >= '20190101'
						or	coalesce(cast(DateShip as date), cast(EntryDate as date)) >= '20190101'
						)
),
cte_SlaveBase as ( --same source pool/filters as cte_AWB, kept separate because the slave/master pairing needs its own row_number ordering
			select		  *
						, ix	=	row_number() over (partition by RowGuid_AWB order by HWB desc, SCD_UpdateDate desc)
			from		ODS.NORAMOPSDW_tblAWB
			where		LinkServer = 'TGOPSINTL'
			and			HWB like '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9]%'
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			(	coalesce(cast(ETADate as date), cast(DateShip as date), cast(EntryDate as date)) >= '20190101'
						or	coalesce(cast(DateShip as date), cast(EntryDate as date)) >= '20190101'
						)
),
cte_SlaveMasters as (
			select		*
			from		cte_SlaveBase
			where		len(HWB) = 11
			and			ix = 1
),
cte_SlaveSlaves as (
			select		  MasterHWB	=	left(HWB,11)
						, *
			from		cte_SlaveBase
			where		len(HWB) > 11
			and			HWB like '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][A-Z]%'
			and			ix = 1
),
cte_Slaves as ( --inlined from CALC.v_NORAMOPSDW_AWB_SlavesAndMasters (Slave_RowGuid_AWB only, used to exclude slaves)
			select		Slave_RowGuid_AWB	=	cte_SlaveSlaves.rowguid_AWB
			from		cte_SlaveMasters
			join		cte_SlaveSlaves
			on			cte_SlaveSlaves.MasterHWB = cte_SlaveMasters.HWB
),
cte_MAWB as ( --inlined from CALC.v_NORAMOPSDW_MAWB, extended with the extra columns this view needs
			select		*
			from		(
						select		  rowguid_AWB					=	am.rowguid_AWB
									, MAWB							=	first_value(m.MAWB)					over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, OriginCityCode				=	first_value(m.OriginCityCode)			over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, DestCityCode					=	first_value(m.DestCityCode)			over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, DepartureDate					=	first_value(m.DepartureDate)			over(partition by am.rowguid_AWB order by m.DepartureDate desc)
									, ETADate						=	first_value(m.ETADate)					over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, PTLOAD						=	first_value(m.PTLOAD)					over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, PlDelv						=	first_value(m.PlDelv)					over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, VesselName					=	first_value(m.VesselName)				over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, VoyageNo						=	first_value(m.VoyageNo)					over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, CarrierService				=	first_value(m.CarrierService)			over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, FlightNumber					=	first_value(m.FlightNumber)				over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, rowguid_CarrierVendor			=	first_value(m.rowguid_CarrierVendor)	over(partition by am.rowguid_AWB order by m.LastEdit desc)
									, ix							=	row_number()							over(partition by am.rowguid_AWB order by m.LastEdit desc)
						from		ODS.NORAMOPSDW_tblMAWB m
						join		ODS.NORAMOPSDW_xrfMAWBAWB am
						on			m.rowguid_MAWB = am.rowguid_MAWB
						and			am.SCD_ActiveFlag = 1
						and			am.SCD_IsDeleted = 0
						where		m.SCD_ActiveFlag = 1
						and			m.SCD_IsDeleted = 0
						) x
			where		ix = 1
),
cte_MAWBOcean as ( --inlined from CALC.v_NORAMOPSDW_MAWBOcean, extended with the extra columns this view needs
			select		*
			from		(
						select		  rowguid_AWB	=	am.rowguid_AWB
									, PlAcceptCode	=	first_value(o.PlAcceptCode)	over(partition by am.rowguid_AWB order by o.LastEdit desc)
									, PtLoadCode	=	first_value(o.PtLoadCode)	over(partition by am.rowguid_AWB order by o.LastEdit desc)
									, PtDischCode	=	first_value(o.PtDischCode)	over(partition by am.rowguid_AWB order by o.LastEdit desc)
									, PlDelvCode	=	first_value(o.PlDelvCode)	over(partition by am.rowguid_AWB order by o.LastEdit desc)
									, PlAccept		=	first_value(o.PlAccept)		over(partition by am.rowguid_AWB order by o.LastEdit desc)
									, PtLoad		=	first_value(o.PtLoad)		over(partition by am.rowguid_AWB order by o.LastEdit desc)
									, PtDisch		=	first_value(o.PtDisch)		over(partition by am.rowguid_AWB order by o.LastEdit desc)
									, PlDelv		=	first_value(o.PlDelv)		over(partition by am.rowguid_AWB order by o.LastEdit desc)
									, MoveType		=	first_value(o.MoveType)		over(partition by am.rowguid_AWB order by o.LastEdit desc)
									, ix			=	row_number()				over(partition by am.rowguid_AWB order by o.LastEdit desc)
						from		ODS.NORAMOPSDW_tblMAWBOcean o
						join		ODS.NORAMOPSDW_xrfMAWBAWB am
						on			o.rowguid_MAWB = am.rowguid_MAWB
						and			am.SCD_ActiveFlag = 1
						and			am.SCD_IsDeleted = 0
						where		o.SCD_ActiveFlag = 1
						and			o.SCD_IsDeleted = 0
						) x
			where		ix = 1
),
cte_Pieces as ( --inlined from CALC.v_NORAMOPSDW_Shipment's `piec` subquery, extended with ChgWght for ChargeableWeight/Volume
			select		  rowguid_AWB
						, FghtDesc		=	cast(string_agg(replace(cast(nullif(ap.FghtDesc,'') as varchar(max)),'"',''''),',')								as varchar(500))
						, CnrtLoad		=	max(CnrtLoad)
						, ChgWght		=	sum(ChgWght)
						, TEU			=	sum(case	when CntSize like '10%' then 0.5
													when CntSize like '20%' then 1
													when CntSize like '40%' then 2
													when CntSize like '45%' then 2.25
													else 0 end)
						, ContainerNos	=	cast(left(string_agg(cast(nullif(ContainerNumber_BI,'') as varchar(max)),',') within group( order by ContainerNumber_BI ), 1000)	as varchar(1000))
			from		(
						select		  rowguid_AWB			=	ap.rowguid_AWB
									, CntSize				=	ap.CntSize
									, ContainerNumber_BI	=	ap.ContainerNumber_BI
									, FghtDesc				=	cast(string_agg(replace(cast(nullif(ap.FghtDesc,'') as varchar(max)),'"',''''),',')	as varchar(500))
									, CnrtLoad				=	max(CnrtLoad)
									, ChgWght				=	max(ap.ChgWght)
						from		ODS.NORAMOPSDW_tblAWBPieces ap
						where		ap.SCD_ActiveFlag = 1
						and			ap.SCD_IsDeleted = 0
						and			(	nullif(ap.FghtDesc,'')				is not null
									or	nullif(ap.ContainerNumber_BI,'')	is not null
									or	nullif(ap.CnrtLoad,'')				is not null
									or	ap.ChgWght							is not null
									)
						group by	  ap.rowguid_AWB
									, ap.CntSize
									, ap.ContainerNumber_BI
						) ap
			group by	rowguid_AWB
),
cte_CalcValues as (
			select		rowguid_AWB
						, AWBChrgWt
			from		ODS.NORAMOPSDW_tblAWBCalcValues
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
),
cte_Vendor as (
			select		*
			from		(
						select		  am.rowguid_AWB
									, VendorNo		=	cast(mv.VendorNo	as varchar(50))
									, VendorName	=	cast(mv.VendorName	as varchar(100))
									, ix			=	row_number() over(partition by am.rowguid_AWB order by m.MAWBID)
						from		ODS.NORAMOPSDW_lkpVendor mv
						join		ODS.NORAMOPSDW_tblMAWB m
						on			mv.rowguid_Vendor = m.rowguid_CarrierVendor
						and			m.SCD_ActiveFlag = 1
						and			m.SCD_IsDeleted = 0
						join		ODS.NORAMOPSDW_xrfMawbAwb am
						on			m.rowguid_MAWB = am.rowguid_MAWB
						and			am.SCD_ActiveFlag = 1
						and			am.SCD_IsDeleted = 0
						where		mv.SCD_ActiveFlag = 1
						and			mv.SCD_IsDeleted = 0
						) x
			where		ix = 1
)
select		  JOB_UNID					=	a.rowguid_AWB
			, Branch					=	cast(i.ICOId													as varchar(50))
			, CarrierCode				=	cast(vnd.VendorNo												as varchar(50))
			, CarrierName				=	cast(vnd.VendorName												as varchar(100))
			, ChargeableWeight			=	cw.ChargeableWeight
			, ClosingDate				=	ar.EntryDate
			, ConsigneeID				=	cast(null														as varchar(50))		--Excel: no OPS source
			, ConsigneeName				=	cast(con.Name													as varchar(100))
			, ConsigneeAddress1			=	cast(con.Address1												as varchar(50))
			, ConsigneeAddress2			=	cast(con.Address2												as varchar(50))
			, ConsigneeAddress3			=	cast(con.Address3												as varchar(50))
			, ConsigneeAddress4			=	cast(null														as varchar(50))		--Excel: no OPS source
			, ConsigneeCity				=	cast(con.City													as varchar(50))
			, ConsigneeState			=	cast(con.State													as varchar(50))
			, ConsigneePostalCode		=	cast(con.Zip													as varchar(50))
			, ConsigneeCountryCode		=	cast(con.Country												as varchar(50))
			, CustomerID				=	cast(lc.SlsPsnID												as varchar(50))
			, CustomerName				=	cast(lc.CustName												as varchar(100))
			, CustomerCode				=	cast(lc.CustNo													as varchar(50))
			, CustomerContact			=	cast(lc.Contact													as varchar(100))
			, CustomerPhone				=	cast(lc.Phone													as varchar(50))
			, CustomerAddress1			=	cast(lc.Address1												as varchar(100))
			, CustomerAddress2			=	cast(lc.Address2												as varchar(100))
			, CustomerAddress3			=	cast(lc.Address3												as varchar(100))
			, CustomerAddress4			=	cast(null														as varchar(100))	--Excel: no OPS source
			, CustomerCity				=	cast(lc.City													as varchar(50))
			, CustomerState				=	cast(lc.State													as varchar(50))
			, CustomerPostalCode		=	cast(lc.Zip														as varchar(50))
			, CustomerCountryCode		=	cast(lc.Country													as varchar(50))
			, CreateDate				=	a.EntryDate
			, Delivery					=	cast(coalesce(a.UltDestCode, mawoc.PlDelvCode, intl.PlDelvCode)	as varchar(50))
			, Department				=	cast(ld.DeptName												as varchar(100))
			, FinalDestination			=	cast(coalesce(mawoc.PlDelv, maw.PlDelv)						as varchar(100))
			, FinalDestinationDate		=	a.ScheduledDelivery
			, FlightNumber				=	cast(maw.FlightNumber											as varchar(50))
			, FreightDescription		=	cast(piec.FghtDesc												as varchar(500))
			, House						=	cast(a.HWB														as varchar(50))
			, JobNo						=	cast(a.HWB														as varchar(50))
			, Master					=	cast(maw.MAWB													as varchar(50))
			, ModeOfTransport			=	cast(case	when isnull(ld.TransportMode_BK,'') <> ''
													then ld.TransportMode_BK
													else case when a.IsInternational = 0 then 'Surface' else 'Other' end
												end															as varchar(50))
			, Pieces					=	a.TotalPieces
			, POD						=	cast(coalesce(a.PtDischCode, a.DestCityCode, mawoc.PtDischCode, maw.DestCityCode)					as varchar(50))
			, PODETADate				=	coalesce(a.ETADate, maw.ETADate)
			, POL						=	cast(coalesce(a.PtLoadCode, intl.TranShipmentPointCode2, a.OriginCityCode, mawoc.PtLoadCode, maw.OriginCityCode)	as varchar(50))
			, POLETDDate				=	coalesce(a.ETDDate, maw.DepartureDate)
			, POR						=	cast(coalesce(mawoc.PlAcceptCode, intl.PlAcceptCode)			as varchar(50))
			, PORETDDate				=	a.DateShip
			, ServiceLevel				=	cast(maw.CarrierService											as varchar(50))
			, ServiceType				=	cast(mawoc.MoveType												as varchar(50))
			, ShipmentID				=	cast(utilities.ufn_GetCleanGlobalShipmentId(trim(coalesce(calc.HouseNoForGlobalShipment, calc.MasterNoForGlobalShipment, calc.UniqueBookingIdentifier)))	as varchar(150))
			, ShipperID					=	cast(null														as varchar(50))		--Excel: no OPS source
			, ShipperName				=	cast(shp.Name													as varchar(100))
			, ShipperAddress1			=	cast(shp.Address1												as varchar(50))
			, ShipperAddress2			=	cast(shp.Address2												as varchar(50))
			, ShipperAddress3			=	cast(shp.Address3												as varchar(50))
			, ShipperAddress4			=	cast(null														as varchar(50))		--Excel: no OPS source
			, ShipperCity				=	cast(shp.City													as varchar(50))
			, ShipperState				=	cast(shp.State													as varchar(50))
			, ShipperPostalCode			=	cast(shp.Zip													as varchar(50))
			, ShipperCountryCode		=	cast(shp.Country												as varchar(50))
			, TEU						=	isnull(piec.TEU,0)
			, TSP						=	cast(null														as varchar(50))		--Excel: no OPS source
			, VesselName				=	cast(maw.VesselName												as varchar(50))
			, VIA						=	cast(a.GatewayCode												as varchar(50))
			, Volume					=	case when piec.CnrtLoad = 'FCL' then cw.ChargeableWeight else a.Volume2 end
			, VoyageNo					=	cast(maw.VoyageNo												as varchar(50))
			, Weight					=	a.TotalWeight
			, Weight_UT					=	cast(a.TotalDimWeight											as varchar(50))
			, UniqueRecordKey			=	utilities.ufn_GetHashedUID('NORAMOPSDW', coalesce(cast(a.rowguid_AWB as varchar(500)), '¤NULL¤'), default, default, default)
			, DataAgeHOT				=	a.SCD_UpdateDate
			, DataAgeCOLD				=	(
											select	max(v)
											from	(
													values	  (a.SCD_UpdateDate), (con.SCD_UpdateDate), (shp.SCD_UpdateDate)
															, (i.SCD_UpdateDate), (intl.SCD_UpdateDate), (lc.SCD_UpdateDate)
													) x (v)
											)
			, RecordChangeDateTime		=	getdate()
from		cte_AWB a
join		ODS.NORAMOPSDW_tblICO i
on			a.rowguid_ICO = i.rowguid_ICO
and			i.SCD_ActiveFlag = 1
and			i.SCD_IsDeleted = 0
join		ODS.NORAMOPSDW_tblAWBActive ac
on			ac.rowguid_AWB = a.rowguid_AWB
and			ac.SCD_ActiveFlag = 1
and			ac.SCD_IsDeleted = 0
left join	cte_Slaves sam
on			sam.Slave_RowGuid_AWB = a.rowguid_AWB
left join	ODS.NORAMOPSDW_lkpDepartment ld
on			a.DepartmentID = ld.DepartmentID
and			a.LinkServer = ld.LinkServer
and			ld.SCD_ActiveFlag = 1
and			ld.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblAWBRecap ar
on			ar.rowguid_ICO = a.rowguid_ICO
and			ar.RecapNo = a.RecapNo
and			ar.SCD_ActiveFlag = 1
and			ar.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblAWBInternational intl
on			a.rowguid_AWB = intl.rowguid_AWB
and			intl.SCD_ActiveFlag = 1
and			intl.SCD_IsDeleted = 0
left join	cte_MAWB maw
on			maw.rowguid_AWB = a.rowguid_AWB
left join	cte_MAWBOcean mawoc
on			mawoc.rowguid_AWB = a.rowguid_AWB
left join	cte_Vendor vnd
on			vnd.rowguid_AWB = a.rowguid_AWB
left join	cte_Pieces piec
on			piec.rowguid_AWB = a.rowguid_AWB
left join	cte_CalcValues acv
on			acv.rowguid_AWB = a.rowguid_AWB
left join	ODS.NORAMOPSDW_tblCustomer lc
on			a.rowguid_Customer = lc.rowguid_Customer
and			lc.SCD_ActiveFlag = 1
and			lc.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblAWBShipper shp
on			a.Rowguid_AWB = shp.Rowguid_AWB
and			shp.SCD_ActiveFlag = 1
and			shp.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblAWBConsignee con
on			a.Rowguid_AWB = con.Rowguid_AWB
and			con.SCD_ActiveFlag = 1
and			con.SCD_IsDeleted = 0
cross apply	(
			select		ChargeableWeight	=	cast(case when piec.CnrtLoad = 'FCL' then piec.ChgWght else acv.AWBChrgWt end as float)
			) cw
cross apply	(
			select		  HouseNo						=	case	when ld.ImpExp = 'E' then left(a.HWB,11)
																	when a.ImportHWBNo is not null then a.ImportHWBNo
																	when a.HWB like '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9]%' then left(a.HWB,11)
																	else a.HWB
															end
						, MasterNo						=	cast(nullif(nullif(trim(isnull(maw.MAWB,'')),''),'----')	as varchar(100))
						, MasterNoForGlobalShipment		=	cast(case	when ld.TransportMode_BK <> 'Air' then null
																	when replace(replace(maw.MAWB,'0',''),'-','') = '' then null
																	else nullif(nullif(trim(isnull(maw.MAWB,'')),''),'----') end	as varchar(100))
						, UniqueBookingIdentifier		=	cast('NORAMOPSDW|' + isnull(convert(varchar(16),a.AWBID),'')	as varchar(100))
			) precalc
cross apply	(
			select		  HouseNo					=	case	when replace(precalc.HouseNo, '0','') = '' then null
															else precalc.HouseNo
														end
						, HouseNoForGlobalShipment	=	case	when len(precalc.HouseNo)<4 then null
															when replace(precalc.HouseNo, '0','') = '' then null
															when precalc.HouseNo not like '%[0-9][0-9][0-9]%' then null
															else precalc.HouseNo
														end
						, MasterNO					=	precalc.MasterNO
						, MasterNoForGlobalShipment	=	case	when len(precalc.MasterNoForGlobalShipment)<4 then null
															when precalc.MasterNoForGlobalShipment not like '%[0-9][0-9][0-9]%' then null
															else precalc.MasterNoForGlobalShipment
														end
						, UniqueBookingIdentifier	=	precalc.UniqueBookingIdentifier
			) calc
where		i.ICOID not in ('9999','8888','CPH99','SHARED','0000', 'BATCH','GOT99')
and			i.ICOID not like 'TC%'
and			i.ICOID not like 'CN%'
and			a.rn = 1
and			sam.Slave_RowGuid_AWB is null --filter out slaves
GO
