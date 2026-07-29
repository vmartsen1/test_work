USE [SGLBI]
GO
/****** Object:  View [CALC].[v_NORAMOPSDW_AWB_SlavesAndMasters]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-7158 --Objective remove duplicates
--Prevtask unknown, hash unknown
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_NORAMOPSDW_AWB_SlavesAndMasters'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_NORAMOPSDW_AWB_SlavesAndMasters'
CREATE   view [CALC].[v_NORAMOPSDW_AWB_SlavesAndMasters]
--https://sgl.atlassian.net/browse/COBI-7158
--NORAMOPSDW has a very specific feature of duplicating AWB entries
--This entity is intended to create a map of duplicated (Slave) rows with correspondent main (Master) row. 
--Later we'll filter out all Slaves from calc.NORAMOPSDW_Shipment and CALC.NORAMOPSDW_ShipmentItem
--And also we'll remap shipment relationships for InvoiceTransaction and FileTransaction, from Slaves to Masters.
as
with cte_ as (
			select		* 
						, ix = row_number() over (partition by RowGuid_AWB order by HWB desc, SCD_UpdateDate desc)
			from		ODS.NORAMOPSDW_tblAWB
			where		--conditions on TGOPSINTL and HWB like '12345-67890%' - limit what we 
						--deduplicate (COBI-7158)
						LinkServer = 'TGOPSINTL' 
			and			HWB like '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9]%'
			-- conditions below should be same as conditions in CALC.NORAMOPSDW_Shipment!!!
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			(	coalesce(cast(ETADate as date), cast(DateShip as date), cast(EntryDate as date))>= '20190101'
						or	coalesce(cast(DateShip as date),cast(EntryDate as date)) >= '20190101'
						)

)
, cte_masters as ( --masters have HWB in strict format 12345-67890
			select		* 
			from		cte_ 
			where		len(hwb)= 11
			and			ix = 1
)
, cte_slaves as (  --slaves have HWB same as masters, but with additional suffixes
			select		MasterHWB = left(HWB,11)
						, * 
			from		cte_ 
			where		len(hwb)>11
			and			hwb like  '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][A-Z]%' 
			-- suffix should start with letter character
			and			ix = 1
)
select 
			  Master_RowGuid_AWB							= cte_masters.rowguid_AWB
			, Slave_RowGuid_AWB								= cte_slaves.rowguid_AWB
			, MasterHWB										= cast(cte_masters.HWB	as varchar(50))
			, SlaveHWB										= cast(cte_slaves.HWB	as varchar(50))
			, UniqueRecordKey								= utilities.ufn_GetHashedUID('NORAMOPSDW', cte_slaves.RowGuid_AWB, null,null, null)
			, DataAgeHOT									= cte_slaves.SCD_UpdateDate
			, DataAgeCOLD									= cte_slaves.SCD_UpdateDate
			, RecordChangeDateTime							= getdate()
from		cte_masters
join		cte_slaves
on			cte_slaves.MasterHWB = cte_masters.HWB
GO
/****** Object:  View [CALC].[v_NORAMOPSDW_Location]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-5516 --Performance fix
--prevtask none, hash none
--exec utilities.usp_ConvertViewToLoadComplex_simple 'CALC','v_NORAMOPSDW_Location'
CREATE view [CALC].[v_NORAMOPSDW_Location]
as
select		  CountryCode
			, Location_BK
			, UniqueRecordKey						=	utilities.ufn_GetHashedUID('NORAMOPSDW',Location_BK,default,default,default)
			, DataAgeHOT							=	c.SCD_UpdateDate
			, DataAgeCOLD							=	c.SCD_UpdateDate
			, RecordChangeDateTime					=	getdate() 
from		(
			select 
						  CountryCode		= isnull(c.ISOChrCd,'')
						, Location_BK		= cast(c.CityCode AS varchar(50))
						, SCD_UpdateDate	= c.SCD_UpdateDate
						, ix				= row_number() over (partition by c.CityCode order by LastEdit desc)
			from		ods.NORAMOPSDW_lkpCity c
			where		c.SCD_ActiveFlag = 1
			and			c.SCD_IsDeleted = 0
			and			LinkServer  in ( 'TGOPSINTL','TGOPSDOM','CNAOPSDOM')
			) c
where		ix = 1
GO
/****** Object:  View [CALC].[v_NORAMOPSDW_MAWB]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-5516 --Performance fix
--prevtask none, hash none
--exec utilities.usp_ConvertViewToLoadComplex_simple 'CALC','v_NORAMOPSDW_MAWB'
CREATE view [CALC].[v_NORAMOPSDW_MAWB]
as
select		
			  rowguid_AWB
			, MAWB				
			, OriginCityCode	
			, DestCityCode		
			, DepartureDate		
			, UniqueRecordKey				= utilities.ufn_GetHashedUID('NORAMOPSDW', rowguid_AWB,default,default,default)
			, DataAgeHOT		
			, DataAgeCOLD		
			, RecordChangeDateTime			= getdate() 
from		(
			select		  am.rowguid_AWB
						, MAWB							= first_value(m.MAWB)			over(partition by am.rowguid_AWB order by m.LastEdit desc)	
						, OriginCityCode				= first_value(m.OriginCityCode) over(partition by am.rowguid_AWB order by m.LastEdit desc)
						, DestCityCode					= first_value(m.DestCityCode)	over(partition by am.rowguid_AWB order by m.LastEdit desc)
						, DepartureDate					= first_value(m.DepartureDate)	over(partition by am.rowguid_AWB order by m.DepartureDate desc)
						, ix							= row_number()					over(partition by am.rowguid_AWB order by m.LastEdit desc)
						, DataAgeHOT					= case when m.SCD_UpdateDate > am.SCD_UpdateDate then m.SCD_UpdateDate else am.SCD_UpdateDate end
						, DataAgeCOLD					= case when m.SCD_UpdateDate > am.SCD_UpdateDate then m.SCD_UpdateDate else am.SCD_UpdateDate end
			from		ODS.NORAMOPSDW_tblMAWB m 
			join		ODS.NORAMOPSDW_xrfMAWBAWB am 
			on			m.rowguid_MAWB = am.rowguid_MAWB
			and			am.SCD_ActiveFlag = 1
			and			am.SCD_IsDeleted = 0
			where		m.SCD_ActiveFlag = 1
			and			m.SCD_IsDeleted = 0
			) x
where		ix = 1
GO
/****** Object:  View [CALC].[v_NORAMOPSDW_MAWBOcean]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-5516 --Performance fix
--prevtask none, hash none
--exec utilities.usp_ConvertViewToLoadComplex_simple 'CALC','v_NORAMOPSDW_MAWBOcean'
create view [CALC].[v_NORAMOPSDW_MAWBOcean]
as
select		  rowguid_AWB
			, PlAcceptCode
			, PtLoadCode
			, PtDischCode
			, PlDelvCode
			, UniqueRecordKey				= utilities.ufn_GetHashedUID('NORAMOPSDW', x.rowguid_AWB,default,default,default)
			, DataAgeHOT					= x.SCD_UpdateDate 
			, DataAgeCOLD					= x.SCD_UpdateDate 
			, RecordChangeDateTime			= getdate() 
from		(
			select		  rowguid_AWB		= am.rowguid_AWB
						, PlAcceptCode		= first_value(o.PlAcceptCode)	over(partition by am.rowguid_AWB order by o.LastEdit desc)	
						, PtLoadCode		= first_value(o.PtLoadCode)		over(partition by am.rowguid_AWB order by o.LastEdit desc)
						, PtDischCode		= first_value(o.PtDischCode)	over(partition by am.rowguid_AWB order by o.LastEdit desc)
						, PlDelvCode		= first_value(o.PlDelvCode)		over(partition by am.rowguid_AWB order by o.LastEdit desc)
						, ix				= row_number()					over(partition by am.rowguid_AWB order by o.LastEdit desc)
						, o.SCD_UpdateDate
			from		ODS.NORAMOPSDW_tblMAWBOcean o 
			join		ODS.NORAMOPSDW_xrfMAWBAWB am 
			on			o.rowguid_MAWB = am.rowguid_MAWB 
			and			am.SCD_ActiveFlag = 1
			and			am.SCD_IsDeleted = 0
			where		o.SCD_ActiveFlag = 1
			and			o.SCD_IsDeleted = 0
			) x
where		ix = 1
and			(	PlAcceptCode	is not null
			 or PtLoadCode		is not null
			 or PtDischCode		is not null
			 or PlDelvCode		is not null
			)
GO
/****** Object:  View [CALC].[v_NORAMOPSDW_Party]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO







--COBI-7305
--Prev task - unknown, hash - unknown
--exec utilities.usp_ConvertViewToLoadComplex 'CALC', 'v_NORAMOPSDW_Party'

CREATE view [CALC].[v_NORAMOPSDW_Party]
as
with cte as
(
select		 Party_BK				=	pa.Party_BK							
			, AccountNo				=	pa.AccountNo						
			, LocationCode			=	pa.LocationCode						
			, CountryCode			=	pa.CountryCode						
			, ZipCode				=   null								
			, CityName				=   null								
			, [State] 				=   null								
			, [Address] 			=   null								
			, IsActive				=	pa.IsActive							
			, LastActiveDate		=	pa.LastActiveDate					
			, LastUpdateDate		=	pa.LastUpdateDate					
			, CustomerState			=	pa.CustomerState					
			, [Name]				=	pa.NameFull							
			, CarrierCode			=	pa.AccountNo						
			, SCACCode				=	pa.AccountNo						
			, IsShipperConsignee	=	case when pg.Party_BK is not null then 1 else 0 end
			, SCD_UpdateDate
from		ODS.NORAMOPSDW_tblShipmentParty pa
left join	(
			select	distinct	Party_BK	=	cast('S_' + case	when a.LinkServer = 'TGOPSINTL' then 'I_'
																						when a.LinkServer = 'CNAOPSDOM' then 'C_'
																						when a.LinkServer = 'TGOPSDOM' then 'D_'
																						end 
																						+ cast(ash.AwbShipperID as varchar(50))			as varchar(50))
			from		ODS.NORAMOPSDW_tblAWB a
			left join	ODS.NORAMOPSDW_tblAWBShipper ash 
			on			a.Rowguid_AWB = ash.Rowguid_AWB
			and			ash.SCD_ActiveFlag = 1
			and			ash.SCD_IsDeleted = 0
			union 
			select	distinct	Party_BK	=	cast('C_' + case	when a.LinkServer = 'TGOPSINTL' then 'I_'
																						when a.LinkServer = 'CNAOPSDOM' then 'C_'
																						when a.LinkServer = 'TGOPSDOM' then 'D_'
																						end 
																						+ cast(con.AwbConsigneeID as varchar(50))		as varchar(50))
			from		ODS.NORAMOPSDW_tblAWB a
			left join	ODS.NORAMOPSDW_tblAWBConsignee con 
			on			a.Rowguid_AWB = con.Rowguid_AWB
			and			con.SCD_ActiveFlag = 1
			and			con.SCD_IsDeleted = 0
			) pg
on			pg.Party_BK = pa.Party_BK
where		SCD_ActiveFlag	= 1
and			SCD_IsDeleted	= 0 
union all
select		 Party_BK				=	isnull(nullif(pa.CustomerParty_BK,''), nullif(pa.AgentParty_BK,''))	
			, AccountNo				=	pa.CustNo															
			, LocationCode			=	null															
			, CountryCode			=	pa.Country															
			, ZipCode				=   pa.Zip																
			, CityName				=   pa.City															
			, [State] 				=   pa.State															
			, [Address] 			=   pa.Address1 + ', ' +	pa.Address2 +', '	+ pa.Address3					
			, IsActive				=	null															
			, LastActiveDate		=	pa.LastEdit														
			, LastUpdateDate		=	pa.LastEdit														
			, CustomerState			=	null															
			, [Name]				=	pa.CustName														
			, CarrierCode			=	pa.CustNo															
			, SCACCode				=	pa.CustNo															
			, IsShipperConsignee	=	0
			, pa.SCD_UpdateDate
from		ODS.NORAMOPSDW_tblCustomer pa
left join	ODS.NORAMOPSDW_tblShipmentParty sp
on			isnull(nullif(pa.CustomerParty_BK,''), nullif(pa.AgentParty_BK,'')) = sp.Party_BK
and			sp.SCD_ActiveFlag	= 1
and			sp.SCD_IsDeleted	= 0 
where		pa.SCD_ActiveFlag	= 1
and			pa.SCD_IsDeleted	= 0 
and			sp.Party_BK is null
)
select		  CorrectedParty_BK				=	cast(CorrectedParty_BK			as varchar(100))
			, OriginalParty_BK				=	cast(OriginalParty_BK			as varchar(50))
			, NameFull						=	cast(Name						as varchar(150))
			, LocationCode					=	cast(LocationCode				as varchar(50))
			, CountryCode					=	cast(CountryCode				as varchar(50))
			, IsActive						=	cast(IsActive					as varchar(50))
			, LastActiveDate				=	cast(LastActiveDate				as date)
			, LastUpdateDate				=	cast(LastUpdateDate				as date)
			, ZipCode			
			, CityName						
			, [State] 			
			, [Address] 		
			, AccountNo			
			, CustomerState		
			, CarrierCode		
			, SCACCode			
			, UniqueRecordKey				=	utilities.ufn_GetHashedUID(OriginalParty_BK, default, default, default, default)
			, DataAgeHOT					=	SCD_UpdateDate
			, DataAgeCOLD					=	SCD_UpdateDate
			, RecordChangeDateTime			=	getdate() 
from		(
			select		  CorrectedParty_BK			=	utilities.ufn_CLR_ReplaceSpecialCharacters(upper(CorrectedParty_BK))
						, OriginalParty_BK	
						, AccountNo			
						, LocationCode		
						, CountryCode		
						, ZipCode			
						, CityName			
						, [State] 			
						, [Address] 		
						, IsActive			
						, LastActiveDate	
						, LastUpdateDate	
						, CustomerState		
						, [Name]			
						, CarrierCode		
						, SCACCode			
						, SCD_UpdateDate
						, idx						=	row_number() over (partition by OriginalParty_BK order by SCD_UpdateDate desc)
			from		
(						select		  CorrectedParty_BK			=	cte.Party_BK
									, OriginalParty_BK			=	cte.Party_BK
									, AccountNo			
									, LocationCode		
									, CountryCode		
									, ZipCode			
									, CityName			
									, [State] 			
									, [Address] 		
									, IsActive			
									, LastActiveDate	
									, LastUpdateDate	
									, CustomerState		
									, [Name]			
									, CarrierCode		
									, SCACCode			
									, SCD_UpdateDate
						from		cte
						where		IsShipperConsignee = 0
						union all
						--Consignees and shippers. these are "bucketed" by NameFull which becomes the new BK
						select		  CorrectedParty_BK			=	cte.Name
									, OriginalParty_BK			=	cte.Party_BK
									, AccountNo			
									, LocationCode		
									, CountryCode		
									, ZipCode			
									, CityName			
									, [State] 			
									, [Address] 		
									, IsActive			
									, LastActiveDate	
									, LastUpdateDate	
									, CustomerState		
									, [Name]			
									, CarrierCode		
									, SCACCode			
									, SCD_UpdateDate
						from		cte
						where		IsShipperConsignee = 1
						and			cte.Name <> ''
						and			cte.Name not like '[0-9]'
						) x
			) x
where		idx = 1
and			len(CorrectedParty_BK) > 1
GO
/****** Object:  View [CALC].[v_NORAMOPSDW_Shipment]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-7377 --Objective Adjust XXX_Party_BK data type size
--prevtask COBI-7305, hash = -387045174
--exec  [utilities].[usp_ConvertViewToLoadComplex] @TargetSchema = 'CALC', @TargetView = 'v_NORAMOPSDW_Shipment'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_NORAMOPSDW_Shipment'
CREATE view [CALC].[v_NORAMOPSDW_Shipment]
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
as
select 	 
			  ShipmentCount							=	try_cast(am.ShipmentCount											as bigint)
			, ActivityCount							=	try_cast(am.ActivityCount											as bigint)
			, GlobalShipmentId_BK					=	utilities.ufn_GetCleanGlobalShipmentId(trim(coalesce(calc.HouseNoForGlobalShipment, calc.MasterNoForGlobalShipment, calc.UniqueBookingIdentifier)))
			, LocalShipmentId_BK     				=	cast(a.rowguid_AWB													as varchar(50))
			, HouseCode 							=	cast(calc.HouseNo													as varchar(50))
			, MasterCode							=	cast(isnull(maw.MAWB,'')											as varchar(50))
			, BookingNumber							=	cast(a.HWB															as varchar(50))
			, System_BK        						=	cast('NORAMOPSDW'													as varchar(50))
			, Company_BK       						=	cast(i.rowguid_ICO													as varchar(50))
			, Department_BK  						=	cast(ld.rowguid_Department											as varchar(50))
			, CostCenter_BK							=	cast(i.rowguid_ICO													as varchar(50))
			, File_BK       						=	cast(a.rowguid_AWB													as varchar(50))
			, ServiceCode_BK						=	cast(case calc2.TransportMode_BK when 'Air' then 'Air' + ' ' + calc2.ShipmentDirection when 'Sea' then 'Ocean' + ' ' + calc2.ShipmentDirection when 'Surface' then 'Road' + ' ' + calc2.ShipmentDirection when 'Warehouse' then 'Warehouse' else 'UnknownTransportMode' end		as varchar(50))
			, Currency_BK    						=	cast(isnull(isnull(cur.CurrencyType, cur2.CurrencyType),'USD')		as varchar(50))
			, TransportMode_BK						=	cast(calc2.TransportMode_BK											as varchar(50))
			, ShipmentDirection_BK					=	cast(calc2.ShipmentDirection										as varchar(50))  
			, CompanyCountryCode					=	cast(calc1.CompanyCountryCode										as varchar(50))
			, OriginCountryCode						=	cast(OriginCountry.CountryCode 										as varchar(50)) 
			, DestinationCountryCode				=	cast(DestinationCountry.CountryCode 								as varchar(50)) 
			, ActivityType_BK						=	cast(am.Activity_Bk													as varchar(50))
			, ShipmentType_BK						=	cast(case 
															when ld.TransportMode_BK = 'Sea' and piec.CnrtLoad = 'FCL' then 'FCL' 
															when ld.TransportMode_BK = 'Sea' and piec.CnrtLoad = 'LCL' then 'LCL' 
															when ld.TransportMode_BK = 'Sea' and piec.CnrtLoad = 'BB'	then 'BB' 
															when ld.TransportMode_BK = 'Sea' and piec.CnrtLoad = 'BUY' then 'BUY' 
															when ld.TransportMode_BK = 'Air' then 'HAWB'		
															when ld.TransportMode_BK = 'Other' then 'OTH' 		
															when ld.TransportMode_BK = 'Surface' then 'OTH' 	
															when ld.TransportMode_BK = 'Warehouse' then 'OTH' 	
															else ''
															end																as varchar(50))
			, CustomerParty_BK						=	cast(isnull(cust.CorrectedParty_BK	,prtcalc.CustomerParty_BK	)	as varchar(100))
			, ConsignorParty_BK						=	cast(isnull(csgn.CorrectedParty_BK	,prtcalc.ConsignorParty_BK	)	as varchar(100))
			, ConsigneeParty_BK						=	cast(isnull(csgnee.CorrectedParty_BK,prtcalc.ConsigneeParty_BK	)	as varchar(100))
			, ShipperParty_BK						=	cast(isnull(shpr.CorrectedParty_BK	,prtcalc.ShipperParty_BK	)	as varchar(100))
			, CarrierParty_BK 						=	cast(isnull(crr.CorrectedParty_BK	,prtcalc.CarrierParty_BK 	)	as varchar(100))
			, AgentParty_BK							=	cast(isnull(agn.CorrectedParty_BK	,prtcalc.AgentParty_BK		)	as varchar(100))
			, PickUpParty_BK						=	cast(null															as varchar(100))
			, DeliveryParty_BK						=	cast(null															as varchar(100))
			, NotifyParty_BK						=	cast(null															as varchar(100))
			, PreTransportDepartureLocation_BK		=	cast(coalesce(mawoc.PlAcceptCode, intl.PlAcceptCode,'')				as varchar(50))
			, PreTransportArrivalLocation_BK		=	cast(coalesce(	case
																			when	mawoc.PlAcceptCode is not null 
																			then	isnull(mawoc.PtLoadCode, maw.OriginCityCode)
																			else '' 
																		end, intl.PtLoadCode, a.OriginCityCode)				as varchar(50))
			, MainTransportDepartureLocation_BK		=	cast(coalesce(a.PtLoadCode, intl.TranShipmentPointCode2, a.OriginCityCode, mawoc.PtLoadCode, maw.OriginCityCode, '') as varchar(50))
			, MainTransportArrivalLocation_BK		=	cast(coalesce(a.PtDischCode, a.DestCityCode, mawoc.PtDischCode, maw.DestCityCode,'') as varchar(50))
			, PostTransportDepartureLocation_BK		=	cast(coalesce(	case 
																			when	mawoc.PlDelvCode is not null 
																			then	isnull(mawoc.PtDischCode, maw.DestCityCode)
																			else '' 
																		end, intl.PlDelvCode, a.DestCityCode)				as varchar(50))
			, PostTransportArrivalLocation_BK		=	cast(coalesce(a.UltDestCode, mawoc.PlDelvCode,intl.PlDelvCode,'')	as varchar(50))
			, TransportLane_BK                 		=	cast(calc2.[Transportlane_BK]										as varchar(50))
			, MainTransportLane_BK                 	=	cast(calc2.[MainTransportlane_BK]									as varchar(50))
			, ShipmentDepartureDate_BK				=	cast(maw.DepartureDate 												as date) 
			, ShipmentArrivalDate_BK				=	cast(stat.StatusDateTime											as date)
			, MainTransportDepartureDate_BK			=	cast(coalesce(a.ETDDate, a.DateShip) 								as date)
			, MainTransportArrivalDate_BK			=	cast(coalesce(a.ETADate, a.ScheduledDelivery, a.ReqDelv) 			as date)
			, CreateDate_BK							=	cast(a.EntryDate													as date)
			, FinancialDate_BK						=	cast(ar.WeekEnding													as date)
			, ShipmentDate_BK						=	case  
															when calc2.ShipmentDirection = 'Import' 
															then coalesce(cast(a.ETADate as date), cast(a.ScheduledDelivery as date), cast(a.ReqDelv as date), cast(a.EntryDate as date))
															else coalesce(cast(a.ETDDate as date),cast(a.DateShip as date),cast(a.EntryDate as date))
														end
			, PreTransportDepartureDate_BK			=	cast(null									   						as date)
			, PostTransportArrivalDate_BK			=	cast(null									   						as date)
			, ActualPreTransportDepartureDate_BK	=	cast(null															as date)	
			, ActualMainTransportDepartureDate_BK	=	cast(null															as date)	
			, ActualMainTransportArrivalDate_BK		=	cast(null															as date)	
			, ActualPostTransportArrivalDate_Bk		=	cast(null															as date)	
			, ShipmentCompletedDate_BK				=	cast(null															as date)
			, TransportDocumentDate_BK				=	cast(null															as date)
			, DangerousGoods						=	cast(case when intl.DGR in ('J','Y','Yes') then 1 else 0 end		as bit)
			, GoodsDescription  					=	cast(isnull(piec.FghtDesc,'')										as varchar(500))
			, FullGoodsDescription					=	cast(isnull(piec.FghtDesc,'')										as varchar(500))
			, TermsOfDeliveryGroup					=	cast(null															as varchar(50))
			, TermsOfDeliveryCode					=	cast(isnull(a.IncoTermCode,'')										as varchar(50))
			, TermsOfDeliveryLocation				=	cast(null															as varchar(50))
			, CompanyCountry						=	cast(null															as varchar(50))
			, PackagesCode                    		=	cast(null															as varchar(50))
			, ContainerNos                    		=	cast(piec.ContainerNos												as varchar(1000)) 
			, ValidForEmissionsCalculation  		=	cast(null															as bit)			--TBD
			, ExternalRevenue						=	cast(reve.ExternalRevenue	* isnull(excact.ExchangeRateUSD ,1)		as float)			
			, InvoicedRevenue						=	cast(reve.InvoicedRevenue 	* isnull(excact.ExchangeRateUSD ,1)		as float)
			, AgentRevenue							=	cast(reve.AgentRevenue		* isnull(excact.ExchangeRateUSD ,1)		as float)		
			, CustomerReference2					=	cast(''																as varchar(50))
			, CommodityCode							=	cast(''																as varchar(50))
			, BookingCreateUser						=	cast(a.EntryBy														as varchar(50))
			, BookingUser							=	cast(a.EntryBy														as varchar(50))
			, ControlledBy							=	cast(null															as varchar(50))	--must review Axsfreight setup to understand this one
			, IsTemplate							=	cast(0																as bit)
			, CustomerReference						=	cast(null															as varchar(50))	--TBD
			, VesselName							=	cast(null															as varchar(50))	--TBD
			, VoyageNumber							=	cast(null															as varchar(50))	--TBD
			, FlightNumber							=	cast(null															as varchar(50))	--TBD
 			, Comments								=	cast(''																as varchar(500))
			, ConsolidationNo						=	cast(null															as varchar(50))
			, SHPRNAME								=	cast(''																as varchar(100))
			, SHPRADDR1								=	cast(''																as varchar(50))
			, SHPRADDR2								=	cast(''																as varchar(50))
			, SHPRADDR3								=	cast(''																as varchar(50))
			, SHPRADDR4								=	cast(''																as varchar(50))
			, CSGNNAME								=	cast(''																as varchar(100))
			, CSGNADDR1								=	cast(''																as varchar(50))
			, CSGNADDR2								=	cast(''																as varchar(50))
			, CSGNADDR3								=	cast(''																as varchar(50))
			, CSGNADDR4								=	cast(''																as varchar(50))
			, rowguid_AWB							=	a.rowguid_AWB	
			, RecapNo								=	a.RecapNo
			, LinkServer							=	a.LinkServer
			, DepartmentID							=	a.DepartmentID
			, TotalWeight							=	a.TotalWeight
			, TotalPieces							=	a.TotalPieces
			, UnitMeas								=	a.UnitMeas
			, Volume2								=	a.Volume2
			, DimWtUnit								=	a.DimWtUnit
			, FileStatusID							=	a.FileStatusID
			, CarrierCode							=	isnull(Carr.VendorNo, case ld.TransportMode_BK 
																				when 'Air' then airmap.[2LetterIATA]
																				when 'Sea' then left(maw.MAWB,4)
																			  end)
			, BookingUpdateUser						=	a.LastEditBy
			, UniqueRecordKey						=	utilities.ufn_GetHashedUID('NORAMOPSDW',coalesce(cast(a.rowguid_AWB as varchar(500)), '¤NULL¤'),default,default,default)
			, DataAgeHOT							=	a.SCD_UpdateDate
			, DataAgeCOLD							=	(
														select	max(v) 
														from	(
																values	  (a.SCD_UpdateDate),(opt.SCD_UpdateDate)
																		, (i.SCD_UpdateDate),(ash.SCD_UpdateDate)
																		, (con.SCD_UpdateDate),(intl.SCD_UpdateDate)
																		, (maw.DataAgeCOLD),(reve.DataAgeCOLD)
																		, (mawoc.DataAgeCold),(Carr.SCD_UpdateDate)
																		, (Stat.SCD_UpdateDate),(piec.SCD_UpdateDate)
																) x (v)
														)
			, RecordChangeDateTime					=	getdate() 
from		(
			select		  *
						, rn	=	row_number() over (partition by rowguid_AWB order by LastEdit desc)
			from		ODS.NORAMOPSDW_tblAWB
			where		AWBID	is not null 
			-- NB!!!! Those conditions should be same conditions in CALC.NORAMOPSDW_AWB_SlavesAndMasters!!!
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			(	coalesce(cast(ETADate as date), cast(DateShip as date), cast(EntryDate as date))>= '20190101'
						or	coalesce(cast(DateShip as date),cast(EntryDate as date)) >= '20190101'
						)
			) a
left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam --filter out slaves
on			a.rowguid_AWB = sam.Slave_RowGuid_AWB
join		ODS.NORAMOPSDW_tblAWBActive ac
on			ac.rowguid_AWB = a.rowguid_awb
and			ac.SCD_ActiveFlag = 1
and			ac.SCD_IsDeleted = 0
join		ODS.NORAMOPSDW_tblICO i 
on			a.rowguid_ICO = i.rowguid_ICO
and			i.SCD_ActiveFlag = 1
and			i.SCD_IsDeleted = 0
left join	(
			select		  *  
						, ix = row_number() over (partition by rowguid_ICO order by rowguid_ico) 
			from		ODS.NORAMOPSDW_lkpIcoOption
			where		OptionName = 'RestrictCurrency'
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			)  opt
on			opt.RowGuid_ICO = i.rowguid_ICO 
and			opt.ix = 1
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
left join	ODS.NORAMOPSDW_lkpCurrency cur 
on			a.rowguid_Currency = cur.rowguid_Currency
and			cur.SCD_ActiveFlag = 1
and			cur.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpCurrency cur2 
on			cur2.LinkServer = a.LinkServer 
and			cur2.CurrencyID = opt.OptionValue
and			cur2.SCD_ActiveFlag = 1
and			cur2.SCD_IsDeleted = 0				
left join	ODS.NORAMOPSDW_tblCustomer lc 
on			a.rowguid_Customer = lc.rowguid_Customer
and			lc.SCD_ActiveFlag = 1
and			lc.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblAWBShipper ash 
on			a.Rowguid_AWB = ash.Rowguid_AWB
and			ash.SCD_ActiveFlag = 1
and			ash.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblAWBConsignee con 
on			a.Rowguid_AWB = con.Rowguid_AWB
and			con.SCD_ActiveFlag = 1
and			con.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblAWBInternational intl  
on			a.rowguid_AWB = intl.rowguid_AWB
and			intl.SCD_ActiveFlag = 1
and			intl.SCD_IsDeleted = 0
left join	CALC.NORAMOPSDW_MAWB maw
on			maw.rowguid_AWB = a.rowguid_AWB
left join	CALC.NORAMOPSDW_MAWBOcean mawoc
on			mawoc.rowguid_AWB = a.rowguid_AWB
left join	(
			select		  am.rowguid_AWB
						, VendorNo			= cast(mv.VendorNo as varchar(50)) 
						, ix				= row_number() over(partition by am.rowguid_AWB order by m.MAWBID)
						, mv.SCD_UpdateDate
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
			) Carr
on			Carr.rowguid_AWB = a.rowguid_AWB
and			Carr.ix = 1
left join	(
			select		  rowguid_AWB			= sts.rowguid_AWB
						, StatusDateTime		= max(sts.StatusDateTime)
						, SCD_UpdateDate		= max(sts.SCD_UpdateDate)
			from		ODS.NORAMOPSDW_tblAWBStatus sts 
			join		ODS.NORAMOPSDW_lkpShipmentStatus lss 
			on			sts.rowguid_ShipmentStatus = lss.rowguid_ShipmentStatus 
			and			lss.SCD_ActiveFlag = 1
			and			lss.SCD_IsDeleted  = 0
			where		lss.StsCode = 'D' 
			and			isnull(sts.Hide,'N') = 'N'
			and			sts.SCD_ActiveFlag = 1
			and			sts.SCD_IsDeleted = 0
			group by	sts.rowguid_AWB
			) Stat
on			Stat.rowguid_AWB = a.rowguid_AWB
left join	(
			select		  rowguid_AWB
						, FghtDesc			= cast(string_agg(replace(cast(nullif(ap.FghtDesc,'') as varchar(max)),'"','''') ,',') as varchar(500))
						, CnrtLoad			= max(CnrtLoad)
						, TEU				= sum(case 
														when CntSize like '10%' then 0.5 
														when CntSize like '20%' then 1 
														when CntSize like '40%' then 2 
														when CntSize like '45%' then 2.25
														else 0 end
													)
						, ContainerNos		= cast(left(string_agg(cast(nullif(ContainerNumber_BI,'') as varchar(max)),',') within group( order by ContainerNumber_BI ) , 1000) as varchar(1000))
						, SCD_UpdateDate	= max(ap.SCD_UpdateDate)
			from		(
						select		  rowguid_AWB			=	ap.rowguid_AWB
									, CntSize 				=	ap.CntSize
									, ContainerNumber_BI	=	ap.ContainerNumber_BI
									, FghtDesc			= cast(string_agg(replace(cast(nullif(ap.FghtDesc,'') as varchar(max)),'"','''') ,',') as varchar(500))
									, CnrtLoad			= max(CnrtLoad)
									, SCD_UpdateDate	= max(ap.SCD_UpdateDate)
						from		ODS.NORAMOPSDW_tblAWBPieces ap
						where		ap.SCD_ActiveFlag = 1
						and			ap.SCD_IsDeleted = 0
						and			(	nullif(ap.FghtDesc,'')				is not null
									or	nullif(ap.ContainerNumber_BI,'')	is not null
									or	nullif(ap.CnrtLoad,'')				is not null
									)
						group by	  ap.rowguid_AWB
									, ap.CntSize
									, ap.ContainerNumber_BI
						) ap
			group by	rowguid_AWB
			) piec
on			piec.rowguid_AWB = a.rowguid_AWB
cross apply (
			select		  HouseNo						= case 
																when ld.ImpExp = 'E' then left(a.HWB,11)
																when a.ImportHWBNo is not null then a.ImportHWBNo
																when a.HWB like '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9]%' then left(HWB,11) 
																else a.HWB 
														  end
						, MasterNo						= cast(nullif(nullif(trim(isnull(maw.MAWB,'')),''),'----') as varchar(100))
						, MasterNoForGlobalShipment		= cast(case when ld.TransportMode_BK <> 'Air' then null 
																	when replace(replace(maw.MAWB,'0',''),'-','') = '' then null
																	else nullif(nullif(trim(isnull(maw.MAWB,'')),''),'----') end  as varchar(100))
						, UniqueBookingIdentifier		= cast('NORAMOPSDW|' + isnull(convert(varchar(16),a.AWBID),'') as varchar(100))
			) precalc
cross apply (
			select		  HouseNo					= case	when replace(precalc.HouseNo, '0','') = ''
															then null
															else precalc.HouseNo
													  end
						, HouseNoForGlobalShipment	= case 
																when len(precalc.HouseNo)<4 
																then null
																when replace(precalc.HouseNo, '0','') = ''
																then null
																when precalc.HouseNo not like '%[0-9][0-9][0-9]%' 
																then null
																else precalc.HouseNo
													  end
						, MasterNO					= precalc.MasterNO
						, MasterNoForGlobalShipment = case 
																when len(precalc.MasterNoForGlobalShipment)<4 then null
																when precalc.MasterNoForGlobalShipment not like '%[0-9][0-9][0-9]%' then null
																else precalc.MasterNoForGlobalShipment
													  end
						, UniqueBookingIdentifier	= precalc.UniqueBookingIdentifier
			) calc
outer apply (
			select		  OriginLocation					= coalesce(mawoc.PlAcceptCode, intl.PlAcceptCode, a.PtLoadCode, intl.TranShipmentPointCode2, mawoc.PtLoadCode, maw.OriginCityCode, a.OriginCityCode, '')
						, DestinationLocation				= coalesce(mawoc.PlDelvCode, intl.PlDelvCode, a.PtDischCode, mawoc.PtDischCode, maw.DestCityCode, a.DestCityCode,'')
						, MainOriginLocation				= coalesce(a.PtLoadCode, intl.TranShipmentPointCode2,a.OriginCityCode, mawoc.PtLoadCode, maw.OriginCityCode, '')	
						, MainDestinationLocation			= coalesce(a.PtDischCode,a.DestCityCode, mawoc.PtDischCode, maw.DestCityCode,'')				
						, CompanyCountryCode				= isnull((case 
																		when i.RecapDatabase in ('TGRECAP','TFRECAP') then  'US'
																		when i.RecapDatabase in ('CanDomRecap','CanIntlRecap','TFRCANADA','TGRCANADA') then  'CA'
																		when i.RecapDatabase in ('MexDomRecap','MexIntlRecap') then  'MX'
																		else ''
																	  end),'')
			) calc1
left join	CALC.NORAMOPSDW_Location OriginCountry
on			calc1.OriginLocation			= OriginCountry.Location_BK
left join	CALC.NORAMOPSDW_Location DestinationCountry
on			calc1.DestinationLocation		= DestinationCountry.Location_BK
left join	CALC.NORAMOPSDW_Location MainOriginCountry
on			calc1.MainOriginLocation		= MainOriginCountry.Location_BK
left join	CALC.NORAMOPSDW_Location MainDestinationCountry
on			calc1.MainDestinationLocation	= MainDestinationCountry.Location_BK
left join	CALC.BIRef_ActivityMapping am
on			am.Activity_BK = cast(case 
																	when a.DepartmentId in (5) or a.InvoiceTypeId is not null or a.FileStatusDesc = 'Closed - Not Recapped' 
																	then 'OTH'
																	else 'CON'
																	end														as varchar(50))
outer apply (
			select		ShipmentDirection		=	case	
														when  (OriginCountry.CountryCode = DestinationCountry.CountryCode and OriginCountry.CountryCode = calc1.CompanyCountryCode)
														then 'Domestic'
														when OriginCountry.CountryCode = Calc1.CompanyCountryCode
														then 'Export'
														when DestinationCountry.CountryCode = Calc1.CompanyCountryCode
														then 'Import'
														when Calc1.CompanyCountryCode <> DestinationCountry.CountryCode and Calc1.CompanyCountryCode <> OriginCountry.CountryCode
														then 'Cross Trade'
														when isnull(try_cast(am.ShipmentCount as int),0) = 0 or am.ShipmentCount = 'NULL'
														then 'No movement' 
														else 'Other'  
													end
						, TransportMode_BK		= cast(case when isnull(ld.[TransportMode_BK], '') <> '' 
																then ld.[TransportMode_BK] 
																else 
																	case when a.IsInternational = 0 
																		then 'Surface' 
																		else 'Other' 
																	end 
															end			as varchar(50))
						, TransportLane_BK		=	cast(OriginCountry.CountryCode		+ '-' + DestinationCountry.CountryCode		as varchar(50))
						, MainTransportLane_BK	= 	cast(MainOriginCountry.CountryCode	+ '-' + MainDestinationCountry.CountryCode	as varchar(50))	
			)	calc2
outer apply (
			select		  CustomerParty_BK						=	cast(coalesce(nullif(lc.[CustomerParty_BK], ''), lc.AgentParty_BK)	as varchar(50))
						, ConsignorParty_BK						=	cast(coalesce(nullif(lc.[CustomerParty_BK], ''), lc.AgentParty_BK)	as varchar(50))
						, ConsigneeParty_BK						=	cast('C_' + case	when a.LinkServer = 'TGOPSINTL' then 'I_'
																						when a.LinkServer = 'CNAOPSDOM' then 'C_'
																						when a.LinkServer = 'TGOPSDOM' then 'D_'
																						end 
																						+ cast(con.AwbConsigneeID as varchar(50))		as varchar(50))
						, ShipperParty_BK						=	cast('S_' + case	when a.LinkServer = 'TGOPSINTL' then 'I_'
																						when a.LinkServer = 'CNAOPSDOM' then 'C_'
																						when a.LinkServer = 'TGOPSDOM' then 'D_'
																						end 
																						+ cast(ash.AwbShipperID as varchar(50))			as varchar(50))
						, CarrierParty_BK 						=	cast(isnull('V_' + Carr.VendorNo, '')								as varchar(50))
						, AgentParty_BK							=	cast('A_' + case	when a.LinkServer = 'TGOPSINTL' then 'I_'
																						when a.LinkServer = 'CNAOPSDOM' then 'C_'
																						when a.LinkServer = 'TGOPSDOM' then 'D_'
																						end 
																						+ a.AgentNo										as varchar(50))
			) prtcalc
left join	CALC.NORAMOPSDW_Party cust
on			cust.OriginalParty_BK = prtcalc.CustomerParty_BK
left join	CALC.NORAMOPSDW_Party csgn
on			csgn.OriginalParty_BK = prtcalc.ConsignorParty_BK	
left join	CALC.NORAMOPSDW_Party csgnee
on			csgnee.OriginalParty_BK = prtcalc.ConsigneeParty_BK
left join	CALC.NORAMOPSDW_Party shpr
on			shpr.OriginalParty_BK = prtcalc.ShipperParty_BK
left join	CALC.NORAMOPSDW_Party crr
on			crr.OriginalParty_BK = prtcalc.CarrierParty_BK
left join	CALC.NORAMOPSDW_Party agn
on			agn.OriginalParty_BK = prtcalc.AgentParty_BK
left join	CALC.NORAMOPSDW_ShipmentRevenue reve
on			a.rowguid_AWB =reve.rowguid_AWB
left join	CALC.Calc_ExchangeRatePeriodTypeReporting excact
on			excact.BaseCurrency						=	isnull(isnull(cur.CurrencyType, cur2.CurrencyType),'USD')
and			excact.ExchangeRateCalculationMethod_BK =	'PnL'
and			excact.Period_BK						=	year(a.EntryDate) * 100 + month(a.EntryDate)
and			excact.ExchangeRateSource_BK			=	'Actual'
left join	CALC.BiRef_AirLineMapping airmap
on			airmap.[3DigitIATA] = left(maw.MAWB,3)
where		i.ICOID not in ('9999','8888','CPH99','SHARED','0000', 'BATCH','GOT99')
and			i.ICOID not like 'TC%' 
and			i.ICOID not like 'CN%'
and			case	--this case is exact ShipmentDate_BK >='20190101' condition, but it will be executed only after ShipmentDirection calculated
					-- so we'll prefilter tblAWB table with 'or' statement below, should make filtering faster
				when calc2.ShipmentDirection = 'Import' 
				then coalesce(cast(a.ETADate as date), cast(a.DateShip as date), cast(a.EntryDate as date))
				else coalesce(cast(a.DateShip as date),cast(a.EntryDate as date))
			end >= '20190101'
and			a.rn = 1
and			sam.Slave_RowGuid_AWB is null --filter out slaves
GO
/****** Object:  View [CALC].[v_NORAMOPSDW_ShipmentItem]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




--COBI-7077 --Change Items to Container 
--prevtask COBI-6931, hash = --1407771646
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_NORAMOPSDW_ShipmentItem'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_NORAMOPSDW_ShipmentItem'
CREATE view [CALC].[v_NORAMOPSDW_ShipmentItem] 
as
select		  ShipmentItemCount								= cast(1 as bigint)
			--Convert lbs to kg
			, ShipmentItemWeight							= cast(coalesce(ap.[Weight],s.TotalWeight)	as float) 
																* case when isnull(s.UnitMeas, case when s.LinkServer like '%DOM%' then 'lb' else 'kg' end) = 'lb' then 0.453592 else 1 end
			--Convert lbs to kg
			, ShipmentItemChargeableWeight					= cast(case	--if exist item in a shipment with ChgWhgt = NULL - we take weight from acv.AWBChrgWt 
																	when min(case when ap.ChgWght is null then 'IsNull' else 'NoNull' end)
																		 over (partition by s.System_BK, s.Company_Bk, s.LocalShipmentId_BK)  = 'IsNull' 
																	then cast(acv.AWBChrgWt as float) /  count(1) over (partition by s.System_BK, s.Company_Bk, s.LocalShipmentId_BK)
																	else ap.ChgWght
															  end as float)
															  * case when isnull(s.UnitMeas, case when s.LinkServer like '%DOM%' then 'lb' else 'kg' end) = 'lb' then 0.453592 else 1 end
			, ShipmentItemVolume							= cast((case	when	ap.ChgWght > 1000 and ap.CnrtLoad = 'FCL' and s.TransportMode_BK = 'Sea'	then	ap.ChgWght/1000 
																			when	ap.CnrtLoad = 'FCL' and s.TransportMode_BK = 'Sea'							then	ap.ChgWght 
																			else	s.Volume2 
																	end) 
																	* 
																	(case	when	isnull(s.DimWtUnit, '') = 'CFT' 
																			then	0.0283 
																			else	1 end)	as float)
			, ShipmentItemColliCount						= cast(null						as float)
			, ShipmentItemSystemAnalysisTEUCount			= cast(teu.TEU					as float)
			, ShipmentItemCarrierTEUCount					= cast(teu.TEU					as float)
			, ShipmentItemCustomerTEUCount					= cast(teu.TEU					as float)
			, ContainerNo									= cast(ap.ContainerNumber_BI	as varchar(50))
			, SealNo										= cast(ap.SealNo				as varchar(50))
			, GoodsDescription								= s.GoodsDescription
			, GlobalShipmentItemId_BK						= cast(coalesce(ap.GlobalShipmentItemId_BK, concat(s.[GlobalShipmentId_BK],'__' ,isnull(nullif(trim(ap.ShipmentItemId_BK),''),ap.ContainerNumber_BI)))  as varchar(100))
			, LocalShipmentItemID_BK						= cast('NORAMOPSDW__' as varchar(50)) + cast(s.Company_BK as varchar(50)) + '__' + cast(s.LocalShipmentId_BK	 as varchar(50)) + '__' + cast(trim(isnull(ap.ShipmentItemId_BK,'')) as varchar(30))
			, ContainerType_BK								= cast(ISNULL(ap.cntSize,'')	as varchar(50))
			, System_BK										= cast('NORAMOPSDW'				as varchar(50))
			, GlobalShipmentId_BK							= s.[GlobalShipmentId_BK]
			, LocalShipmentID_BK							= s.[LocalShipmentID_BK]
			, Company_BK									= s.Company_BK
			, ValidForEmissionsCalculationBoolean_BK		= cast(case when s.ShipmentCount = 1 then 1 else 0 end as varchar(50))
			, CustomerParty_BK								= s.[CustomerParty_BK]		
			, Department_BK									= s.[Department_BK]			
			, CostCenter_BK									= s.[CostCenter_BK]			
			, Currency_BK									= s.[Currency_BK]				
			, ShipmentDirection_BK							= s.[ShipmentDirection_BK]	
			, CreateDate_BK									= cast(s.CreateDate_BK			as date)
			, Date_BK										= s.[ShipmentDate_BK]				
			, FinancialDate_BK								= s.[FinancialDate_BK]	
			, UniqueRecordKey								= utilities.ufn_GetHashedUID('NORAMOPSDW', s.Company_BK, s.LocalShipmentId_BK,ap.ShipmentItemId_BK, null)
			, DataAgeHOT									= s.DataAgeHot
			, DataAgeCOLD									= (select max(v) from (values (ap.SCD_UpdateDate), (ld.SCD_UpdateDate), (s.DataAgeCOLD)) x (v))
			, RecordChangeDateTime							= getdate()
from		CALC.NORAMOPSDW_Shipment s
left join	(
			select		  ap.rowguid_AWB
						, ap.ContainerNumber_BI
						, ap.SealNo
						, ap.cntSize
						, ap.CnrtLoad
						, ChgWght					=	sum(ap.ChgWght)
						, [Weight]					=	sum(ap.[Weight])
						, SCD_UpdateDate			=	max(ap.SCD_UpdateDate)
						, ShipmentItemId_BK			=	max(ap.ShipmentItemId_BK)
						, GlobalShipmentItemId_BK	=	max(ap.GlobalShipmentItemId_BK)
			from		ODS.NORAMOPSDW_tblAWBPieces ap
			where		ap.CnrtLoad = 'FCL'
			and			ap.SCD_ActiveFlag = 1
			and			ap.SCD_IsDeleted = 0
			and			nullif(ap.ContainerNumber_BI, '') is not null
			group by	  ap.rowguid_AWB
						, ap.ContainerNumber_BI
						, ap.SealNo
						, ap.cntSize
						, ap.CnrtLoad
			) ap 
on			s.rowguid_AWB = ap.rowguid_AWB
left join	ODS.NORAMOPSDW_tblAWBCalcValues acv 
on			s.rowguid_AWB = acv.rowguid_AWB
and			acv.SCD_ActiveFlag = 1
and			acv.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpDepartment ld 
on			s.DepartmentID = ld.DepartmentID 
and			s.LinkServer = ld.LinkServer
and			ld.SCD_ActiveFlag = 1
and			ld.SCD_IsDeleted = 0
cross apply (
			select		TEU =	case 
									when ap.CntSize like '10%' and ap.CnrtLoad = 'FCL' then 0.5 
									when ap.CntSize like '20%' and ap.CnrtLoad = 'FCL'  then 1 
									when ap.CntSize like '40%' and ap.CnrtLoad = 'FCL'  then 2 
									when ap.CntSize like '45%' and ap.CnrtLoad = 'FCL'  then 2.25
									else 0 
								end
			) teu
GO
/****** Object:  View [CALC].[v_NORAMOPSDW_ShipmentRevenue]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-7158 --Objective remove AWB duplicates
--prevtask COBI-5516, hash =54049938
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_NORAMOPSDW_ShipmentRevenue'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_NORAMOPSDW_ShipmentRevenue'
CREATE view [CALC].[v_NORAMOPSDW_ShipmentRevenue]
as
select		  rowguid_AWB										= isnull(sam.Master_RowGuid_AWB,ai.rowguid_AWB)
			, ExternalRevenue									= sum(aid.Amount) 
			, InvoicedRevenue									= sum(aid.Amount) 
			, AgentRevenue										= cast(null as float) ---how to identify agent? 
			, UniqueRecordKey									= utilities.ufn_GetHashedUID('NORAMOPSDW', isnull(sam.Master_RowGuid_AWB,ai.rowguid_AWB),default,default,default)
			, DataAgeHOT										= max(ai.SCD_UpdateDate)
			, DataAgeCOLD										= max(ai.SCD_UpdateDate)
			, RecordChangeDateTime								= getdate() 
from		ODS.NORAMOPSDW_tblAWBInvoice ai
left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam
on			ai.rowguid_AWB = sam.Slave_Rowguid_AWB
join		ODS.NORAMOPSDW_tblAWBInvoiceDetail aid 
on			ai.rowguid_AWBInvoice = aid.rowguid_AWBInvoice
and			aid.SCD_ActiveFlag = 1
and			aid.SCD_IsDeleted = 0
where		ai.SCD_ActiveFlag = 1
and			ai.SCD_IsDeleted = 0
and			aid.Amount is not null
group by	isnull(sam.Master_RowGuid_AWB,ai.rowguid_AWB)
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_Company]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-6532 Objective Adjust BiCompany
--PrevTask COBI-4442, hash = -1890126473
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_NORAMOPSDW_dim_Company'
--select * from utilities.vcheckdefinitionsyncronization_ext where ObjectName = 'v_NORAMOPSDW_dim_Company'
CREATE view [DW].[v_NORAMOPSDW_dim_Company] 
AS
select		  System_BK								= 'NORAMOPSDW' 
			, Company_BK							= cast(x.Company_BK																	as varchar(50))
			, BICompany								= cast(x.BICompany																	as varchar(50))
			, CompanyCode							= cast(x.CompanyNumber																as varchar(50))
			, CompanyName							= cast(coalesce(x.CompanyName,cd.LocalCompanyName)									as varchar(50))
			, CompanyZipCode						= cast(coalesce(x.CompanyZipCode, cd.LocalCompanyZipCode, '(Not mapped)')			as varchar(50))
			, CompanyCity							= cast(coalesce(x.CompanyCity, '(Not mapped)')										as varchar(50))
			, CompanyCountryCode					= cast(coalesce(x.CompanyCountryCode,cd.LocalCompanyCountryCode, '(Not mapped)')	as varchar(50))
			, CompanyCountryName					= cast(coalesce(x.CompanyCountry, cd.LocalCompanyCountryName, '(Not mapped)')		as varchar(50))
			, UniqueRecordKey						= utilities.ufn_GetHashedUID('NORAMOPSDW',x.Company_BK, default, default, default)
			, DataAgeHOT							= x.SCD_UpdateDate
			, DataAgeCOLD							= (select max(v) from (values (x.SCD_UpdateDate), (cd.SCD_UpdateDate)) as value(v)) 
			, RecordChangeDateTime					= getdate() 
from		(
			select		  [Company_BK]						= i.rowguid_ICO
						, [BICompany]						= i.Company_BK
						, [CompanyName]						= i.ICOName
						, [CompanyZipCode]					= isnull(i.Zip,'')
						, [CompanyCity]						= isnull(i.City,'')
						, [CompanyCountryCode]				= isnull((	case 
																			when i.RecapDatabase IN ('TGRECAP','TFRECAP') then  'US'
																			when i.RecapDatabase IN ('CanDomRecap','CanIntlRecap','TFRCANADA','TGRCANADA') then  'CA'
																			when i.RecapDatabase IN ('MexDomRecap','MexIntlRecap') then  'MX'
																			else ''
																		end),'')
						, [CompanyCountry]					= isnull((	case 
																			when i.RecapDatabase IN ('TGRECAP','TFRECAP') then  'United States'
																			when i.RecapDatabase IN ('CanDomRecap','CanIntlRecap','TFRCANADA','TGRCANADA') then  'Canada'
																			when i.RecapDatabase IN ('MexDomRecap','MexIntlRecap') then  'Mexico'
																			else ''
																		end),'')
						, [CompanyNumber]					= i.ICOId
						, [SCD_UpdateDate]																	
			from		ODS.NORAMOPSDW_tblICO i	
			where		i.ICOID NOT IN ('9999','8888','0000','CPH99','CN99','SHARED', 'TC27')
			and			i.RecapDatabase <> 'TRANSRELIEF'
			and			i.SCD_ActiveFlag = 1
			and			i.SCD_IsDeleted = 0
			) x
left join	CALC.BIRef_CompanyDetails cd
on			x.Company_BK = cd.Company_BK
and			cd.System_BK = 'NORAMOPSDW'
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_CostCenter]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-4442 Objective Adjust UniqueRecordKey
--PrevTask COBI-5215, hash = 481668558
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_NORAMOPSDW_dim_CostCenter'
CREATE view [DW].[v_NORAMOPSDW_dim_CostCenter]
as
select		  System_BK				
			, Company_BK			
			, Costcenter_BK
			, CostCenter			
			, CostCenterName		
			, LocalCostCenterName	
			, CompanyCostCenterCode	
			, CompanyDivisionCode	
			, CompanyDivisionName	
			, IsActive				
			, LastActiveDate		
			, LastUpdateDate	
			, UniqueRecordKey	 
			, DataAgeHOT			 
			, DataAgeCOLD			  
			, RecordChangeDateTime
from		(
			select
						  System_BK				=	'NORAMOPSDW'
						, Company_BK			=	cast(case when c.Company_BK = '' then 'CNA' else trim(c.Company_BK) end		as varchar(50))
						, Costcenter_BK			=	cast(case when c.Company_BK = '' then 'CNA' else trim(c.Company_BK) end		as varchar(50))
						, CostCenter			=	cast(nullif(trim(c.CompanyCode)		,	'')									as varchar(50))
						, CostCenterName		=	cast(nullif(trim(c.CompanyName)		,	'')									as varchar(150))				
						, LocalCostCenterName	=	cast(nullif(trim(c.CompanyName)		,	'')									as varchar(100))		
						, CompanyCostCenterCode	=	cast(ccm.Company_Costcenter													as varchar(100))	
						, CompanyDivisionCode	=	cast(ccm.Company_Division													as varchar(100))	
						, CompanyDivisionName	=	cast(ccm.Company_Division_Name												as varchar(100))	
						, IsActive				=	cast(1																		as int)
						, LastActiveDate		=	cast(null																	as datetime)
						, LastUpdateDate		=	cast(null																	as datetime)
						, UniqueRecordKey		=	utilities.ufn_GetHashedUID('NORAMOPSDW', case when c.Company_BK = '' then 'CNA' else c.Company_BK end, default, default, default)
						, DataAgeHOT			=	c.DataAgeHOT
						, DataAgeCOLD			=	(select max(v) FROM (VALUES (c.DataAgeCOLD),(ccm.SCD_UpdateDate)) AS value(v)) 
						, RecordChangeDateTime	=	getdate()
						, idx					=	row_number()over(partition by c.Company_BK order by c.CompanyName)
			from		DW.NORAMOPSDW_dim_Company c
			left join	(
						select		*
									, idx = row_number() over (partition by system_bk, company_bk, costcenter_bk order by CostCenter_Name asc)
						from		CALC.BIRef_CostCenterMapping
						) ccm
			on			ccm.System_BK = 'NORAMOPSDW'
			and			ccm.Company_BK = c.BICompany
			and			(	cast(ccm.Costcenter_BK as varchar) = cast(trim(c.Company_BK) as varchar)
						or	cast(ccm.Costcenter_BK as varchar) = cast(trim(c.Company_BK) as varchar)
						)
			and			Idx = 1
			) x
where		idx = 1
union
select		  System_BK				=	'NORAMOPSDW'
			, Company_BK			=	'NAHQ'
			, Costcenter_BK			=	'NAHQ'
			, CostCenter			=	''
			, CostCenterName		=	'NAHQ'
			, LocalCostCenterName	=	'NAHQ'
			, CompanyCostCenterCode	=	''
			, CompanyDivisionCode	=	''
			, CompanyDivisionName	=	''
			, IsActive				=	1
			, LastActiveDate		=	null
			, LastUpdateDate		=	null
			, UniqueRecordKey		=	utilities.ufn_GetHashedUID('NORAMOPSDW', 'NAHQ', 'NAHQ', default, default)
			, DataAgeHOT			=	cast('20221001' as datetime)
			, DataAgeCOLD			=	cast('20221001' as datetime) 
			, RecordChangeDateTime	=	getdate()
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_Department]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




--COBI-5697 --Objective adjustment of Department columns
--Prevtask COBI-5239 hash = -2104214157
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_NORAMOPSDW_dim_Department', @LoadMode = 'full'
--Run with forcing full only if you need to do so
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
CREATE view [DW].[v_NORAMOPSDW_dim_Department] 
as
select		  DepartmentCode		
			, DepartmentFullName	
			, DepartmentName		
			, GlobalCompanyCode			
			, MappingDepartmentCode		
			, System_BK					
			, Company_BK				
			, Department_BK				
			, UniqueRecordKey			
			, DataAgeHOT				
			, DataAgeCOLD				
			, RecordChangeDateTime		
from (
			select		  DepartmentCode			=	cast(isnull(i.ICOId,'') + '-' + isnull(cast(ld.DepartmentID as varchar),'')	as varchar(50))
						, DepartmentFullName		=	cast(isnull(i.ICOId,'') + '-' + isnull(cast(ld.DepartmentID as varchar),'') + ' - ' + isnull(ld.DeptName,'') + ' (' +  isnull(i.ICOName,'') + ')' as varchar(100))
						, DepartmentName			=	isnull(ld.DeptName,'') + ' (' +  isnull(i.ICOName,'') + ')'						
						, GlobalCompanyCode			=	cast(dm.GlobalCompanyCode					as varchar(50))
						, MappingDepartmentCode		=	cast(dm.MappingDepartmentCode				as varchar(50))
						, System_BK					=	cast('NORAMOPSDW'							as varchar(50))	
						, Company_BK				=	cast(i.rowguid_ICO							as varchar(50))
						, Department_BK				=	cast(ld.rowguid_Department					as varchar(100))
						, UniqueRecordKey			=	utilities.ufn_GetHashedUID('NORAMOPSDW', ld.rowguid_Department, i.rowguid_ICO, default, default)
						, DataAgeHOT				=	ld.SCD_UpdateDate
						, DataAgeCOLD				=	(select max(v) from (values (ld.SCD_UpdateDate),(i.SCD_UpdateDate)) as vals(v))
						, RecordChangeDateTime		=	getdate()
						, rn						=	row_number() over (partition by i.rowguid_ICO, ld.rowguid_Department order by ld.SCD_UpdateDate desc)
			from		ODS.NORAMOPSDW_tblICO i
			join		ODS.NORAMOPSDW_lkpDepartment ld 
			on			i.LinkServer = ld.LinkServer
			and			ld.SCD_ActiveFlag = 1
			and			ld.SCD_IsDeleted = 0
			left join  (
						select		  *
									, ix		=	row_number() over (partition by Station, TransportMode_BK, ShipmentDirection_BK order by GlobalCompanyCode asc, MappingDepartmentCode asc) 
						from		(
									select		distinct	
						  						  Station					=	right('0000' + cast(Station as varchar), 4)
						  						, TransportMode_BK			=	case Activity
						  															 when	'AIR'		then 'Air'
						  															 when	'ROA'		then 'Surface'
						  															 when	'OCE'		then 'Sea'
						  															 else    case  when [BusinessArea] = 'WHS' then 'Warehouse' end 
						  														end	
						  						, ShipmentDirection_BK		=	case [BusinessArea] 
						  															 when 'IMP' then 'Import' 
						  															 when 'EXP' then 'Export' 
						  															 when 'DOM' then 'Domestic'
						  															 when 'WHS' then
						  															 case when [IntDom] = 'Domestic' then 'Domestic' end 
						  															 else ''
						  														 end
						  						, GlobalCompanyCode			=	[CompanyNo]
						  						, MappingDepartmentCode		=	[DepartmentNo]
						  			from		CALC.FinRef_SGLNORAM_DepartmentMapping 
						  			) x
						) dm
			on			dm.Station = right('0000' + cast(i.ICOID as varchar), 4)
			and			dm.TransportMode_BK = ld.TransportMode_BK
			and			dm.ShipmentDirection_BK = ld.ShipmentDirection_BK
			and			dm.ix = 1
			where		i.ICOId NOT IN ('BATCH', '9999', '8888', '000', '0000', 'SHARED')
			and			i.SCD_ActiveFlag = 1
			and			i.SCD_IsDeleted = 0
			and			exists	(
								select		1
								from		ODS.NORAMOPSDW_TBLAWB t
								where		t.ROWGUID_ICO = i.ROWGUID_ICO
								and			t.DepartmentId = ld.DepartmentId
								and			t.SCD_ActiveFlag = 1
								and			t.SCD_IsDeleted = 0
								)
) p
where		rn = 1

GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_File]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-7451
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
--PrevTask COBI-5246, hash = -1468607345
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_NORAMOPSDW_dim_File'
CREATE view [DW].[v_NORAMOPSDW_dim_File]
as
select 
			  FileId	
			, File_BK	
			, Company_BK
			, System_BK
			, FileStatusCode	
			, FileStatus		
			, CreateDate
			, UniqueRecordKey	
			, DataAgeHOT			
			, DataAgeCOLD			
			, RecordChangeDateTime	
from		(
			select 
						  FileId					=	cast(ls.File_BK							as varchar(50))
						, File_BK					=	cast(ls.File_BK							as varchar(50))
						, Company_BK				=	cast(ls.Company_BK						as varchar(50))
						, System_BK					=	cast('NORAMOPSDW'						as varchar(50))
						, FileStatusCode			=	cast(isnull(fs.[FileStatus]	,'Open')	as varchar(50))
						, FileStatus				=	cast(isnull(fs.[Description],'Open')	as varchar(50))
						, CreateDate				=	convert(varchar(50), ls.CreateDate_BK, 112)
						, UniqueRecordKey			=	utilities.ufn_GetHashedUID('NORAMOPSDW',ls.File_BK,default,default,default)
						, DataAgeHOT				=	ls.DataAgeHOT
						, DataAgeCOLD				=	ls.DataAgeCOLD 
						, RecordChangeDateTime		=	getdate()
						, idx						=	row_number()over(partition by ls.File_BK , ls.Company_BK order by ls.DataAgeHot desc)
			from		CALC.NORAMOPSDW_Shipment ls
			left join	ODS.NORAMOPSDW_lkpFileStatus fs 
			on			fs.LinkServer = ls.LinkServer 
			and			fs.FileStatusID = ls.FileStatusID 
			and			fs.SCD_ActiveFlag = 1
			and			fs.SCD_IsDeleted = 0
			and			fs.FileStatus NOT IN ('TS-PEND','PROFILE','TSTemp')
			where		ls.File_BK is not null
			and			ls.Company_BK is not null
			) x
where		idx = 1
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_Invoice]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-6467 --Objective Finance System/Company
--PrevTask COBI-4442, hash = -1107943722
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_NORAMOPSDW_dim_Invoice'
--select * from utilities.vCheckDefinitionSyncronization where objectname = 'v_NORAMOPSDW_dim_Invoice'
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
CREATE view [DW].[v_NORAMOPSDW_dim_Invoice] 
as
select 
			  System_BK					
			, FinanceSystem_BK			
			, Company_BK				
			, FinancialCompany_BK		
			, InvoiceId_BK				
			, InvoiceNumber				
			, UniqueRecordKey			=	utilities.ufn_GetHashedUID('NORAMOPSDW', x.[Company_BK], x.[InvoiceId_BK], default, default)
			, DataAgeHOT				
			, DataAgeCOLD				
			, RecordChangeDateTime		
from		(
			select		  System_BK					=	cast('NORAMOPSDW'			as varchar(50)) 
						, FinanceSystem_BK			=	cast('NORAMOPSDW'			as varchar(50)) 
						, Company_BK				=	cast(i.[Company_BK]			as varchar(50)) 
						, FinancialCompany_BK		=	cast(i.[Company_BK]			as varchar(50)) 
						, InvoiceId_BK				=	cast(ai.rowguid_AWBInvoice	as varchar(50)) 
						, InvoiceNumber				=	cast(ai.[InvoiceId]			as varchar(50)) 
						, DataAgeHOT				=	ai.SCD_UpdateDate
						, DataAgeCOLD				=	(select	max(v) from	(values (ai.SCD_UpdateDate), (i.DataAgeCOLD)) x (v))
						, RecordChangeDateTime		=	getdate()
						, ix						=	row_number() over (partition by i.[Company_BK],ai.rowguid_AWBInvoice order by ai.scd_updatedate desc, ai.invoiceid_bk desc, i.localshipmentid_bk desc)
			from		 ODS.NORAMOPSDW_tblAWBInvoice ai
			join		 CALC.NORAMOPSDW_Shipment as i
			on			 i.rowguid_AWB = ai.rowguid_AWB		
			where		 ai.SCD_ActiveFlag	= 1
			and			 ai.SCD_IsDeleted	= 0
			) x
where		x.ix = 1
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_InvoiceType]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
--COBI-4442 Objective Adjust UniqueRecordKey
--PrevTask COBI-3662, hash = -936837815
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_NORAMOPSDW_dim_InvoiceType'
CREATE view [DW].[v_NORAMOPSDW_dim_InvoiceType]
as
select		  System_BK				=	cast('NORAMOPSDW'							as varchar(50))
			, Company_BK			=	cast('NAHQ'									as varchar(50))
			, InvoiceType_BK		=	cast(lit.rowguid_InvoiceType				as varchar(50))
			, InvoiceTypeName		=	cast(isnull(lit.InvoiceType,'')				as varchar(50))
			, InvoiceTypeName2		=	cast(isnull(lit.[Description],'')			as varchar(100))
			, SubNoteType			=	cast(''										as varchar(30))
			, NoteClass				=	cast(''										as varchar(30))
			, UniqueRecordKey		=	utilities.ufn_GetHashedUID('NORAMOPSDW', lit.rowguid_InvoiceType, default, default, default)
			, DataAgeHOT			=	lit.SCD_UpdateDate
			, DataAgeCOLD			=	lit.SCD_UpdateDate
			, RecordChangeDateTime	=	getdate()
from		ODS.NORAMOPSDW_lkpInvoiceType lit
where 		lit.SCD_ActiveFlag	= 1
and		    lit.SCD_IsDeleted	= 0
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_Item]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
--COBI-4442 Objective Adjust UniqueRecordKey
--PrevTask COBI-3662, hash = 750149201
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_NORAMOPSDW_dim_Item'
CREATE view [DW].[v_NORAMOPSDW_dim_Item]
as
select        System_BK				=	cast('NORAMOPSDW'																						as varchar(50))	  
			, Company_BK			=   cast(i.rowguid_ICO																						as varchar(50))
			, Item_BK 				=   cast(lcc.rowguid_ChargeCode																				as varchar(100))
			, ItemName				=	cast(replace(lcc.ChrgDesc,'"','''')																		as varchar(50))
			, ServiceCode			=	cast(lcc.ChrgCode																						as varchar(100))
			, ChargeCode			=	cast(lcc.ChrgCode																						as varchar(50))
			, InvoiceText1			=   cast(''																									as varchar(50))
			, InvoiceText2			=   cast(''																									as varchar(50))
			, InvoiceText3			=   cast(''																									as varchar(50))
			, InvoiceText4			=   cast(''																									as varchar(50))
			, InvoiceText5			=   cast(''																									as varchar(50))
			, UniqueRecordKey		=	utilities.ufn_GetHashedUID('NORAMOPSDW',i.rowguid_ICO,lcc.rowguid_ChargeCode, default, default)
			, DataAgeHOT			=	lcc.SCD_UpdateDate
			, DataAgeCOLD			=	lcc.SCD_UpdateDate
			, RecordChangeDateTime	=	getdate()
from		ODS.NORAMOPSDW_lkpChargeCode lcc
cross join	ODS.NORAMOPSDW_tblICO i	
where		lcc.SCD_ActiveFlag = 1
and			lcc.SCD_IsDeleted = 0 
and			i.ICOID NOT IN ('9999','8888','0000','CPH99','CN99','SHARED', 'TC27')
and			i.RecapDatabase <> 'TRANSRELIEF'
and			i.SCD_ActiveFlag = 1
and			i.SCD_IsDeleted = 0
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_Location]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-6916 --Objective duplicates in Location_BK
--prevtask COBI-4442, hash = -779437378
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_NORAMOPSDW_dim_Location'
--select * from utilities.vCheckDefinitionSyncronization where objectname = 'v_NORAMOPSDW_dim_Location'
CREATE view [DW].[v_NORAMOPSDW_dim_Location]  
as
select		   System_BK				= cast('NORAMOPSDW'			as varchar(50))
			 , LocationCode				= cast(trim(LocationCode)	as varchar(50))
			 , LocationName				= cast(trim(LocationName)	as varchar(50))
			 , LocationUN				= cast(trim(LocationUN)		as varchar(50))
			 , CountryCode				= cast(trim(l.CountryCode)	as varchar(50))
			 , CountryName				= cast(trim(CountryName)	as varchar(100))
			 , TimeZone					= cast(trim(TimeZone)		as varchar(50))
			 , IsExpired				= cast(IsExpired			as int)	
			 , FreightArea				= cast(trim(FreightArea)	as varchar(50))
			 , Location_BK				= cast(Location_BK			as varchar(50))
			 , UniqueRecordKey			= utilities.ufn_GetHashedUID('NORAMOPSDW',RowID, default, default, default)
			 , DataAgeHOT				= l.SCD_UpdateDate			
			 , DataAgeCOLD				= (select max(v) from (values (l.SCD_UpdateDate),(c.SCD_UpdateDate)) as value(v)) 			
			 , RecordChangeDateTime		= getdate()
from (
			select		  LocationCode			 = cast(c.CityCode as varchar(50))
						, LocationName			 = cast(c.City as varchar(50))
						, LocationUN			 = cast(isnull((case 
														when len(c.CityCode) = 3 AND c.CityCode NOT like '0-9%' 
															then c.ISOChrCd + c.CityCode
														when len(c.CityCode) = 5 AND c.CityCode NOT like '0-9%' 
															then c.CityCode
														else ''
													  end),'')	as varchar(50))
						, CountryCode			 = cast(isnull(c.ISOChrCd,'') as varchar(50))
						, TimeZone				 = cast(isnull((case c.EDITimeZone 
												 					when 'ADT'  then '-03:00'
												 					when 'AKDT' then '-08:00'
												 					when 'AKST' then '-09:00'
												 					when 'AST'  then '-04:00'
												 					when 'AT'   then '-04:00'
												 					when 'CDT'  then '-05:00'
												 					when 'CST'  then '-06:00'
												 					when 'CT'   then '-06:00'
												 					when 'EDT'  then '-04:00'
												 					when 'EGST' then '+00:00'
												 					when 'EGT'  then '-01:00'
												 					when 'EST'  then '-05:00'
												 					when 'ET'   then '-05:00'
												 					when 'GMT'  then '+00:00'
												 					when 'HDT'  then '-09:00'
												 					when 'HST'  then '-10:00'
												 					when 'MDT'  then '-06:00'
												 					when 'MST'  then '-07:00'
												 					when 'MT'   then '-07:00'
												 					when 'NDT'  then '-02:30'
												 					when 'NST'  then '-03:30'
												 					when 'PDT'  then '-07:00'
												 					when 'PMDT' then '-02:00'
												 					when 'PMST' then '-03:00'
												 					when 'PST'  then '-08:00'
												 					when 'PT'   then '-08:00'
												 					when 'WGST' then '-02:00'
												 					when 'WGT'  then '-03:00'
												 					else c.GMTOffset
												 				end),'') as varchar(50))
						, IsExpired				 = cast(0 as int)
						, FreightArea			 = isnull(cast(null as varchar(50)),'')
						, Location_BK			 = cast(trim(c.CityCode) as varchar(50))
						, RowID					 = c.rowguid_City
						, SCD_UpdateDate
						, ix					 = row_number() over (partition by trim(c.CityCode) order by LastEdit desc)
			from		ODS.NORAMOPSDW_lkpCity c
			where		c.SCD_ActiveFlag = 1
			and			c.SCD_IsDeleted = 0
			and			LinkServer  in ( 'TGOPSINTL','TGOPSDOM','CNAOPSDOM')
) l
left join		CALC.BIRef_Country c
on				c.CountryCode = l.CountryCode
where			l.ix = 1
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_Party]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO









--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
--COBI-7305 Fixing partytype flags
--PrevTask COBI-7286, hash = 1253083118
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_NORAMOPSDW_dim_Party'
--select * from utilities.vcheckdefinitionsyncronization_ext where objectname = 'v_NORAMOPSDW_dim_Party'
CREATE view [DW].[v_NORAMOPSDW_dim_Party] 
as
select		  System_BK				
			, Party_BK				
			, AccountNo				
			, NameFull				
			, StatisticNo			
			, StatisticNameFull		
			, LocationCode			
			, CountryCode			
			, ZipCode				
			, CityName				
			, [State] 				
			, [Address] 			
			, IsActive				
			, LastActiveDate		
			, LastUpdateDate		
			, CustomerState			
			, [Name]				
			, StatisticName			
			, DunsNo				
			, StatisticDunsNo		
			, CarrierCode			
			, SCACCode				
			, IsCustomer			
			, IsConsignor			
			, IsConsignee			
			, IsAgent				
			, IsShipper				
			, IsCarrier				
			, IsPickUp				
			, IsDelivery			
			, IsNotify				
			, IsCreditor			
			, IsDebtor				
			, IsAccount				
			, UniqueRecordKey		
			, DataAgeHOT			
			, DataAgeCOLD			
			, RecordChangeDateTime	
from (
			select		  System_BK				=	cast('NORAMOPSDW'																				as varchar(50))
						, Party_BK				=	cast(pa.CorrectedParty_BK																		as varchar(100))
						, AccountNo				=	cast(pa.AccountNo																				as varchar(50))
						, NameFull				=	cast(pa.AccountNo + ' - ' + pa.NameFull															as varchar(100))
						, StatisticNo			=	cast(coalesce(snm1.StatisticNo, snm2.StatisticNo, pa.AccountNo)									as varchar(50))
						, StatisticNameFull		=	cast(coalesce(isnull(snm1.StatisticNo, snm2.StatisticNo) + ' - ' + isnull(snm1.StatisticName, snm2.StatisticName), pa.AccountNo + ' - ' + pa.NameFull)	as varchar(150))
						, LocationCode			=	cast(pa.LocationCode																			as varchar(50))
						, CountryCode			=	cast(pa.CountryCode																				as varchar(50))
						, ZipCode				=	cast(ZipCode																					as varchar(50))
						, CityName				=	cast(CityName																					as varchar(50))
						, [State] 				=	cast([State]																					as varchar(50))
						, [Address] 			=	cast([Address]																					as varchar(250))
						, IsActive				=	cast(pa.IsActive																				as varchar(50))
						, LastActiveDate		=	try_cast(pa.LastActiveDate																		as date)
						, LastUpdateDate		=	try_cast(pa.LastUpdateDate																		as datetime)
						, CustomerState			=	cast(pa.CustomerState																			as varchar(50))
						, [Name]				=	cast(pa.NameFull																				as varchar(100))
						, StatisticName			=	cast(coalesce(snm1.StatisticName, snm2.StatisticName, pa.NameFull)								as varchar(100))
						, DunsNo				=	cast(null																						as varchar(50))
						, StatisticDunsNo		=	cast(null																						as varchar(50))
						, CarrierCode			=	cast(pa.CarrierCode																				as varchar(50))
						, SCACCode				=	cast(pa.SCACCode																				as varchar(50))
						, IsCustomer			=	cast(isnull(t.IsCustomer	, 0)																as bit)
						, IsConsignor			=	cast(isnull(t.IsConsignor	, 0)																as bit)
						, IsConsignee			=	cast(isnull(t.IsConsignee	, 0)																as bit)
						, IsAgent				=	cast(isnull(t.IsAgent		, 0)																as bit)
						, IsShipper				=	cast(isnull(t.IsShipper	, 0)																	as bit)
						, IsCarrier				=	cast(isnull(t.IsCarrier	, 0)																	as bit)
						, IsPickUp				=	cast(isnull(t.IsPickUp	, 0)																	as bit)
						, IsDelivery			=	cast(isnull(t.IsDelivery, 0)																	as bit)
						, IsNotify				=	cast(isnull(t.IsNotify	, 0)																	as bit)
						, IsCreditor			=	cast(isnull(cred.IsCreditor,0)																	as bit)
						, IsDebtor				=	cast(isnull(debt.IsDebtor,0)																	as bit)
						, IsAccount				=	cast(0																							as bit)
						, UniqueRecordKey		=	utilities.ufn_GetHashedUID('NORAMOPSDW',pa.CorrectedParty_BK, default, default, default)
						, DataAgeHOT			=	pa.DataAgeCOLD
						, DataAgeCOLD			=	pa.DataAgeCOLD
						, RecordChangeDateTime	=	getdate()
						, rn					=	row_number() over (partition by CorrectedParty_BK order by t.IsCustomer desc, t.IsConsignor desc, t.IsConsignee desc,
																											   t.IsAgent desc, t.IsShipper desc, t.IsCarrier desc, 
																											   t.IsPickUp desc, t.IsDelivery desc, t.IsNotify desc, cred.IsCreditor desc, debt.IsDebtor desc) 
			from		CALC.NORAMOPSDW_Party pa
			left join	CALC.BIRef_StatisticsNoMapping snm1
			on			snm1.System_BK = 'NORAMOPSDW'
			and			snm1.Party_BK = pa.CorrectedParty_BK
			left join	CALC.BIRef_StatisticsNoMapping snm2
			on			snm2.System_BK = 'NORAMOPSDW'
			and			snm2.Party_BK = pa.OriginalParty_BK
			left join	(
						select		Party_BK
									, IsCustomer		=	max(case when PartyType = 'CustomerParty_BK' then 1 else 0 end) 
									, IsConsignor		=	max(case when PartyType = 'ConsignorParty_BK' then 1 else 0 end) 
									, IsConsignee		=	max(case when PartyType = 'ConsigneeParty_BK' then 1 else 0 end) 
									, IsShipper			=	max(case when PartyType = 'ShipperParty_BK' then 1 else 0 end) 
									, IsAgent			=	max(case when PartyType = 'AgentParty_BK' then 1 else 0 end) 
									, IsCarrier			=	max(case when PartyType = 'CarrierParty_BK' then 1 else 0 end) 
									, IsPickUp			=	max(case when PartyType = 'PickUpParty_BK' then 1 else 0 end) 
									, IsDelivery		=	max(case when PartyType = 'DeliveryParty_BK' then 1 else 0 end) 
									, IsNotify			=	max(case when PartyType = 'NotifyParty_BK' then 1 else 0 end) 
						from (
									select			Party_BK, PartyType
									from			CALC.NORAMOPSDW_Shipment
									unpivot (
									Party_BK for PartyType in (CustomerParty_BK, ConsignorParty_BK, ConsigneeParty_BK, ShipperParty_BK, CarrierParty_BK, AgentParty_BK, PickUpParty_BK, DeliveryParty_BK, NotifyParty_BK)
									) u
						) t
						group by	Party_BK
						) t
			on			t.Party_BK = pa.CorrectedParty_BK
			left join	(
						select distinct
									 DebtorParty_BK					=	nullif(bc.CustomerParty_BK, '')
									, IsDebtor							=	1
						from		ODS.NORAMOPSDW_tblAWBInvoice  ai
						join		ODS.NORAMOPSDW_tblCustomer  bc 
						on			ai.Rowguid_Customer = bc.Rowguid_Customer
						and			bc.SCD_ActiveFlag = 1
						and			bc.SCD_IsDeleted = 0	
						where		ai.SCD_ActiveFlag = 1
						and			ai.SCD_IsDeleted = 0	
						union
						select distinct
									  DebtorParty_BK					=	nullif(sp.Party_BK, '')
									, IsDebtor							=	1
						from		ODS.NORAMOPSDW_tblAWBInvoice inv
						join		ODS.NORAMOPSDW_tblShipmentParty sp
						on			sp.RowID = inv.rowguid_Customer
						and			sp.SCD_ActiveFlag = 1
						and			sp.SCD_IsDeleted = 0
						where		inv.SCD_ActiveFlag = 1
						and			inv.SCD_IsDeleted = 0	
						) debt
			on			debt.DebtorParty_BK = pa.OriginalParty_BK
			left join	(
						select distinct
									  CreditorParty_BK					=	nullif(sp.Party_BK, '')
									, IsCreditor						=	1
						from		ODS.NORAMOPSDW_tblAWBCost cst
						join		ODS.NORAMOPSDW_tblShipmentParty sp
						on			sp.RowID = cst.rowguid_Vendor
						and			sp.SCD_ActiveFlag = 1
						and			sp.SCD_IsDeleted = 0
						where		cst.SCD_ActiveFlag = 1
						and			cst.SCD_IsDeleted = 0	
						) cred
			on			cred.CreditorParty_BK = pa.OriginalParty_BK
) t
where		t.rn = 1
and			(
			isnull(t.IsCustomer, 0)		= 1
or			isnull(t.IsConsignor, 0)	= 1
or			isnull(t.IsConsignee, 0)	= 1
or			isnull(t.IsAgent	, 0)	= 1
or			isnull(t.IsShipper	, 0)	= 1
or			isnull(t.IsCarrier	, 0)	= 1
or			isnull(t.IsPickUp	, 0)	= 1
or			isnull(t.IsDelivery, 0)		= 1
or			isnull(t.IsNotify	, 0)	= 1
or			isnull(t.IsCreditor, 0)		= 1
or			isnull(t.IsDebtor	, 0)	= 1
			)
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_PaymentTerm]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-7398 --Objective PaymentTerm dim to NoramOpsDW
--prevtask none, hash = none
--exec utilities.usp_ConvertViewToLoadComplex 'DW', 'v_NORAMOPSDW_dim_PaymentTerm'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_NORAMOPSDW_dim_PaymentTerm'
CREATE   view [DW].[v_NORAMOPSDW_dim_PaymentTerm]
as
select		
			  System_BK					
			, PaymentTerm_BK	
			, PaymentTermClass			
			, PaymentTerm				
			, PaymentTermDays			
			, PaymentTermDaysInterval010		=	cast(floor(PaymentTermDays/10) * 10 as varchar)   + '-' + cast(ceiling(PaymentTermDays/10) * 10 as varchar)
			, PaymentTermDaysInterval050		=	cast(floor(PaymentTermDays/50) * 50 as varchar)   + '-' + cast(ceiling(PaymentTermDays/50) * 50 as varchar)
			, PaymentTermDaysInterval100		=	cast(floor(PaymentTermDays/100) * 100 as varchar) + '-' + cast(ceiling(PaymentTermDays/100) * 100 as varchar)
			, PaymentTermDaysInterval010SortKey	=	floor(PaymentTermDays/10) * 10
			, PaymentTermDaysInterval050SortKey	=	floor(PaymentTermDays/50) * 50
			, PaymentTermDaysInterval100SortKey	=	floor(PaymentTermDays/100) * 100
			, UniqueRecordKey		
			, DataAgeHOT				
			, DataAgeCOLD				
			, RecordChangeDateTime		
from		(
			select		
						  System_BK					=	'NORAMOPSDW'
						, PaymentTerm_BK			=	ai.TermsCode
						, PaymentTermClass			=	case 
															when ai.TermsCode like 'net%'	then 'Net'
															when ai.TermsCode like 'EOM%'	then 'EndOfMonth'
															when ai.TermsCode like 'CASH%'	then 'Cash'
															when ai.TermsCode like 'EOP%'	then 'EndOfPeriod'
															else ai.TermsCode
														end
						, PaymentTerm				=	ai.TermsCode
						, PaymentTermDays			=	ai.TermsPayDays
						, UniqueRecordKey			=	utilities.ufn_GetHashedUID('NORAMOPSDW', ai.TermsCode,default ,default,default)
						, DataAgeHOT				=	SCD_UpdateDate
						, DataAgeCOLD				=	SCD_UpdateDate 
						, RecordChangeDateTime		=	getdate()
						, ix						=	row_number() over (
																	partition by ai.TermsCode
																	order by SCD_UpdateDate desc)
			from		ODS.NORAMOPSDW_tblAWBInvoice ai
			where		ai.SCD_ActiveFlag = 1
			and			ai.SCD_IsDeleted = 0
			and			ai.TermsCode is not null
			) x
			where ix = 1
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_PostingType]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-4442 Objective Adjust UniqueRecordKey
--PrevTask COBI-5247, hash=-911090267
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_NORAMOPSDW_dim_PostingType'
CREATE view [DW].[v_NORAMOPSDW_dim_PostingType]
as
select		  PostingTypeCode			=	cast(Code			as varchar(200))
			, PostingType				=	cast(TypeName		as varchar(200))
			, PostingType_BK			=	cast(Code			as varchar(100))
			, System_BK					=	cast('NORAMOPSDW'	as varchar(50))
			, UniqueRecordKey			=	utilities.ufn_GetHashedUID('NORAMOPSDW', Code, default, default, default)
			, DataAgeHOT				=	cast('20221001' as datetime)
			, DataAgeCOLD				=	cast('20221001' as datetime)
			, RecordChangeDateTime		=	getdate()
from		(
			values	  ('CREDIT', 'CREDIT' )
					, ('DEBIT' , 'DEBIT')
			) x (Code, TypeName)	
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_Service]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-5242 (cobi-5205) --Objective rename attributes
--Prevtask COBI-5286, hash = -3309298598996678655
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_NORAMOPSDW_dim_Service'
CREATE view [DW].[v_NORAMOPSDW_dim_Service]
as
select		  ServiceCode			= cast(se.ServiceCode_BK							as varchar(100))
			, ServiceGroup			= cast(trim(se.LocalServiceGroup)					as varchar(100))
			, Service				= cast(trim(se.LocalService)						as varchar(100))
			, ServiceCode_BK		= cast(nullif(trim(se.ServiceCode_BK), '')			as varchar(100))		
			, Company_BK			= cast(se.Company_BK								as varchar(50))
			, System_BK				= cast(se.System_BK									as varchar(50))
			, UniqueRecordKey		= utilities.ufn_GetHashedUID('NORAMOPSDW',Company_BK, ServiceCode_BK,default,default)
			, DataAgeHOT			= se.SCD_UpdateDate
			, DataAgeCOLD			= se.SCD_UpdateDate
			, RecordChangeDateTime	= getdate()		
from		CALC.BIRef_Service se
where		System_BK = 'NORAMOPSDW'
and			Company_BK is not null
and			ServiceCode_BK is not null
GO
/****** Object:  View [DW].[v_NORAMOPSDW_dim_ShipmentType]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-5243 (COBI-5206) --Objective rename attributes
--PrevTask COBI-5286, hash = --7138069361757026134
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_NORAMOPSDW_dim_ShipmentType'
CREATE view [DW].[v_NORAMOPSDW_dim_ShipmentType]
as
select 
			  System_BK					= cast(System_BK					as varchar(50))
			, ShipmentType_BK			= cast(ShipmentType_BK				as varchar(50))
			, ShipmentTypeCode			= cast(st.LegacyShipmentTypeCode	as varchar(50))
			, ShipmentType				= cast(st.LegacyShipmentType		as varchar(50))
			, GlobalShipmentTypeCode	= cast(st.ShipmentTypeCode			as varchar(50))
			, GlobalShipmentType		= cast(st.ShipmentType				as varchar(50))
			, UniqueRecordKey			= utilities.ufn_GetHashedUID('NORAMOPSDW',st.ShipmentType_BK,default,default,default)
			, DataAgeHOT				= SCD_UpdateDate
			, DataAgeCOLD				= SCD_UpdateDate
			, RecordChangeDateTime		= getdate()
from		CALC.BIRef_ShipmentType  st
where		st.System_BK = 'NORAMOPSDW'
GO
/****** Object:  View [DW].[v_NORAMOPSDW_fact_File]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-7158 --Objective remove AWB duplicates
--prevtask COBI-7141, hash = -1103274379
--exec utilities.usp_convertviewtoloadcomplex 'DW','v_NORAMOPSDW_fact_File'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_NORAMOPSDW_fact_File'
CREATE view [DW].[v_NORAMOPSDW_fact_File]
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.

as
select		  FileCount								= cast(1 as bigint)
			, ClosingCount							= cast(null 	as bigint)
			, DaysToFirstInvoice					= cast(datediff(day, min(CreateDate_BK), min(FirstInvoiceDate_BK))	as bigint)  							  
			--Dimension_BK
			, [System_BK]							= cast('NORAMOPSDW' as varchar(50))
			, [OperationalSystem_BK]				= cast('NORAMOPSDW' as varchar(50))										
			, [FinanceSystem_BK]					= cast('NORAMOPSDW' as varchar(50))	
			, [OperationalCompany_BK]				= max([OperationalCompany_BK]	)
			, [FinancialCompany_BK]					= max([FinancialCompany_BK]		)
			, [Company_BK]							= max([Company_BK]				)
			, [File_BK]								= File_BK
			--Dates--
			, [CreateDate_BK]						= min(CreateDate_BK)
			, FirstInvoiceDate_BK					= min(FirstInvoiceDate_BK)
			, FirstAccrualDate_BK					= min(FirstAccrualDate_BK)
			, FirstCostDate_BK						= min(FirstCostDate_BK)
			, ActivityCompletedDate_BK				= max(ActivityCompletedDate_BK)
			, FirstClosingDate_BK					= min(FirstClosingDate_BK)
			---LifecycleDay---
			, FirstInvoiceDate_LifecycleDay_BK		= cast(datediff(day, min(CreateDate_BK), min(FirstInvoiceDate_BK)) + 1		as bigint)
			, FirstAccrualDate_LifecycleDay_BK		= cast(datediff(day, min(CreateDate_BK), min(FirstAccrualDate_BK)) + 1			as bigint)
			, FirstCostDate_LifecycleDay_BK			= cast(datediff(day, min(CreateDate_BK), min(FirstCostDate_BK)) + 1			as bigint)
			, ActivityCompletedDate_LifecycleDay_BK	= cast(datediff(day, min(CreateDate_BK), max(ActivityCompletedDate_BK)) + 1	as bigint)
			, FirstClosingDate_LifecycleDay_BK		= cast(datediff(day, min(CreateDate_BK), min(FirstClosingDate_BK )) + 1		as bigint)
			, UniqueRecordKey						= utilities.ufn_GetHashedUID('NORAMOPSDW', File_BK, default, default, default)
			, DataAgeHOT							= max(DataAgeHot)
			, DataAgeCOLD							= max(DataAgeCold)
from (
			select		--Measures
						  ClosingCount							= cast(null					as bigint)
						, [OperationalCompany_BK]				= cast(s.Company_BK			as varchar(50))	
						, [FinancialCompany_BK]					= cast(s.Company_BK			as varchar(50))	
						, [Company_BK]							= cast(s.Company_BK			as varchar(50))	
						, [File_BK]								= s.File_BK
						--Dates--
						, [CreateDate_BK]						= s.CreateDate_BK
						, FirstInvoiceDate_BK					= cast(cv.InvDate			as date)
						, FirstAccrualDate_BK					= cast(null					as date)
						, FirstCostDate_BK						= cast(null					as date)
						, ActivityCompletedDate_BK				= cast(null					as date)
						, FirstClosingDate_BK					= cast(null					as date)
						, DataAgeHOT							= s.DataAgeHOT
						, DataAgeCOLD							= (select max(v) from (values (s.DataAgeCOLD),(cv.SCD_UpdateDate), (inv.SCD_UpdateDate)) as value(v))
			from		ODS.NORAMOPSDW_tblAWBInvoice inv 
			left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam
			on			inv.rowguid_AWB = sam.Slave_RowGuid_AWB
			join		CALC.NORAMOPSDW_Shipment s
			on			isnull(sam.Master_RowGuid_AWB, inv.rowguid_AWB) = s.rowguid_AWB
			join		ODS.NORAMOPSDW_tblAWBCalcValues cv 
			on			cv.rowguid_AWB = s.rowguid_AWB
			and			cv.SCD_ActiveFlag = 1
			and			cv.SCD_IsDeleted = 0
			where		s.CreateDate_BK >= '2018-01-01'
			and			inv.SCD_ActiveFlag = 1
			and			inv.SCD_IsDeleted = 0
			union all
			select		--Measures
						  ClosingCount							= cast(null as bigint)
						, [OperationalCompany_BK]				= cast(s.Company_BK	as varchar(50))	
						, [FinancialCompany_BK]					= cast(s.Company_BK	as varchar(50))	
						, [Company_BK]							= cast(s.Company_BK	as varchar(50))	
						, [File_BK]								= s.File_BK
						--Dates--
						, [CreateDate_BK]						= s.CreateDate_BK
						, FirstInvoiceDate_BK					= cast(cv.InvDate	as date)
						, FirstAccrualDate_BK					= cast(null			as date)
						, FirstCostDate_BK						= cast(cv.InvDate	as date)
						, ActivityCompletedDate_BK				= cast(null			as date)
						, FirstClosingDate_BK					= cast(null			as date)
						, DataAgeHOT							= s.DataAgeHOT
						, DataAgeCOLD							= (select max(v) from (values (s.DataAgeCOLD),(cv.SCD_UpdateDate), (cst.SCD_UpdateDate)) as value(v))
			from		ODS.NORAMOPSDW_tblAWBCost cst  
			left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam
			on			cst.rowguid_AWB = sam.Slave_RowGuid_AWB
			join		CALC.NORAMOPSDW_Shipment s		
			on			isnull(sam.Master_RowGuid_AWB,cst.rowguid_AWB) = s.rowguid_AWB
			join		ODS.NORAMOPSDW_tblAWBCalcValues cv 
			on			cv.rowguid_AWB = s.rowguid_AWB
			and			cv.SCD_ActiveFlag = 1
			and			cv.SCD_IsDeleted = 0
			where		s.CreateDate_BK >= '2018-01-01'
			and			cst.SCD_ActiveFlag = 1
			and			cst.SCD_IsDeleted = 0
			) u
group by 	File_BK
GO
/****** Object:  View [DW].[v_NORAMOPSDW_fact_FileTransaction]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-7330 --Objective FileAmountLocal always have a value
--prevtask COBI-7305, hash = 1724848529
--exec utilities.usp_convertviewtoloadcomplex 'DW','v_NORAMOPSDW_fact_FileTransaction'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_NORAMOPSDW_fact_FileTransaction'
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
CREATE view [DW].[v_NORAMOPSDW_fact_FileTransaction]
as
-- Temporary solution for NORAMOPSDW_tblShipmentParty which is having multiple Part_Bk with same RowID
with NORAMOPSDW_tblShipmentParty 
as (
select		  p.*
			, ix  = row_number() over(partition by p.[RowID] order by p.[LastUpdateDate] desc)
from		ODS.NORAMOPSDW_tblShipmentParty p
where		p.SCD_ActiveFlag = 1
and			p.SCD_IsDeleted = 0
)
select 
			  [FileRevenueTransaction]					=	cast(case when invd.NotDutyOutlayFlag = 1 then 
																			invd.DetailSumUSD
																	   when invd.NotDutyOutlayFlag is null then
																			coalesce(inv.USDInvAmt,inv.InvAmt)
																	   when invd.NotDutyOutlayFlag = 0 then
																			null --NotDutyOutlayFlag = 0 not included 
																	   else  --this should never happen, as flag is (1,0,null)
																			coalesce(inv.USDInvAmt,inv.InvAmt) 
																	  end 															as float)
			, [FileCostTransaction]						=	cast(null																as float) 
			, [FileAmountTransaction]					=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)
																								as float)
			, [FileRevenueLocal]						=	cast(case when invd.NotDutyOutlayFlag = 1 then 
																			invd.DetailSumUSD
																	   when invd.NotDutyOutlayFlag is null then
																			coalesce(inv.USDInvAmt,inv.InvAmt)
																	   when invd.NotDutyOutlayFlag = 0 then
																			null --NotDutyOutlayFlag = 0 not included 
																	   else  --this should never happen, as flag is (1,0,null)
																			coalesce(inv.USDInvAmt,inv.InvAmt) 
																	   end  														as float)
			, [FileCostLocal]							=	cast(null																as float)
			, [FileAmountLocal]							=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)				as float)
			, [FileRevenueTransactionTotal]				=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)									as float)
			, [FileCostTransactionTotal]				=	cast(null																as float) 
			, [FileAmountTransactionTotal]				=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)									as float)
			, [FileRevenueLocalTotal]					=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)									as float)
			, [FileCostLocalTotal]						=	cast(null																as float)
			, [FileAmountLocalTotal]					=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)									as float)			
			, [System_BK]								=	cast('NORAMOPSDW'	as varchar(50))
			, [OperationalSystem_BK]					=	cast('NORAMOPSDW'	as varchar(50))										
			, [FinanceSystem_BK]						=	cast('NORAMOPSDW'	as varchar(50))	
			, [OperationalCompany_BK]					=	s.Company_BK	
			, [FinancialCompany_BK]						=	s.Company_BK	
			, [Company_BK]								=	s.Company_BK	
			, [BaseCurrency_BK]							=	cast(cd.BaseCurrencyCode as varchar(50))
			, [ExchangeRatePeriod_BK]					=	cast(year(try_cast(cast(s.ShipmentDate_BK as varchar) as date)) * 100 + month(try_cast(cast(s.ShipmentDate_BK as varchar) as date))	 as varchar(50))
			, [GlobalShipmentId_BK]						=	s.[GlobalShipmentId_BK]		
			, [LocalShipmentId_BK]						=	s.[LocalShipmentId_BK]		
			, [Currency_BK]								=	cast(isnull(isnull(cur.CurrencyType, cur2.CurrencyType),'USD') as varchar(50))
			, [TurnOverGroup_BK]						=	cast('' as varchar(50))
			, [SetOffLedgerAccount_BK]					=	cast('' as varchar(50))
			, [Department_BK]							=	s.[Department_BK]
			, [Costcenter_BK]							=	s.CostCenter_BK
			, [File_BK]									=	s.File_BK
			, [ExchangeRateCalculationMethod_BK]		=	cast('PnL'	 as varchar(50))
			, [LedgerAccount_BK]						=	cast('' as varchar(50))
			, [CreditorParty_BK]						=	cast('' as varchar(50))
			, [DebtorParty_BK]							=	cast(isnull(dbt.CorrectedParty_BK, sp.Party_BK)		as varchar(100))
			, [CustomerParty_BK]						=	cast(isnull(cstp.CorrectedParty_BK, s.CustomerParty_BK)	as varchar(100))
			, [Date_BK]									=	cast(inv.InvDate as date)
			, [EntryDate_BK]							=	s.CreateDate_BK
			, [VoucherDate_BK]							=	cast(inv.InvDate as date)
			, [FinancialDate_BK]						=	cast(rec.EntryDate as date)
			, [FirstFinancialDate_BK]					=	cast(min(rec.EntryDate) over (partition by s.Company_BK, s.File_BK) as date)
			, [CreateDate_BK]							=	s.CreateDate_BK
			, FileTransactionStatus_BK					=	cast(null as varchar(50))
			, ARP_Account_BK							=	cast(isnull(sp.Party_BK,'') as varchar(50))
			-----LifecycleDay------
			, Date_LifecycleDay_BK						=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, EntryDate_LifecycleDay_BK					=	cast(datediff(day, s.CreateDate_BK, s.CreateDate_BK) + 1 as bigint)
			, VoucherDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, FinancialDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, ShipmentDepartureDate_LifecycleDay_BK		=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDepartureDate_BK) + 1 as bigint)
			, ShipmentArrivalDate_LifecycleDay_BK		=	cast(datediff(day, s.CreateDate_BK, s.ShipmentArrivalDate_BK) + 1 as bigint)
			, MainTransportDepartureDate_LifecycleDay_BK=	cast(datediff(day, s.CreateDate_BK, s.MainTransportDepartureDate_BK) + 1 as bigint)
			, MainTransportArrivalDate_LifecycleDay_BK	=	cast(datediff(day, s.CreateDate_BK, s.MainTransportArrivalDate_BK) + 1 as bigint)
			, ShipmentDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDate_BK) + 1 as bigint)
			, PostingText								=	cast(concat('<no text available>|NORAMOPSDW|revenue|rowguid_AWB=', s.rowguid_AWB,'|rowguid_AWBInvoice=', inv.rowguid_AWBInvoice) as varchar(250))
			, UniqueRecordKey							=	utilities.ufn_GetHashedUID('NORAMOPSDW|revenue|', s.rowguid_AWB, inv.rowguid_AWBInvoice, default, default)
			, DataAgeHOT								=   s.DataAgeHOT
			, DataAgeCOLD								=   (select max(v) from (values (s.DataAgeCOLD), (inv.SCD_UpdateDate), (rec.SCD_UpdateDate), (sp.SCD_UpdateDate), (sam.DataAgeCold)) as value(v))
			, RecordChangeDateTime						=	cast(getdate() as datetime)
from		ODS.NORAMOPSDW_tblAWBInvoice inv 
left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam
on			inv.rowguid_AWB = sam.Slave_RowGuid_AWB
join		CALC.NORAMOPSDW_Shipment s
on			isnull(sam.Master_RowGuid_AWB, inv.rowguid_AWB) = s.rowguid_AWB
left join	(
			select 		  invd.rowguid_AWBInvoice
						--NotDutyOutlayFlag - deliberate choice of flag name, as value 1 -> DetailSumUSD goes into revenue, 0 -> DutyOutlay
						, NotDutyOutlayFlag				= case when ChrgCode in ('DUTY','DUTYA','DUTYC','DUTYO','MPF','HMF','DTY','DUT') then 0 else 1 end 
						, DetailSumUSD					= sum(Amount * ExchRate.ExchRate)
			from		ODS.NORAMOPSDW_tblAWBInvoicedetail invd 
			left join	ODS.NORAMOPSDW_lkpCurrency cur
			on			invd.rowguid_Currency = cur.rowguid_Currency
			and			cur.SCD_ActiveFlag = 1
			and			cur.SCD_IsDeleted = 0
			left join	ODS.NORAMOPSDW_tblAWBInvoice inv
			on			invd.rowguid_AWBInvoice = inv.rowguid_AWBInvoice
			and			inv.SCD_ActiveFlag = 1
			and			inv.SCD_IsDeleted = 0
			outer apply (
						select ExchRate = cast(inv.USDInvAmt as float)/nullif(cast(inv.InvAmt as float),0)
						) ExchRateFromHeader
			outer apply (
						select ExchRate = coalesce(
									 cast(ExchRateFromHeader.ExchRate as float)
									,cast(1.0 as float)
									)
						) ExchRate
			where		1=1
			and			invd.rowguid_AWBInvoice is not null
			and			invd.SCD_ActiveFlag = 1
			and			invd.SCD_IsDeleted = 0
			and			invd.Amount is not null
			group by	  invd.rowguid_AWBInvoice
						, case when ChrgCode in ('DUTY','DUTYA','DUTYC','DUTYO','MPF','HMF','DTY','DUT') then 0 else 1 end 
			) invd
on			invd.rowguid_AWBInvoice = inv.rowguid_AWBInvoice
left join	ODS.NORAMOPSDW_tblAWBRecap rec
on			s.RecapNo = rec.RecapNo
and			s.Company_BK = rec.rowguid_ICO
and			rec.SCD_ActiveFlag = 1
and			rec.SCD_IsDeleted = 0
left join	CALC.BIRef_CompanyDetails cd
on			s.Company_BK = cd.Company_BK
and			cd.System_BK = 'NORAMOPSDW'
left join	ODS.NORAMOPSDW_lkpIcoOption opt 
on			opt.RowGuid_ICO = s.Company_BK
and			opt.OptionName = 'RestrictCurrency'
and			opt.SCD_ActiveFlag = 1
and			opt.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpCurrency cur 
on			cur.rowguid_Currency = inv.rowguid_Currency
and			cur.SCD_ActiveFlag = 1
and			cur.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpCurrency cur2 
on			cur2.LinkServer = inv.LinkServer 
and			cur2.CurrencyID = opt.OptionValue
and			cur2.SCD_ActiveFlag = 1
and			cur2.SCD_IsDeleted = 0
left join	NORAMOPSDW_tblShipmentParty sp
on			sp.RowID = inv.rowguid_Customer
and			sp.ix = 1
left join	CALC.NORAMOPSDW_Party dbt
on 			dbt.OriginalParty_BK	=	sp.Party_BK
left join	CALC.NORAMOPSDW_Party cstp
on 			cstp.OriginalParty_BK	=	s.CustomerParty_BK
where 		inv.SCD_ActiveFlag = 1
and			inv.SCD_IsDeleted = 0
union all
select 
			  [FileRevenueTransaction]					=	cast(null						as float)
			, [FileCostTransaction]						=	cast(isnull(case when cst.ChrgCode not in ('DUTY','DUTYA','DUTYC','DUTYO','MPF','HMF','DTY','DUT') then cst.Amount else 0 end,0)		as float) 
			, [FileAmountTransaction]					=	cast(isnull(cst.Amount ,0)		as float)  * -1
			, [FileRevenueLocal]						=	cast(null						as float)
			, [FileCostLocal]							=	cast(isnull(case when cst.ChrgCode not in ('DUTY','DUTYA','DUTYC','DUTYO','MPF','HMF','DTY','DUT') then cst.Amount else 0 end,0)		as float)
			, [FileAmountLocal]							=	cast(isnull(cst.Amount ,0)		as float)  * -1
			, [FileRevenueTransactionTotal]				=	cast(null						as float)
			, [FileCostTransactionTotal]				=	cast(isnull(cst.Amount,0)		as float) 
			, [FileAmountTransactionTotal]				=	cast(isnull(cst.Amount,0)		as float)  * -1
			, [FileRevenueLocalTotal]					=	cast(null						as float)
			, [FileCostLocalTotal]						=	cast(isnull(cst.Amount,0)		as float)
			, [FileAmountLocalTotal]					=	cast(isnull(cst.Amount,0)		as float)  * -1
			, [System_BK]								=	cast('NORAMOPSDW' as varchar(50))
			, [OperationalSystem_BK]					=	cast('NORAMOPSDW' as varchar(50))										
			, [FinanceSystem_BK]						=	cast('NORAMOPSDW' as varchar(50))	
			, [OperationalCompany_BK]					=	s.Company_BK	
			, [FinancialCompany_BK]						=	s.Company_BK	
			, [Company_BK]								=	s.Company_BK	
			, [BaseCurrency_BK]							=	cast(cd.BaseCurrencyCode as varchar(50))
			, [ExchangeRatePeriod_BK]					=	cast(year(try_cast(cast(s.ShipmentDate_BK as varchar) as date)) * 100 + month(try_cast(cast(s.ShipmentDate_BK as varchar) as date))	 as varchar(50))
			, [GlobalShipmentId_BK]						=	s.[GlobalShipmentId_BK]		
			, [LocalShipmentId_BK]						=	s.[LocalShipmentId_BK]		
			, [Currency_BK]								=	cast(isnull( cur2.CurrencyType,'USD') as varchar(50))
			, [TurnOverGroup_BK]						=	cast('' as varchar(50))
			, [SetOffLedgerAccount_BK]					=	cast('' as varchar(50))
			, [Department_BK]							=	s.[Department_BK]
			, [Costcenter_BK]							=	cast('' as varchar(50))
			, [File_BK]									=	s.File_BK
			, [ExchangeRateCalculationMethod_BK]		=	cast('PnL'	 as varchar(50))
			, [LedgerAccount_BK]						=	cast('' as varchar(50))
			, [CreditorParty_BK]						=	cast(isnull(crd.CorrectedParty_BK, sp.Party_BK)		as varchar(100))
			, [DebtorParty_BK]							=	cast('' as varchar(50))
			, [CustomerParty_BK]						=	cast(isnull(cstp.CorrectedParty_BK, s.CustomerParty_BK)	as varchar(100))
			, [Date_BK]									=	cast(inv.InvDate as date)
			, [EntryDate_BK]							=	s.CreateDate_BK
			, [VoucherDate_BK]							=	cast(inv.InvDate as date)
			, [FinancialDate_BK]						=	cast(rec.EntryDate as date)
			, [FirstFinancialDate_BK]					=	cast(min(rec.EntryDate) over (partition by s.Company_BK, s.File_BK) as date)
			, [CreateDate_BK]							=	s.CreateDate_BK
			, FileTransactionStatus_BK					=	cast(null as varchar)
			, ARP_Account_BK							=	cast(isnull(sp.Party_BK,'') as varchar(50))
			-----LifecycleDay------
			, Date_LifecycleDay_BK						=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, EntryDate_LifecycleDay_BK					=	cast(datediff(day, s.CreateDate_BK, s.CreateDate_BK) + 1 as bigint)
			, VoucherDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, FinancialDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, ShipmentDepartureDate_LifecycleDay_BK		=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDepartureDate_BK) + 1 as bigint)
			, ShipmentArrivalDate_LifecycleDay_BK		=	cast(datediff(day, s.CreateDate_BK, s.ShipmentArrivalDate_BK) + 1 as bigint)
			, MainTransportDepartureDate_LifecycleDay_BK=	cast(datediff(day, s.CreateDate_BK, s.MainTransportDepartureDate_BK) + 1 as bigint)
			, MainTransportArrivalDate_LifecycleDay_BK	=	cast(datediff(day, s.CreateDate_BK, s.MainTransportArrivalDate_BK) + 1 as bigint)
			, ShipmentDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDate_BK) + 1 as bigint)
			, PostingText								=	cast(concat('<no text available>|NORAMOPSDW|cost|rowguid_AWB=', s.rowguid_AWB,'|rowguid_AWBCost=',cst.rowguid_AWBCost) as varchar(250))
			, UniqueRecordKey							=	utilities.ufn_GetHashedUID('NORAMOPSDW|cost|', s.rowguid_AWB, cst.rowguid_AWBCost, default, default)
			, DataAgeHOT								=	s.DataAgeHOT
			, DataAgeCOLD								=	(select max(v) from (values (s.DataAgeCOLD), (cst.SCD_UpdateDate), (rec.SCD_UpdateDate), (sp.SCD_UpdateDate), (sam.DataAgeCold)) as value(v))
			, RecordChangeDateTime						=	cast(getdate() as datetime)
from		ODS.NORAMOPSDW_tblAWBCost cst  
left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam
on			cst.rowguid_AWB = sam.Slave_RowGuid_AWB
join		CALC.NORAMOPSDW_Shipment s		
on			isnull(sam.Master_RowGuid_AWB,cst.rowguid_AWB) = s.rowguid_AWB
left join	ODS.NORAMOPSDW_tblAWBRecap rec
on			s.RecapNo = rec.RecapNo
and			s.Company_BK = rec.rowguid_ICO
and			rec.SCD_ActiveFlag = 1
and			rec.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpIcoOption opt 
on			opt.RowGuid_ICO = s.Company_BK
and			opt.OptionName = 'RestrictCurrency'
and			opt.SCD_ActiveFlag = 1
and			opt.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpCurrency cur2 
on			cur2.LinkServer = s.LinkServer 
and			cur2.CurrencyID = opt.OptionValue
and			cur2.SCD_ActiveFlag = 1
and			cur2.SCD_IsDeleted = 0
left join (
			select		  inv.InvDate
						, inv.rowguid_AWB
						, inv.rowguid_Customer
						, ix					=	row_number() over(partition by inv.rowguid_AWB  order by InvDate) 
			from		ODS.NORAMOPSDW_tblAWBInvoice inv
			where 		SCD_ActiveFlag	= 1
			and			SCD_IsDeleted	= 0
			and			inv.InvDate is not null
			) inv
on			inv.rowguid_AWB = s.rowguid_AWB
and			inv.ix = 1
left join	NORAMOPSDW_tblShipmentParty sp
on			sp.RowID = cst.rowguid_Vendor
and			sp.ix = 1 
left join	CALC.BIRef_CompanyDetails cd
on			s.Company_BK = cd.Company_BK
and			cd.System_BK = 'NORAMOPSDW'
left join	CALC.NORAMOPSDW_Party crd
on 			crd.OriginalParty_BK	=	sp.Party_BK
left join	CALC.NORAMOPSDW_Party cstp
on 			cstp.OriginalParty_BK	=	s.CustomerParty_BK
where		cast(inv.InvDate as date) >= '2018-01-01'
and			cst.SCD_ActiveFlag = 1
and			cst.SCD_IsDeleted = 0

GO
/****** Object:  View [DW].[v_NORAMOPSDW_fact_FileTransaction_AG_DEBUG_20260611]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [DW].[v_NORAMOPSDW_fact_FileTransaction_AG_DEBUG_20260611]
as
-- Temporary solution for NORAMOPSDW_tblShipmentParty which is having multiple Part_Bk with same RowID
with NORAMOPSDW_tblShipmentParty 
as (
select		  p.*
			, ix  = row_number() over(partition by p.[RowID] order by p.[LastUpdateDate] desc)
from		ODS.NORAMOPSDW_tblShipmentParty p
where		p.SCD_ActiveFlag = 1
and			p.SCD_IsDeleted = 0
)
select 
			  [FileRevenueTransaction]					=	cast(case when invd.NotDutyOutlayFlag = 1 then 
																			invd.DetailSumUSD
																	   when invd.NotDutyOutlayFlag is null then
																			coalesce(inv.USDInvAmt,inv.InvAmt)
																	   when invd.NotDutyOutlayFlag = 0 then
																			null --NotDutyOutlayFlag = 0 not included 
																	   else  --this should never happen, as flag is (1,0,null)
																			coalesce(inv.USDInvAmt,inv.InvAmt) 
																	  end 															as float)
			, [FileCostTransaction]						=	cast(null																as float) 
			, [FileAmountTransaction]					=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)
																								as float)
			, [FileRevenueLocal]						=	cast(case when invd.NotDutyOutlayFlag = 1 then 
																			invd.DetailSumUSD
																	   when invd.NotDutyOutlayFlag is null then
																			coalesce(inv.USDInvAmt,inv.InvAmt)
																	   when invd.NotDutyOutlayFlag = 0 then
																			null --NotDutyOutlayFlag = 0 not included 
																	   else  --this should never happen, as flag is (1,0,null)
																			coalesce(inv.USDInvAmt,inv.InvAmt) 
																	   end  														as float)
			, [FileCostLocal]							=	cast(null																as float)
			, [FileAmountLocal]							=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)				as float)
			, [FileRevenueTransactionTotal]				=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)									as float)
			, [FileCostTransactionTotal]				=	cast(null																as float) 
			, [FileAmountTransactionTotal]				=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)									as float)
			, [FileRevenueLocalTotal]					=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)									as float)
			, [FileCostLocalTotal]						=	cast(null																as float)
			, [FileAmountLocalTotal]					=	cast(coalesce(invd.DetailSumUSD,inv.USDInvAmt,inv.InvAmt)									as float)			
			, [System_BK]								=	cast('NORAMOPSDW'	as varchar(50))
			, [OperationalSystem_BK]					=	cast('NORAMOPSDW'	as varchar(50))										
			, [FinanceSystem_BK]						=	cast('NORAMOPSDW'	as varchar(50))	
			, [OperationalCompany_BK]					=	s.Company_BK	
			, [FinancialCompany_BK]						=	s.Company_BK	
			, [Company_BK]								=	s.Company_BK	
			, [BaseCurrency_BK]							=	cast(cd.BaseCurrencyCode as varchar(50))
			, [ExchangeRatePeriod_BK]					=	cast(year(try_cast(cast(s.ShipmentDate_BK as varchar) as date)) * 100 + month(try_cast(cast(s.ShipmentDate_BK as varchar) as date))	 as varchar(50))
			, [GlobalShipmentId_BK]						=	s.[GlobalShipmentId_BK]		
			, [LocalShipmentId_BK]						=	s.[LocalShipmentId_BK]		
			, [Currency_BK]								=	cast(isnull(isnull(cur.CurrencyType, cur2.CurrencyType),'USD') as varchar(50))
			, [TurnOverGroup_BK]						=	cast('' as varchar(50))
			, [SetOffLedgerAccount_BK]					=	cast('' as varchar(50))
			, [Department_BK]							=	s.[Department_BK]
			, [Costcenter_BK]							=	s.CostCenter_BK
			, [File_BK]									=	s.File_BK
			, [ExchangeRateCalculationMethod_BK]		=	cast('PnL'	 as varchar(50))
			, [LedgerAccount_BK]						=	cast('' as varchar(50))
			, [CreditorParty_BK]						=	cast('' as varchar(50))
			, [DebtorParty_BK]							=	cast(isnull(dbt.CorrectedParty_BK, sp.Party_BK)		as varchar(100))
			, [CustomerParty_BK]						=	cast(isnull(cstp.CorrectedParty_BK, s.CustomerParty_BK)	as varchar(100))
			, [Date_BK]									=	cast(inv.InvDate as date)
			, [EntryDate_BK]							=	s.CreateDate_BK
			, [VoucherDate_BK]							=	cast(inv.InvDate as date)
			, [FinancialDate_BK]						=	cast(rec.EntryDate as date)
			, [FirstFinancialDate_BK]					=	cast(min(rec.EntryDate) over (partition by s.Company_BK, s.File_BK) as date)
			, [CreateDate_BK]							=	s.CreateDate_BK
			, FileTransactionStatus_BK					=	cast(null as varchar(50))
			, ARP_Account_BK							=	cast(isnull(sp.Party_BK,'') as varchar(50))
			-----LifecycleDay------
			, Date_LifecycleDay_BK						=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, EntryDate_LifecycleDay_BK					=	cast(datediff(day, s.CreateDate_BK, s.CreateDate_BK) + 1 as bigint)
			, VoucherDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, FinancialDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, ShipmentDepartureDate_LifecycleDay_BK		=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDepartureDate_BK) + 1 as bigint)
			, ShipmentArrivalDate_LifecycleDay_BK		=	cast(datediff(day, s.CreateDate_BK, s.ShipmentArrivalDate_BK) + 1 as bigint)
			, MainTransportDepartureDate_LifecycleDay_BK=	cast(datediff(day, s.CreateDate_BK, s.MainTransportDepartureDate_BK) + 1 as bigint)
			, MainTransportArrivalDate_LifecycleDay_BK	=	cast(datediff(day, s.CreateDate_BK, s.MainTransportArrivalDate_BK) + 1 as bigint)
			, ShipmentDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDate_BK) + 1 as bigint)
			, PostingText								=	cast(concat('<no text available>|NORAMOPSDW|revenue|rowguid_AWB=', s.rowguid_AWB,'|rowguid_AWBInvoice=', inv.rowguid_AWBInvoice) as varchar(250))
			, UniqueRecordKey							=	utilities.ufn_GetHashedUID('NORAMOPSDW|revenue|', s.rowguid_AWB, inv.rowguid_AWBInvoice, default, default)
			, DataAgeHOT								=   s.DataAgeHOT
			, DataAgeCOLD								=   (select max(v) from (values (s.DataAgeCOLD), (inv.SCD_UpdateDate), (rec.SCD_UpdateDate), (sp.SCD_UpdateDate), (sam.DataAgeCold)) as value(v))
			, RecordChangeDateTime						=	cast(getdate() as datetime)
from		ODS.NORAMOPSDW_tblAWBInvoice inv 
left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam
on			inv.rowguid_AWB = sam.Slave_RowGuid_AWB
join		CALC.NORAMOPSDW_Shipment s
on			isnull(sam.Master_RowGuid_AWB, inv.rowguid_AWB) = s.rowguid_AWB
left join	(
			select 		  invd.rowguid_AWBInvoice
						--NotDutyOutlayFlag - deliberate choice of flag name, as value 1 -> DetailSumUSD goes into revenue, 0 -> DutyOutlay
						, NotDutyOutlayFlag				= case when ChrgCode in ('DUTY','DUTYA','DUTYC','DUTYO','MPF','HMF','DTY','DUT') then 0 else 1 end 
						, DetailSumUSD					= sum(Amount * ExchRate.ExchRate)
			from		ODS.NORAMOPSDW_tblAWBInvoicedetail invd 
			left join	ODS.NORAMOPSDW_lkpCurrency cur
			on			invd.rowguid_Currency = cur.rowguid_Currency
			and			cur.SCD_ActiveFlag = 1
			and			cur.SCD_IsDeleted = 0
			left join	ODS.NORAMOPSDW_tblAWBInvoice inv
			on			invd.rowguid_AWBInvoice = inv.rowguid_AWBInvoice
			and			inv.SCD_ActiveFlag = 1
			and			inv.SCD_IsDeleted = 0
			outer apply (
						select ExchRate = cast(inv.USDInvAmt as float)/nullif(cast(inv.InvAmt as float),0)
						) ExchRateFromHeader
			outer apply (
						select ExchRate = coalesce(
									 cast(ExchRateFromHeader.ExchRate as float)
									,cast(1.0 as float)
									)
						) ExchRate
			where		1=1
			and			invd.rowguid_AWBInvoice is not null
			and			invd.SCD_ActiveFlag = 1
			and			invd.SCD_IsDeleted = 0
			and			invd.Amount is not null
			group by	  invd.rowguid_AWBInvoice
						, case when ChrgCode in ('DUTY','DUTYA','DUTYC','DUTYO','MPF','HMF','DTY','DUT') then 0 else 1 end 
			) invd
on			invd.rowguid_AWBInvoice = inv.rowguid_AWBInvoice
left join	ODS.NORAMOPSDW_tblAWBRecap rec
on			s.RecapNo = rec.RecapNo
and			s.Company_BK = rec.rowguid_ICO
and			rec.SCD_ActiveFlag = 1
and			rec.SCD_IsDeleted = 0
left join	CALC.BIRef_CompanyDetails cd
on			s.Company_BK = cd.Company_BK
and			cd.System_BK = 'NORAMOPSDW'
left join	ODS.NORAMOPSDW_lkpIcoOption opt 
on			opt.RowGuid_ICO = s.Company_BK
and			opt.OptionName = 'RestrictCurrency'
and			opt.SCD_ActiveFlag = 1
and			opt.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpCurrency cur 
on			cur.rowguid_Currency = inv.rowguid_Currency
and			cur.SCD_ActiveFlag = 1
and			cur.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpCurrency cur2 
on			cur2.LinkServer = inv.LinkServer 
and			cur2.CurrencyID = opt.OptionValue
and			cur2.SCD_ActiveFlag = 1
and			cur2.SCD_IsDeleted = 0
left join	NORAMOPSDW_tblShipmentParty sp
on			sp.RowID = inv.rowguid_Customer
and			sp.ix = 1
left join	CALC.NORAMOPSDW_Party dbt
on 			dbt.OriginalParty_BK	=	sp.Party_BK
left join	CALC.NORAMOPSDW_Party cstp
on 			cstp.OriginalParty_BK	=	s.CustomerParty_BK
where 		inv.SCD_ActiveFlag = 1
and			inv.SCD_IsDeleted = 0
--and			coalesce(nullif(invd.DetailSumUSD,0),nullif(inv.USDInvAmt,0),nullif(inv.InvAmt,0)) is not null
union all
select 
			  [FileRevenueTransaction]					=	cast(null						as float)
			, [FileCostTransaction]						=	cast(isnull(case when cst.ChrgCode not in ('DUTY','DUTYA','DUTYC','DUTYO','MPF','HMF','DTY','DUT') then cst.Amount else 0 end,0)		as float) 
			, [FileAmountTransaction]					=	cast(isnull(cst.Amount ,0)		as float)  * -1
			, [FileRevenueLocal]						=	cast(null						as float)
			, [FileCostLocal]							=	cast(isnull(case when cst.ChrgCode not in ('DUTY','DUTYA','DUTYC','DUTYO','MPF','HMF','DTY','DUT') then cst.Amount else 0 end,0)		as float)
			, [FileAmountLocal]							=	cast(isnull(cst.Amount ,0)		as float)  * -1
			, [FileRevenueTransactionTotal]				=	cast(null						as float)
			, [FileCostTransactionTotal]				=	cast(isnull(cst.Amount,0)		as float) 
			, [FileAmountTransactionTotal]				=	cast(isnull(cst.Amount,0)		as float)  * -1
			, [FileRevenueLocalTotal]					=	cast(null						as float)
			, [FileCostLocalTotal]						=	cast(isnull(cst.Amount,0)		as float)
			, [FileAmountLocalTotal]					=	cast(isnull(cst.Amount,0)		as float)  * -1
			, [System_BK]								=	cast('NORAMOPSDW' as varchar(50))
			, [OperationalSystem_BK]					=	cast('NORAMOPSDW' as varchar(50))										
			, [FinanceSystem_BK]						=	cast('NORAMOPSDW' as varchar(50))	
			, [OperationalCompany_BK]					=	s.Company_BK	
			, [FinancialCompany_BK]						=	s.Company_BK	
			, [Company_BK]								=	s.Company_BK	
			, [BaseCurrency_BK]							=	cast(cd.BaseCurrencyCode as varchar(50))
			, [ExchangeRatePeriod_BK]					=	cast(year(try_cast(cast(s.ShipmentDate_BK as varchar) as date)) * 100 + month(try_cast(cast(s.ShipmentDate_BK as varchar) as date))	 as varchar(50))
			, [GlobalShipmentId_BK]						=	s.[GlobalShipmentId_BK]		
			, [LocalShipmentId_BK]						=	s.[LocalShipmentId_BK]		
			, [Currency_BK]								=	cast(isnull( cur2.CurrencyType,'USD') as varchar(50))
			, [TurnOverGroup_BK]						=	cast('' as varchar(50))
			, [SetOffLedgerAccount_BK]					=	cast('' as varchar(50))
			, [Department_BK]							=	s.[Department_BK]
			, [Costcenter_BK]							=	cast('' as varchar(50))
			, [File_BK]									=	s.File_BK
			, [ExchangeRateCalculationMethod_BK]		=	cast('PnL'	 as varchar(50))
			, [LedgerAccount_BK]						=	cast('' as varchar(50))
			, [CreditorParty_BK]						=	cast(isnull(crd.CorrectedParty_BK, sp.Party_BK)		as varchar(100))
			, [DebtorParty_BK]							=	cast('' as varchar(50))
			, [CustomerParty_BK]						=	cast(isnull(cstp.CorrectedParty_BK, s.CustomerParty_BK)	as varchar(100))
			, [Date_BK]									=	cast(inv.InvDate as date)
			, [EntryDate_BK]							=	s.CreateDate_BK
			, [VoucherDate_BK]							=	cast(inv.InvDate as date)
			, [FinancialDate_BK]						=	cast(rec.EntryDate as date)
			, [FirstFinancialDate_BK]					=	cast(min(rec.EntryDate) over (partition by s.Company_BK, s.File_BK) as date)
			, [CreateDate_BK]							=	s.CreateDate_BK
			, FileTransactionStatus_BK					=	cast(null as varchar)
			, ARP_Account_BK							=	cast(isnull(sp.Party_BK,'') as varchar(50))
			-----LifecycleDay------
			, Date_LifecycleDay_BK						=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, EntryDate_LifecycleDay_BK					=	cast(datediff(day, s.CreateDate_BK, s.CreateDate_BK) + 1 as bigint)
			, VoucherDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, FinancialDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, inv.InvDate) + 1 as bigint)
			, ShipmentDepartureDate_LifecycleDay_BK		=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDepartureDate_BK) + 1 as bigint)
			, ShipmentArrivalDate_LifecycleDay_BK		=	cast(datediff(day, s.CreateDate_BK, s.ShipmentArrivalDate_BK) + 1 as bigint)
			, MainTransportDepartureDate_LifecycleDay_BK=	cast(datediff(day, s.CreateDate_BK, s.MainTransportDepartureDate_BK) + 1 as bigint)
			, MainTransportArrivalDate_LifecycleDay_BK	=	cast(datediff(day, s.CreateDate_BK, s.MainTransportArrivalDate_BK) + 1 as bigint)
			, ShipmentDate_LifecycleDay_BK				=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDate_BK) + 1 as bigint)
			, PostingText								=	cast(concat('<no text available>|NORAMOPSDW|cost|rowguid_AWB=', s.rowguid_AWB,'|rowguid_AWBCost=',cst.rowguid_AWBCost) as varchar(250))
			, UniqueRecordKey							=	utilities.ufn_GetHashedUID('NORAMOPSDW|cost|', s.rowguid_AWB, cst.rowguid_AWBCost, default, default)
			, DataAgeHOT								=	s.DataAgeHOT
			, DataAgeCOLD								=	(select max(v) from (values (s.DataAgeCOLD), (cst.SCD_UpdateDate), (rec.SCD_UpdateDate), (sp.SCD_UpdateDate), (sam.DataAgeCold)) as value(v))
			, RecordChangeDateTime						=	cast(getdate() as datetime)
from		ODS.NORAMOPSDW_tblAWBCost cst  
left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam
on			cst.rowguid_AWB = sam.Slave_RowGuid_AWB
join		CALC.NORAMOPSDW_Shipment s		
on			isnull(sam.Master_RowGuid_AWB,cst.rowguid_AWB) = s.rowguid_AWB
left join	ODS.NORAMOPSDW_tblAWBRecap rec
on			s.RecapNo = rec.RecapNo
and			s.Company_BK = rec.rowguid_ICO
and			rec.SCD_ActiveFlag = 1
and			rec.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpIcoOption opt 
on			opt.RowGuid_ICO = s.Company_BK
and			opt.OptionName = 'RestrictCurrency'
and			opt.SCD_ActiveFlag = 1
and			opt.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpCurrency cur2 
on			cur2.LinkServer = s.LinkServer 
and			cur2.CurrencyID = opt.OptionValue
and			cur2.SCD_ActiveFlag = 1
and			cur2.SCD_IsDeleted = 0
left join (
			select		  inv.InvDate
						, inv.rowguid_AWB
						, inv.rowguid_Customer
						, ix					=	row_number() over(partition by inv.rowguid_AWB  order by InvDate) 
			from		ODS.NORAMOPSDW_tblAWBInvoice inv
			where 		SCD_ActiveFlag	= 1
			and			SCD_IsDeleted	= 0
			and			inv.InvDate is not null
			) inv
on			inv.rowguid_AWB = s.rowguid_AWB
and			inv.ix = 1
left join	NORAMOPSDW_tblShipmentParty sp
on			sp.RowID = cst.rowguid_Vendor
and			sp.ix = 1 
left join	CALC.BIRef_CompanyDetails cd
on			s.Company_BK = cd.Company_BK
and			cd.System_BK = 'NORAMOPSDW'
left join	CALC.NORAMOPSDW_Party crd
on 			crd.OriginalParty_BK	=	sp.Party_BK
left join	CALC.NORAMOPSDW_Party cstp
on 			cstp.OriginalParty_BK	=	s.CustomerParty_BK
where		cast(inv.InvDate as date) >= '2018-01-01'
and			cst.SCD_ActiveFlag = 1
and			cst.SCD_IsDeleted = 0

GO
/****** Object:  View [DW].[v_NORAMOPSDW_fact_Invoice]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-7398 --Objective PaymentTerm_BK
--prevtask COBI-7305, hash = 1936639577
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_NORAMOPSDW_fact_Invoice'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_NORAMOPSDW_fact_Invoice'
CREATE       view [DW].[v_NORAMOPSDW_fact_Invoice]
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
as
select		--Measures--------------------------------------------------------------
			  DocumentCount						=	try_cast(1																							as bigint) 
			, InvoiceCount						=	try_cast(ai.InvoiceCount																			as bigint)
			, InvoiceCountNet					=	try_cast(ai.InvoiceCountNet																			as bigint)
			, PaymentDays						=	try_cast(coalesce(ai.TermsPayDays, 0)																as int)
			--Dimension Business Keys-----------------------------------------------
			, System_BK							=	cast('NORAMOPSDW'																					as varchar(10))
			, OperationalSystem_BK				=	cast('NORAMOPSDW'																					as varchar(10))
			, FinanceSystem_BK					=	cast('NORAMOPSDW'																					as varchar(10))
			, Company_BK						=	cast(case when trim(s.Company_BK)		= '' then 'NAHQ' else trim(s.Company_BK)	end				as varchar(50))
			, OperationalCompany_BK				=	cast(case when trim(s.Company_BK)		= '' then 'NAHQ' else trim(s.Company_BK)	end				as varchar(50))
			, FinancialCompany_BK				=	cast(case when trim(s.Company_BK)		= '' then 'NAHQ' else trim(s.Company_BK)	end				as varchar(50))
			, Currency_BK						=	cast(s.Currency_BK																					as varchar(3))
			, File_BK							=	cast(s.File_BK																						as varchar(50))
			, Department_BK						=	cast(s.Department_BK																				as varchar(50))
			, CostCenter_BK						=	cast(s.CostCenter_BK																				as varchar(50))
			, InvoiceId_BK						=	cast(ai.rowguid_AWBInvoice																			as varchar(50))
			, InvoiceType_BK					=	cast(ai.rowguid_InvoiceType																			as varchar(50))
			, GlobalShipmentId_BK				=	cast(s.GlobalShipmentId_BK																			as varchar(150))
			, LocalShipmentId_BK				=	cast(s.LocalShipmentId_BK																			as varchar(50))
			, InvoicePaymentTerm_IntervalDay_BK	=	cast(ai.TermsPayDays																				as int)
			, PaymentTerm_BK					=	cast(ai.TermsCode																					as varchar(50))
			, ExchangeRateCalculationMethod_BK	=	cast('PnL'																							as varchar(3))
			, DebtorParty_BK					=	cast(isnull(dbt.CorrectedParty_BK, bc.CustomerParty_BK)												as varchar(100))
			, CustomerParty_BK					=	cast(isnull(cstp.CorrectedParty_BK,s.CustomerParty_BK)												as varchar(100))
			, ARP_Account_BK					=	cast(nullif(bc.CustomerParty_BK, '')																as varchar(50))
			--Date BK's--------------------------------------------------------------
			, InvoiceDate_BK					=	try_cast(ai.InvDate																					as date)
			, DueDate_BK						=	try_cast(ai.DueDate																					as date)
			, PrintDate_BK						=	try_cast(ai.LockedDateTime																			as date)
			, Date_BK							=	try_cast(ai.InvDate																					as date)
			, FinancialDate_BK					=	try_cast(ai.InvDate																					as date)
			, Voucher_BK						=	cast(ai.InvoiceId_BK																				as varchar(50))
			, CreateDate_BK						=	s.CreateDate_BK			
			, UniqueRecordKey					=	utilities.ufn_GetHashedUID('NORAMOPSDW', s.[Company_BK], ai.[InvoiceId_BK], default, default)
			, DataAgeHOT						=	ai.SCD_UpdateDate
			, DataAgeCOLD						=	(select max(v) from (values (s.DataAgeCOLD), (ai.SCD_UpdateDate), (bc.SCD_UpdateDate), (sam.DataAgeCold)) as value(v))
			, RecordChangeDateTime				=	cast(getdate() as datetime)
from		ODS.NORAMOPSDW_tblAWBInvoice as ai
left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam
on			ai.rowguid_AWB = sam.Slave_Rowguid_AWB
join		CALC.NORAMOPSDW_Shipment s
on			s.rowguid_AWB = isnull(sam.Master_RowGuid_AWB,ai.rowguid_AWB)	
left join	ODS.NORAMOPSDW_tblCustomer as bc 
on			ai.Rowguid_Customer = bc.Rowguid_Customer
and			bc.SCD_ActiveFlag = 1
and			bc.SCD_IsDeleted = 0	
left join	CALC.NORAMOPSDW_Party dbt
on 			dbt.OriginalParty_BK	=	bc.CustomerParty_BK
left join	CALC.NORAMOPSDW_Party cstp
on 			cstp.OriginalParty_BK	=	s.CustomerParty_BK
where 		ai.SCD_ActiveFlag = 1
and			ai.SCD_IsDeleted = 0
and			try_cast(ai.InvDate as date) >= '2018-01-01'
GO
/****** Object:  View [DW].[v_NORAMOPSDW_fact_InvoiceTransaction]    Script Date: 7/29/2026 1:46:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-7398 --Objective add PaymentTerm_BK
--prevtask COBI-7305, hash = -214334241
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_NORAMOPSDW_fact_InvoiceTransaction'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_NORAMOPSDW_fact_InvoiceTransaction'
CREATE   view [DW].[v_NORAMOPSDW_fact_InvoiceTransaction]
--ROWGUIDs from NORAMOPSDW are used, though those are generated inside NORAMOPSDW and not in TGOPS. We assess the risk of ROW_GUIDs changing as small.
as 
select		--Measures--------------------------------------------------------------
			  InvoicedAmountTransaction			=	try_cast(coalesce(aid.Amount, 0)				as float)
			, VatAmountTransaction				=	try_cast(aid.TaxAndDutyAmountTransaction_BI		as float)
			, DocumentAmountTransaction			=	try_cast(aid.DocumentAmountTransaction_BI		as float)
			, InvoicedAmountLocal				=	try_cast(coalesce(aid.Amount, 0)				as float)
			, VatAmountLocal					=	try_cast(aid.TaxAndDutyAmountTransaction_BI		as float)
			, DocumentAmountLocal				=	try_cast(aid.DocumentAmountTransaction_BI		as float)	
			, TransactionCount					=	try_cast(1										as bigint)
			, OriginalVoucher					=	cast(ai.InvoiceId_BK							as varchar(50)) 
			, LineNumber						=	cast(null										as varchar(50)) 
			, ChargeLineCode					=	cast(nullif(aid.ChrgCode,'')					as varchar(50))
			, ChargeLineText					=	cast(nullif(aid.ChrgDesc,'')					as varchar(250))	
			--Dimension Business Keys-----------------------------------------------
			, System_BK							=	cast('NORAMOPSDW'								as varchar(50))
			, OperationalSystem_BK				=	cast('NORAMOPSDW'								as varchar(50))
			, FinanceSystem_BK					=	cast('NORAMOPSDW'								as varchar(50))
			, Company_BK						=	cast(s.Company_BK								as varchar(50))
			, OperationalCompany_BK				=	cast(s.Company_Bk								as varchar(50))
			, FinancialCompany_BK				=	cast(s.Company_Bk								as varchar(50))
			, BaseCurrency_BK					=	cast(coalesce(cur.CurrencyType, cur2.CurrencyType, 'USD')		as varchar(50))
			, ExchangeRatePeriod_BK				=	try_cast(year(try_cast(cast(ai.InvDate as varchar) as date)) * 100 + month(try_cast(cast(ai.InvDate as varchar) as date))	as varchar(50))
			, Currency_BK						=	cast(coalesce(cur.CurrencyType, cur2.CurrencyType, 'USD')		as varchar(50))
			, Department_BK						=	cast(s.Department_BK							as varchar(50))
			, File_BK							=	cast(s.File_BK									as varchar(50))
			, TurnoverGroup_BK					=	cast(null										as varchar(50))
			, Item_BK							=	cast(chrg.rowguid_ChargeCode					as varchar(100))
			, LedgerAccount_BK					=	cast(null										as varchar(50))
			, SetOffLedgerAccount_BK			=	cast(null										as varchar(50))
			, CostCenter_BK						=	cast(s.CostCenter_BK							as varchar(50))
			, SetOffCostCenter_BK				=	cast(null										as varchar(50))
			, InvoiceId_BK						=	cast(ai.rowguid_AWBInvoice						as varchar(50))
			, InvoiceType_BK					=	cast(ai.rowguid_InvoiceType						as varchar(50))	
			, GlobalShipmentId_BK				=	s.GlobalShipmentId_BK
			, LocalShipmentId_BK				=	cast(s.LocalShipmentId_BK						as varchar(50))
			, InvoicePaymentTerm_IntervalDay_BK	=	cast(ai.TermsPayDays							as int)
			, PaymentTerm_BK					=	cast(ai.TermsCode								as varchar(50))
			, ExchangeRateCalculationMethod_BK	=	cast( 'PnL'										as varchar(50))
			, VatReason_BK						=	cast(null										as varchar(50))
			, DebtorParty_BK					=	cast(isnull(dbt.CorrectedParty_BK, bc.CustomerParty_BK)	as varchar(100))
			, CustomerParty_BK					=	cast(isnull(cstp.CorrectedParty_BK, s.CustomerParty_BK)	as varchar(100))
			, ARP_Account_BK					=	cast(nullif(bc.CustomerParty_BK, '')			as varchar(50))
			--Date BK's-------------------------------------------------------------
			, InvoiceDate_BK					=	try_cast(ai.InvDate								as date)
			, DueDate_BK						=	try_cast(ai.DueDate								as date)
			, PrintDate_BK						=	try_cast(ai.LockedDateTime						as date)
			, Date_BK							=	try_cast(ai.InvDate								as date)
			, FinancialDate_BK					=	try_cast(ai.InvDate								as date)
			, CreateDate_BK						=	try_cast(ai.InvDate								as date)
			, Voucher_BK						=	cast(ai.InvoiceId_BK							as varchar(50))			
			, UniqueRecordKey					=	utilities.ufn_GetHashedUID('NORAMOPSDW', s.Company_BK, aid.InvoiceDetailID, default, default)
			, DataAgeHOT						=	aid.SCD_UpdateDate
			, DataAgeCOLD						=	(select max(v) from (values (aid.SCD_UpdateDate), (s.DataAgeCold), (ai.SCD_UpdateDate), (bc.SCD_UpdateDate), (sam.DataAgeCold)) as value(v))
			, RecordChangeDateTime				=	cast(getdate() as datetime)
from		ODS.NORAMOPSDW_tblAWBInvoice ai
join		ODS.NORAMOPSDW_tblAWBInvoiceDetail aid
on			aid.rowguid_AWBInvoice = ai.rowguid_AWBInvoice
and			aid.SCD_ActiveFlag = 1
and			aid.SCD_IsDeleted = 0
left join	CALC.NORAMOPSDW_AWB_SlavesAndMasters sam
on			ai.rowguid_AWB = sam.Slave_Rowguid_AWB
join		CALC.NORAMOPSDW_Shipment s
on			s.rowguid_AWB = isnull(sam.Master_RowGuid_AWB,ai.rowguid_AWB)	
left join	ODS.NORAMOPSDW_tblCustomer bc 
on			ai.Rowguid_Customer = bc.Rowguid_Customer
and			bc.SCD_ActiveFlag = 1
and			bc.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpCurrency cur 
on			ai.rowguid_Currency = cur.rowguid_Currency
and			cur.SCD_ActiveFlag = 1
and			cur.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpIcoOption opt 
on			opt.RowGuid_ICO = s.Company_BK 
and			opt.OptionName = 'RestrictCurrency'
and			opt.SCD_ActiveFlag = 1
and			opt.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpCurrency cur2 
on			cur2.LinkServer = ai.LinkServer 
and			cur2.CurrencyID = opt.OptionValue
and			cur2.SCD_ActiveFlag = 1
and			cur2.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpChargeCode chrg
on			chrg.ChrgCode	= aid.ChrgCode
and			chrg.LinkServer = ai.LinkServer
and			chrg.SCD_ActiveFlag = 1
and			chrg.SCD_IsDeleted = 0		
left join	CALC.NORAMOPSDW_Party dbt
on 			dbt.OriginalParty_BK	=	bc.CustomerParty_BK
left join	CALC.NORAMOPSDW_Party cstp
on 			cstp.OriginalParty_BK	=	s.CustomerParty_BK
where 		ai.SCD_ActiveFlag = 1
and			ai.SCD_IsDeleted = 0
and			try_cast(ai.InvDate as date) >= '2018-01-01'
GO
