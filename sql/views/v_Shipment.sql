USE [SGLBI]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =====================================================================================================
-- View:    Reports.v_Shipment
-- Purpose: 1 row = 1 JOB (TMFF) or 1 AWB (NORAMOPSDW/OPS), UNION ALL'd into one table, covering the
--          "Shipment" tab of UP_Data_Model_1108.xlsx.
--
-- This is a structural clone of Reports.v_Job: the Shipment tab lists the exact same 68 field names as
-- the Job tab in this workbook (verified field-by-field - zero difference either way), the same source
-- entities/columns, and even the same wording on the trickier fields (CarrierCode's IATA/MasterCode
-- fallback, ChargeableWeight's FCL vs non-FCL split, TEU) - so this view reuses every fix and
-- optimization already made for v_Job rather than re-deriving them:
--   * Consignee/Shipper come from the snapshot fields on JOB/JOBOTHER (TMFF), not FMPARTY - same
--     mislabeled-column bug in v_TMFF_Shipment this was built to avoid (see docs/HANDOFF_SUMMARY.md).
--     Customer stays on FMPARTY/FMPARTYADDR (no snapshot exists for it).
--   * OPS Consignee/Shipper come from tblAWBConsignee/tblAWBShipper directly (already correct there).
--   * ShipmentID / TEU / the OPS slave-AWB exclusion all reuse the same window-function-based logic
--     (no self-joins, no repeated table scans, no separate CTEs re-scanning the driving table) worked
--     out for v_Job - see that file's history for why each is shaped the way it is.
--   * Every join key / id column is cast to varchar so TMFF's numeric UNID and OPS's uniqueidentifier
--     rowguid_AWB don't clash in the UNION ALL.
--
-- Only real difference from v_Job: this workbook renames two fields - Delivery -> DeliveryLocationCode,
-- FinalDestination -> FinalDestinationLocationCode (same source columns, just renamed output). Note the
-- Job tab in this same (newer) workbook already uses these same renamed names too - v_Job.sql was built
-- from the older UP_Data_Model_2907__copy.xlsx and still says Delivery/FinalDestination; worth checking
-- whether it should be renamed to match this newer naming for consistency.
--
-- See docs/ASSUMPTIONS.md for the full list of fields taken from the Excel mapping without DDL
-- confirmation, and docs/HANDOFF_SUMMARY.md for the original Consignee/Shipper snapshot-vs-party-master
-- background.
-- =====================================================================================================
create view [Reports].[v_Shipment]
as
with cte_TEU as ( --TEU reconstructed at job grain from CALC.v_TMFF_AllItemsWithTEUAllocation's real allocation logic
			--(container/load-unit TEU split by cargo-volume share across every job sharing the container, plus
			--virtual containers/vehicles implied by TMFF_SEA/TMFF_ROAD when no real container/load-unit row
			--exists yet) - see v_Job.sql's history for the full derivation. All four sources UNION ALL'd, one
			--GROUP BY JOB_UNID at the end.
			select		JOB_UNID, TEU = sum(AllocatedTEU)
			from		(

						select		  sci.JOB_UNID
									, AllocatedTEU	=	coalesce(
															sci.ItemVolume / nullif(sum(sci.ItemVolume) over (partition by sci.CONTAINER_UNID), 0) * cnt.CalculatedTEU
														, 1.0 / nullif(count(*) over (partition by sci.CONTAINER_UNID), 0) * cnt.CalculatedTEU
														)
						from		(
									select		JOB_UNID, CONTAINER_UNID, ItemVolume = sum(TOTVOL)
									from		ODS.TMFF_SEACONTITEM
									where		SCD_ActiveFlag = 1
									and			SCD_IsDeleted = 0
									group by	JOB_UNID, CONTAINER_UNID
									) sci
						join		(
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
									) cnt
						on			cnt.UNID = sci.CONTAINER_UNID

						union all

						select		  lui.JOB_UNID
									, AllocatedTEU	=	coalesce(
															lui.ItemVolume / nullif(sum(lui.ItemVolume) over (partition by lui.UNITUNID), 0) * lu.CalculatedTEU
														, 1.0 / nullif(count(*) over (partition by lui.UNITUNID), 0) * lu.CalculatedTEU
														)
						from		(
									select		JOB_UNID, UNITUNID, ItemVolume = sum(TOTVOL)
									from		ODS.TMFF_LOADUNITITEM
									where		SCD_ActiveFlag = 1
									and			SCD_IsDeleted = 0
									and			JOB_UNID is not null
									group by	JOB_UNID, UNITUNID
									) lui
						join		(
									select		  UNID
												, CalculatedTEU	=	case	when UNITTYPE like '%10%' then 0.50
																		when UNITTYPE like '%20%' then 1.00
																		when UNITTYPE like '%40%' then 2.00
																		when UNITTYPE like '%45%' then 2.25
																	end
									from		ODS.TMFF_LOADUNIT
									where		SCD_ActiveFlag = 1
									and			SCD_IsDeleted = 0
									) lu
						on			lu.UNID = lui.UNITUNID

						union all

						select		  sea.JOB_UNID
									, AllocatedTEU	=	v.qty * case	when v.typ like '%10%' then 0.50
																	when v.typ like '%20%' then 1.00
																	when v.typ like '%40%' then 2.00
																	when v.typ like '%45%' then 2.25
																	else 0
																end
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
						and			sci.JOB_UNID is null
						and			v.qty > 0
						and			v.ispart = 0

						union all

						select		  road.JOB_UNID
									, AllocatedTEU	=	v.qty * case	when v.typ like '%10%' then 0.50
																	when v.typ like '%20%' then 1.00
																	when v.typ like '%40%' then 2.00
																	when v.typ like '%45%' then 2.25
																	else 0
																end
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
						and			lui.JOB_UNID is null
						and			v.qty > 0
						) all_teu
			group by	JOB_UNID
)
select		  JOB_UNID					=	cast(j.UNID									as varchar(50))
			, System_BK					=	cast('TMFF'									as varchar(50))
			, Branch					=	cast(j.OWNERID								as varchar(50))
			, CarrierCode				=	cast(coalesce(j.CARRIERCODE, j.CARRIERID, case tm.TransportMode_BK
																								 when 'Air' then airm.[2LetterIATA]
																								 when 'Sea' then left(mc.MasterCode, 4)
																							 end)			as varchar(50))
			, CarrierName				=	cast(null									as varchar(100))  ---????
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
			, CreateDate				=	j.CREATEDATE
			, CustomerID				=	cast(coalesce(jp.CONTROLPARTY, j.PARTYID_CUST)					as varchar(50))
			, CustomerName				=	cast(custp.FULLNAME												as varchar(150))
			, CustomerCode				=	cast(null														as varchar(50))
			, CustomerContact			=	cast(null														as varchar(50))
			, CustomerPhone				=	cast(null														as varchar(50))
			, CustomerAddress1			=	cast(custpa.ADDR1												as varchar(100))
			, CustomerAddress2			=	cast(custpa.ADDR2												as varchar(100))
			, CustomerAddress3			=	cast(custpa.ADDR3												as varchar(100))
			, CustomerAddress4			=	cast(custpa.ADDR4												as varchar(100))
			, CustomerCity				=	cast(coalesce(custpa.CITYNAME, custci.[Description])			as varchar(50))
			, CustomerState				=	cast(coalesce(custpa.STATEPROV, custci.STATEPROV)				as varchar(50))
			, CustomerPostalCode		=	cast(custpa.POSTALCODE											as varchar(50))
			, CustomerCountryCode		=	cast(custpa.CTRYCODE											as varchar(50))
			, DeliveryLocationCode		=	cast(j.DEVRYCTRY + j.DEVRYCITY									as varchar(50))
			, Department				=	cast(jo.BIZSCOPE												as varchar(50))
			, FinalDestinationLocationCode	=	cast(j.DESTCTRY + j.DESTCITY								as varchar(50))
			, FinalDestinationDate		=	j.FINALDESTETADATE
			, FlightNumber				=	cast(air.BY1FLTNO												as varchar(50)) --actually it is null in calc shipment
			, FreightDescription		=	cast(jo.COMMLOCALDESC											as varchar(500))
			, House						=	cast(j.SHPNO													as varchar(50))
			, JobNo						=	cast(j.JOBNO													as varchar(50))
			, Master					=	cast(mc.MasterCode												as varchar(50))
			, ModeOfTransport			=	cast(tm.TransportMode_BK										as varchar(50))
			, Pieces					=	j.TOTPCS
			, POD						=	cast(j.PODCTRY + j.PODCITY										as varchar(50))
			, PODETADate				=	j.PODETADATE
			, POL						=	cast(j.POLCTRY + j.POLCITY										as varchar(50))
			, POLETDDate				=	j.POLETDDATE
			, POR						=	cast(j.PORCTRY + j.PORCITY										as varchar(50))
			, PORETDDate				=	j.PORETDDATE
			, ServiceLevel				=	cast(jo.SERVICELEVEL											as varchar(50))
			, ServiceType				=	cast(jo.SERVICETYPE												as varchar(50))
			, ShipmentID				=	cast(coalesce(
														case	when min(shpnoc.clean_SHPNO) over (partition by j.GSHPID) <> max(shpnoc.clean_SHPNO) over (partition by j.GSHPID)
																then first_value(shpnoc.clean_SHPNO) over (partition by j.GSHPID order by case when shpnoc.clean_SHPNO is null then 999 else 1 end asc, j.CREATEDATE asc)
															end
													, shpnoc.clean_SHPNO
													, 'TMFF|' + j.OWNERID + '|' + cast(j.UNID as varchar)
													) as varchar(150))
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
			, TEU						=	isnull(teu.TEU,0)
			, TSP						=	cast(null														as varchar(50)) --???????
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
outer apply	(select CleanRaw = utilities.ufn_GetCleanGlobalShipmentId(j.SHPNO)) shpno --same GlobalShipmentId_BK cleaning as CALC.v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company;
																					  --folded into the main scan of ODS.TMFF_JOB instead of a separate cte_ShipmentId
																					  --(that used to re-scan the whole table + re-call this UDF once per row all over again)
cross apply	(select clean_SHPNO = case when replace(shpno.CleanRaw,'0','') = '' then null else shpno.CleanRaw end) shpnoc
left join	(
			select		  JOB_UNID
						, ClosingDate	=	min(STATUSDATE)
			from		ODS.TMFF_JOBINTFEXPDTL
			where		REFNO1 = 'OPSTATUS_CLOSE'
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			group by	JOB_UNID
			) cd
on			cd.JOB_UNID = j.UNID
left join	ODS.TMFF_JOBOTHER jo
on			jo.JOB_UNID = j.UNID
and			jo.SCD_ActiveFlag = 1
and			jo.SCD_IsDeleted = 0
left join	(select		  JOB_UNID
						, REALCSGN		=	max(case when PARTYTYPE = 'REALCSGN'		then PARTYID end)
						, CONTROLPARTY	=	max(case when PARTYTYPE = 'CONTROLPARTY'	then PARTYID end)
			from		ODS.TMFF_JOBPARTY
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			JOB_UNID is not null
			group by	JOB_UNID
			) jp
on			jp.JOB_UNID = j.UNID
left join	(
			select		  *
						, rn	=	row_number() over (partition by PARTYID order by SCD_UpdateDate desc)
			from		ODS.TMFF_FMPARTY
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			) custp
on			custp.PARTYID = coalesce(jp.CONTROLPARTY, j.PARTYID_CUST)
and			custp.rn = 1
left join	(
			select		  *
						, rn	=	row_number() over (partition by FMPARTY_UNID order by SCD_UpdateDate desc)
			from		ODS.TMFF_FMPARTYADDR
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			) custpa
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
left join	(
			select		  JOB_UNID
						, MAWBNO	=	max(MAWBNO)
			from		ODS.TMFF_JOBROUTE
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			MAWBNO is not null
			group by	JOB_UNID
			) jro
on			jro.JOB_UNID = j.UNID
outer apply	(
			select		MasterCode	=	case	when j.SHPTYPE = 'D'
												then coalesce(sea.MBLNO, j.SHPNO)
												else coalesce(sea.MBLNO, j.CONSOLNO, jro.MAWBNO)
										end
			) mc
outer apply	(
			select		TransportMode_BK				=	case
																when jo.TPTTYPE is not null												then jo.TPTTYPE
																when j.BIZTYPE	in ('AE','AI')											then 'AIR'
																when j.BIZTYPE	in ('SE','SI')											then 'SEA'
																when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'COU'								then 'COU'
																when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'SEA'								then 'SEA'
																when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'AIR'								then 'AIR'
																when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'TRK'								then 'ROAD'
																when j.BIZTYPE = 'NJ' and j.JOBTYPE not in ('COU','SEA','AIR','TRK')	then 'OTH'
																else null
															end
			) tm
left join	CALC.BiRef_AirLineMapping airm -- should we remove that table?? Carrier Code relates to it
on			airm.[3DigitIATA] = left(mc.MasterCode, 3)
left join	ODS.TMFF_VEWMOTHERVESSEL mo
on			mo.JOBUNID = j.UNID
and			mo.SCD_ActiveFlag = 1
and			mo.SCD_IsDeleted = 0
left join	cte_TEU teu
on			teu.JOB_UNID = j.UNID
where		j.SCD_ActiveFlag = 1
and			j.SCD_IsDeleted = 0
and			j.VOIDDATE is null



union all


select		  JOB_UNID					=	cast(a.rowguid_AWB												as varchar(50))
			, System_BK					=	cast('NORAMOPSDW'												as varchar(50))
			, Branch					=	cast(i.ICOId													as varchar(50))
			, CarrierCode				=	cast(vnd.VendorNo												as varchar(50))
			, CarrierName				=	cast(vnd.VendorName												as varchar(100))

			, ChargeableWeight			=	cw.ChargeableWeight

			, ClosingDate				=	ar.EntryDate

			, ConsigneeID				=	cast(con.AwbConsigneeID												as varchar(50))	--??
			, ConsigneeName				=	cast(con.Name													as varchar(100))
			, ConsigneeAddress1			=	cast(con.Address1												as varchar(50))
			, ConsigneeAddress2			=	cast(con.Address2												as varchar(50))
			, ConsigneeAddress3			=	cast(con.Address3												as varchar(50))
			, ConsigneeAddress4			=	cast(null														as varchar(50))
			, ConsigneeCity				=	cast(con.City													as varchar(50))
			, ConsigneeState			=	cast(con.State													as varchar(50))
			, ConsigneePostalCode		=	cast(con.Zip													as varchar(50))
			, ConsigneeCountryCode		=	cast(con.Country												as varchar(50))

			, CreateDate				=	a.EntryDate

			, CustomerID				=	cast(lc.SlsPsnID												as varchar(50))
			, CustomerName				=	cast(lc.CustName												as varchar(100))
			, CustomerCode				=	cast(lc.CustNo													as varchar(50))
			, CustomerContact			=	cast(lc.Contact													as varchar(100))
			, CustomerPhone				=	cast(lc.Phone													as varchar(50))
			, CustomerAddress1			=	cast(lc.Address1												as varchar(100))
			, CustomerAddress2			=	cast(lc.Address2												as varchar(100))
			, CustomerAddress3			=	cast(lc.Address3												as varchar(100))
			, CustomerAddress4			=	cast(null														as varchar(100))
			, CustomerCity				=	cast(lc.City													as varchar(50))
			, CustomerState				=	cast(lc.State													as varchar(50))
			, CustomerPostalCode		=	cast(lc.Zip														as varchar(50))
			, CustomerCountryCode		=	cast(lc.Country													as varchar(50))

			, DeliveryLocationCode		=	cast(coalesce(a.UltDestCode, mawoc.PlDelvCode, intl.PlDelvCode)	as varchar(50))
			, Department				=	cast(ld.DeptName												as varchar(100))
			, FinalDestinationLocationCode	=	cast(coalesce(mawoc.PlDelv, maw.PlDelv)					as varchar(100))
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

			, ShipperID					=	cast(shp.AwbShipperID											as varchar(50))
			, ShipperName				=	cast(shp.Name													as varchar(100))
			, ShipperAddress1			=	cast(shp.Address1												as varchar(50))
			, ShipperAddress2			=	cast(shp.Address2												as varchar(50))
			, ShipperAddress3			=	cast(shp.Address3												as varchar(50))
			, ShipperAddress4			=	cast(null														as varchar(50))
			, ShipperCity				=	cast(shp.City													as varchar(50))
			, ShipperState				=	cast(shp.State													as varchar(50))
			, ShipperPostalCode			=	cast(shp.Zip													as varchar(50))
			, ShipperCountryCode		=	cast(shp.Country												as varchar(50))

			, TEU						=	isnull(piec.TEU,0)
			, TSP						=	cast(null														as varchar(50))

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

from		(
			select		  *
						, rn	=	row_number() over (partition by rowguid_AWB order by LastEdit desc)
			from		ODS.NORAMOPSDW_tblAWB
			where		AWBID is not null
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			(	coalesce(cast(ETADate as date), cast(DateShip as date), cast(EntryDate as date)) >= '20190101'
						or	coalesce(cast(DateShip as date), cast(EntryDate as date)) >= '20190101'
						)
			) a
join		ODS.NORAMOPSDW_tblICO i
on			a.rowguid_ICO = i.rowguid_ICO
and			i.SCD_ActiveFlag = 1
and			i.SCD_IsDeleted = 0
left join	(
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
			) vnd
on			vnd.rowguid_AWB = a.rowguid_AWB
left join	(
			select		  rowguid_AWB
						, FghtDesc		=	cast(string_agg(replace(cast(nullif(ap.FghtDesc,'') as varchar(max)),'"',''''),',')								as varchar(500))
						, CnrtLoad		=	max(CnrtLoad)
						, ChgWght		=	sum(ChgWght)
						, TEU			=	sum(case	when CntSize like '10%' then 0.5
													when CntSize like '20%' then 1
													when CntSize like '40%' then 2
													when CntSize like '45%' then 2.25
													else 0 end)
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
			) piec
on			piec.rowguid_AWB = a.rowguid_AWB
left join	(
			select		  rowguid_AWB
						, AWBChrgWt
			from		ODS.NORAMOPSDW_tblAWBCalcValues
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			) acv
on			acv.rowguid_AWB = a.rowguid_AWB
cross apply	(
			select		ChargeableWeight	=	cast(case when piec.CnrtLoad = 'FCL' then piec.ChgWght else acv.AWBChrgWt end as float)
			) cw
left join	ODS.NORAMOPSDW_tblAWBRecap ar
on			ar.rowguid_ICO = a.rowguid_ICO
and			ar.RecapNo = a.RecapNo
and			ar.SCD_ActiveFlag = 1
and			ar.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblAWBConsignee con
on			a.Rowguid_AWB = con.Rowguid_AWB
and			con.SCD_ActiveFlag = 1
and			con.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblCustomer lc
on			a.rowguid_Customer = lc.rowguid_Customer
and			lc.SCD_ActiveFlag = 1
and			lc.SCD_IsDeleted = 0
left join	(
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
			) mawoc
on			mawoc.rowguid_AWB = a.rowguid_AWB
left join	ODS.NORAMOPSDW_tblAWBInternational intl
on			a.rowguid_AWB = intl.rowguid_AWB
and			intl.SCD_ActiveFlag = 1
and			intl.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpDepartment ld
on			a.DepartmentID = ld.DepartmentID
and			a.LinkServer = ld.LinkServer
and			ld.SCD_ActiveFlag = 1
and			ld.SCD_IsDeleted = 0
left join	(
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
			) maw
on			maw.rowguid_AWB = a.rowguid_AWB
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
left join	ODS.NORAMOPSDW_tblAWBShipper shp
on			a.Rowguid_AWB = shp.Rowguid_AWB
and			shp.SCD_ActiveFlag = 1
and			shp.SCD_IsDeleted = 0
left join	( --slave-AWB detection, inlined from CALC.v_NORAMOPSDW_AWB_SlavesAndMasters (COBI-7158: NORAMOPSDW
			--duplicates some AWB rows under a suffixed HWB - "12345-67890A" is a duplicate/"slave" of master
			--"12345-67890"). Rewritten as a single scan of the filtered tblAWB pool + two window-function passes
			--instead of a self-join (the self-join version scanned this same filtered pool twice - LIKE
			--patterns using character classes like '[0-9]' can't use an index seek in SQL Server, so each scan
			--was a full scan of this table). Each row gets a MasterKey (its own HWB if master-shaped, or the
			--HWB it would be a slave of if slave-shaped); MAX(...) OVER(PARTITION BY MasterKey) then checks
			--whether a live (ix=1), master-shaped row with that same key exists anywhere in the pool.
			select		  Slave_RowGuid_AWB	=	rowguid_AWB
			from		(
						select		  rowguid_AWB
									, ix
									, IsSlaveShape
									, HasMasterInPool	=	max(case when IsSlaveShape = 0 and ix = 1 then 1 else 0 end) over (partition by MasterKey)
						from		(
									select		  rowguid_AWB
												, ix			=	row_number() over (partition by RowGuid_AWB order by HWB desc, SCD_UpdateDate desc)
												, IsSlaveShape	=	case when len(HWB) > 11 and HWB like '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][A-Z]%' then 1 else 0 end
												, MasterKey		=	case	when len(HWB) > 11 and HWB like '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][A-Z]%' then left(HWB,11)
																		when len(HWB) = 11 then HWB
																		else null
																	end
									from		ODS.NORAMOPSDW_tblAWB
									where		LinkServer = 'TGOPSINTL'
									and			HWB like '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9]%'
									and			SCD_ActiveFlag = 1
									and			SCD_IsDeleted = 0
									and			(	coalesce(cast(ETADate as date), cast(DateShip as date), cast(EntryDate as date)) >= '20190101'
												or	coalesce(cast(DateShip as date), cast(EntryDate as date)) >= '20190101'
												)
									) t0
						) t1
			where		ix = 1
			and			IsSlaveShape = 1
			and			HasMasterInPool = 1
			) sam
on			sam.Slave_RowGuid_AWB = a.rowguid_AWB
where		i.ICOID not in ('9999','8888','CPH99','SHARED','0000', 'BATCH','GOT99')
and			i.ICOID not like 'TC%'
and			i.ICOID not like 'CN%'
and			a.rn = 1
and			sam.Slave_RowGuid_AWB is null --filter out slaves
GO
