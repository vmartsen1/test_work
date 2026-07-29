USE [SGLBI]
GO
/****** Object:  View [CALC].[v_TMFF_OwnerIdCompany]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-5286 --Objective Replace ODS with CALC for BIRefs
--PrevTask COBI-4443, hash = -2894490346948475815
--COBI-4443 , hash = -7380964558566601463
CREATE view [CALC].[v_TMFF_OwnerIdCompany]
as
select		  CompanyName			=	cast(cmp.[DESCRIPTION]							as varchar(50))
			, Company_BK			=	cast(cmp.UNID									as varchar(50))
			, CompanyOwnerId		=	cast(sccmp.OWNERID								as varchar(50))
			, CompanyCityCode		=	cast(sccmp.CITYCODE								as varchar(50))
			, CompanyCountryCode	=	cast(sccmp.CTRYCODE								as varchar(50))
			, CompanyCurrency		=	cast(sccmp.CURRCODE								as varchar(50))
			, GlobalCompanyCode		=	cast(left(sccmp.OWNERID, 4)						as varchar(50))
			, OwnerCode				=	cast(scown.CMPSN								as varchar(50))
			, OwnerName				=	cast(coalesce(scown.FULLNAME, own.[DESCRIPTION])as varchar(50))
			, OwnerOwnerId			=	cast(scown.OWNERID								as varchar(50))
			, OwnerCityCode			=	cast(scown.CITYCODE								as varchar(50))
			, OwnerCountryCode		=	cast(scown.CTRYCODE								as varchar(50))
			, CountrySchemeCode		=	cast(ctryref.[VALUE]							as varchar(50))
 			, UniqueRecordKey		=	utilities.ufn_GetHashedUID('TMFF', scown.ownerid, cmp.UNID, default, default)
			, DataAgeHOT			=	grp.SCD_UpdateDate
			, DataAgeCOLD			=	(
										select max(v) from		(
																values	  (grp.SCD_UpdateDate)
																		, (cmp.SCD_UpdateDate)
																		, (own.SCD_UpdateDate)
																		, (scown.SCD_UpdateDate)
																		, (sccmp.SCD_UpdateDate)
																) x(v)
										)
			, sccmp.SYCOSTRUC_UNID
from		ODS.TMFF_SYCOSTRUC grp
left join	ODS.TMFF_SYCOSTRUC ctry
on			ctry.PARENT_UNID = grp.UNID
and			ctry.SCD_ActiveFlag = 1
and			ctry.SCD_IsDeleted = 0
left join	ODS.TMFF_SYCOPREFERENCE ctryref		--get info for mapping of chargecodes on countrylevel
on			ctryref.SYCOSTRUC_UNID = ctry.UNID
and			ctryref.[TYPE] = 3
left join	ODS.TMFF_SYCOSTRUC cmp
on			cmp.PARENT_UNID = ctry.UNID
and			cmp.SCD_ActiveFlag = 1
and			cmp.SCD_IsDeleted = 0
left join	ODS.TMFF_SYCOSTRUC own
on			own.HLEVEL like cmp.HLEVEL + '_%'
and			own.PARENT_UNID <> grp.UNID
and			own.SCD_ActiveFlag = 1
and			own.SCD_IsDeleted = 0
left join	ODS.TMFF_SYCOMPANY scown
on			scown.SYCOSTRUC_UNID = own.UNID
and			scown.SCD_ActiveFlag = 1
and			scown.SCD_IsDeleted = 0
left join	ODS.TMFF_SYCOMPANY sccmp
on			sccmp.SYCOSTRUC_UNID = cmp.UNID
and			sccmp.SCD_ActiveFlag = 1
and			sccmp.SCD_IsDeleted = 0
left join	CALC.BIRef_CompanyDetails cd
on			cast(cmp.UNID as varchar) = cd.Company_BK
and			cd.System_BK = 'TMFF'
and			cd.SCD_ActiveFlag = 1
and			cd.SCD_IsDeleted = 0
where		grp.PARENT_UNID = 1
and			grp.UNID <> grp.PARENT_UNID
and			grp.SCD_IsDeleted =0
and			grp.SCD_ActiveFlag = 1
and			not exists	(
						select		1
						from		ODS.TMFF_SYCOSTRUC x
						where		x.PARENT_UNID = own.UNID
						)
GO
/****** Object:  View [CALC].[v_TMFF_ARPDocument]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-6042
--Prevtask COBI-4443, hash = 1615305292
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_TMFF_ARPDocument'
--select top 100 * from utilities.vcheckdefinitionsyncronization_ext where objectname = 'v_TMFF_ARPDocument'
CREATE   view [CALC].[v_TMFF_ARPDocument]
as
with InvoicesAggregated
as
(
select		  Direction					
			, DocumentNo				
			, DistributedAmountLocal	
			, DocumentAmountLocal		
			, NonDistributedAmountLocal		=	DocumentAmountLocal - DistributedAmountLocal
			, InvoiceType
			, DataAgeHot
			, DataAgeCold
from		(
			--revenue
			select		  Direction					=	'AR'
						, DocumentNo				=	cast(agg.DOCNO as varchar(50))
						, DistributedAmountLocal	=	agg.DistributedAmountLocal
						, DocumentAmountLocal		=	hdr.DOCAMTLC
						, InvoiceType				=	cast(hdr.DOCTYPE as varchar(10)) 
						, DataAgeHot				=	agg.DataAgeHOT
						, DataAgeCold				=	(select max(v) from (values (agg.DataAgeHot), (hdr.SCD_UpdateDate)) vals(v))
			from		(
						select		  DOCNO						=	INVDOCNO
									, DistributedAmountLocal	=	sum(ACTUALAMTLC) + sum(ACTUALVATAMTLC) 
									, DataAgeHOT				=	max(r.SCD_UpdateDate)
						from		ODS.TMFF_REVENUE r
						where		INVDOCNO is not null
						and			r.SCD_ActiveFlag= 1
						and			r.SCD_IsDeleted = 0
						group by	INVDOCNO
						) agg
			join		ODS.TMFF_IVHDR hdr
			on			hdr.DOCNO = agg.DOCNO
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			union all
			--cost
			select		  Direction					=	'AP'
						, DocumentNo				=	cast(agg.DOCNO as varchar(50))
						, DistributedAmountLocal	=	agg.DistributedAmountLocal
						, DocumentAmountLocal		=	hdr.AMTLC
						, InvoiceType				=	cast(null as varchar(10)) --only relevant for invoices we create so hard-coded to null
						, DataAgeHot				=	agg.DataAgeHOT
						, DataAgeCold				=	(select max(v) from (values (agg.DataAgeHot), (hdr.SCD_UpdateDate)) vals(v))
			from		(
						select		  DOCNO						=	CPVDOCNO
									, DistributedAmountLocal	=	sum(ACTUALAMTLC) + sum(ACTUALVATAMTLC) 
									, DataAgeHOT				=	max(r.SCD_UpdateDate)
						from		ODS.TMFF_COST r
						where		CPVDOCNO is not null
						and			r.SCD_ActiveFlag = 1
						and			r.SCD_IsDeleted = 0
						group by	  CPVDOCNO
						) agg
			join		ODS.TMFF_CPVHDR hdr
			on			hdr.CPVNO = agg.DOCNO
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			) x
)
select		  Direction						=	x.Direction				
			, DocumentNo					=	x.DocumentNo			
			, InvoiceType					=	x.InvoiceType
			, Company_BK					=	oc.Company_BK
			, LocalShipmentId_BK			=	x.LocalShipmentId_BK
			, GlobalShipmentId_BK			=	gs.GlobalShipmentId_BK
			, DistributedAmountLocal		=	x.DistributedAmountLocal
			, DocumentAmountLocal			=	x.DocumentAmountLocal	
			, LineAmountLocal				=	x.LineAmountLocal
			, Allocation					=	x.LineAmountLocal / nullif(x.DocumentAmountLocal, 0)
			, UniqueRecordKey				=	utilities.ufn_GetHashedUID10('TMFF', x.Direction, x.DocumentNo, x.LocalShipmentId_BK, x.SourceTb, x.SNO, default, default, default, default)
			, DataAgeHot					=	x.DataAgeHot
			, DataAgeCold					=	x.DataAgeCold
			, RecordChangeDateTime			=	getdate()
from		(
			select		  agg.*
						, r.SNO
						, SourceTb					=	'REVENUE'
						, LineAmountLocal			=	r.ACTUALAMTLC + r.ACTUALVATAMTLC
						, LocalShipmentId_BK		=	cast(JOB_UNID as varchar(50))
						, r.JOB_UNID
			from		ODS.TMFF_REVENUE r
			join		InvoicesAggregated agg
			on			r.INVDOCNO = agg.DocumentNo
			and			agg.DIRECTION = 'AR'
			where		r.SCD_ActiveFlag = 1
			and			r.SCD_IsDeleted = 0
			union all
			select		  agg.*
						, r.SNO
						, SourceTb					=	'COST'
						, LineAmountLocal			=	r.ACTUALAMTLC + r.ACTUALVATAMTLC
						, LocalShipmentId_BK		=	cast(JOB_UNID as varchar(50))
						, r.JOB_UNID
			from		ODS.TMFF_COST r
			join		InvoicesAggregated agg
			on			r.CPVDOCNO = agg.DocumentNo
			and			agg.DIRECTION = 'AP'
			where		r.SCD_ActiveFlag = 1
			and			r.SCD_IsDeleted = 0
			union all
			select		  agg.*
						, SNO = 0
						, SourceTb					=	'NONE'
						, LineAmountLocal			=	agg.NonDistributedAmountLocal
						, LocalShipmentId_BK		=	cast('No Job. record is a Diff. Record' as varchar(50))
						, null
			from		InvoicesAggregated agg
			where		NonDistributedAmountLocal <> 0
			) x
left join	CALC.TMFF_Job_GlobalShipmentId_Weight_Volume_Company gs
on			gs.JOB_UNID = x.JOB_UNID
left join	ODS.TMFF_JOB j
on			j.UNID = try_cast(x.LocalShipmentId_BK as bigint)
and			j.SCD_ActiveFlag = 1
and			j.SCD_IsDeleted = 0
left join	CALC.v_TMFF_OwnerIdCompany oc
on			oc.OwnerOwnerId = j.OWNERID

GO
/****** Object:  View [CALC].[TMFF_ARP_Documents]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-4443, hash = 876547959768884573
CREATE   view [CALC].[TMFF_ARP_Documents]
as
with InvoicesAggregated
as
(
select		  Direction					
			, DocumentNo				
			, DistributedAmountLocal	
			, DocumentAmountLocal		
			, NonDistributedAmountLocal		=	DocumentAmountLocal - DistributedAmountLocal
			, DataAgeHot
			, DataAgeCold
from		(
			--revenue
			select		  Direction					=	'AR'
						, DocumentNo				=	agg.DOCNO
						, DistributedAmountLocal	=	agg.DistributedAmountLocal
						, DocumentAmountLocal		=	hdr.DOCAMTLC
						, DataAgeHot				=	agg.DataAgeHOT
						, DataAgeCold				=	(select max(v) from (values (agg.DataAgeHot), (hdr.SCD_UpdateDate)) vals(v))
			from		(
						select		  DOCNO						=	INVDOCNO
									, DistributedAmountLocal	=	sum(ACTUALAMTLC) + sum(ACTUALVATAMTLC) 
									, DataAgeHOT				=	max(r.SCD_UpdateDate)
						from		ODS.TMFF_REVENUE r
						where		INVDOCNO is not null
						group by	  INVDOCNO
						) agg
			join		ODS.TMFF_IVHDR hdr
			on			hdr.DOCNO = agg.DOCNO
			union all
			--cost
			select		  Direction					=	'AP'
						, DocumentNo				=	agg.DOCNO
						, DistributedAmountLocal	=	agg.DistributedAmountLocal
						, DocumentAmountLocal		=	hdr.DOCAMTLC
						, DataAgeHot				=	agg.DataAgeHOT
						, DataAgeCold				=	(select max(v) from (values (agg.DataAgeHot), (hdr.SCD_UpdateDate)) vals(v))
			from		(
						select		  DOCNO						=	CPVDOCNO
									, DistributedAmountLocal	=	sum(ACTUALAMTLC) + sum(ACTUALVATAMTLC) 
									, DataAgeHOT				=	max(r.SCD_UpdateDate)
						from		ODS.TMFF_COST r
						where		CPVDOCNO is not null
						group by	  CPVDOCNO
						) agg
			join		ODS.TMFF_IVHDR hdr
			on			hdr.DOCNO = agg.DOCNO
			) x
)

select		  Direction						=	x.Direction				
			, DocumentNo					=	x.DocumentNo			
			, LocalShipmentId_BK			=	x.LocalShipmentId_BK
			, GlobalShipmentId_BK			=	gs.GlobalShipmentId_BK
			, DistributedAmountLocal		=	x.DistributedAmountLocal
			, DocumentAmountLocal			=	x.DocumentAmountLocal	
			, LineAmountLocal				=	x.LineAmountLocal
			, Allocation					=	x.LineAmountLocal / nullif(x.DocumentAmountLocal, 0)
			, UniqueRecordKey				=	utilities.ufn_GetHashedUID('TMFF', x.Direction, x.DocumentNo, x.LocalShipmentId_BK, default)
			, DataAgeHot					=	x.DataAgeHot
			, DataAgeCold					=	x.DataAgeCold
			, RecordChangeDateTime			=	getdate()
from		(
			select		  agg.*
						, LineAmountLocal			=	r.ACTUALAMTLC + r.ACTUALVATAMTLC
						, LocalShipmentId_BK		=	cast(JOB_UNID as varchar(50))
						, r.JOB_UNID
			from		ODS.TMFF_REVENUE r
			join		InvoicesAggregated agg
			on			r.INVDOCNO = agg.DocumentNo
			and			agg.DIRECTION = 'AR'
			union all
			select		  agg.*
						, LineAmountLocal			=	r.ACTUALAMTLC + r.ACTUALVATAMTLC
						, LocalShipmentId_BK		=	cast(JOB_UNID as varchar(50))
						, r.JOB_UNID
			from		ODS.TMFF_COST r
			join		InvoicesAggregated agg
			on			r.CPVDOCNO = agg.DocumentNo
			and			agg.DIRECTION = 'AP'
			union all
			select		  agg.*
						, LineAmountLocal			=	agg.NonDistributedAmountLocal
						, LocalShipmentId_BK		=	cast('No Job. record is a Diff. Record' as varchar(50))
						, null
			from		InvoicesAggregated agg
			where		NonDistributedAmountLocal <> 0
			) x
left join	CALC.TMFF_Job_GlobalShipmentId_Weight_Volume_Company gs
on			gs.JOB_UNID = x.JOB_UNID


GO
/****** Object:  View [CALC].[v_TMFF_AllItems]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO







--COBI-7494 --Objective SEACONTITEM fix
--Prevtask=COBI-7445 , hash=419123951
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_TMFF_AllItems'
--select * from utilities.vCheckDefinitionSyncronization_ext where ObjectName = 'v_TMFF_AllItems'
CREATE view [CALC].[v_TMFF_AllItems]
as
--seaconitem
--VB - SEACONITEM must be inner joined to CARGOUNITITEM as the source does not handle deletes on SEACONITEM
select		  Src					=	'SEACONTITEM'
			, JOB_UNID				=	sci.JOB_UNID
			, Company_BK			=	cast(s.Company_BK as varchar(50))
			, RowNumber				=	row_number() over (partition by sci.JOB_UNID order by sci.CONTAINER_UNID)
			, CONTAINER_UNID		=	sci.CONTAINER_UNID
			, UNITUNID				=	cast(null as varchar(50))
			, ItemVolume			=	sum(sci.TOTVOL)
			, ItemWeight			=	sum(sci.TOTWGT)
			, ItemPieces			=	sum(sci.TOTPCS)
			, GoodsDescription		=	cast(string_agg(ci.[DESCRIPTION], '-') as varchar(500))
			, ContainerType			=	co.CONTTYPE
			, DirectTEU				=	null
			, DataAgeCold			=	(select max(v) from (values (max(sci.SCD_UpdateDate)), (max(s.DataAgeCold)), (max(ci.SCD_UpdateDate))) x(v))
			, DataAgeHot			=	max(sci.SCD_UpdateDate)
from		ODS.TMFF_SEACONTITEM sci
join		CALC.TMFF_Shipment s
on			s.LocalShipmentId_BK = sci.JOB_UNID
join		ODS.TMFF_CARGOITEM ci
on			ci.JOB_UNID = sci.JOB_UNID
and			ci.SNO = sci.SEAITEM_SNO
and			ci.SCD_ActiveFlag = 1
and			ci.SCD_IsDeleted  = 0
left join	ODS.TMFF_CONTAINER co
on			co.UNID = sci.CONTAINER_UNID
and			co.SCD_ActiveFlag = 1
and			co.SCD_IsDeleted  = 0
where		sci.SCD_ActiveFlag = 1
and			sci.SCD_IsDeleted = 0
group by	sci.JOB_UNID
			, s.Company_BK
			, sci.CONTAINER_UNID
			, co.CONTTYPE
union all
--Items based on Cargo Load Plan (CLS) where we have a CargoItem, but no Seacontitem defined so we create virtual records.
select		  Src					=	'SEA'
			, JOB_UNID				=	sea.JOB_UNID
			, Company_BK			=	cast(s.Company_BK as varchar(50))
			, RowNumber				=	row_number() over (partition by sea.JOB_UNID order by ctn.ctnix * 100 + 1000 + ctn.ctncnt)
			, CONTAINER_UNID		=	cast(null as numeric)
			, UNITUNID				=	cast(null as varchar(50))
			, ItemVolume			=	ci.ItemVolume / (isnull(sea.CTNQTY1, 0) + isnull(sea.CTNQTY2, 0) + isnull(sea.CTNQTY3, 0) + isnull(sea.CTNQTY4, 0))
			, ItemWeight			=	ci.ItemWeight / (isnull(sea.CTNQTY1, 0) + isnull(sea.CTNQTY2, 0) + isnull(sea.CTNQTY3, 0) + isnull(sea.CTNQTY4, 0))
			, ItemPieces			=	ci.ItemPieces / (isnull(sea.CTNQTY1, 0) + isnull(sea.CTNQTY2, 0) + isnull(sea.CTNQTY3, 0) + isnull(sea.CTNQTY4, 0))
			, GoodsDescription		=	ci.GoodsDescription
			, ContainerType			=	calc.ContTypeCalc
			, DirectTEU				=	case	
											when calc.ContTypeCalc like '%10%' and calc.Ispart = 0 then 0.50
											when calc.ContTypeCalc like '%20%' and calc.Ispart = 0 then 1.00
											when calc.ContTypeCalc like '%40%' and calc.Ispart = 0 then 2.00
											when calc.ContTypeCalc like '%45%' and calc.Ispart = 0 then 2.25
										end
			, DataAgeCold			=	sea.SCD_UpdateDate
			, DataAgeHot			=	(select max(v) from (values (sea.SCD_UpdateDate), (s.DataAgeCold), (ci.SCD_UpdateDate)) x(v))
from		CALC.TMFF_Shipment s
join		ODS.TMFF_SEA sea
on			sea.JOB_UNID = s.LocalShipmentId_BK
and			sea.SCD_ActiveFlag = 1
and			sea.SCD_IsDeleted = 0
left join	(
			select		  JOB_UNID				=	ci.JOB_UNID
						, ItemVolume			=	cast(sum(ci.VOL) as float)
						, ItemWeight			=	cast(sum(ci.WGT) as float)
						, ItemPieces			=	cast(sum(ci.PCS) as float)
						, PiecesUnit			=	cast(max(ci.PCS_UT) as varchar(50))
						, GoodsDescription		=	cast(max(ci.[DESCRIPTION]) as varchar(500))
						, SCD_UpdateDate		=	max(ci.SCD_UpdateDate)
			from		ODS.TMFF_CARGOITEM ci
			where		ci.SCD_ActiveFlag = 1
			and			ci.SCD_IsDeleted  = 0
			group by	ci.JOB_UNID
			) ci
on			ci.JOB_UNID = sea.JOB_UNID
join		(
			select		*
			from		(values (1),(2),(3),(4)) x (ctnix)
						cross join	(values (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)
											,(11),(12),(13),(14),(15),(16),(17),(18),(19),(20)
											,(21),(22),(23),(24),(25),(26),(27),(28),(29),(30)
											,(31),(32),(33),(34),(35),(36),(37),(38),(39),(40)
											,(41),(42),(43),(44),(45),(46),(47),(48),(49),(50)
											,(51),(52),(53),(54),(55),(56),(57),(58),(59),(60)
											,(61),(62),(63),(64),(65),(66),(67),(68),(69),(70)
											,(71),(72),(73),(74),(75),(76),(77),(78),(79),(80)
											,(81),(82),(83),(84),(85),(86),(87),(88),(89),(90)
											,(91),(92),(93),(94),(95),(96),(97),(98),(99),(100)) y (ctncnt)
			) ctn
on			ctn.ctnix = 1 
and			sea.CTNQTY1 is not null
and			sea.CTNQTY1 >= ctn.ctncnt
or			ctn.ctnix = 2 
and			sea.CTNQTY2 is not null
and			sea.CTNQTY2 >= ctn.ctncnt
or			ctn.ctnix = 3 
and			sea.CTNQTY3 is not null
and			sea.CTNQTY3 >= ctn.ctncnt
or			ctn.ctnix = 4
and			sea.CTNQTY4 is not null
and			sea.CTNQTY4 >= ctn.ctncnt
cross apply	(
			select ContTypeCalc	=	case 
										when ctn.ctnix = 1 then CTNTYPE1 
										when ctn.ctnix = 2 then CTNTYPE2 
										when ctn.ctnix = 3 then CTNTYPE3 
										when ctn.ctnix = 4 then CTNTYPE4 
									end
				,	Ispart		=	case 
										when ctn.ctnix = 1 then ISPARTOF1 
										when ctn.ctnix = 2 then ISPARTOF2 
										when ctn.ctnix = 3 then ISPARTOF3 
										when ctn.ctnix = 4 then ISPARTOF4 
									end
			) calc
left join	(--filter out record where exists seacontitem, because they appear in first select
			select		distinct 
						JOB_UNID
			from		ODS.TMFF_SEACONTITEM sci 
			where		sci.SCD_ActiveFlag = 1
			and			sci.SCD_IsDeleted = 0
			) sci
on			sci.JOB_UNID = sea.JOB_UNID
where		coalesce(sea.CTNQTY1, sea.CTNQTY2, sea.CTNQTY3, sea.CTNQTY4) > 0
and			sci.JOB_UNID is null --filter out record where exists seacontitem, because they appear in first select
and			sea.LOADTERM in ('FCL','CONS')
union all
select		  Src					=	'LOADUNITITEM'
			, JOB_UNID				=	lui.JOB_UNID
			, Company_BK			=	cast(s.Company_BK as varchar(50))
			, RowNumber				=	row_number() over (partition by lui.JOB_UNID order by lui.UNITUNID)
			, CONTAINER_UNID		=	cast(null as numeric)--try_cast(replace(lui.INTUNITNO, 'UNIT', '') as numeric)
			, UNITUNID				=	lui.UNITUNID
			, ItemVolume			=	sum(lui.TOTVOL)
			, ItemWeight			=	sum(lui.TOTWGT)
			, ItemPieces			=	sum(lui.TOTPCS)
			, GoodsDescription		=	cast(string_agg(ci.[DESCRIPTION], '-') as varchar(500))
			, ContainerType			=	null
			, DirectTEU				=	null
			, DataAgeCold			=	(select max(v) from (values (max(lui.SCD_UpdateDate)), (max(s.DataAgeCold)), (max(ci.SCD_UpdateDate))) x(v))
			, DataAgeHot			=	max(lui.SCD_UpdateDate)
from		ODS.TMFF_LOADUNITITEM lui	
join		CALC.TMFF_Shipment s
on			s.LocalShipmentId_BK = lui.JOB_UNID
left join	ODS.TMFF_CARGOITEM ci
on			ci.JOB_UNID = lui.JOB_UNID
and			ci.SNO = lui.CARGOITEMSNO
and			ci.SCD_ActiveFlag = 1
and			ci.SCD_IsDeleted  = 0
left join	ODS.TMFF_LOADUNIT lu
on			lu.UNID = lui.UNITUNID
and			lu.SCD_ActiveFlag = 1
and			lu.SCD_IsDeleted  = 0
where		lui.SCD_ActiveFlag = 1
and			lui.SCD_IsDeleted = 0
and			lui.job_unid is not null
group by	lui.JOB_UNID
			, lui.UNITUNID
			, s.Company_BK
union all
select		  Src					=	'ROAD'
			, JOB_UNID				=	road.JOB_UNID
			, Company_BK			=	cast(s.Company_BK as varchar(50))
			, RowNumber				=	row_number() over (partition by road.JOB_UNID order by ctn.ctnix * 100 + 1000 + ctn.ctncnt)
			, CONTAINER_UNID		=	cast(null as numeric)
			, UNITUNID				=	cast(null as varchar(50))
			, ItemVolume			=	ci.ItemVolume / (isnull(road.VEHICLEQTY1, 0) + isnull(road.VEHICLEQTY2, 0) + isnull(road.VEHICLEQTY3, 0) + isnull(road.VEHICLEQTY4, 0))
			, ItemWeight			=	ci.ItemWeight / (isnull(road.VEHICLEQTY1, 0) + isnull(road.VEHICLEQTY2, 0) + isnull(road.VEHICLEQTY3, 0) + isnull(road.VEHICLEQTY4, 0))
			, ItemPieces			=	ci.ItemPieces / (isnull(road.VEHICLEQTY1, 0) + isnull(road.VEHICLEQTY2, 0) + isnull(road.VEHICLEQTY3, 0) + isnull(road.VEHICLEQTY4, 0))
			, GoodsDescription		=	ci.GoodsDescription
			, ContainerType			=	calc.ContTypeCalc
			, DirectTEU				=	case	
											when calc.ContTypeCalc like '%10%' then 0.50
											when calc.ContTypeCalc like '%20%' then 1.00
											when calc.ContTypeCalc like '%40%' then 2.00
											when calc.ContTypeCalc like '%45%' then 2.25
										end
			, DataAgeCold			=	road.SCD_UpdateDate
			, DataAgeHot			=	(select max(v) from (values (road.SCD_UpdateDate), (s.DataAgeCold), (ci.SCD_UpdateDate)) x(v))
from		CALC.TMFF_Shipment s
join		ODS.TMFF_ROAD road
on			road.JOB_UNID = s.LocalShipmentId_BK
and			road.SCD_ActiveFlag = 1
and			road.SCD_IsDeleted = 0
left join	(
			select		  JOB_UNID				=	ci.JOB_UNID
						, ItemVolume			=	cast(sum(ci.VOL) as float)
						, ItemWeight			=	cast(sum(ci.WGT) as float)
						, ItemPieces			=	cast(sum(ci.PCS) as float)
						, PiecesUnit			=	cast(max(ci.PCS_UT) as varchar(50))
						, GoodsDescription		=	cast(max(ci.[DESCRIPTION]) as varchar(500))
						, SCD_UpdateDate		=	max(ci.SCD_UpdateDate)
			from		ODS.TMFF_CARGOITEM ci
			where		ci.SCD_ActiveFlag = 1
			and			ci.SCD_IsDeleted  = 0
			group by	ci.JOB_UNID
			) ci
on			ci.JOB_UNID = road.JOB_UNID
join		(
			select		*
			from		(values (1),(2),(3),(4)) x (ctnix)
						cross join	(values (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)
											,(11),(12),(13),(14),(15),(16),(17),(18),(19),(20)
											,(21),(22),(23),(24),(25),(26),(27),(28),(29),(30)
											,(31),(32),(33),(34),(35),(36),(37),(38),(39),(40)
											,(41),(42),(43),(44),(45),(46),(47),(48),(49),(50)
											,(51),(52),(53),(54),(55),(56),(57),(58),(59),(60)
											,(61),(62),(63),(64),(65),(66),(67),(68),(69),(70)
											,(71),(72),(73),(74),(75),(76),(77),(78),(79),(80)
											,(81),(82),(83),(84),(85),(86),(87),(88),(89),(90)
											,(91),(92),(93),(94),(95),(96),(97),(98),(99),(100)) y (ctncnt)
			) ctn
on			ctn.ctnix = 1 
and			road.VEHICLEQTY1 is not null
and			road.VEHICLEQTY1 >= ctn.ctncnt
or			ctn.ctnix = 2 
and			road.VEHICLEQTY2 is not null
and			road.VEHICLEQTY2 >= ctn.ctncnt
or			ctn.ctnix = 3 
and			road.VEHICLEQTY3 is not null
and			road.VEHICLEQTY3 >= ctn.ctncnt
or			ctn.ctnix = 4
and			road.VEHICLEQTY4 is not null
and			road.VEHICLEQTY4 >= ctn.ctncnt
cross apply	(
			select ContTypeCalc	=	case 
										when ctn.ctnix = 1 then VEHICLETYPE1 
										when ctn.ctnix = 2 then VEHICLETYPE2 
										when ctn.ctnix = 3 then VEHICLETYPE3 
										when ctn.ctnix = 4 then VEHICLETYPE4 
									end
			) calc
--COBI-7055 - we filter out ROAD part by those loaded already by TMFF_LOADUNITITEM
left join  (select    	distinct 
            			JOB_UNID
			from    	ODS.TMFF_LOADUNITITEM lui  
      		where    	lui.SCD_ActiveFlag = 1
      		and      	lui.SCD_IsDeleted = 0
      		) lui
on      	road.JOB_UNID = lui.JOB_UNID
where   	coalesce(road.VEHICLEQTY1, road.VEHICLEQTY2, road.VEHICLEQTY3, road.VEHICLEQTY4) > 0
and     	s.TransportMode_BK = 'Rail'
and     	s.ShipmentType_BK = 'FCL'
and     	lui.JOB_UNID is null
union all
--Shipments not in CONTAINER or SEACONTITEM or SEA
select		  Src					=	'JOB'
			, JOB_UNID				=	j.UNID
			, Company_BK			=	cast(s.Company_BK as varchar(50))
			, RowNumber				=	1 -- we don't expect multiple rows here
			, CONTAINER_UNID		=	cast(null as numeric)
			, UNITUNID				=	cast(null as varchar(50))
			, ItemVolume			=	j.TOTVOL
			, ItemWeight			=	j.TOTGWGT
			, ItemPieces			=	j.TOTPCS
			, GoodsDescription		=	cast(coalesce(jo.COMMLOCALDESC, jo.COMM) as varchar(500))
			, ContainerType			=	null
			, DirectTEU				=	null
			, DataAgeCold			=	(select max(v) from (values (j.SCD_UpdateDate), (s.DataAgeCold)) x(v))
			, DataAgeHot			=	j.SCD_UpdateDate
from		ODS.TMFF_JOB j
join		ODS.TMFF_JOBOTHER jo
on			j.UNID = jo.JOB_UNID
and			jo.SCD_ActiveFlag = 1
and			jo.SCD_IsDeleted = 0
join		CALC.TMFF_Shipment s
on			s.LocalShipmentId_BK = j.UNID
left join	(
			select		distinct 
						JOB_UNID
						, VEHICLEQTY = coalesce(VEHICLEQTY1, VEHICLEQTY2, VEHICLEQTY3, VEHICLEQTY4)
			from		ODS.TMFF_ROAD
			where		SCD_IsDeleted = 0
			and			SCD_ActiveFlag = 1
			) roa
on			roa.JOB_UNID = j.UNID
and			s.TransportMode_BK = 'Rail'
and     	s.ShipmentType_BK = 'FCL'
and			roa.VEHICLEQTY > 0
left join	(
			select		distinct 
						JOB_UNID
			from		ODS.TMFF_SEACONTITEM 
			where		SCD_IsDeleted = 0
			and			SCD_ActiveFlag = 1
			) sci
on			sci.JOB_UNID = j.UNID
left join	(
			select		distinct 
						JOB_UNID
			from		ODS.TMFF_CONTAINER
			where		SCD_IsDeleted = 0
			and			SCD_ActiveFlag = 1
			) cnt
on			cnt.JOB_UNID = j.UNID
left join	(
			select		distinct 
						JOB_UNID
			from		ODS.TMFF_SEA
			where		SCD_IsDeleted = 0
			and			SCD_ActiveFlag = 1
			and			coalesce(CTNQTY1, CTNQTY2, CTNQTY3, CTNQTY4) > 0
			and			LOADTERM in ('FCL','CONS')
			)sea
on			sea.JOB_UNID = j.UNID
left join	(
			select		distinct 
						JOB_UNID
			from		ODS.TMFF_LOADUNITITEM
			where		SCD_IsDeleted = 0
			and			SCD_ActiveFlag = 1
			) lui
on			lui.JOB_UNID = j.UNID
where		sci.JOB_UNID is null	--filter out those records because those are present in other selects in the union	
and			cnt.JOB_UNID is null	--filter out those records because those are present in other selects in the union
and			sea.JOB_UNID is null 	--filter out those records because those are present in other selects in the union
and			lui.JOB_UNID is null	--filter out those records because those are present in other selects in the union
and			roa.JOB_UNID is null	--filter out those records because those are present in other selects in the union
and			j.SCD_ActiveFlag = 1
and			j.SCD_IsDeleted  = 0
and			j.VOIDDATE is null


			
GO
/****** Object:  View [CALC].[v_TMFF_AllItemsWithTEUAllocation]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






--COBI-7445 --Objective Fix LOADUNITITEM
--Prevtask COBI-7200 , hash = -2088562498
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_TMFF_AllItemsWithTEUAllocation'
--select * from utilities.vCheckDefinitionSyncronization where ObjectName = 'v_TMFF_AllItemsWithTEUAllocation'
CREATE view [CALC].[v_TMFF_AllItemsWithTEUAllocation]
as
select		  ai.Src
			, ai.JOB_UNID
			, ai.Company_BK
			, ai.RowNumber
			, ai.CONTAINER_UNID
			, ai.UNITUNID
			, ai.ItemVolume
			, ai.ItemWeight
			, ai.ItemPieces
			, ai.GoodsDescription
			, ContainerType = coalesce(ai.ContainerType, lu.UNITTYPE)
			, ai.DirectTEU
			, ai.DataAgeCold
			, ai.DataAgeHot
			, ShipmentItemSuffix		=	case ai.Src
												when	'JOB'			then '____JOB'
												when	'SEACONTITEM'	then '_____SCI' + cast(ai.RowNumber as varchar)
												when	'SEA'			then '_____SEA' + cast(ai.RowNumber as varchar)
												when	'LOADUNITITEM'	then '_____LUI' + cast(ai.RowNumber as varchar)
												when	'ROAD'			then '_____ROAD' + cast(ai.RowNumber as varchar)
												else	'?!?'
											end
			, TEU						=	coalesce(cntg.TEU, lu.CalculatedTEU)
			, CONTNO					=	coalesce(cntg.CONTNO, lu.UNITNO)
			, SEALNO					=	coalesce(cntg.SEALNO, lu.SEALNO)
			, CalculatedTEU				=	coalesce(cntg.CalculatedTEU, lu.CalculatedTEU)
			, ContainerItemVolume		=	coalesce(cntg.ContainerItemVolume, lu.ContainerItemVolume)
			, ContainerItemCount		=	coalesce(cntg.ContainerItemCount, lu.ContainerItemCount)
			, AllocatedTEU				=	coalesce(
													  DirectTEU
													, cast(ai.ItemVolume as float) / nullif(cast(cntg.ContainerItemVolume as float), 0) * cast(cntg.CalculatedTEU as float)
													, cast(1 as float) / nullif(cast(cntg.ContainerItemCount as float), 0) * cast(cntg.CalculatedTEU as float)
													, cast(ai.ItemVolume as float) / nullif(cast(lu.ContainerItemVolume as float), 0) * cast(lu.CalculatedTEU as float)
													, cast(1 as float) / nullif(cast(lu.ContainerItemCount as float), 0) * cast(lu.CalculatedTEU as float)
													)
			, RecordChangeDateTime		=	getdate()

from		CALC.TMFF_AllItems ai
left join	(
			select		  CONTAINER_UNID			=	ai.CONTAINER_UNID
						, ai.Company_BK
						, ai.Src
						, cnt.TEU
						, ContainerType				=	ai.ContainerType
						, cnt.CONTNO
						, cnt.SEALNO
						, ContainerItemVolume		=	sum(case when ai.DirectTEU is null then ai.ItemVolume else 0 end)
						, ContainerItemCount		=	count(*)
						, CalculatedTEU				=	case
															when cnt.TEU is not null then cast(cnt.TEU as decimal(19,2))
															when ai.ContainerType like '%10%' then 0.50
															when ai.ContainerType like '%20%' then 1.00
															when ai.ContainerType like '%40%' then 2.00
															when ai.ContainerType like '%45%' then 2.25
															else 0
														end
						, DataAgeHot				=	max(ai.DataAgeHot)
						, DataAgeCold				=	(select max(v) from (values (max(ai.DataAgeCold)), (max(cnt.SCD_UpdateDate))) x(v))
			from		CALC.TMFF_AllItems ai
			join		ODS.TMFF_CONTAINER cnt
			on			cnt.UNID = ai.CONTAINER_UNID
			and			cnt.SCD_ActiveFlag =1
			and			cnt.SCD_IsDeleted = 0
			group by	  ai.CONTAINER_UNID
						, ai.Src
						, ai.Company_BK
						, cnt.TEU
						, ai.ContainerType
						, cnt.CONTNO
						, cnt.SEALNO
			) cntg
on			cntg.CONTAINER_UNID = ai.CONTAINER_UNID
and			cntg.Company_BK = ai.Company_BK
and			cntg.Src = ai.Src
left join	(
			select 
						  s.Company_BK
						, lu.UNID
						, lu.UNITNO 
						, lu.SEALNO
						, lu.UNITTYPE
						, ContainerItemVolume		=	lu.TOTVOL
						, ContainerItemCount		=	(select count(*) from ODS.TMFF_LOADUNITITEM lui where lui.UNITUNID = lu.UNID )
						, CalculatedTEU				=	case	
															when lu.UNITTYPE like '%10%' then 0.50
															when lu.UNITTYPE like '%20%' then 1.00
															when lu.UNITTYPE like '%40%' then 2.00
															when lu.UNITTYPE like '%45%' then 2.25
														end
						, Src = 'LOADUNITITEM'

			from		ODS.TMFF_LOADUNIT lu
			join		CALC.TMFF_OwnerIdCompany s
			on			s.OwnerOwnerId = lu.OWNERID
			where 		lu.SCD_ActiveFlag = 1
			and			lu.SCD_IsDeleted = 0
) lu
on			lu.Company_Bk  = ai.Company_Bk
and			lu.UNID = ai.UNITUNID 
and			lu.Src = ai.Src 


			
GO
/****** Object:  View [CALC].[v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-6820 --Cleanup GlobalShipmentId_BK
--prevtask COBI-6730, hash  = 735652670
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company'
--select * from utilities.vCheckDefinitionSyncronization where ObjectName = 'v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company'
CREATE view [CALC].[v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company]
as
with		cte_JOB as (
			select		  * 
						, clean_SHPNO	=	case	
											when replace(utilities.ufn_GetCleanGlobalShipmentId(SHPNO),'0','') = '' then null
											else utilities.ufn_GetCleanGlobalShipmentId(SHPNO)
											end
			from		ODS.TMFF_JOB
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			VOIDDATE is null
)
select		  JOB_UNID					=	j.UNID
			, GlobalShipmentId_BK		=	cast(coalesce(gsid.clean_SHPNO, j.clean_SHPNO, 'TMFF|' + coalesce(cast(oic.Company_BK as varchar), j.OWNERID) + '|' + cast(j.UNID as varchar)) as varchar(150))
			, LocalShipmentId_BK		=	CAST(j.UNID as varchar(50))
			, ChargeableWeight			=	isnull(j.TOTCWGT,0)
			, ChargeableWeightUnit		=	cast(j.TOTCWGT_UT as varchar(50))
			, Company_BK				=	cast(coalesce(oic.Company_BK, j.OWNERID) as varchar(50))
			, ShipmentWeight			=	isnull(j.TOTGWGT,0)
			, ShipmentVolume			=	isnull(j.TOTVOL,0)
			, CargoItemWeightSum		=	cit.CargoItemWeightSum
			, CargoItemVolumeSum		=	cit.CargoItemVolumeSum
			, ContainerWeightSum		=	cntt.ContainerWeightSum
			, ContainerVolumeSum		=	cntt.ContainerVolumeSum
			, WeightUnit				=	cast(j.TOTGWGT_UT	as varchar(50))
			, VolumeUnit				=	cast(j.TOTVOL_UT	as varchar(50))
			, ShipmentCount				=	cast(j.ISSHP as bigint)
			, ShpType					=	j.SHPTYPE				
			, GoodsDescription			=	cast(jo.BKGGOODDESC as varchar(500))
			, CreateDate				=	j.CREATEDATE
			, CreateDate_BK				=   j.CREATEDATE
			, GlobalShipmentId			=	cast(j.GSHPID as varchar(150))
			, OPSTATUS					=	jo.OPSTATUS
			, UniqueRecordKey			=	utilities.ufn_GetHashedUID('TMFF', cast(j.UNID as varchar),default,default,default)
			, DataAgeHot				=	jo.SCD_UpdateDate
			, DataAgeCOLD				=	(select max(v) from (values(oic.DataAgeCOLD), (jo.SCD_UpdateDate)) x(v))
			, RecordChangeDateTime		=	getdate()
from		cte_JOB j
join		ODS.TMFF_JOBOTHER jo
on			jo.JOB_UNID = j.UNID
and			jo.SCD_ActiveFlag = 1
and			jo.SCD_IsDeleted = 0
left join	CALC.TMFF_OwnerIdCompany oic
on			oic.OwnerOwnerId = j.OWNERID
left join	(
			select		  gsid.GSHPID
						, clean_SHPNO			
						, ix			=	row_number() over (partition by gsid.GSHPID order by case when clean_SHPNO is null then 999 else 1 end asc, j.createdate asc)
			from		(
						select		GSHPID
						from		cte_JOB
						where		SCD_ActiveFlag = 1
						and			SCD_IsDeleted = 0
						and			VOIDDATE is null
						group by	GSHPID
						having		count(distinct clean_SHPNO) > 1
						) gsid
			join		cte_JOB j
			on			gsid.GSHPID = j.GSHPID
			and			j.SCD_ActiveFlag = 1
			and			j.SCD_IsDeleted = 0
			and			j.VOIDDATE is null
			) gsid
on			gsid.GSHPID = j.GSHPID
and			gsid.ix = 1
left join	(
			select		  JOB_UNID
						, CargoItemWeightSum	=	sum(WGT)
						, CargoItemVolumeSum	=	sum(VOL)
			from		ODS.TMFF_CARGOITEM
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			JOB_UNID is not null
			group by	JOB_UNID
			) cit
on			cit.JOB_UNID = j.UNID
left join	(
			select		  JOB_UNID
						, ContainerWeightSum	=	sum(TOTWGT)
						, ContainerVolumeSum	=	sum(TOTVOL)
			from		ODS.TMFF_CONTAINER
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			JOB_UNID is not null
			group by	JOB_UNID
			) cntt
on			cntt.JOB_UNID = j.UNID
where		j.SCD_ActiveFlag = 1
and			j.SCD_IsDeleted = 0
and			j.VOIDDATE is null
			
GO
/****** Object:  View [CALC].[v_TMFF_JOBPARTY]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-6043 --Objective eliminate nvarchars
--prevtask COBI-4443, hash = 174491260
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_TMFF_JOBPARTY'
--select * from utilities.vcheckdefinitionsyncronization where objectname= 'v_TMFF_JOBPARTY' and schemaname ='CALC'
CREATE view [CALC].[v_TMFF_JOBPARTY]
as
select	
			  [JOB_UNID]
			, [PCF]						= cast(max([PCF])							as varchar(50))
			, [BY]						= cast(max([BY])							as varchar(50))
			, [LOCATIONORIGINAL]		= cast(max([LOCATIONORIGINAL])				as varchar(50))
			, [SCREENING]				= cast(max([SCREENING])						as varchar(50))
			, [CUSTLIST]				= cast(max([CUSTLIST])						as varchar(50))
			, [SUBCONTRACTOR]			= cast(max([SUBCONTRACTOR])					as varchar(50))
			, [ORAG]					= cast(max([ORAG])							as varchar(50))
			, [EXPASSIGNEE]				= cast(max([EXPASSIGNEE])					as varchar(50))
			, [ALSONTFY]				= cast(max([ALSONTFY])						as varchar(50))
			, [CL]						= cast(max([CL])							as varchar(50))
			, [HANDLINGAGENT]			= cast(max([HANDLINGAGENT])					as varchar(50))
			, [OAGENT]					= cast(max([OAGENT])						as varchar(50))
			, [REALCSGN]				= cast(max([REALCSGN])						as varchar(50))
			, [CONTROLPARTY]			= cast(max([CONTROLPARTY])					as varchar(50))
			, [CARRIERAGENTO]			= cast(max([CARRIERAGENTO])					as varchar(50))
			, [COL]						= cast(max([COL])							as varchar(50))
			, [PAY]						= cast(max([PAY])							as varchar(50))
			, [TRUCKING]				= cast(max([TRUCKING])						as varchar(50))
			, [ALSONTFY2]				= cast(max([ALSONTFY2])						as varchar(50))
			, [INS]						= cast(max([INS])							as varchar(50))
			, [CS]						= cast(max([CS])							as varchar(50))
			, [QUARANTINE]				= cast(max([QUARANTINE])					as varchar(50))
			, [CU]						= cast(max([CU])							as varchar(50))
			, [WAREHOUSE]				= cast(max([WAREHOUSE])						as varchar(50))
			, [CONTRA]					= cast(max([CONTRA])						as varchar(50))
			, [BROKER]					= cast(max([BROKER])						as varchar(50))
			, [TERM]					= cast(max([TERM])							as varchar(50))
			, [CFS]						= cast(max([CFS])							as varchar(50))
			, [CO]						= cast(max([CO])							as varchar(50))
			, [INTTRA_BKOFFICE]			= cast(max([INTTRA_BKOFFICE])				as varchar(50))
			, [GHAGENT]					= cast(max([GHAGENT])						as varchar(50))
			, [THIRDPARTY]				= cast(max([THIRDPARTY])					as varchar(50))
			, [BA]						= cast(max([BA])							as varchar(50))
			, [CSOR]					= cast(max([CSOR])							as varchar(50))
			, [SH]						= cast(max([SH])							as varchar(50))
			, [NT]						= cast(max([NT])							as varchar(50))
			, [SE]						= cast(max([SE])							as varchar(50))
			, [MCCGP]					= cast(max([MCCGP])							as varchar(50))
			, [DEL]						= cast(max([DEL])							as varchar(50))
			, [FCRBUYER]				= cast(max([FCRBUYER])						as varchar(50))
			, [INTTRA_FRTPAYER]			= cast(max([INTTRA_FRTPAYER])				as varchar(50))
			, [STATISTICS]				= cast(max([STATISTICS])					as varchar(50))
			, SCD_UpdateDate			= max(SCD_UpdateDate)
			, UniqueRecordKey			= utilities.ufn_GetHashedUID('TMFF', JOB_UNID, default, default, default)
			, DataAgeHOT				= max(SCD_UpdateDate)
			, DataAgeCOLD				= max(SCD_UpdateDate)
			, RecordChangeDateTime		= getdate()	
												

from		ODS.TMFF_JOBPARTY jp
pivot		(
			max(PARTYID)
			for	PARTYTYPE in 
				(
			  [SCREENING]
			, [OAGENT]
			, [FCRBUYER]
			, [GHAGENT]
			, [BROKER]
			, [HANDLINGAGENT]
			, [INTTRA_FRTPAYER]
			, [CUSTLIST]
			, [SE]
			, [TERM]
			, [SUBCONTRACTOR]
			, [THIRDPARTY]
			, [INTTRA_BKOFFICE]
			, [LOCATIONORIGINAL]
			, [CSOR]
			, [MCCGP]
			, [TRUCKING]
			, [INS]
			, [COL]
			, [ORAG]
			, [BY]
			, [STATISTICS]
			, [REALCSGN]
			, [ALSONTFY]
			, [CO]
			, [CONTRA]
			, [CONTROLPARTY]
			, [QUARANTINE]
			, [PAY]
			, [SH]
			, [PCF]
			, [CS]
			, [EXPASSIGNEE]
			, [WAREHOUSE]
			, [BA]
			, [CARRIERAGENTO]
			, [DEL]
			, [NT]
			, [ALSONTFY2]
			, [CFS]
			, [CU]
			, [CL]
				)
			) pvt
where		SCD_ActiveFlag = 1
and			SCD_IsDeleted = 0
group by	job_unid
GO
/****** Object:  View [CALC].[v_TMFF_RecognitionEvents]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-7385 --Objective Fix discrepancies
--prevtask COBI-6733, hash=-1092941365
--exec utilities.usp_ConvertViewToLoadComplex 'CALC', 'v_TMFF_RecognitionEvents'
--select * from utilities.vcheckdefinitionsyncronization where ObjectName = 'v_TMFF_RecognitionEvents'
CREATE view [CALC].[v_TMFF_RecognitionEvents]
as
select		  JOB_UNID				
			, SNO					
			, CHRGCODE				
			, CHRGDESC				
			, CHARGETYPE			
			, RECORDAMTLC			
			, RECORDSTATE			
			, RECOGNITIONDATE		
			, src					
			, Invoiceunid			
			, AMTLC					
			, AMTFC					
			, ACTUALAMTLC			
			, ACTUALAMTFC			
			, CREATEDATE			
			, UPDATEDATE			
			, CRI					
			, PARTYID_COUNTERPARTY	
			, DOCDATE				
			, DOCNO					
			, INVSTS				
			, CURRCODE				
			, ACTUALCURRCODE	
			, UniqueRecordKey			= utilities.ufn_GetHashedUID('TMFF', JOB_UNID, SNO, CHARGETYPE, default)
			, DateAgeHot				= SCD_UpdateDate
			, DateAgeCold				= SCD_UpdateDate
			, RecordChangeDateTime		= getdate()
from		(
			--########### C O S T #########################
			--retrieve all recognitions and unrecognized amounts.
			--1. here we retrieve all recognitions from changelog, the base table and the invoice details. plus non-actualized residualamounts and actualized non-recognized amounts
			--we do that for changelog and base table in one go and for invoices in a second and then do a union all.
			select		  JOB_UNID					=	JOB_UNID
						, SNO						=	COST_SNO
						, CHRGCODE					=	CHRGCODE
						, CHRGDESC					=	CHRGDESC
						, CHARGETYPE				=	'COST'
						, RECORDAMTLC				=	x.RECOGNITIONAMTLC * multiplier - Prev_RECOGNITIONAMTLC * prev_multiplier
						, RECORDSTATE				=	'ESTIMATED-RECOGNIZED'
						, RECOGNITIONDATE			=	RECOGNITIONDATE
						, src						=	src
						, Invoiceunid				=	Invoiceunid
						, AMTLC						=	AMTLC
						, AMTFC						=	AMTFC
						, ACTUALAMTLC				=	ACTUALAMTLC
						, ACTUALAMTFC				=	ACTUALAMTFC
						, CREATEDATE				=	CREATEDATE
						, UPDATEDATE				=	UPDATEDATE
						, CRI						=	CRI
						, PARTYID_COUNTERPARTY		=	PARTYID_COUNTERPARTY
						, DOCDATE					=	DOCDATE
						, DOCNO						=	DOCNO									
						, INVSTS					=	INVSTS
						, CURRCODE					=	CURRCODE
						, ACTUALCURRCODE			=	ACTUALCURRCODE
						, SCD_UpdateDate			=	SCD_UpdateDate
			from		(
						--Changelog and base table 
						--  the inner union can retrieve records that do not have a change in amount so it does not warrant registration.
						--  so, in the outer select we limit to only the relevant changes.
						select		*
									, Prev_RECOGNITIONAMTLC		=	lag(RECOGNITIONAMTLC, 1, 0) over (partition by JOB_UNID, COST_SNO order by SNO)
									, Prev_Multiplier			=	lag(Multiplier, 1, 0) over (partition by JOB_UNID, COST_SNO order by SNO)
									, Prev_RECOGNITIONDATE		=	lag(RECOGNITIONDATE, 1, null) over (partition by JOB_UNID, COST_SNO order by SNO)
						from		(
									--Here we find any changelogs that have a recognitiondate that is different from the previous record in changelog
									--Since the update of recognitiondate does not create a new record in changelog, the recognitiondate actually applies to the record before the one with the current recognitiondate.
									--therefore we return CHRGCODE and DOCTYPE from the previous record.
									select		  JOB_UNID				=	cln.JOB_UNID
												, COST_SNO				=	cln.COST_SNO
												, SNO					=	cln.SNO
												, CHRGCODE				=	coalesce(clp.CHRGCODE, cln.CHRGCODE)	--intentionally using clp... -see above
												, CHRGDESC				=	coalesce(clp.CHRGDESC, cln.CHRGDESC)
												, RECOGNITIONAMTLC		=	cln.RECOGNITIONAMTLC
												, RECOGNITIONDATE		=	cln.RECOGNITIONDATE
												, src					=	'CHANGELOGCOST'
												, Multiplier			=	case when coalesce(clp.DOCTYPE,cln.DOCTYPE) = 'CN' then -1 else 1 end --intentionally using clp... -see above
												, invoiceunid			=	cast(null as bigint)
												, AMTLC					=	coalesce(l.AMTLC, cln.AMTLC)
												, AMTFC					=	coalesce(l.AMTFC, cln.AMTFC)
												, ACTUALAMTLC			=	coalesce(l.ACTUALAMTLC , cln.ACTUALAMTLC)
												, ACTUALAMTFC			=	coalesce(l.ACTUALAMTBC , cln.ACTUALAMTBC)
												, CREATEDATE			=	coalesce(l.CREATEDATE  , cln.CHANGEDATE )
												, UPDATEDATE			=	coalesce(l.UPDATEDATE, cln.CHANGEDATE)
												, CRI					=	hdr.CRI
												, PARTYID_COUNTERPARTY	=	l.PAYEE_PARTYID
												, DOCDATE				=	hdr.APDOCDATE
												, DOCNO					=	hdr.APDOCNO									
												, INVSTS				=	coalesce(l.INVSTS, cln.INVSTS)
												, CURRCODE				=	coalesce(l.CURRCODE, cln.CURRCODE)
												, ACTUALCURRCODE		=	coalesce(l.ACTUALCURRCODE, cln.ACTUALCURRCODE)
												, SCD_UpdateDate		=	cln.SCD_UpdateDate
									from		ODS.TMFF_CHANGELOGCOST cln --Change Log Now
									join		ODS.TMFF_COST l
									on			l.JOB_UNID = cln.JOB_UNID
									and			l.SNO = cln.COST_SNO
									and			l.SCD_ActiveFlag = 1
									and			l.SCD_IsDeleted = 0
									left join	ODS.TMFF_CHANGELOGCOST clp --Change Log Previous
									on			clp.JOB_UNID = cln.JOB_UNID
									and			clp.COST_SNO = cln.COST_SNO
									and			clp.SNO = cln.SNO - 1
									and			clp.SCD_ActiveFlag = 1
									and			clp.SCD_IsDeleted = 0
									left join	ODS.TMFF_CPVDTL dtl
									on			cln.JOB_UNID = dtl.SOURCEUNID
									and			cln.COST_SNO = dtl.SOURCESNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									left join	ODS.TMFF_CPVHDR hdr
									on			hdr.UNID = dtl.CPVHDR_UNID
									and			hdr.SCD_ActiveFlag = 1
									and			hdr.SCD_IsDeleted = 0
									where		cln.RECOGNITIONDATE is not null
									and			isnull(l.INVSTS, '') not in ('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or Credited (C) as they are replaced by new charge lines.
									and			isnull(clp.RECOGNITIONDATE, '19000101') <> cln.RECOGNITIONDATE
									and			cln.SCD_ActiveFlag = 1
									and			cln.SCD_IsDeleted = 0
									union all
									--base table
									select		  JOB_UNID				=	l.JOB_UNID
												, COST_SNO				=	l.SNO
												, SNO					=	999999
												, CHRGCODE				=	l.CHRGCODE
												, CHRGDESC				=	l.CHRGDESC
												, RECOGNITIONAMTLC		=	l.RECOGNITIONAMTLC	
												, RECOGNITIONDATE		=	l.RECOGNITIONDATE	
												, src					=	'COST'
												, Multiplier			=	case when l.DOCTYPE = 'CN' then -1 else 1 end
												, invoiceunid			=	cast(null as bigint)
												, AMTLC					=	l.AMTLC
												, AMTFC					=	l.AMTFC
												, ACTUALAMTLC			=	l.ACTUALAMTLC
												, ACTUALAMTFC			=	l.ACTUALAMTBC
												, CREATEDATE			=	l.CREATEDATE
												, UPDATEDATE			=	l.UPDATEDATE
												, CRI					=	hdr.CRI
												, PARTYID_COUNTERPARTY	=	l.PAYEE_PARTYID
												, DOCDATE				=	hdr.APDOCDATE
												, DOCNO					=	hdr.APDOCNO									
												, INVSTS				=	l.INVSTS
												, CURRCODE				=	l.CURRCODE
												, ACTUALCURRCODE		=	l.ACTUALCURRCODE
												, SCD_UpdateDate		=	l.SCD_UpdateDate
									from		ODS.TMFF_COST l
									left join	ODS.TMFF_CPVDTL dtl
									on			l.JOB_UNID = dtl.SOURCEUNID
									and			l.SNO = dtl.SOURCESNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									left join	ODS.TMFF_CPVHDR hdr
									on			hdr.UNID = dtl.CPVHDR_UNID
									and			hdr.SCD_ActiveFlag = 1
									and			hdr.SCD_IsDeleted = 0
									where		l.SCD_ActiveFlag = 1
									and			l.SCD_IsDeleted = 0
									and			l.RECOGNITIONDATE is not null
									and			isnull(l.INVSTS, '') not in ('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or credited (C) as they are replaced by new charge lines.
									--changelog that are no longer in base table
									--  for a while it was possible to delete recognized charge lines. 
									--  when fixing it, amounts were matched, but in some cases not all deleted posts were recreated. 
									--  Instead the amounts on another record was increased. So we need to create a negation record 
									--  to set the recognized amount for that particular line to 0 in the recognition period. 
									union all
									select		  JOB_UNID				=	JOB_UNID
												, COST_SNO				=	COST_SNO		
												, SNO					=	999999
												, CHRGCODE				=	CHRGCODE
												, CHRGDESC				=	CHRGDESC
												, RECOGNITIONAMTLC		=	0
												, RECOGNITIONDATE		=	RECOGNITIONDATE
												, src					=	src
												, Multiplier			=	Multiplier 
												, invoiceunid			=	cast(null as bigint)
												, AMTFC					=	AMTFC
												, AMTLC					=	AMTLC
												, ACTUALAMTLC			=	ACTUALAMTLC
												, ACTUALAMTFC			=	ACTUALAMTBC
												, CREATEDATE			=	null
												, UPDATEDATE			=	CHANGEDATE
												, CRI					=	cast(null as nvarchar(2))
												, PARTYID_COUNTERPARTY	=	PAYEE_PARTYID
												, DOCDATE				=	cast(null as datetime)
												, DOCNO					=	cast(null as nvarchar(40))
												, INVSTS				=	INVSTS
												, CURRCODE				=	CURRCODE
												, ACTUALCURRCODE		=	ACTUALCURRCODE
												, SCD_UpdateDate		=	SCD_UpdateDate
									from		(
												select		  JOB_UNID
															, COST_SNO		
															, CHRGCODE
															, CHRGDESC
															, PAYEE_PARTYID
															, RECOGNITIONAMTLC
															, RECOGNITIONDATE
															, src					=	'CHANGELOGCOST_NULLIFICATION'
															, ix					=	row_number() over (partition by JOB_UNID, COST_SNO order by SNO desc) 
															, Multiplier			=	case when DOCTYPE = 'CN' then -1 else 1 end
															, AMTLC						
															, AMTFC						
															, ACTUALAMTLC
															, ACTUALAMTBC
															, INVSTS
															, CURRCODE				
															, CHANGEDATE
															, ACTUALCURRCODE	
															, cl.SCD_UpdateDate	
												from		ODS.TMFF_CHANGELOGCOST cl
												where		cl.SCD_ActiveFlag = 1
												and			cl.SCD_IsDeleted = 0
												and			RECOGNITIONDATE is not null
												and			not exists	(
																		select		1
																		from		ODS.TMFF_COST l
																		where		l.JOB_UNID = cl.JOB_UNID
																		and			l.SNO = cl.COST_SNO
																		and			l.SCD_ActiveFlag = 1
																		and			l.SCD_IsDeleted = 0
																		)
												) x
									where		ix = 1
									) x
						) x
			where		x.Prev_RECOGNITIONAMTLC <> x.RECOGNITIONAMTLC --this is what filters out unnecessary duplications
			union all
			--Now we extract recognitions for all invoices that have been recognized and where there is an amount change towards the base table
			select		  JOB_UNID					=	SOURCEUNID
						, SNO						=	SOURCESNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'COST'
						, RECORDAMTLC				=	case when hdr.DOCTYPE = 'CN' then -1 else 1 end * case when hdr.DOCTYPE = 'CN' and l.INVSTS is not null then dtl.AMTLC else dtl.AMTLC - case when l.RECOGNITIONDATE is not null then isnull(l.RECOGNITIONAMTLC, 0) else 0 end end --a credit note must be included in full if the line is marked with a C
						, RECORDSTATE				=	'ACTUALIZED-RECOGNIZED'
						, RECOGNITIONDATE			=	dtl.RECOGNITIONDATE
						, src						=	'CPVDTL'
						, invoiceunid				=	dtl.CPVHDR_UNID
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	hdr.CRI
						, PARTYID_COUNTERPARTY		=	l.PAYEE_PARTYID
						, DOCDATE					=	hdr.APDOCDATE
						, DOCNO						=	hdr.APDOCNO
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	dtl.SCD_UpdateDate
			from		ODS.TMFF_CPVDTL dtl
			join		ODS.TMFF_COST l
			on			l.JOB_UNID = dtl.SOURCEUNID
			and			l.SNO = dtl.SOURCESNO
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			join		ODS.TMFF_CPVHDR hdr
			on			hdr.UNID = dtl.CPVHDR_UNID
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			where		dtl.RECOGNITIONDATE is not null
			and			hdr.VOIDDATE is null
			and			dtl.SCD_ActiveFlag = 1
			and			dtl.SCD_IsDeleted = 0
			union all
			--Now we extract from the base table that have not been actualized and where the AMTLC <> isnull(RECOGNIZEDAMTLC, 0)
			select		  JOB_UNID					=	JOB_UNID
						, SNO						=	SNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'COST'
						, RECORDAMTLC				=	(AMTLC - isnull(RECOGNITIONAMTLC, 0)) * case when l.DOCTYPE = 'CN' then -1 else 1 end
						, RECORDSTATE				=	'ESTIMATED'
						, RECOGNITIONDATE			=	cast(null as datetime)
						, src						=	'COST'
						, invoiceunid				=	cast(null as bigint)
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	cast(null as nvarchar(2))
						, PARTYID_COUNTERPARTY		=	cast(null as nvarchar(100))
						, DOCDATE					=	cast(null as datetime)
						, DOCNO						=	cast(null as nvarchar(40))
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	l.SCD_UpdateDate
			from		ODS.TMFF_COST l
			where		l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			and			not exists	(
									select		1
									from		ODS.TMFF_CPVDTL dtl
									where		dtl.SOURCEUNID = l.JOB_UNID
									and			dtl.SOURCESNO = l.SNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									)
			and			isnull(INVSTS, '') not in ('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or credited (C) as they are replaced by new charge lines.
			and			AMTLC is not null
			and			AMTLC <> isnull(RECOGNITIONAMTLC, 0)
			--lastly we take any invoice details that have not yet been recognized
			--we still need to correct for any recognized amounts on the base table
			union all
			select		  JOB_UNID					=	dtl.SOURCEUNID
						, SNO						=	dtl.SOURCESNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'COST'
						, RECORDAMTLC				=	case when hdr.DOCTYPE = 'CN' then -1 else 1 end * (dtl.AMTLC - case when hdr.DOCTYPE = 'CN' and l.INVSTS = 'C' then 0 else isnull(l.RECOGNITIONAMTLC, 0) end)
						, RECORDSTATE				=	'ACTUALIZED'
						, RECOGNITIONDATE			=	cast(null as datetime)
						, src						=	'CPVDTL'
						, invoiceunid				=	dtl.CPVHDR_UNID
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	hdr.CRI
						, PARTYID_COUNTERPARTY		=	l.PAYEE_PARTYID
						, DOCDATE					=	hdr.APDOCDATE
						, DOCNO						=	hdr.APDOCNO
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	dtl.SCD_UpdateDate
			from		ODS.TMFF_CPVDTL dtl
			join		ODS.TMFF_CPVHDR hdr
			on			hdr.UNID = dtl.CPVHDR_UNID
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			join		ODS.TMFF_COST l
			on			l.JOB_UNID = dtl.SOURCEUNID
			and			l.SNO = dtl.SOURCESNO
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			where		dtl.RECOGNITIONDATE is null
			and			hdr.VOIDDATE is null
			and			dtl.SCD_ActiveFlag = 1
			and			dtl.SCD_IsDeleted = 0
			union all
			--########### REVENUE #########################
			--retrieve all recognitions and unrecognized amounts.
			--So, all the core postings. Then we eventually join them with the Jobrevenueing in order to distribute to return only on Houses and Houseless Masters
			--1. here we retrieve all recognitions from changelog, the base table and the invoice details. plus non-actualized residualamounts and actualized non-recognized amounts
			--we do that for changelog and base table in one go and for invoices in a second and then do a union all.
			select		  JOB_UNID					=	JOB_UNID
						, SNO						=	REVENUE_SNO
						, CHRGCODE					=	CHRGCODE
						, CHRGDESC					=	CHRGDESC
						, CHARGETYPE				=	'REVENUE'
						, RECORDAMTLC				=	RECOGNITIONAMTLC  * Multiplier - Prev_RECOGNITIONAMTLC * Prev_Multiplier
						, RECORDSTATE				=	'ESTIMATED-RECOGNIZED'
						, RECOGNITIONDATE			=	RECOGNITIONDATE
						, src						=	src
						, Invoiceunid				=	Invoiceunid
						, AMTLC						=	AMTLC
						, AMTFC						=	AMTFC
						, ACTUALAMTLC				=	ACTUALAMTLC
						, ACTUALAMTFC				=	ACTUALAMTFC
						, CREATEDATE				=	CREATEDATE
						, UPDATEDATE				=	UPDATEDATE
						, CRI						=	CRI
						, PARTYID_COUNTERPARTY		=	PARTYID_COUNTERPARTY
						, DOCDATE					=	DOCDATE
						, DOCNO						=	DOCNO									
						, INVSTS					=	INVSTS
						, CURRCODE					=	CURRCODE
						, ACTUALCURRCODE			=	ACTUALCURRCODE
						, SCD_UpdateDate			=	SCD_UpdateDate
			from		(
						--Changelog and base table 
						--  the inner union can retrieve records that do not have a change in amount so it does not warrant registration.
						--  so, in the outer select we limit to only the relevant changes.
						select		*
									, Prev_RECOGNITIONAMTLC		=	lag(RECOGNITIONAMTLC, 1, 0) over (partition by JOB_UNID, REVENUE_SNO order by SNO)
									, Prev_Multiplier			=	lag(Multiplier, 1, 0) over (partition by JOB_UNID, REVENUE_SNO order by SNO)
									, Prev_RECOGNITIONDATE		=	lag(RECOGNITIONDATE, 1, null) over (partition by JOB_UNID, REVENUE_SNO order by SNO)
						from		(
									--Here we find any changelogs that have a recognitiondate that is different from the previous record in changelog
									--Since the update of recognitiondate does not create a new record in changelog, the recognitiondate actually applies to the record before the one with the current recognitiondate.
									--therefore we return CHRGCODE and DOCTYPE from the previous record.
									select		  JOB_UNID				=	cln.JOB_UNID
												, REVENUE_SNO			=	cln.REVENUE_SNO
												, SNO					=	cln.SNO
												, CHRGCODE				=	coalesce(clp.CHRGCODE, cln.CHRGCODE)	--intentionally using clp as first choice... -see above
												, CHRGDESC				=	coalesce(clp.CHRGDESC, cln.CHRGDESC)
												, RECOGNITIONAMTLC		=	cln.RECOGNITIONAMTLC
												, RECOGNITIONDATE		=	cln.RECOGNITIONDATE
												, src					=	'CHANGELOGREV'
												, Multiplier			=	case when clp.DOCTYPE = 'CN' then -1 else 1 end --intentionally using clp... -see above
												, invoiceunid			=	cast(null as bigint)
												, AMTLC					=	coalesce(l.AMTLC, cln.AMTLC)
												, AMTFC					=	coalesce(l.AMTFC, cln.AMTFC)
												, ACTUALAMTLC			=	coalesce(l.ACTUALAMTLC , cln.ACTUALAMTLC)
												, ACTUALAMTFC			=	coalesce(l.ACTUALAMTBC , cln.ACTUALAMTBC)
												, CREATEDATE			=	coalesce(l.CREATEDATE  , cln.CHANGEDATE )
												, UPDATEDATE			=	coalesce(l.UPDATEDATE, cln.CHANGEDATE)
												, CRI					=	hdr.CRI
												, PARTYID_COUNTERPARTY	=	hdr.PARTYID_CUST
												, DOCDATE				=	hdr.DOCDATE
												, DOCNO					=	hdr.DOCNO									
												, INVSTS				=	coalesce(l.INVSTS, cln.INVSTS)
												, CURRCODE				=	coalesce(l.CURRCODE, cln.CURRCODE)
												, ACTUALCURRCODE		=	coalesce(l.ACTUALCURRCODE, cln.ACTUALCURRCODE)
												, SCD_UpdateDate		=	cln.SCD_UpdateDate
									from		ODS.TMFF_CHANGELOGREV cln --Change Log Now
									join		ODS.TMFF_REVENUE l
									on			l.JOB_UNID = cln.JOB_UNID
									and			l.SNO = cln.REVENUE_SNO
									and			l.SCD_ActiveFlag = 1
									and			l.SCD_IsDeleted = 0
									left join	ODS.TMFF_CHANGELOGREV clp --Change Log Previous
									on			clp.JOB_UNID = cln.JOB_UNID
									and			clp.REVENUE_SNO = cln.REVENUE_SNO
									and			clp.SNO = cln.SNO - 1
									and			clp.SCD_ActiveFlag = 1
									and			clp.SCD_IsDeleted = 0
									left join	ODS.TMFF_IVDTL dtl
									on			cln.JOB_UNID = dtl.SOURCEUNID
									and			cln.REVENUE_SNO = dtl.SOURCESNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									left join	ODS.TMFF_IVHDR hdr
									on			hdr.UNID = dtl.IVHDR_UNID
									and			hdr.SCD_ActiveFlag = 1
									and			hdr.SCD_IsDeleted = 0
									where		cln.RECOGNITIONDATE is not null
									and			isnull(l.INVSTS, '') not in ('V')--('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or Credited (C) as they are replaced by new charge lines.
									and			isnull(clp.RECOGNITIONDATE, '19000101') <> cln.RECOGNITIONDATE
									and			cln.SCD_ActiveFlag = 1
									and			cln.SCD_IsDeleted = 0
									union all
									--base table
									select		  JOB_UNID				=	l.JOB_UNID
												, REVENUE_SNO			=	l.SNO
												, SNO					=	999999
												, CHRGCODE				=	l.CHRGCODE
												, CHRGDESC				=	l.CHRGDESC
												, RECOGNITIONAMTLC		=	l.RECOGNITIONAMTLC	
												, RECOGNITIONDATE		=	l.RECOGNITIONDATE	
												, src					=	'REVENUE'
												, Multiplier			=	case when l.DOCTYPE = 'CN' then -1 else 1 end
												, invoiceunid			=	cast(null as bigint)
												, AMTLC					=	l.AMTLC
												, AMTFC					=	l.AMTFC
												, ACTUALAMTLC			=	l.ACTUALAMTLC
												, ACTUALAMTFC			=	l.ACTUALAMTBC
												, CREATEDATE			=	l.CREATEDATE
												, UPDATEDATE			=	l.UPDATEDATE
												, CRI					=	hdr.CRI
												, PARTYID_COUNTERPARTY	=	l.BILLING_PARTYID
												, DOCDATE				=	hdr.DOCDATE
												, DOCNO					=	hdr.DOCNO									
												, INVSTS				=	l.INVSTS
												, CURRCODE				=	l.CURRCODE
												, ACTUALCURRCODE		=	l.ACTUALCURRCODE
												, SCD_UpdateDate		=	l.SCD_UpdateDate
									from		ODS.TMFF_REVENUE l
									left join	ODS.TMFF_IVDTL dtl
									on			l.JOB_UNID = dtl.SOURCEUNID
									and			l.SNO = dtl.SOURCESNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									left join	ODS.TMFF_IVHDR hdr
									on			hdr.UNID = dtl.IVHDR_UNID
									and			hdr.SCD_ActiveFlag = 1
									and			hdr.SCD_IsDeleted = 0
									where		l.SCD_ActiveFlag = 1
									and			l.SCD_IsDeleted = 0
									and			l.RECOGNITIONDATE is not null
									and			isnull(l.INVSTS, '') not in ('V')--('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or credited (C) as they are replaced by new charge lines.
									--changelog that are no longer in base table
									--  for a while it was possible to delete recognized charge lines. 
									--  when fixing it, amounts were matched, but in some cases not all deleted posts were recreated. 
									--  Instead the amounts on another record was increased. So we need to create a negation record 
									--  to set the recognized amount for that particular line to 0 in the recognition period. 
									union all
									select		  JOB_UNID				=	JOB_UNID
												, REVENUE_SNO				=	REVENUE_SNO		
												, SNO					=	999999
												, CHRGCODE				=	CHRGCODE
												, CHRGDESC				=	CHRGDESC
												, RECOGNITIONAMTLC		=	0
												, RECOGNITIONDATE		=	RECOGNITIONDATE
												, src					=	src
												, Multiplier			=	Multiplier 
												, invoiceunid			=	cast(null as bigint)
												, AMTFC					=	AMTFC
												, AMTLC					=	AMTLC
												, ACTUALAMTLC			=	ACTUALAMTLC
												, ACTUALAMTFC			=	ACTUALAMTBC
												, CREATEDATE			=	null
												, UPDATEDATE			=	CHANGEDATE
												, CRI					=	cast(null as nvarchar(2))
												, PARTYID_COUNTERPARTY	=	BILLING_PARTYID
												, DOCDATE				=	cast(null as datetime)
												, DOCNO					=	cast(null as nvarchar(40))
												, INVSTS				=	INVSTS
												, CURRCODE				=	CURRCODE
												, ACTUALCURRCODE		=	ACTUALCURRCODE
												, SCD_UpdateDate		=	SCD_UpdateDate
									from		(
												select		  JOB_UNID
															, REVENUE_SNO		
															, CHRGCODE
															, CHRGDESC
															, BILLING_PARTYID
															, RECOGNITIONAMTLC
															, RECOGNITIONDATE
															, src					=	'CHANGELOG_NULLIFICATION'
															, ix					=	row_number() over (partition by JOB_UNID, REVENUE_SNO order by SNO desc) 
															, Multiplier			=	case when DOCTYPE = 'CN' then -1 else 1 end
															, AMTLC						
															, AMTFC						
															, ACTUALAMTLC
															, ACTUALAMTBC
															, INVSTS
															, CURRCODE				
															, CHANGEDATE
															, ACTUALCURRCODE		
															, SCD_UpdateDate
												from		ODS.TMFF_CHANGELOGREV cl
												where		cl.SCD_ActiveFlag = 1
												and			cl.SCD_IsDeleted = 0
												and			RECOGNITIONDATE is not null
												and			not exists	(
																		select		1
																		from		ODS.TMFF_REVENUE l
																		where		l.JOB_UNID = cl.JOB_UNID
																		and			l.SNO = cl.REVENUE_SNO
																		and			l.SCD_ActiveFlag = 1
																		and			l.SCD_IsDeleted = 0
																		)
												) x
									where		ix = 1
									) x
						) x
			where		x.Prev_RECOGNITIONAMTLC  <> x.RECOGNITIONAMTLC --this is what filters out unnecessary duplications
			union all
			--Now we extract recognitions for all invoices that have been recognized and where there is an amount change towards the base table
			select		  JOB_UNID					=	SOURCEUNID
						, SNO						=	SOURCESNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'REVENUE'
						, RECORDAMTLC				=	case when hdr.DOCTYPE = 'CN' then -1 else 1 end * case when hdr.DOCTYPE = 'CN' and l.INVSTS is not null then dtl.AMTLC else dtl.AMTLC - case when l.RECOGNITIONDATE is not null then isnull(l.RECOGNITIONAMTLC, 0) else 0 end end --a credit note must be included in full if the line is marked with a C
						, RECORDSTATE				=	'ACTUALIZED-RECOGNIZED'
						, RECOGNITIONDATE			=	dtl.RECOGNITIONDATE
						, src						=	'IVDTL'
						, invoiceunid				=	dtl.IVHDR_UNID
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	hdr.CRI
						, PARTYID_COUNTERPARTY		=	l.BILLING_PARTYID
						, DOCDATE					=	hdr.DOCDATE
						, DOCNO						=	hdr.DOCNO
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	l.SCD_UpdateDate
			from		ODS.TMFF_IVDTL dtl
			join		ODS.TMFF_REVENUE l
			on			l.JOB_UNID = dtl.SOURCEUNID
			and			l.SNO = dtl.SOURCESNO
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			join		ODS.TMFF_IVHDR hdr
			on			hdr.UNID = dtl.IVHDR_UNID
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			where		dtl.RECOGNITIONDATE is not null
			and			hdr.VOIDDATE is null
			and			dtl.SCD_ActiveFlag = 1
			and			dtl.SCD_IsDeleted = 0
			union all
			--Now we extract from the base table that have not been actualized and where the AMTLC <> isnull(RECOGNIZEDAMTLC, 0)
			select		  JOB_UNID					=	JOB_UNID
						, SNO						=	SNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'REVENUE'
						, RECORDAMTLC				=	(AMTLC - isnull(RECOGNITIONAMTLC, 0)) * case when l.DOCTYPE = 'CN' then -1 else 1 end
						, RECORDSTATE				=	'ESTIMATED'
						, RECOGNITIONDATE			=	cast(null as datetime)
						, src						=	'REVENUE'
						, invoiceunid				=	cast(null as bigint)
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	cast(null as nvarchar(2))
						, PARTYID_COUNTERPARTY		=	l.BILLING_PARTYID
						, DOCDATE					=	cast(null as datetime)
						, DOCNO						=	cast(null as nvarchar(40))
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	l.SCD_UpdateDate
			from		ODS.TMFF_REVENUE l
			where		not exists	(
									select		1
									from		ODS.TMFF_IVDTL dtl
									where		dtl.SOURCEUNID = l.JOB_UNID
									and			dtl.SOURCESNO = l.SNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									)
			and			isnull(INVSTS, '') not in ('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or credited (C) as they are replaced by new charge lines.
			and			AMTLC is not null
			and			AMTLC <> isnull(RECOGNITIONAMTLC, 0)
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			--lastly we take any invoice details that have not yet been recognized
			--we still need to correct for any recognized amounts on the base table
			union all
			select		  JOB_UNID					=	dtl.SOURCEUNID
						, SNO						=	dtl.SOURCESNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'REVENUE'
						, RECORDAMTLC				=	case when hdr.DOCTYPE = 'CN' then -1 else 1 end * (dtl.AMTLC - case when hdr.DOCTYPE = 'CN' and l.INVSTS = 'C' then 0 else isnull(l.RECOGNITIONAMTLC, 0) end)
						, RECORDSTATE				=	'ACTUALIZED'
						, RECOGNITIONDATE			=	cast(null as datetime)
						, src						=	'IVDTL'
						, invoiceunid				=	dtl.IVHDR_UNID
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	hdr.CRI
						, PARTYID_COUNTERPARTY		=	l.BILLING_PARTYID
						, DOCDATE					=	hdr.DOCDATE
						, DOCNO						=	hdr.DOCNO
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	l.SCD_UpdateDate
			from		ODS.TMFF_IVDTL dtl
			join		ODS.TMFF_IVHDR hdr
			on			hdr.UNID = dtl.IVHDR_UNID
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			join		ODS.TMFF_REVENUE l
			on			l.JOB_UNID = dtl.SOURCEUNID
			and			l.SNO = dtl.SOURCESNO
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			where		dtl.RECOGNITIONDATE is null
			and			hdr.VOIDDATE is null
			and			dtl.SCD_ActiveFlag = 1
			and			dtl.SCD_IsDeleted = 0
			) recog
GO
/****** Object:  View [CALC].[v_TMFF_RecognitionEvents_AG_DEBUG_20260622]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--exec calc.usp_Load_TMFF_RecognitionEvents



--COBI-6930 --Objective CHRGCODE and CHRGDESC adjustment
--prevtask COBI-6733, hash=-2017846912
--exec utilities.usp_ConvertViewToLoadComplex 'CALC', 'v_TMFF_RecognitionEvents'
--select * from utilities.vcheckdefinitionsyncronization where ObjectName = 'v_TMFF_RecognitionEvents'
create view [CALC].[v_TMFF_RecognitionEvents_AG_DEBUG_20260622]
as
select		  JOB_UNID				
			, SNO					
			, CHRGCODE				
			, CHRGDESC				
			, CHARGETYPE			
			, RECORDAMTLC			
			, RECORDSTATE			
			, RECOGNITIONDATE		
			, src					
			, Invoiceunid			
			, AMTLC					
			, AMTFC					
			, ACTUALAMTLC			
			, ACTUALAMTFC			
			, CREATEDATE			
			, UPDATEDATE			
			, CRI					
			, PARTYID_COUNTERPARTY	
			, DOCDATE				
			, DOCNO					
			, INVSTS				
			, CURRCODE				
			, ACTUALCURRCODE	
			, UniqueRecordKey			= utilities.ufn_GetHashedUID('TMFF', JOB_UNID, SNO, CHARGETYPE, default)
			, DateAgeHot				= SCD_UpdateDate
			, DateAgeCold				= SCD_UpdateDate
			, RecordChangeDateTime		= getdate()
from		(
			--########### C O S T #########################
			--retrieve all recognitions and unrecognized amounts.
			--1. here we retrieve all recognitions from changelog, the base table and the invoice details. plus non-actualized residualamounts and actualized non-recognized amounts
			--we do that for changelog and base table in one go and for invoices in a second and then do a union all.
			select		  JOB_UNID					=	JOB_UNID
						, SNO						=	COST_SNO
						, CHRGCODE					=	CHRGCODE
						, CHRGDESC					=	CHRGDESC
						, CHARGETYPE				=	'COST'
						, RECORDAMTLC				=	x.RECOGNITIONAMTLC * multiplier - Prev_RECOGNITIONAMTLC * prev_multiplier
						, RECORDSTATE				=	'ESTIMATED-RECOGNIZED'
						, RECOGNITIONDATE			=	RECOGNITIONDATE
						, src						=	src
						, Invoiceunid				=	Invoiceunid
						, AMTLC						=	AMTLC
						, AMTFC						=	AMTFC
						, ACTUALAMTLC				=	ACTUALAMTLC
						, ACTUALAMTFC				=	ACTUALAMTFC
						, CREATEDATE				=	CREATEDATE
						, UPDATEDATE				=	UPDATEDATE
						, CRI						=	CRI
						, PARTYID_COUNTERPARTY		=	PARTYID_COUNTERPARTY
						, DOCDATE					=	DOCDATE
						, DOCNO						=	DOCNO									
						, INVSTS					=	INVSTS
						, CURRCODE					=	CURRCODE
						, ACTUALCURRCODE			=	ACTUALCURRCODE
						, SCD_UpdateDate			=	SCD_UpdateDate
			from		(
						--Changelog and base table 
						--  the inner union can retrieve records that do not have a change in amount so it does not warrant registration.
						--  so, in the outer select we limit to only the relevant changes.
						select		*
									, Prev_RECOGNITIONAMTLC		=	lag(RECOGNITIONAMTLC, 1, 0) over (partition by JOB_UNID, COST_SNO order by SNO)
									, Prev_Multiplier			=	lag(Multiplier, 1, 0) over (partition by JOB_UNID, COST_SNO order by SNO)
									, Prev_RECOGNITIONDATE		=	lag(RECOGNITIONDATE, 1, null) over (partition by JOB_UNID, COST_SNO order by SNO)
						from		(
									--Here we find any changelogs that have a recognitiondate that is different from the previous record in changelog
									--Since the update of recognitiondate does not create a new record in changelog, the recognitiondate actually applies to the record before the one with the current recognitiondate.
									--therefore we return CHRGCODE and DOCTYPE from the previous record.
									select		  JOB_UNID				=	cln.JOB_UNID
												, COST_SNO				=	cln.COST_SNO
												, SNO					=	cln.SNO
												, CHRGCODE				=	coalesce(clp.CHRGCODE, cln.CHRGCODE)	--intentionally using clp... -see above
												, CHRGDESC				=	coalesce(clp.CHRGDESC, cln.CHRGDESC)
												, RECOGNITIONAMTLC		=	cln.RECOGNITIONAMTLC
												, RECOGNITIONDATE		=	cln.RECOGNITIONDATE
												, src					=	'CHANGELOGCOST'
												, Multiplier			=	case when coalesce(clp.DOCTYPE,cln.DOCTYPE) = 'CN' then -1 else 1 end --intentionally using clp... -see above
												, invoiceunid			=	cast(null as bigint)
												, AMTLC					=	coalesce(l.AMTLC, cln.AMTLC)
												, AMTFC					=	coalesce(l.AMTFC, cln.AMTFC)
												, ACTUALAMTLC			=	coalesce(l.ACTUALAMTLC , cln.ACTUALAMTLC)
												, ACTUALAMTFC			=	coalesce(l.ACTUALAMTBC , cln.ACTUALAMTBC)
												, CREATEDATE			=	coalesce(l.CREATEDATE  , cln.CHANGEDATE )
												, UPDATEDATE			=	coalesce(l.UPDATEDATE, cln.CHANGEDATE)
												, CRI					=	hdr.CRI
												, PARTYID_COUNTERPARTY	=	l.PAYEE_PARTYID
												, DOCDATE				=	hdr.APDOCDATE
												, DOCNO					=	hdr.APDOCNO									
												, INVSTS				=	coalesce(l.INVSTS, cln.INVSTS)
												, CURRCODE				=	coalesce(l.CURRCODE, cln.CURRCODE)
												, ACTUALCURRCODE		=	coalesce(l.ACTUALCURRCODE, cln.ACTUALCURRCODE)
												, SCD_UpdateDate		=	cln.SCD_UpdateDate
									from		ODS.TMFF_CHANGELOGCOST cln --Change Log Now
									join		ODS.TMFF_COST l
									on			l.JOB_UNID = cln.JOB_UNID
									and			l.SNO = cln.COST_SNO
									and			l.SCD_ActiveFlag = 1
									and			l.SCD_IsDeleted = 0
									left join	ODS.TMFF_CHANGELOGCOST clp --Change Log Previous
									on			clp.JOB_UNID = cln.JOB_UNID
									and			clp.COST_SNO = cln.COST_SNO
									and			clp.SNO = cln.SNO - 1
									and			clp.SCD_ActiveFlag = 1
									and			clp.SCD_IsDeleted = 0
									left join	ODS.TMFF_CPVDTL dtl
									on			cln.JOB_UNID = dtl.SOURCEUNID
									and			cln.COST_SNO = dtl.SOURCESNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									left join	ODS.TMFF_CPVHDR hdr
									on			hdr.UNID = dtl.CPVHDR_UNID
									and			hdr.SCD_ActiveFlag = 1
									and			hdr.SCD_IsDeleted = 0
									where		cln.RECOGNITIONDATE is not null
									and			isnull(l.INVSTS, '') not in ('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or Credited (C) as they are replaced by new charge lines.
									and			isnull(clp.RECOGNITIONDATE, '19000101') <> cln.RECOGNITIONDATE
									and			cln.SCD_ActiveFlag = 1
									and			cln.SCD_IsDeleted = 0
									union all
									--base table
									select		  JOB_UNID				=	l.JOB_UNID
												, COST_SNO				=	l.SNO
												, SNO					=	999999
												, CHRGCODE				=	l.CHRGCODE
												, CHRGDESC				=	l.CHRGDESC
												, RECOGNITIONAMTLC		=	l.RECOGNITIONAMTLC	
												, RECOGNITIONDATE		=	l.RECOGNITIONDATE	
												, src					=	'COST'
												, Multiplier			=	case when l.DOCTYPE = 'CN' then -1 else 1 end
												, invoiceunid			=	cast(null as bigint)
												, AMTLC					=	l.AMTLC
												, AMTFC					=	l.AMTFC
												, ACTUALAMTLC			=	l.ACTUALAMTLC
												, ACTUALAMTFC			=	l.ACTUALAMTBC
												, CREATEDATE			=	l.CREATEDATE
												, UPDATEDATE			=	l.UPDATEDATE
												, CRI					=	hdr.CRI
												, PARTYID_COUNTERPARTY	=	l.PAYEE_PARTYID
												, DOCDATE				=	hdr.APDOCDATE
												, DOCNO					=	hdr.APDOCNO									
												, INVSTS				=	l.INVSTS
												, CURRCODE				=	l.CURRCODE
												, ACTUALCURRCODE		=	l.ACTUALCURRCODE
												, SCD_UpdateDate		=	l.SCD_UpdateDate
									from		ODS.TMFF_COST l
									left join	ODS.TMFF_CPVDTL dtl
									on			l.JOB_UNID = dtl.SOURCEUNID
									and			l.SNO = dtl.SOURCESNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									left join	ODS.TMFF_CPVHDR hdr
									on			hdr.UNID = dtl.CPVHDR_UNID
									and			hdr.SCD_ActiveFlag = 1
									and			hdr.SCD_IsDeleted = 0
									where		l.SCD_ActiveFlag = 1
									and			l.SCD_IsDeleted = 0
									and			l.RECOGNITIONDATE is not null
									and			isnull(l.INVSTS, '') not in ('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or credited (C) as they are replaced by new charge lines.
									--changelog that are no longer in base table
									--  for a while it was possible to delete recognized charge lines. 
									--  when fixing it, amounts were matched, but in some cases not all deleted posts were recreated. 
									--  Instead the amounts on another record was increased. So we need to create a negation record 
									--  to set the recognized amount for that particular line to 0 in the recognition period. 
									union all
									select		  JOB_UNID				=	JOB_UNID
												, COST_SNO				=	COST_SNO		
												, SNO					=	999999
												, CHRGCODE				=	CHRGCODE
												, CHRGDESC				=	CHRGDESC
												, RECOGNITIONAMTLC		=	0
												, RECOGNITIONDATE		=	RECOGNITIONDATE
												, src					=	src
												, Multiplier			=	Multiplier 
												, invoiceunid			=	cast(null as bigint)
												, AMTFC					=	AMTFC
												, AMTLC					=	AMTLC
												, ACTUALAMTLC			=	ACTUALAMTLC
												, ACTUALAMTFC			=	ACTUALAMTBC
												, CREATEDATE			=	null
												, UPDATEDATE			=	CHANGEDATE
												, CRI					=	cast(null as nvarchar(2))
												, PARTYID_COUNTERPARTY	=	PAYEE_PARTYID
												, DOCDATE				=	cast(null as datetime)
												, DOCNO					=	cast(null as nvarchar(40))
												, INVSTS				=	INVSTS
												, CURRCODE				=	CURRCODE
												, ACTUALCURRCODE		=	ACTUALCURRCODE
												, SCD_UpdateDate		=	SCD_UpdateDate
									from		(
												select		  JOB_UNID
															, COST_SNO		
															, CHRGCODE
															, CHRGDESC
															, PAYEE_PARTYID
															, RECOGNITIONAMTLC
															, RECOGNITIONDATE
															, src					=	'CHANGELOGCOST_NULLIFICATION'
															, ix					=	row_number() over (partition by JOB_UNID, COST_SNO order by SNO desc) 
															, Multiplier			=	case when DOCTYPE = 'CN' then -1 else 1 end
															, AMTLC						
															, AMTFC						
															, ACTUALAMTLC
															, ACTUALAMTBC
															, INVSTS
															, CURRCODE				
															, CHANGEDATE
															, ACTUALCURRCODE	
															, cl.SCD_UpdateDate	
												from		ODS.TMFF_CHANGELOGCOST cl
												where		cl.SCD_ActiveFlag = 1
												and			cl.SCD_IsDeleted = 0
												and			RECOGNITIONDATE is not null
												and			not exists	(
																		select		1
																		from		ODS.TMFF_COST l
																		where		l.JOB_UNID = cl.JOB_UNID
																		and			l.SNO = cl.COST_SNO
																		and			l.SCD_ActiveFlag = 1
																		and			l.SCD_IsDeleted = 0
																		)
												) x
									where		ix = 1
									) x
						) x
			where		x.Prev_RECOGNITIONAMTLC <> x.RECOGNITIONAMTLC --this is what filters out unnecessary duplications
			union all
			--Now we extract recognitions for all invoices that have been recognized and where there is an amount change towards the base table
			select		  JOB_UNID					=	SOURCEUNID
						, SNO						=	SOURCESNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'COST'
						, RECORDAMTLC				=	case when hdr.DOCTYPE = 'CN' then -1 else 1 end * case when hdr.DOCTYPE = 'CN' and l.INVSTS is not null then dtl.AMTLC else dtl.AMTLC - case when l.RECOGNITIONDATE is not null then isnull(l.RECOGNITIONAMTLC, 0) else 0 end end --a credit note must be included in full if the line is marked with a C
						, RECORDSTATE				=	'ACTUALIZED-RECOGNIZED'
						, RECOGNITIONDATE			=	dtl.RECOGNITIONDATE
						, src						=	'CPVDTL'
						, invoiceunid				=	dtl.CPVHDR_UNID
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	hdr.CRI
						, PARTYID_COUNTERPARTY		=	l.PAYEE_PARTYID
						, DOCDATE					=	hdr.APDOCDATE
						, DOCNO						=	hdr.APDOCNO
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	dtl.SCD_UpdateDate
			from		ODS.TMFF_CPVDTL dtl
			join		ODS.TMFF_COST l
			on			l.JOB_UNID = dtl.SOURCEUNID
			and			l.SNO = dtl.SOURCESNO
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			join		ODS.TMFF_CPVHDR hdr
			on			hdr.UNID = dtl.CPVHDR_UNID
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			where		dtl.RECOGNITIONDATE is not null
			and			hdr.VOIDDATE is null
			and			dtl.SCD_ActiveFlag = 1
			and			dtl.SCD_IsDeleted = 0
			union all
			--Now we extract from the base table that have not been actualized and where the AMTLC <> isnull(RECOGNIZEDAMTLC, 0)
			select		  JOB_UNID					=	JOB_UNID
						, SNO						=	SNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'COST'
						, RECORDAMTLC				=	(AMTLC - isnull(RECOGNITIONAMTLC, 0)) * case when l.DOCTYPE = 'CN' then -1 else 1 end
						, RECORDSTATE				=	'ESTIMATED'
						, RECOGNITIONDATE			=	cast(null as datetime)
						, src						=	'COST'
						, invoiceunid				=	cast(null as bigint)
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	cast(null as nvarchar(2))
						, PARTYID_COUNTERPARTY		=	cast(null as nvarchar(100))
						, DOCDATE					=	cast(null as datetime)
						, DOCNO						=	cast(null as nvarchar(40))
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	l.SCD_UpdateDate
			from		ODS.TMFF_COST l
			where		l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			and			not exists	(
									select		1
									from		ODS.TMFF_CPVDTL dtl
									where		dtl.SOURCEUNID = l.JOB_UNID
									and			dtl.SOURCESNO = l.SNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									)
			and			isnull(INVSTS, '') not in ('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or credited (C) as they are replaced by new charge lines.
			and			AMTLC is not null
			and			AMTLC <> isnull(RECOGNITIONAMTLC, 0)
			--lastly we take any invoice details that have not yet been recognized
			--we still need to correct for any recognized amounts on the base table
			union all
			select		  JOB_UNID					=	dtl.SOURCEUNID
						, SNO						=	dtl.SOURCESNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'COST'
						, RECORDAMTLC				=	case when hdr.DOCTYPE = 'CN' then -1 else 1 end * (dtl.AMTLC - case when hdr.DOCTYPE = 'CN' and l.INVSTS = 'C' then 0 else isnull(l.RECOGNITIONAMTLC, 0) end)
						, RECORDSTATE				=	'ACTUALIZED'
						, RECOGNITIONDATE			=	cast(null as datetime)
						, src						=	'CPVDTL'
						, invoiceunid				=	dtl.CPVHDR_UNID
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	hdr.CRI
						, PARTYID_COUNTERPARTY		=	l.PAYEE_PARTYID
						, DOCDATE					=	hdr.APDOCDATE
						, DOCNO						=	hdr.APDOCNO
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	dtl.SCD_UpdateDate
			from		ODS.TMFF_CPVDTL dtl
			join		ODS.TMFF_CPVHDR hdr
			on			hdr.UNID = dtl.CPVHDR_UNID
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			join		ODS.TMFF_COST l
			on			l.JOB_UNID = dtl.SOURCEUNID
			and			l.SNO = dtl.SOURCESNO
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			where		dtl.RECOGNITIONDATE is null
			and			hdr.VOIDDATE is null
			and			dtl.SCD_ActiveFlag = 1
			and			dtl.SCD_IsDeleted = 0
			union all
			--########### REVENUE #########################
			--retrieve all recognitions and unrecognized amounts.
			--So, all the core postings. Then we eventually join them with the Jobrevenueing in order to distribute to return only on Houses and Houseless Masters
			--1. here we retrieve all recognitions from changelog, the base table and the invoice details. plus non-actualized residualamounts and actualized non-recognized amounts
			--we do that for changelog and base table in one go and for invoices in a second and then do a union all.
			select		  JOB_UNID					=	JOB_UNID
						, SNO						=	REVENUE_SNO
						, CHRGCODE					=	CHRGCODE
						, CHRGDESC					=	CHRGDESC
						, CHARGETYPE				=	'REVENUE'
						, RECORDAMTLC				=	RECOGNITIONAMTLC  * Multiplier - Prev_RECOGNITIONAMTLC * Prev_Multiplier
						, RECORDSTATE				=	'ESTIMATED-RECOGNIZED'
						, RECOGNITIONDATE			=	RECOGNITIONDATE
						, src						=	src
						, Invoiceunid				=	Invoiceunid
						, AMTLC						=	AMTLC
						, AMTFC						=	AMTFC
						, ACTUALAMTLC				=	ACTUALAMTLC
						, ACTUALAMTFC				=	ACTUALAMTFC
						, CREATEDATE				=	CREATEDATE
						, UPDATEDATE				=	UPDATEDATE
						, CRI						=	CRI
						, PARTYID_COUNTERPARTY		=	PARTYID_COUNTERPARTY
						, DOCDATE					=	DOCDATE
						, DOCNO						=	DOCNO									
						, INVSTS					=	INVSTS
						, CURRCODE					=	CURRCODE
						, ACTUALCURRCODE			=	ACTUALCURRCODE
						, SCD_UpdateDate			=	SCD_UpdateDate
			from		(
						--Changelog and base table 
						--  the inner union can retrieve records that do not have a change in amount so it does not warrant registration.
						--  so, in the outer select we limit to only the relevant changes.
						select		*
									, Prev_RECOGNITIONAMTLC		=	lag(RECOGNITIONAMTLC, 1, 0) over (partition by JOB_UNID, REVENUE_SNO order by SNO)
									, Prev_Multiplier			=	lag(Multiplier, 1, 0) over (partition by JOB_UNID, REVENUE_SNO order by SNO)
									, Prev_RECOGNITIONDATE		=	lag(RECOGNITIONDATE, 1, null) over (partition by JOB_UNID, REVENUE_SNO order by SNO)
						from		(
									--Here we find any changelogs that have a recognitiondate that is different from the previous record in changelog
									--Since the update of recognitiondate does not create a new record in changelog, the recognitiondate actually applies to the record before the one with the current recognitiondate.
									--therefore we return CHRGCODE and DOCTYPE from the previous record.
									select		  JOB_UNID				=	cln.JOB_UNID
												, REVENUE_SNO			=	cln.REVENUE_SNO
												, SNO					=	cln.SNO
												, CHRGCODE				=	coalesce(clp.CHRGCODE, cln.CHRGCODE)	--intentionally using clp as first choice... -see above
												, CHRGDESC				=	coalesce(clp.CHRGDESC, cln.CHRGDESC)
												, RECOGNITIONAMTLC		=	cln.RECOGNITIONAMTLC
												, RECOGNITIONDATE		=	cln.RECOGNITIONDATE
												, src					=	'CHANGELOGREV'
												, Multiplier			=	case when clp.DOCTYPE = 'CN' then -1 else 1 end --intentionally using clp... -see above
												, invoiceunid			=	cast(null as bigint)
												, AMTLC					=	coalesce(l.AMTLC, cln.AMTLC)
												, AMTFC					=	coalesce(l.AMTFC, cln.AMTFC)
												, ACTUALAMTLC			=	coalesce(l.ACTUALAMTLC , cln.ACTUALAMTLC)
												, ACTUALAMTFC			=	coalesce(l.ACTUALAMTBC , cln.ACTUALAMTBC)
												, CREATEDATE			=	coalesce(l.CREATEDATE  , cln.CHANGEDATE )
												, UPDATEDATE			=	coalesce(l.UPDATEDATE, cln.CHANGEDATE)
												, CRI					=	hdr.CRI
												, PARTYID_COUNTERPARTY	=	hdr.PARTYID_CUST
												, DOCDATE				=	hdr.DOCDATE
												, DOCNO					=	hdr.DOCNO									
												, INVSTS				=	coalesce(l.INVSTS, cln.INVSTS)
												, CURRCODE				=	coalesce(l.CURRCODE, cln.CURRCODE)
												, ACTUALCURRCODE		=	coalesce(l.ACTUALCURRCODE, cln.ACTUALCURRCODE)
												, SCD_UpdateDate		=	cln.SCD_UpdateDate
									from		ODS.TMFF_CHANGELOGREV cln --Change Log Now
									join		ODS.TMFF_REVENUE l
									on			l.JOB_UNID = cln.JOB_UNID
									and			l.SNO = cln.REVENUE_SNO
									and			l.SCD_ActiveFlag = 1
									and			l.SCD_IsDeleted = 0
									left join	ODS.TMFF_CHANGELOGREV clp --Change Log Previous
									on			clp.JOB_UNID = cln.JOB_UNID
									and			clp.REVENUE_SNO = cln.REVENUE_SNO
									and			clp.SNO = cln.SNO - 1
									and			clp.SCD_ActiveFlag = 1
									and			clp.SCD_IsDeleted = 0
									left join	ODS.TMFF_IVDTL dtl
									on			cln.JOB_UNID = dtl.SOURCEUNID
									and			cln.REVENUE_SNO = dtl.SOURCESNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									left join	ODS.TMFF_IVHDR hdr
									on			hdr.UNID = dtl.IVHDR_UNID
									and			hdr.SCD_ActiveFlag = 1
									and			hdr.SCD_IsDeleted = 0
									where		cln.RECOGNITIONDATE is not null
									and			isnull(l.INVSTS, '') not in ('V')--('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or Credited (C) as they are replaced by new charge lines.
									and			isnull(clp.RECOGNITIONDATE, '19000101') <> cln.RECOGNITIONDATE
									and			cln.SCD_ActiveFlag = 1
									and			cln.SCD_IsDeleted = 0
									union all
									--base table
									select		  JOB_UNID				=	l.JOB_UNID
												, REVENUE_SNO			=	l.SNO
												, SNO					=	999999
												, CHRGCODE				=	l.CHRGCODE
												, CHRGDESC				=	l.CHRGDESC
												, RECOGNITIONAMTLC		=	l.RECOGNITIONAMTLC	
												, RECOGNITIONDATE		=	l.RECOGNITIONDATE	
												, src					=	'REVENUE'
												, Multiplier			=	case when l.DOCTYPE = 'CN' then -1 else 1 end
												, invoiceunid			=	cast(null as bigint)
												, AMTLC					=	l.AMTLC
												, AMTFC					=	l.AMTFC
												, ACTUALAMTLC			=	l.ACTUALAMTLC
												, ACTUALAMTFC			=	l.ACTUALAMTBC
												, CREATEDATE			=	l.CREATEDATE
												, UPDATEDATE			=	l.UPDATEDATE
												, CRI					=	hdr.CRI
												, PARTYID_COUNTERPARTY	=	l.BILLING_PARTYID
												, DOCDATE				=	hdr.DOCDATE
												, DOCNO					=	hdr.DOCNO									
												, INVSTS				=	l.INVSTS
												, CURRCODE				=	l.CURRCODE
												, ACTUALCURRCODE		=	l.ACTUALCURRCODE
												, SCD_UpdateDate		=	l.SCD_UpdateDate
									from		ODS.TMFF_REVENUE l
									left join	ODS.TMFF_IVDTL dtl
									on			l.JOB_UNID = dtl.SOURCEUNID
									and			l.SNO = dtl.SOURCESNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									left join	ODS.TMFF_IVHDR hdr
									on			hdr.UNID = dtl.IVHDR_UNID
									and			hdr.SCD_ActiveFlag = 1
									and			hdr.SCD_IsDeleted = 0
									where		l.SCD_ActiveFlag = 1
									and			l.SCD_IsDeleted = 0
									and			l.RECOGNITIONDATE is not null
									and			isnull(l.INVSTS, '') not in ('V')--('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or credited (C) as they are replaced by new charge lines.
									--changelog that are no longer in base table
									--  for a while it was possible to delete recognized charge lines. 
									--  when fixing it, amounts were matched, but in some cases not all deleted posts were recreated. 
									--  Instead the amounts on another record was increased. So we need to create a negation record 
									--  to set the recognized amount for that particular line to 0 in the recognition period. 
									union all
									select		  JOB_UNID				=	JOB_UNID
												, REVENUE_SNO				=	REVENUE_SNO		
												, SNO					=	999999
												, CHRGCODE				=	CHRGCODE
												, CHRGDESC				=	CHRGDESC
												, RECOGNITIONAMTLC		=	0
												, RECOGNITIONDATE		=	RECOGNITIONDATE
												, src					=	src
												, Multiplier			=	Multiplier 
												, invoiceunid			=	cast(null as bigint)
												, AMTFC					=	AMTFC
												, AMTLC					=	AMTLC
												, ACTUALAMTLC			=	ACTUALAMTLC
												, ACTUALAMTFC			=	ACTUALAMTBC
												, CREATEDATE			=	null
												, UPDATEDATE			=	CHANGEDATE
												, CRI					=	cast(null as nvarchar(2))
												, PARTYID_COUNTERPARTY	=	BILLING_PARTYID
												, DOCDATE				=	cast(null as datetime)
												, DOCNO					=	cast(null as nvarchar(40))
												, INVSTS				=	INVSTS
												, CURRCODE				=	CURRCODE
												, ACTUALCURRCODE		=	ACTUALCURRCODE
												, SCD_UpdateDate		=	SCD_UpdateDate
									from		(
												select		  JOB_UNID
															, REVENUE_SNO		
															, CHRGCODE
															, CHRGDESC
															, BILLING_PARTYID
															, RECOGNITIONAMTLC
															, RECOGNITIONDATE
															, src					=	'CHANGELOG_NULLIFICATION'
															, ix					=	row_number() over (partition by JOB_UNID, REVENUE_SNO order by SNO desc) 
															, Multiplier			=	case when DOCTYPE = 'CN' then -1 else 1 end
															, AMTLC						
															, AMTFC						
															, ACTUALAMTLC
															, ACTUALAMTBC
															, INVSTS
															, CURRCODE				
															, CHANGEDATE
															, ACTUALCURRCODE		
															, SCD_UpdateDate
												from		ODS.TMFF_CHANGELOGREV cl
												where		cl.SCD_ActiveFlag = 1
												and			cl.SCD_IsDeleted = 0
												and			RECOGNITIONDATE is not null
												and			not exists	(
																		select		1
																		from		ODS.TMFF_REVENUE l
																		where		l.JOB_UNID = cl.JOB_UNID
																		and			l.SNO = cl.REVENUE_SNO
																		and			l.SCD_ActiveFlag = 1
																		and			l.SCD_IsDeleted = 0
																		)
												) x
									where		ix = 1
									) x
						) x
			where		x.Prev_RECOGNITIONAMTLC  <> x.RECOGNITIONAMTLC --this is what filters out unnecessary duplications
			union all
			--Now we extract recognitions for all invoices that have been recognized and where there is an amount change towards the base table
			select		  JOB_UNID					=	SOURCEUNID
						, SNO						=	SOURCESNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'REVENUE'
						, RECORDAMTLC				=	case when hdr.DOCTYPE = 'CN' then -1 else 1 end * case when hdr.DOCTYPE = 'CN' and l.INVSTS is not null then dtl.AMTLC else dtl.AMTLC - case when l.RECOGNITIONDATE is not null then isnull(l.RECOGNITIONAMTLC, 0) else 0 end end --a credit note must be included in full if the line is marked with a C
						, RECORDSTATE				=	'ACTUALIZED-RECOGNIZED'
						, RECOGNITIONDATE			=	dtl.RECOGNITIONDATE
						, src						=	'IVDTL'
						, invoiceunid				=	dtl.IVHDR_UNID
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	hdr.CRI
						, PARTYID_COUNTERPARTY		=	l.BILLING_PARTYID
						, DOCDATE					=	hdr.DOCDATE
						, DOCNO						=	hdr.DOCNO
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	l.SCD_UpdateDate
			from		ODS.TMFF_IVDTL dtl
			join		ODS.TMFF_REVENUE l
			on			l.JOB_UNID = dtl.SOURCEUNID
			and			l.SNO = dtl.SOURCESNO
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			join		ODS.TMFF_IVHDR hdr
			on			hdr.UNID = dtl.IVHDR_UNID
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			where		dtl.RECOGNITIONDATE is not null
			and			hdr.VOIDDATE is null
			and			dtl.SCD_ActiveFlag = 1
			and			dtl.SCD_IsDeleted = 0
			union all
			--Now we extract from the base table that have not been actualized and where the AMTLC <> isnull(RECOGNIZEDAMTLC, 0)
			select		  JOB_UNID					=	JOB_UNID
						, SNO						=	SNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'REVENUE'
						, RECORDAMTLC				=	(AMTLC - isnull(RECOGNITIONAMTLC, 0)) * case when l.DOCTYPE = 'CN' then -1 else 1 end
						, RECORDSTATE				=	'ESTIMATED'
						, RECOGNITIONDATE			=	cast(null as datetime)
						, src						=	'REVENUE'
						, invoiceunid				=	cast(null as bigint)
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	cast(null as nvarchar(2))
						, PARTYID_COUNTERPARTY		=	l.BILLING_PARTYID
						, DOCDATE					=	cast(null as datetime)
						, DOCNO						=	cast(null as nvarchar(40))
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	l.SCD_UpdateDate
			from		ODS.TMFF_REVENUE l
			where		not exists	(
									select		1
									from		ODS.TMFF_IVDTL dtl
									where		dtl.SOURCEUNID = l.JOB_UNID
									and			dtl.SOURCESNO = l.SNO
									and			dtl.SCD_ActiveFlag = 1
									and			dtl.SCD_IsDeleted = 0
									)
			and			isnull(INVSTS, '') not in ('C', 'V') --we exclude estimate charge lines that are marked as voided (V) or credited (C) as they are replaced by new charge lines.
			and			AMTLC is not null
			and			AMTLC <> isnull(RECOGNITIONAMTLC, 0)
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			--lastly we take any invoice details that have not yet been recognized
			--we still need to correct for any recognized amounts on the base table
			union all
			select		  JOB_UNID					=	dtl.SOURCEUNID
						, SNO						=	dtl.SOURCESNO
						, CHRGCODE					=	l.CHRGCODE
						, CHRGDESC					=	l.CHRGDESC
						, CHARGETYPE				=	'REVENUE'
						, RECORDAMTLC				=	case when hdr.DOCTYPE = 'CN' then -1 else 1 end * (dtl.AMTLC - case when hdr.DOCTYPE = 'CN' and l.INVSTS = 'C' then 0 else isnull(l.RECOGNITIONAMTLC, 0) end)
						, RECORDSTATE				=	'ACTUALIZED'
						, RECOGNITIONDATE			=	cast(null as datetime)
						, src						=	'IVDTL'
						, invoiceunid				=	dtl.IVHDR_UNID
						, AMTLC						=	l.AMTLC
						, AMTFC						=	l.AMTFC
						, ACTUALAMTLC				=	l.ACTUALAMTLC
						, ACTUALAMTFC				=	l.ACTUALAMTBC
						, CREATEDATE				=	l.CREATEDATE
						, UPDATEDATE				=	l.UPDATEDATE
						, CRI						=	hdr.CRI
						, PARTYID_COUNTERPARTY		=	l.BILLING_PARTYID
						, DOCDATE					=	hdr.DOCDATE
						, DOCNO						=	hdr.DOCNO
						, INVSTS					=	l.INVSTS
						, CURRCODE					=	l.CURRCODE
						, ACTUALCURRCODE			=	l.ACTUALCURRCODE
						, SCD_UpdateDate			=	l.SCD_UpdateDate
			from		ODS.TMFF_IVDTL dtl
			join		ODS.TMFF_IVHDR hdr
			on			hdr.UNID = dtl.IVHDR_UNID
			and			hdr.SCD_ActiveFlag = 1
			and			hdr.SCD_IsDeleted = 0
			join		ODS.TMFF_REVENUE l
			on			l.JOB_UNID = dtl.SOURCEUNID
			and			l.SNO = dtl.SOURCESNO
			and			l.SCD_ActiveFlag = 1
			and			l.SCD_IsDeleted = 0
			where		dtl.RECOGNITIONDATE is null
			and			hdr.VOIDDATE is null
			and			dtl.SCD_ActiveFlag = 1
			and			dtl.SCD_IsDeleted = 0
			) recog
GO
/****** Object:  View [CALC].[v_TMFF_Shipment]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






--COBI-7488 --Objective Add ServiceType
--prevtask COBI-7453, hash = -824431106
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_TMFF_Shipment'
--select * from utilities.vCheckDefinitionSyncronization_ext where objectname = 'v_TMFF_Shipment'
CREATE view [CALC].[v_TMFF_Shipment]
as
with File_status as 
(
			select		distinct j2.CONSOLLOT_UNID
			from		ODS.TMFF_JOB j2
			join		ODS.TMFF_JOBOTHER jo2
			on			jo2.JOB_UNID = j2.UNID
			and			jo2.WFBOOKINGSTATUS = 'OPEN'
			and			isnull(j2.JOBSTAGECODE,'') not in ('P','Q','T') 
			and			jo2.SCD_ActiveFlag = 1
			and			jo2.SCD_IsDeleted = 0
			where		j2.SCD_ActiveFlag = 1
			and			j2.SCD_IsDeleted = 0
),
TMFF_JOBPARTY as (
			select		  JOB_UNID
						, PARTYTYPE
						, PartyId
						, FULLNAME	
						, ADDR1		
						, ADDR2		
						, ADDR3		
						, ADDR4		
			from		ODS.TMFF_JOBPARTY 
			where		PARTYTYPE in ('DEL','PCF','NOTIFY')
			and			JOB_UNID is not null
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
)
select		  ShipmentCount							=	try_cast(am.ShipmentCount														as bigint)
			, ActivityCount							=	cast(1																			as bigint)
			, GlobalShipmentId_BK					=	cast(jgwvc.GlobalShipmentId_BK													as varchar(150))
			, LocalShipmentId_BK     				=	cast(jgwvc.LocalShipmentId_BK													as varchar(50))
			, HouseCode 							=	cast(case	when j.shptype IN ('M','S','X') then null 
																	else coalesce(j.SHPNO, j.JOBNO) 
															  end																		as varchar(50))
			-- VB 2026-04-23 based od logic from Mads Foged we are prioritizing MAWB/BL No (NO4) for BIZTYPE = NJ
			, MasterCode							=	cast(replace(case when j.BIZTYPE = 'NJ' then coalesce(nullif(ref.NO4, ''), mc.MasterCode) else coalesce(mc.MasterCode,ref.no4) end, char(160), '') as varchar(50))
			, BookingNumber							=	cast(j.JOBNO																	as varchar(50))
			, System_BK        						=	cast('TMFF'																		as varchar(50))
			, Company_BK       						=	cast(coalesce(cast(odc.Company_BK as varchar), j.OWNERID)						as varchar(50))
			, Department_BK  						=	cast(jo.BIZSCOPE																as varchar(50))
			, CostCenter_BK  						=	cast(jo.BIZSCOPE																as varchar(50))
			, File_BK       						=	cast(j.UNID																		as varchar(50))
			, FileStatus_BK							=	case 
															when calc.FileStatus = 'Closed' then 'Fully Closed'
															when calc.FileStatus = 'Open' and jo.WFBOOKINGSTATUS  = 'Closed'  then 'Partly Closed'
															when jo.WFBOOKINGSTATUS = 'Open' then 'Open'
															else 'Open'
														end
			, ServiceCode_BK 						=	cast(j.BIZTYPE																	as varchar(50))
			, Currency_BK    						=	cast(coalesce(jo.PPCURRCODE, CCCURRCODE)										as varchar(50))
			, TransportMode_BK						=	cast(tm.TransportMode_BK														as varchar(50))
			, ShipmentDirection_BK					=	sd2.ShipmentDirection_BK
			, CompanyCountryCode					=	cast(odc.CompanyCountryCode														as varchar(50))
			, OriginCountryCode						=	cast(od.originCountry															as varchar(50))
			, DestinationCountryCode				=	cast(od.destinationcountry														as varchar(50))
			, ActivityType_BK						=	cast(amcalc.ActivityType_BK														as varchar(50))
			, ShipmentType_BK						=	cast(case
																when jo.TPTTYPE = 'Rail' and jo.SERVICELEVEL = 'BCN'		then 'BCN'
																when jo.TPTTYPE = 'Rail' and road.LOADTERM = 'FTL'			then 'FCL'
																when jo.TPTTYPE = 'Rail' and road.LOADTERM = 'LTL'			then 'LCL'
																when jo.SERVICELEVEL = 'BCN'								then 'BCN'
																when jo.SERVICELEVEL = 'CONS'								then 'LCL'
																else coalesce(road.LOADTERM,sea.LOADTERM,j.SHPTYPE)	
															 end																		as varchar(50))
			, CustomerParty_BK						=	cast(coalesce(jp.CONTROLPARTY, j.PARTYID_CUST)									as varchar(50))
			, ConsignorParty_BK						=	cast(j.PARTYID_CUST																as varchar(50))
			, ConsigneeParty_BK						=	cast(coalesce(jp.REALCSGN, jo.PARTYID_CSGNONWB, j.PARTYID_CSGN)					as varchar(50))
			, ShipperParty_BK						=	cast(j.PARTYID_SHPR																as varchar(50))
			, CarrierParty_BK 						=	cast(coalesce(j.CARRIERCODE, j.CARRIERID)										as varchar(50))
			, AgentParty_BK							=	cast(j.OAGENT																	as varchar(50))
			, PickUpParty_BK						=	cast(jp.PCF																		as varchar(50))
			, DeliveryParty_BK						=	cast(jp.DEL																		as varchar(50))			
			, NotifyParty_BK						=	cast(notifyp.PartyId															as varchar(50))
			, PreTransportDepartureLocation_BK		=	cast(case	when j.BIZTYPE = 'IL' then null else j.PORCTRY + j.PORCITY end		as varchar(50))
			, PreTransportArrivalLocation_BK		=	cast(case	when j.BIZTYPE like 'A%' 
																	then 'A'+ j.POLCTRY + j.POLCITY 
																	when j.BIZTYPE = 'IL'
																	then isnull(j.PORCTRY,j.POLCTRY)+isnull(j.PORCITY,j.POLCITY)
																	else j.POLCTRY + j.POLCITY 
																	end																	as varchar(50))
			, MainTransportDepartureLocation_BK		=	cast(case	when j.BIZTYPE like 'A%' 
																	then 'A'+ j.POLCTRY + j.POLCITY 
																	when j.BIZTYPE = 'IL'
																	then isnull(j.PORCTRY,j.POLCTRY)+isnull(j.PORCITY,j.POLCITY)
																	else j.POLCTRY + j.POLCITY 
																	end																	as varchar(50))
			, MainTransportArrivalLocation_BK		=	cast(case	when j.BIZTYPE like 'A%' 
																	then 'A' + j.PODCTRY + j.PODCITY 
																	else isnull(j.DEVRYCTRY,j.PODCTRY) + isnull(j.DEVRYCITY,j.PODCITY) 
																	end																	as varchar(50))
			, PostTransportDepartureLocation_BK		=	cast(case	when j.BIZTYPE like 'A%' 
																	then 'A' + j.PODCTRY + j.PODCITY 
																	else isnull(j.DEVRYCTRY,j.PODCTRY) + isnull(j.DEVRYCITY,j.PODCITY) 
																	end																	as varchar(50))
			, PostTransportArrivalLocation_BK		=	cast(case	when j.BIZTYPE = 'IL' then null else j.DESTCTRY + j.DESTCITY end	as varchar(50))
			, TransportLane_BK                 		=	cast(od.originCountry + '-' + od.destinationcountry								as varchar(50))
			, MainTransportLane_BK					=	cast(od.MainOriginCountry+ '-' + od.MainDestinationCountry						as varchar(50))
			, BaseCurrency_BK						=	cast(odc.CompanyCurrency														as varchar(50))
			, FirstFinancialDate_BK					=	cast(findate.FirstFinancialDate_BK												as date)
			, ShipmentDepartureDate_BK				=	cast(coalesce(j.PORETDDATE, j.POLETDDATE)										as date)
			, ShipmentArrivalDate_BK				=	cast(coalesce(jo.PROMISEDELVYDATE, j.DEVRYETADATE, j.PODETADATE)				as date)
			, MainTransportDepartureDate_BK			=	dates.MainTransportDepartureDate_BK
			, MainTransportArrivalDate_BK			=	dates.MainTransportArrivalDate_BK
			, PreTransportDepartureDate_BK			=	dates.PreTransportDepartureDate_BK
			, PostTransportArrivalDate_BK			=	dates.PostTransportArrivalDate_BK
			, CreateDate_BK							=	dates.CreateDate_BK
			, ShipmentDate_BK						=	case 
															when sd2.ShipmentDirection_BK = 'Export' or sd2.ShipmentDirection_BK = 'Cross Trade (Export)' then 
																	  coalesce (  dates.MainTransportDepartureDate_BK
																				, dates.PreTransportDepartureDate_BK
																				, dates.MainTransportArrivalDate_BK
																				, dates.PostTransportArrivalDate_BK
																				, dates.CreateDate_BK
																				) 
															else 
																	  coalesce (  dates.MainTransportArrivalDate_BK
																				, dates.PostTransportArrivalDate_BK
																				, dates.MainTransportDepartureDate_BK
																				, dates.PreTransportDepartureDate_BK
																				, dates.CreateDate_BK
																				) 
														end
			, ActualPreTransportDepartureDate_BK	=	cast(null as date)	--while we do have some actual values, I am not certain how to get them
			, ActualMainTransportDepartureDate_BK	=	cast(null as date)	--while we do have some actual values, I am not certain how to get them
			, ActualMainTransportArrivalDate_BK		=	cast(null as date)	--while we do have some actual values, I am not certain how to get them
			, ActualPostTransportArrivalDate_Bk		=	cast(null as date)	--while we do have some actual values, I am not certain how to get them
			, ShipmentCompletedDate_BK				=	cast(coalesce(j.DEVRYETADATE, j.PODETADATE)										as date)
			, TransportDocumentDate_BK				=	cast(j.AWBBLDATE																as date)
			, ServiceLevel_BK						=	cast(jo.SERVICELEVEL															as varchar(50))
			, ServiceType							=	cast(jo.SERVICETYPE																as varchar(50))
			, GoodsDescription  					=	cast(case when j.biztype in ('AE','AI') then jo.COMM else jo.BKGGOODDESC end	as varchar(500))
			, FullGoodsDescription					=	cast(case when j.biztype in ('AE','AI') then jo.COMM else jo.BKGGOODDESC end	as varchar(500))
			, TermsOfDeliveryCode					=	cast(jo.INCOTERM																as varchar(50))
			, TermsOfDeliveryLocation				=	cast(jo.INCOTERMLOCATION														as varchar(50))
			, CompanyCountry						=	cast(odc.CompanyCountryCode														as varchar(50))
			, PackagesCode                    		=	cast(j.TOTPCS_UT																as varchar(50))
			, ContainerNos                    		=	cast(con.ContainerNos															as varchar(2000)) 
			, ValidForEmissionsCalculation  		=	cast(null																		as bit)		--TBD
			, ExternalRevenue						=	cast(jr.ExternalRevenueLocal	as float) * isnull(excact.ExchangeRateUSD ,1)
			, InvoicedRevenue						=	cast(jr.InvoicedRevenueLocal	as float) * isnull(excact.ExchangeRateUSD ,1)
			, AgentRevenue							=	cast(jr.AgentRevenueLocal		as float) * isnull(excact.ExchangeRateUSD ,1)
			, BookingCreateUser						=	cast(j.CREATEBY																	as varchar(50))
			, BookingUser							=	cast(jo.OPUSERID																as varchar(50))
			, ControlledBy							=	cast(null																		as varchar(50)) --must review Axsfreight setup to understand this one
			, IsTemplate							=	cast(0																			as bit)
			, CustomerReference						=	cast(ref.NO																		as varchar(50))	
			, CustomerReference2					=	cast(ref.NO2																	as varchar(50))	
			, CommodityCode							=	cast(jo.COMMCODE																as varchar(50))			
			, VesselName							=	cast(mo.VESSELNAME																as varchar(50))
			, VoyageNumber							=	cast(mo.VOYAGE																	as varchar(50))	
			, FlightNumber							=	cast(null																		as varchar(50))	--TBD
			, Comments								=	cast(''																			as varchar(500))
			, ConsolidationNo						=	cast(j.CONSOLNO																	as varchar(50))
 			, GSHPID								=	cast(j.GSHPID																	as varchar(50))
			, CURRENTSTAGE							=	cast(j.CURRENTSTAGE																as varchar(50))
 			, SHPTYPE								=	cast(j.SHPTYPE																	as varchar(50))
			, OPSTATUS								=	cast(jo.OPSTATUS																as varchar(50))
			, BIZTYPE								=	cast(j.BIZTYPE																	as varchar(50))
			, SHPRNAME								=	cast(j.SHPRNAME																	as varchar(100))
			, SHPRADDR1								=	cast(jo.SHPRADDR1																as varchar(50))
			, SHPRADDR2								=	cast(jo.SHPRPOSTALCODE															as varchar(50))
			, SHPRADDR3								=	cast(jo.SHPRCITYNAME															as varchar(50))
			, SHPRADDR4								=	cast(jo.SHPRCTRYCODE															as varchar(50))
			, CSGNNAME								=	cast(coalesce(j.CSGNNAME, jo.CSGNNAMEONWB)										as varchar(100))
			, CSGNADDR1								=	cast(jo.CSGNADDR1																as varchar(50))
			, CSGNADDR2								=	cast(jo.CSGNPOSTALCODE															as varchar(50))
			, CSGNADDR3								=	cast(jo.CSGNONWBCITYNAME														as varchar(50))
			, CSGNADDR4								=	cast(jo.CSGNCTRYCODE															as varchar(50))
			, PCFFULLNAME							=	cast(pcf.FULLNAME																as varchar(150))
			, PCFADDR1								=	cast(pcf.ADDR1																	as varchar(100))
			, PCFADDR2								=	cast(pcf.ADDR2																	as varchar(100))
			, PCFADDR3								=	cast(pcf.ADDR3																	as varchar(100))
			, PCFADDR4								=	cast(pcf.ADDR4																	as varchar(100))
			, DELFULLNAME							=	cast(del.FULLNAME																as varchar(150))
			, DELADDR1								=	cast(del.ADDR1																	as varchar(100))
			, DELADDR2								=	cast(del.ADDR2																	as varchar(100))
			, DELADDR3								=	cast(del.ADDR3																	as varchar(100))
			, DELADDR4								=	cast(del.ADDR4																	as varchar(100))
			, ChargeableWeight						=	isnull(j.TOTCWGT,0)
			, ChargeableWeightUnit					=	cast(j.TOTCWGT_UT																as varchar(50))
			, JOB_UNID								=	j.UNID
			, CountrySchemeCode						=	odc.CountrySchemeCode				
			, GlobalCompanyCode						=	odc.GlobalCompanyCode
			, SalesID								=	cast(jo.SALES																	as varchar(50))
			, CarrierContractID						=	cast(coalesce(so.SRVCONTRACTNO, ref.NO3)										as varchar(150))
			, CarrierCode							=	cast(coalesce(j.CARRIERCODE, j.CARRIERID, case tm.TransportMode_BK 
																								 when 'Air' then airm.[2LetterIATA]
																								 when 'Sea' then left(mc.MasterCode, 4)
																							 end)										as varchar(50))												
			, CarrierBookingCode					=	cast(sea.SONO as varchar(50))
			, DangerousGoods						=	cast(case when jo.SPECIALREQ like '%DGD%' or jo.SPECIALREQ like '%CAO%' then 1 else 0 end as bit)
			, BookingUpdateUser						=	cast(j.UPDATEBY																	as varchar(50))
			, FileConsCode							=	cast(j.Consollot_UNID															as varchar(50))
			, UniqueRecordKey						=	utilities.ufn_GetHashedUID('TMFF', odc.Company_BK, j.ownerid, j.UNID, default)
			, DataAgeHOT							=	j.SCD_UpdateDate
			, DataAgeCOLD							=	(
														select	max(v) 
														from	(
																values	  (j.SCD_UpdateDate)
																		, (jo.SCD_UpdateDate)
																		, (sea.SCD_UpdateDate)
																		, (air.SCD_UpdateDate)
																		, (odc.DataAgeCold)
																		, (jp.DataAgeCold)
																		, (findate.SCD_UpdateDate)
																) x (v)
														)
			, RecordChangeDateTime					=	getdate()
from		ODS.TMFF_JOB j
join		CALC.TMFF_Job_GlobalShipmentId_Weight_Volume_Company jgwvc
on			jgwvc.JOB_UNID = j.UNID
left join	ODS.TMFF_VEWMOTHERVESSEL mo
on			mo.JOBUNID = j.UNID
and			mo.SCD_ActiveFlag = 1
and			mo.SCD_IsDeleted = 0
left join	(
			select		  JOB_UNID
						, LoadTerm = max(LoadTerm)
			from		ODS.TMFF_ROAD 
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			group by	JOB_UNID
			) road
on			road.JOB_UNID = j.UNID
left join	(
			select		  Job_UNID				=	id.SourceUnid
						, InvoicedRevenueLocal	=	sum(case when i.DOCTYPE = 'CN' then -1 else 1 end * try_cast(id.AMTLC as float))						
						, InternalRevenueLocal	=	sum(case when i.DOCTYPE = 'CN' then -1 else 1 end * case when c.OWNERID is not null then id.AMTLC else 0 end)
						, ExternalRevenueLocal	=	sum(case when i.DOCTYPE = 'CN' then -1 else 1 end * case when c.OWNERID is null		then id.AMTLC else 0 end)
						, AgentRevenueLocal		=	sum(case when i.DOCTYPE = 'CN' then -1 else 1 end * case when j.OAGENT = i.partyid_cust then id.AMTLC else 0 end)
			from		ODS.TMFF_IVDTL id
			join		ODS.TMFF_IVHDR i
			on			i.unid = id.ivhdr_unid
			and			i.STATUS = 'Original'
			and			i.SCD_ActiveFlag = 1
			and			i.SCD_IsDeleted = 0
			join		ODS.TMFF_JOB j
			on			j.UNID = id.sourceunid
			and			j.SCD_ActiveFlag = 1
			and			j.SCD_IsDeleted = 0
			left join	ODS.TMFF_SYCOMPANY c
			on			c.OWNERID = i.partyid_cust
			and			c.SCD_ActiveFlag = 1
			and			c.SCD_IsDeleted = 0
			where		id.SCD_ActiveFlag = 1
			and			id.SCD_IsDeleted = 0
			group by	id.sourceunid
			) jr
on			jr.JOB_UNID = j.UNID
left join	(
			select		  JOB_UNID
  						, NO	= cast(isnull(string_agg(case when refcode = 'CUSREF1' then cast(NO as varchar(max)) else null end ,'; '),'') as varchar(1000))
 						, NO2	= cast(isnull(string_agg(case when refcode = 'CUSREF2' then cast(NO as varchar(max)) else null end ,'; '),'') as varchar(1000))
						, NO3	= cast(isnull(string_agg(case when refcode = 'CARCONTRACT' then cast(NO as varchar(max)) else null end ,'; '),'') as varchar(1000))
						, NO4	= cast(isnull(string_agg(case when refcode = 'MST' then cast(NO as varchar(max)) else null end ,'; '),'') as varchar(1000))
			from		(
						select
									  JOB_UNID
									, refcode
									, NO
						from		ODS.TMFF_REFNO
						where		REFCODE in ('CUSREF1','CUSREF2','CARCONTRACT','MST')
						and			SCD_ActiveFlag = 1
						and			SCD_IsDeleted = 0
						group by	JOB_UNID, refcode, NO
			) as s 
			group by	JOB_UNID
			) REF
on			j.UNID = REF.JOB_UNID
left join	ODS.TMFF_JOBOTHER jo
on			jo.JOB_UNID = j.UNID
and			jo.SCD_ActiveFlag = 1
and			jo.SCD_IsDeleted = 0
left join	ODS.TMFF_SEA sea
on			sea.JOB_UNID = j.UNID
and			sea.SCD_ActiveFlag = 1
and			sea.SCD_IsDeleted = 0
left join	ODS.TMFF_AIR air
on			air.JOB_UNID = j.UNID
and			air.SCD_ActiveFlag = 1
and			air.SCD_IsDeleted = 0
left join	CALC.TMFF_JOBPARTY jp
on			j.unid = jp.JOB_UNID	
left join	TMFF_JOBPARTY notifyp
on			j.unid = notifyp.job_unid
and			notifyp.PARTYTYPE = 'NOTIFY'
left join	CALC.TMFF_OwnerIdCompany odc
on			odc.OwnerOwnerId = j.OWNERID
cross apply	(
			select		  OriginCountry			=	coalesce(j.PORCTRY, j.POLCTRY)
						, DestinationCountry	=	coalesce(j.DESTCTRY, j.DEVRYCTRY,j.PODCTRY)
						, MainOriginCountry		=	j.POLCTRY
						, MainDestinationCountry=	coalesce(j.DEVRYCTRY, j.PODCTRY)
			) od
cross apply	(
			select		ShipmentDirection_BK	=	case 
														when odc.CompanyCountryCode not in (od.OriginCountry, od.DestinationCountry) then 'Cross Trade'
														when odc.CompanyCountryCode = od.OriginCountry and odc.CompanyCountryCode = od.DestinationCountry then 'Domestic'
														when odc.CompanyCountryCode = od.OriginCountry then 'Export'
														when odc.CompanyCountryCode = od.DestinationCountry then 'Import'
														else '?!?'
													end
			) sd
cross apply	(
			select		ShipmentDirection_BK	=	case
														when sd.ShipmentDirection_BK = 'Cross Trade' and (j.BIZTYPE in ('SI', 'AI') or (j.BIZTYPE = 'IL' and j.JOBTYPE = 'IN')) then 'Cross Trade (Import)'
														when sd.ShipmentDirection_BK = 'Cross Trade' and (j.BIZTYPE in ('SE', 'AE') or (j.BIZTYPE = 'IL' and j.JOBTYPE = 'OUT')) then 'Cross Trade (Export)' 
														else sd.ShipmentDirection_BK
													end
			) sd2
cross apply (
			select		  MainTransportDepartureDate_BK			=	cast(case	when j.BIZTYPE = 'IL' then coalesce(j.PORETDDATE, j.POLETDDATE)
																				else j.POLETDDATE
																		end		as date)
						, MainTransportArrivalDate_BK			=	cast(case	when j.BIZTYPE = 'IL' then coalesce(jo.PROMISEDELVYDATE, j.DEVRYETADATE,j.PODETADATE)
																				else coalesce(j.DEVRYETADATE, j.PODETADATE)		
																		end 	as date)
						, PreTransportDepartureDate_BK			=	cast(case	when j.BIZTYPE = 'IL' then null else j.PORETDDATE		 end		as date)
						, PostTransportArrivalDate_BK			=	cast(case	when j.BIZTYPE = 'IL' then null else jo.PROMISEDELVYDATE end 		as date)
						, CreateDate_BK							=	cast(j.CREATEDATE																as date)

			) dates
left join	CALC.Calc_ExchangeRatePeriodTypeReporting excact
on			excact.BaseCurrency						=	cast(coalesce(jo.PPCURRCODE, jo.CCCURRCODE) as varchar(50))
and			excact.ExchangeRateCalculationMethod_BK =	'PnL'
and			excact.Period_BK						=	coalesce(year(j.JOBDATE) * 100 + month(j.JOBDATE), year(getdate()) * 100 + month(getdate()))
and			excact.ExchangeRateSource_BK			=	'Actual'
outer apply (
			select ActivityType_BK = case 
										when left(j.BIZTYPE,1) = 'A' and j.SHPTYPE in ('M','S','X')								then 'MAWB'
										when left(j.BIZTYPE,1) = 'S' and j.SHPTYPE in ('M','S','X')								then 'MBL'
										when left(j.BIZTYPE,1) = 'I' and j.SHPTYPE in ('M','S','X')								then 'OTM'
										when jo.OPSTATUS in ('3', '3,5','6','3,6','3,5,6')										then 'OTH'
										when left(j.BIZTYPE,1) in ('A','S', 'I') and j.SHPTYPE IN ('D','H','B') and j.ISSHP = 1	then 'CON'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'COU'												then 'CON'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'SEA'												then 'CON'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'AIR'												then 'CON'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'TRK'												then 'OTH'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'CUS'												then 'CC'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'WHS'												then 'WARE'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'DOC'												then 'DOC'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'INS'												then 'INS'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'XTR'												then 'OTH'
										when j.BIZTYPE = 'NJ' and j.JOBTYPE = 'OTH'												then 'OTH'
										when j.BIZTYPE = 'WH'																	then 'WARE'
										else 'OTH'    
									  end	
			) amcalc
left join	CALC.BIRef_ActivityMapping am
on			am.Activity_BK = amcalc.ActivityType_BK
left join	File_status OpenedHouse
on			OpenedHouse.CONSOLLOT_UNID = j.UNID	
left join	File_status OpenedShipment
on			OpenedShipment.CONSOLLOT_UNID = j.CONSOLLOT_UNID
left join	(
			select	distinct j2.UNID
			from			ODS.TMFF_JOB j2
			join			ODS.TMFF_JOBOTHER jo2
			on				jo2.JOB_UNID = j2.UNID
			and				jo2.WFBOOKINGSTATUS = 'OPEN'
			and				isnull(j2.JOBSTAGECODE,'') not in ('P','Q','T') 
			and				jo2.SCD_ActiveFlag = 1
			and				jo2.SCD_IsDeleted = 0
			where			j2.SCD_ActiveFlag = 1
			and				j2.SCD_IsDeleted = 0
			) OpenedMaster
on			OpenedMaster.UNID = j.CONSOLLOT_UNID
left join	(
			select distinct CONSOLLOT_UNID 
			from			ODS.TMFF_JOB 
			where			SCD_ActiveFlag = 1 
			and				SCD_IsDeleted = 0
			) NoHouse
on			NoHouse.CONSOLLOT_UNID = j.UNID
left join	(
			select		  JOB_UNID
						, FirstFinancialDate_BK			= min(RECOGNITIONDATE)
						, SCD_UpdateDate				= max(SCD_UpdateDate)
			from		(
						select		  JOB_UNID
									, RECOGNITIONDATE = min(RECOGNITIONDATE)
									, SCD_UpdateDate = max(SCD_UpdateDate)
						from		ODS.TMFF_COST
						where		RECOGNITIONDATE is not null
						and			SCD_ActiveFlag = 1 
						and			SCD_IsDeleted = 0
						group by	JOB_UNID
						union all
						select		  SOURCEUNID
									, RECOGNITIONDATE = min(RECOGNITIONDATE)
									, SCD_UpdateDate = max(SCD_UpdateDate)
						from		ODS.TMFF_CPVDTL 
						where		RECOGNITIONDATE is not null
						and			SCD_ActiveFlag = 1 
						and			SCD_IsDeleted = 0
						group by	SOURCEUNID
						union all
						select		  JOB_UNID
									, RECOGNITIONDATE = min(RECOGNITIONDATE)
									, SCD_UpdateDate = max(SCD_UpdateDate)
						from		ODS.TMFF_REVENUE
						where		RECOGNITIONDATE is not null
						and			SCD_ActiveFlag = 1 
						and			SCD_IsDeleted = 0
						group by	JOB_UNID
						union all
						select		  SOURCEUNID
									, RECOGNITIONDATE = min(RECOGNITIONDATE)
									, SCD_UpdateDate = max(SCD_UpdateDate)
						from		ODS.TMFF_IVDTL
						where		RECOGNITIONDATE is not null
						and			SCD_ActiveFlag = 1 
						and			SCD_IsDeleted = 0
						group by	SOURCEUNID
			) x
			group by	JOB_UNID
			) findate
on			findate.JOB_UNID = j.UNID
cross apply (
			select	FileStatus	=	case 
										when OpenedHouse.CONSOLLOT_UNID is not null			then 'Open'					/* There is a master and one of its houses are open*/
										when OpenedShipment.CONSOLLOT_UNID is not null		then 'Open'					/* One of the shipments referencing the master is open */
										when OpenedMaster.UNID is not null					then 'Open'					/*The master is open*/
										when NoHouse.CONSOLLOT_UNID is null					then jo.WFBOOKINGSTATUS		/*There is no house or subhouse, so use its own status*/
										else 'Closed' 
									end
			) calc
left join	(
			select		  JOB_UNID
						, SRVCONTRACTNO 
			from		ODS.TMFF_SOPARTY so
			where		SRVCONTRACTNO is not null
			and			so.SCD_ActiveFlag = 1
			and			so.SCD_IsDeleted = 0
			) so
on			so.JOB_UNID = j.UNID
left join	TMFF_JOBPARTY pcf
on			j.UNID = pcf.JOB_UNID
and			pcf.PARTYTYPE = 'PCF'
left join	TMFF_JOBPARTY del
on			j.UNID = del.JOB_UNID
and			del.PARTYTYPE = 'DEL'
left join	(
			select		  JOB_UNID
						, ContainerNos		=	string_agg(CONTNO, ',') 
			from		(
						select		  sci.JOB_UNID
									, con.CONTNO
						from		ODS.TMFF_SEACONTITEM sci
						join		ODS.TMFF_CONTAINER con
						on			sci.CONTAINER_UNID = con.UNID	
						and			con.SCD_ActiveFlag = 1
						and			con.SCD_IsDeleted = 0
						where		sci.SCD_ActiveFlag = 1
						and			sci.SCD_IsDeleted = 0
						group by	  sci.JOB_UNID
									, con.CONTNO
						) x
			group by	JOB_UNID
			) con
on			con.JOB_UNID = j.UNID
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
left join	(
			select		  JOB_UNID 
						, MAWBNO = max(MAWBNO)
			from		ODS.TMFF_JOBROUTE 
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			MAWBNO is not null
			group by	JOB_UNID
			) jro
on			jro.JOB_UNID = j.UNID
outer apply (
			select		MasterCode						=	case	when j.shptype in ('D') 
																	then coalesce(sea.MBLNO, j.SHPNO)
																	else coalesce(sea.MBLNO, j.CONSOLNO, jro.MAWBNO)	
															end	
			) mc
left join	CALC.BiRef_AirLineMapping airm
on			airm.[3DigitIATA] = left(mc.MasterCode, 3)
where		j.JOBSTAGECODE in ('B', 'N', 'S')
and			j.shptype <> 'B'
and			j.VOIDDATE is null
and			j.SCD_ActiveFlag = 1
and			j.SCD_IsDeleted = 0

GO
/****** Object:  View [CALC].[v_TMFF_ShipmentItem]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-7332 --objective Add FileConsCode
--prevtask COBI-7200, hash = -1200731876
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_TMFF_ShipmentItem'
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_TMFF_ShipmentItem'
CREATE   view [CALC].[v_TMFF_ShipmentItem]
as
select		--Measures---------------------------------------------------------------
			  ShipmentItemCount									=	cast(1 as bigint)
			, ShipmentItemWeight								=	cast(ai.ItemWeight		as float)
			, ShipmentItemChargeableWeight						=	cast(
																		case sh.ChargeableWeightUnit
																			when 'CBM' then 
																				coalesce	(
																							  sh.ChargeableWeight * ai.ItemVolume / nullif(tai.TotalItemVolume, 0)
																							, sh.ChargeableWeight / nullif(tai.JobItemCount, 0)
																							)
																			else 
																				coalesce	(
																							  sh.ChargeableWeight * ai.ItemWeight / nullif(tai.TotalItemWeight, 0)
																							, sh.ChargeableWeight / nullif(tai.JobItemCount, 0)
																							)
																			end 
																			as float
																			)
			, ShipmentItemVolume								=	cast(ai.ItemVolume as float)
			, ShipmentItemColliCount							=	cast(ai.ItemPieces as float)
			, ShipmentItemSystemAnalysisTEUCount				=	cast(nullif(isnull(ai.CalculatedTEU,0) + isnull(ai.AllocatedTEU,0),0)	as float)
			, ShipmentItemCarrierTEUCount						=	cast(case when sh.SHPTYPE in ('M', 'D') then ai.CalculatedTEU else 0 end	as float)
			, ShipmentItemCustomerTEUCount						=	cast(case when sh.SHPTYPE in ('H', 'D') then ai.AllocatedTEU else 0 end as float)
			, ContainerNo										=	cast(ai.CONTNO as varchar(50))
			, SealNo											=	cast(ai.SEALNO										as varchar(50))
			, GoodsDescription									=	coalesce(ai.GoodsDescription, sh.GoodsDescription)
			, FileConsCode										=	sh.FileConsCode
			--Dimension Keys------------------------			----
			, GlobalShipmentItemId_BK							=	cast(sh.GlobalShipmentId_BK + sh.LocalShipmentId_BK + ShipmentItemSuffix		as varchar(150))
			, LocalShipmentItemId_BK							=	cast(sh.LocalShipmentId_BK + ShipmentItemSuffix		as varchar(50))
			, ContainerType_BK									=	cast(ai.ContainerType as varchar(50))
			, System_BK											=	cast('TMFF' as varchar(50))
			, GlobalShipmentId_BK								=	sh.GlobalShipmentId_BK
			, CustomerParty_BK									=	sh.CustomerParty_BK
			, LocalShipmentId_BK								=	sh.LocalShipmentId_BK
			, Company_BK										=	sh.Company_BK
			, Department_BK										=	sh.Department_BK
			, CostCenter_BK										=	sh.Department_BK
			, Currency_BK										=	sh.Currency_BK
			, ShipmentDirection_BK								=	sh.ShipmentDirection_BK	
			, ValidForEmissionsCalculationBoolean_BK			=	cast(null as varchar(50)) --How to calculate this?
			--Date BK's---------------------------------------------
			, Date_BK											=	cast(sh.ShipmentDate_BK as date)
			, FinancialDate_BK									=	cast(sh.ShipmentDate_BK as date)
			, CreateDate_BK										=	cast(sh.CreateDate_BK as date)
			, UniqueRecordKey									=	utilities.ufn_GetHashedUID('TMFF', sh.LocalShipmentId_BK, ShipmentItemSuffix,sh.Company_BK,default)
			, DataAgeHOT										=	ai.DataAgeHot
			, DataAgeCOLD										=	ai.DataAgeCold
			, RecordChangeDateTime								=	getdate()
from		CALC.TMFF_Shipment sh
join		CALC.TMFF_AllItemsWithTEUAllocation ai
on			sh.LocalShipmentId_BK	=	ai.JOB_UNID
join		(
			select		  JOB_UNID
						, TotalItemVolume	=	sum(ItemVolume)
						, TotalItemWeight	=	sum(ItemWeight)
						, JobItemCount		=	count(*)
			from		CALC.TMFF_AllItems
			group by	JOB_UNID
			) tai
on			tai.JOB_UNID = sh.JOB_UNID
GO
/****** Object:  View [DW].[v_TMFF_dim_Company]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-5237
--PrevTask COBI-5286, hash = -8160818026293757549
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_TMFF_dim_Company'
CREATE view [DW].[v_TMFF_dim_Company]
as 
select		  System_BK								= 'TMFF'
			, Company_BK							= cast(oi.Company_BK			as varchar(50))
			, BICompany								= cast(oi.Company_BK			as varchar(50))
			, CompanyCode							= cast(oi.CompanyOwnerId		as varchar(50))
			, CompanyName							= cast(oi.CompanyName			as varchar(50))
			, CompanyZipCode						= cast(null						as varchar(50)) --we have no known way of identifying ZIP and City in SYCOMPANY
			, CompanyCity							= cast(ci.DESCRIPTION			as varchar(50))
			, CompanyCountryCode					= cast(oi.CompanyCountryCode	as varchar(50))
			, CompanyCountryName					= cast(cn.CountryName			as varchar(50))
			, UniqueRecordKey						= utilities.ufn_GetHashedUID('TMFF', oi.Company_BK, default, default, default)
			, DataAgeHOT							= cast(oi.DataAgeHOT			as datetime)
			, DataAgeCOLD							= cast(cn.DataAgeCOLD			as datetime)
			, RecordChangeDateTime					= getdate()
from		(
			select		  Company_BK
						, CompanyOwnerId
						, CompanyName
						, CompanyCountryCode
						, CompanyCityCode
						, DataAgeHOT			= max(DataAgeHOT)
						, DataAgeCOLD			= max(DataAgeCOLD)
			from		CALC.TMFF_OwnerIdCompany
			group by	  Company_BK
						, CompanyOwnerId
						, CompanyName
						, CompanyCountryCode
						, CompanyCityCode
			) oi
left join	(
			select		CountryName,
						CountryCode,
						SCD_ActiveFlag,
						SCD_IsDeleted,
						DataAgeCOLD				= max(SCD_UpdateDate)
			from		CALC.BIRef_Country 
			group by	CountryName,
						CountryCode,
						SCD_ActiveFlag,
						SCD_IsDeleted
			) cn
on			cn.CountryCode = oi.CompanyCountryCode
left join	ODS.TMFF_FMCITY ci
on			ci.CTRYCODE = oi.CompanyCountryCode
and			ci.CITYCODE = oi.CompanyCityCode
and			ci.SCD_ActiveFlag = 1
and			ci.SCD_IsDeleted = 0
GO
/****** Object:  View [DW].[v_TMFF_dim_Department]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-5239 (COBI-5191) --Objective rename attributes
--Prevtask COBI-4443 hash = 637599309705453247
--exec utilities.usp_convertviewtoloadcomplex_simple 'DW','v_TMFF_dim_Department'
CREATE view [DW].[v_TMFF_dim_Department]
as
select		  MappingDepartmentCode							
			, DepartmentCode		
			, DepartmentFullName	
			, DepartmentName		
			, System_BK					
			, Company_BK				
			, Department_BK				
			, UniqueRecordKey			
			, DataAgeHOT				
			, DataAgeCOLD				
			, RecordChangeDateTime		
from (
			select		  MappingDepartmentCode		=	case 
															when fmc.CODE like '%[A-Z][A-Z][0-9][0-9]' then cast(left(fmc.CODE, len(fmc.CODE) - 4) as varchar(50))
															else cast(fmc.CODE as varchar(50))
														end
						, DepartmentCode			=	cast(fmc.CODE								as varchar(50))
						, DepartmentFullName		=	cast(fmc.CODE + ' - ' + fmc.DESCRIPTION		as varchar(50))
						, DepartmentName			=	cast(fmc.DESCRIPTION						as varchar(50))
						, System_BK					=	cast('TMFF'									as varchar(50))
						, Company_BK				=	cast(oic.Company_BK							as varchar(50))
						, Department_BK				=	cast(fmc.CODE								as varchar(50))
						, UniqueRecordKey			=	utilities.ufn_GetHashedUID('TMFF', fmc.CODE, oic.Company_BK, default, default)
						, DataAgeHOT				=	cast(fmc.SCD_UpdateDate						as datetime)
						, DataAgeCOLD				=	cast((select max(v) from (values (fmc.SCD_UpdateDate), (oic.DataAgeCold)) x(v))	as datetime)
						, RecordChangeDateTime		=	getdate()
						, rn						=	row_number() over (partition by oic.Company_BK, fmc.CODE order by fmc.SCD_UpdateDate desc)
			from		(select		  fmc.CODE
									, fmc.DESCRIPTION
									, fmcc.CONDVALUE1
									, SCD_UpdateDate	=	max(fmc.SCD_UpdateDate)  
						from		ODS.TMFF_FMCODE fmc
						left join	ODS.TMFF_FMCODEcond fmcc
						on			fmc.UNID = fmcc.FMCODE_UNID
						and			fmcc.SCD_ActiveFlag = 1
						and			fmcc.SCD_IsDeleted = 0
						where		type = 'bizscope'
						and			fmc.CONDKEY1 = 'ownerid'
						and			fmc.SCD_ActiveFlag = 1
						and			fmc.SCD_IsDeleted = 0
						group by	  fmc.CODE
									, fmc.DESCRIPTION
									, fmcc.CONDVALUE1
						) fmc
			join		CALC.TMFF_OwnerIdCompany oic
			on			fmc.CONDVALUE1 = oic.OwnerOwnerId
) t
where rn = 1
GO
/****** Object:  View [DW].[v_TMFF_dim_File]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-7451 
--PrevTask COBI-5246, hash = 1452467973
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_TMFF_dim_File'
CREATE view [DW].[v_TMFF_dim_File]
as
select 		  FileId					=	cast(j.LocalShipmentId_BK					as varchar(50))
			, File_BK					=	cast(j.LocalShipmentId_BK					as varchar(50))
			, Company_BK				=	cast(j.Company_BK							as varchar(50))
			, System_BK					=	cast('TMFF'									as varchar(50))
			, FileStatusCode			=	cast(isnull(biref.LocalFileStatusCode,'Open')	as varchar(50))
			, FileStatus				=	cast(isnull(biref.LocalFileStatus,'Open')	as varchar(50))
			, CreateDate				=	recog.CreateDate
			, UniqueRecordKey			=	utilities.ufn_GetHashedUID('TMFF', j.LocalShipmentId_BK,default,default,default)
			, DataAgeHot				=	cast(j.DataAgeHot							as datetime)
			, DataAgeCOLD				=	cast(j.DataAgeCOLD							as datetime)
			, RecordChangeDateTime		=	getdate()
from		CALC.TMFF_Job_GlobalShipmentId_Weight_Volume_Company j
left join   CALC.TMFF_Shipment s 
on			s.File_BK = j.LocalShipmentId_BK
left join   CALC.BIRef_FileStatus biref 
on			biref.FileStatus_BK = s.FileStatus_BK
and			biref.System_BK = 'TMFF'
join		(
			select		  Job_Unid
						, CreateDate	=	max(convert(varchar(50), CreateDate, 112))
			from		(
						select		  Job_Unid		=	coalesce(jc.JOB_UNID, recog.JOB_UNID)
									, CreateDate	=	recog.CREATEDATE
						from		CALC.TMFF_RecognitionEvents recog
						left join	(
									select		  ChargeType		=	'COST'
												, JOB_UNID			=	jc.JOB_UNID
												, SNO				=	jc.SNO
												, SOURCEUNID		=	jc.SOURCEUNID
												, SOURCESNO			=	jc.SOURCESNO
									from		ODS.TMFF_JCCOST jc
									join		ODS.TMFF_JOB j
									on			j.UNID = jc.JOB_UNID
									and			j.SHPTYPE in ('H', 'D')
									and			j.SCD_ActiveFlag = 1
									and			j.SCD_IsDeleted = 0
									where		jc.SCD_ActiveFlag = 1
									and			jc.SCD_IsDeleted = 0
									and			jc.SOURCETYPE = 'JB'
									and			jc.SOURCEUNID <> jc.JOB_UNID
									union all
									select		  ChargeType		=	'REVENUE'
												, JOB_UNID			=	jc.JOB_UNID
												, SNO				=	jc.SNO
												, SOURCEUNID		=	jc.SOURCEUNID
												, SOURCESNO			=	jc.SOURCESNO
									from		ODS.TMFF_JCREVENUE jc
									join		ODS.TMFF_JOB j
									on			j.UNID = jc.JOB_UNID
									and			j.SHPTYPE in ('H', 'D')
									and			j.SCD_ActiveFlag = 1
									and			j.SCD_IsDeleted = 0
									where		jc.SCD_ActiveFlag = 1
									and			jc.SCD_IsDeleted = 0
									and			jc.SOURCETYPE = 'JB'
									and			jc.SOURCEUNID <> jc.JOB_UNID
									) jc
						on			recog.JOB_UNID = jc.SOURCEUNID
						and			recog.SNO = jc.SOURCESNO
						and			recog.ChargeType = jc.ChargeType
						join		ODS.TMFF_JOB j
						on			j.UNID = coalesce(jc.JOB_UNID, recog.JOB_UNID)
						and			j.SCD_ActiveFlag = 1
						and			j.SCD_IsDeleted = 0
						where		j.JOBSTAGECODE in ('B', 'N', 'S')
						and			j.VOIDDATE is null
						and			(	
									j.shptype not in  ('M', 'B')
									or	not exists	(
													select		1
													from		ODS.TMFF_JCCOST jcx
													where		jcx.JOB_UNID = j.UNID
													and			SCD_ActiveFlag = 1
													and			SCD_IsDeleted = 0
													)
									)
						) x
			group by	Job_Unid
			) recog
on			recog.Job_Unid = j.LocalShipmentId_BK
GO
/****** Object:  View [DW].[v_TMFF_dim_Invoice]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--COBI-6467 --Objective Finance System/Company
--prevtask COBI-6121, hash = 257291231
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_TMFF_dim_Invoice'
--select * from utilities.vCheckDefinitionSyncronization where objectname = 'v_TMFF_dim_Invoice'
CREATE view [DW].[v_TMFF_dim_Invoice]
as
select		  System_BK				=	cast('TMFF'					as varchar(50))
			, FinanceSystem_BK		=	cast('ProjectOne'			as varchar(50))
			, Company_BK			=	cast(co.Company_BK			as varchar(50))
			, FinancialCompany_BK	=	cast(co.GlobalCompanyCode	as varchar(50))
			, InvoiceId_BK			=	cast(iv.DOCNO				as varchar(50))
			, InvoiceNumber			=	cast(iv.PRINTSNO			as varchar(50))
			, UniqueRecordKey		=	utilities.ufn_GetHashedUID('TMFF', iv.OWNERID, iv.UNID, default, default)
			, DataAgeHOT			=	cast(iv.SCD_UpdateDate		as datetime)
			, DataAgeCOLD			=	cast((select max(v) from (values (iv.SCD_UpdateDate),(co.DataAgeCOLD)) as value(v)) as datetime)
			, RecordChangeDateTime	=	getdate()	
from		ODS.TMFF_IVHDR iv
left join	CALC.TMFF_OwnerIdCompany co
on			iv.OWNERID = co.OwnerOwnerId
where		iv.SCD_ActiveFlag		=	1
and			iv.SCD_IsDeleted		=	0
and			iv.VOIDDATE is null
and			iv.STATUS = 'ORIGINAL'
GO
/****** Object:  View [DW].[v_TMFF_dim_InvoiceType]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-4443, hash = 6050520259772249797
CREATE view [DW].[v_TMFF_dim_InvoiceType] 
as
select		  System_BK					=	cast('TMFF'								as varchar(50))
			, Company_BK				=	cast(oic.Company_BK						as varchar(50)) 
			, Invoicetype_BK			=	cast(isnull(trim(fmc.CODE), '')			as varchar(50))
			, InvoiceTypeName			=	cast(isnull(trim(fmc.[DESCRIPTION]),'')	as varchar(50))
			, InvoiceTypeName2			=	cast(isnull(trim(fmc.[DESCRIPTION]),'')	as varchar(50))
			, SubNoteType				=	cast(null								as varchar(50)) 
			, NoteClass					=	cast(null								as varchar(50))
			, UniqueRecordKey			=	utilities.ufn_GetHashedUID('TMFF', oic.Company_BK, fmc.CODE, default, default)
			, DataAgeHOT				=   fmc.SCD_UpdateDate
			, DataAgeCOLD				=   (select max(v) from (values (fmc.SCD_UpdateDate), (oic.DataAgeCold)) x(v))
			, RecordChangeDateTime		=	cast(getdate() as datetime)
from		(
			select		 *
						, rn			=   row_number() over (partition by trim(CODE) order by SCD_UpdateDate desc, [DESCRIPTION] desc)
			from		ODS.TMFF_FMCODE
			where		[TYPE] = 'DC'
			and			SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			) fmc
cross join	(
			select		  Company_BK
						, DataAgeCold  =	max(DataAgeCOLD) 
			from		CALC.TMFF_OwnerIdCompany 
			where		Company_BK is not null
			group by	Company_BK
			) oic
where		fmc.rn = 1
GO
/****** Object:  View [DW].[v_TMFF_dim_Item]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-7391
--PrevTask COBI-7388, hash = -2048723371
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_TMFF_dim_Item'
CREATE view [DW].[v_TMFF_dim_Item]
as
select		  System_BK					= cast('TMFF'	as varchar(50))
			, Company_BK				= Company_BK
			, Item_BK					= Item_BK
			, ItemName					= ItemName
			, ServiceCode				= ServiceCode
			, ChargeCode				= ChargeCode
			, InvoiceText1				= InvoiceText1
			, InvoiceText2				= InvoiceText2
			, InvoiceText3				= InvoiceText3
			, InvoiceText4				= InvoiceText4
			, InvoiceText5				= InvoiceText5
			, UniqueRecordKey			= utilities.ufn_GetHashedUID('TMFF',Company_BK,Item_BK, default, default)
			, DataAgeHOT				= DataAgeHOT
			, DataAgeCOLD				= DataAgeCOLD
			, RecordChangeDateTime		= getdate()
from		(
			select		
						  s.Company_BK
						, Item_BK			= cast(i.BIZTYPE + it.CHRGCODE		as varchar(100))
						, ItemName			= cast(it.CHRGDESC					as varchar(100))
						, ServiceCode		= cast(null							as varchar(100))
						, ChargeCode		= cast(it.CHRGCODE					as varchar(50))
						, InvoiceText1		= cast(it.CHRGDESC					as varchar(100))
						, InvoiceText2		= cast(it.LOCALDESC					as varchar(50))
						, InvoiceText3		= cast(null							as varchar(50))
						, InvoiceText4		= cast(null							as varchar(50))
						, InvoiceText5		= cast(null							as varchar(50))
						, DataAgeHOT		= it.SCD_UpdateDate
						, DataAgeCOLD		= (select max(v) from (values (it.SCD_UpdateDate),(i.SCD_UpdateDate), (s.DataAgeCold)) as x(v))
						, rn				= row_number() over (partition by s.Company_BK, cast(i.BIZTYPE + it.CHRGCODE as varchar(100)) order by cast(it.CHRGDESC	as varchar(100)))
			from		ODS.TMFF_IVDTL it
			join		ODS.TMFF_IVHDR i
			on			i.UNID = it.IVHDR_UNID
			and			i.VOIDDATE is null
			and			i.SCD_ActiveFlag = 1
			and			i.SCD_IsDeleted = 0
			join		CALC.TMFF_Shipment s
			on			s.LocalShipmentId_BK = it.SOURCEUNID
			and			it.SOURCETYPE = 'JB'
			where		it.SCD_ActiveFlag = 1
			and			it.SCD_IsDeleted = 0
			) x
where		rn = 1
GO
/****** Object:  View [DW].[v_TMFF_dim_Location]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO








--COBI-7056 -- Adjust Location_BK
--PrevTask COBI-5347, hash = 1839437932
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_TMFF_dim_Location'
--select * from utilities.vCheckDefinitionSyncronization_ext where objectname = 'v_TMFF_dim_Location'
CREATE view [DW].[v_TMFF_dim_Location]
as
select		 [LocationCode]
			,[LocationName]
			,[LocationUN]
			,[CountryCode]
			,[CountryName]
			,[TimeZone]
			,[IsExpired]
			,[FreightArea]
			,[Location_BK]
			,[System_BK]
			,[UniqueRecordKey]
			,[DataAgeHOT]
			,[DataAgeCOLD]
			,[RecordChangeDateTime]
from	(	
			select		  LocationCode				=	cast(trim(l.CTRYCITYCODE)			as varchar(50))
						, LocationName				=	cast(trim(l.DESCRIPTION	)			as varchar(50))
						, LocationUN				=	cast(trim(l.CTRYCITYCODE)			as varchar(50))
						, CountryCode				=	cast(trim(l.CTRYCODE)				as varchar(50))
						, CountryName				=	cast(trim(c.CountryName	)			as varchar(100))
						, TimeZone					=	cast(trim(l.TIMEZONECODE)			as varchar(50))
						, IsExpired					=	cast(''								as varchar(50))
						, FreightArea				=	cast(''								as varchar(50))
						, Location_BK				=	cast(l.CTRYCITYCODE					as varchar(50))
						, System_BK					=	cast('TMFF'							as varchar(50))
						, UniqueRecordKey			=	utilities.ufn_GetHashedUID('TMFF', l.CTRYCITYCODE, default, default, default)
						, DataAgeHOT				=   l.SCD_UpdateDate
						, DataAgeCOLD				=   l.SCD_UpdateDate
						, RecordChangeDateTime		=	cast(getdate() as datetime)
			from		ODS.TMFF_FMCITY l
			left join	CALC.BIRef_Country c
			on			c.CountryCode = l.CTRYCODE
			where		l.SCD_ActiveFlag	= 1
			and			l.SCD_IsDeleted		= 0
			union all
			select		  LocationCode				=	cast(trim(l.CITYCODE)				as varchar(50))
						, LocationName				=	cast(trim(l.IATADESC)				as varchar(50))
						, LocationUN				=	cast(trim(l.CTRYCITYCODE)			as varchar(50))
						, CountryCode				=	cast(trim(l.CTRYCODE)				as varchar(50))
						, CountryName				=	cast(trim(c.CountryName)			as varchar(100))
						, TimeZone					=	cast(trim(l.TIMEZONECODE)			as varchar(50))
						, IsExpired					=	cast(''								as varchar(50))
						, FreightArea				=	cast(''								as varchar(50))
						, Location_BK				=	cast('A' + l.CTRYCITYCODE			as varchar(50))
						, System_BK					=	cast('TMFF'							as varchar(50))
						, UniqueRecordKey			=	utilities.ufn_GetHashedUID('TMFF', l.CITYCODE, default, default, default)
						, DataAgeHOT				=   l.SCD_UpdateDate
						, DataAgeCOLD				=   l.SCD_UpdateDate
						, RecordChangeDateTime		=	cast(getdate() as datetime)
			from		ODS.TMFF_FMCITY l
			left join	CALC.BIRef_Country c
			on			c.CountryCode = l.CTRYCODE
			where		l.SCD_ActiveFlag	= 1
			and			l.SCD_IsDeleted		= 0
			and			l.IATADESC is not null
			and			l.CITYCODE not in ( select		CTRYCITYCODE
										  	from		ODS.TMFF_FMCITY 
											where		SCD_ActiveFlag	= 1
											and			SCD_IsDeleted	= 0 )
			) t
GO
/****** Object:  View [DW].[v_TMFF_dim_Party]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO








--COBI-7452 --Objective Adjust DunsNo attribute
--PrevTask COBI-7219, hash = -1193816168
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_TMFF_dim_Party'
--exec dw.usp_load_tmff_dim_party
--select * from utilities.vcheckdefinitionsyncronization where objectname = 'v_TMFF_dim_Party'
CREATE view [DW].[v_TMFF_dim_Party]
as
select		  System_BK				
			, Party_BK				
			, AccountNo				
			, NameFull				
			, StatisticNo			
			, StatisticNameFull		
			, LocationCode			
			, CountryCode			
			, IsActive				
			, LastActiveDate		
			, LastUpdateDate		
		--	, IsCustomer			
			, CustomerState			
			, CarrierCode			
			, SCACCode				
			, [Name]				
			, StatisticName			
			, DunsNo				
			, StatisticDunsNo		
			, [ZipCode]				
			, [CityName]			
			, [State]				
			, [Address]				
			, IsAccount
			, IsCustomer		
			, IsConsignor		
			, IsConsignee		
			, IsShipper			
			, IsCarrier			
			, IsAgent			
			, IsPickUp			
			, IsDelivery		
			, IsNotify			
			, IsCreditor
			, IsDebtor	
			, UniqueRecordKey		
			, DataAgeHOT			
			, DataAgeCOLD			
			, RecordChangeDateTime	
from (
			select		  System_BK				=	cast('TMFF'																					as varchar(50))
						, Party_BK				=	cast(p.PARTYID																				as varchar(50))
						, AccountNo				=	cast(p.PARTYID																				as varchar(300))
						, NameFull				=	cast(p.PARTYID + ' - ' + p.FULLNAME															as varchar(150))
						, StatisticNo			=	cast(coalesce(ast.StatisticNo, cast(stat.CUSTNO as varchar(50)), p.PARTYID) as varchar(50))
						, StatisticNameFull		=	cast(coalesce(ast.StatisticNo + ' - ' + ast.StatisticName, cast(stat.CUSTNO as varchar(50)) + ' - ' + stat.NAME1, p.PARTYID + ' - ' + p.FULLNAME)	as varchar(150))
						, LocationCode			=	cast(p.COUNTRY + p.CITY																		as varchar(50))
						, CountryCode			=	cast(p.COUNTRY																				as varchar(50))
						, IsActive				=	cast('yes'																					as varchar(50))
						, LastActiveDate		=	cast(''																						as datetime)
						, LastUpdateDate		=	cast(coalesce(p.UPDATEDATE,p.CREATEDATE)													as datetime)
						--, IsCustomer			=	cast(''	 																					as varchar(50))
						, CustomerState			=	cast(''	 																					as varchar(50))
						, CarrierCode			=	cast(''	 																					as varchar(50))
						, SCACCode				=	cast(''	 																					as varchar(50))
						, [Name]				=	cast(p.FULLNAME																				as varchar(150))
						, StatisticName			=	cast(coalesce(ast.StatisticName, stat.NAME1, p.FULLNAME)									as varchar(150))
						, DunsNo				=	cast(dn.DunsNo	 																			as varchar(50))
						, StatisticDunsNo		=	cast(dn.DunsNo																				as varchar(50))
						, [ZipCode]				=	cast(pa.POSTALCODE																			as varchar(50))
						, [CityName]			=	cast(ci.Description																			as varchar(50))
						, [State]				=	cast(ci.STATEPROV																			as varchar(50))
						, [Address]				=	cast(pa.ADDR1																				as varchar(100))
						, IsAccount				=	cast(0	as bit)
						, IsCustomer			=	cast(sign(isnull(t.IsCustomer,0) + isnull(lp.IsCustomer,0))									as bit)
						, IsConsignee			=	cast(sign(isnull(t.IsConsignee,0)+ isnull(gp.IsConsignee,0)+ isnull(lp.IsConsignee,0))		as bit)
						, IsConsignor			=	cast(isnull(IsConsignor	,0)																	as bit)
						, IsShipper				=	cast(isnull(IsShipper	,0)																	as bit)
						, IsCarrier				=	cast(isnull(IsCarrier	,0)																	as bit)
						, IsAgent				=	cast(isnull(IsAgent		,0)																	as bit)
						, IsPickUp				=	cast(isnull(IsPickUp	,0)																	as bit)
						, IsDelivery			=	cast(isnull(IsDelivery	,0)																	as bit)
						, IsNotify				=	cast(isnull(IsNotify	,0)																	as bit)
						, IsCreditor			=	cast(isnull(IsCreditor	,0)																	as bit)
						, IsDebtor				=	cast(isnull(IsDebtor	,0)																	as bit)
						, UniqueRecordKey		=	utilities.ufn_GetHashedUID('TMFF',p.UNID, default, default, default)		
						, DataAgeHOT			=	p.SCD_UpdateDate
						, DataAgeCOLD			=	(select max(v) from (values (p.SCD_UpdateDate),(pa.SCD_UpdateDate), (ci.SCD_UpdateDate),(ast.SCD_UpdateDate)) x(v))
						, RecordChangeDateTime	=	getdate()
						, rn					=	row_number() over (partition by p.PARTYID order by p.SCD_UpdateDate desc)
			from		ODS.TMFF_FMPARTY p
			left join	(
						select		 *
									, rn				=	row_number() over (partition by FMPARTY_UNID order by SCD_UpdateDate desc)
						from		ODS.TMFF_FMPARTYADDR 
						where		SCD_ActiveFlag = 1
						and			SCD_IsDeleted = 0
						) pa
			on			p.UNID = pa.FMPARTY_UNID
			and			pa.rn = 1
			left join	ODS.TMFF_FMCITY ci
			on			pa.CITYCODE = ci.CITYCODE
			and			pa.CTRYCODE = ci.CTRYCODE
			and			ci.SCD_ActiveFlag = 1
			and			ci.SCD_IsDeleted = 0
			left join	CALC.BIRef_StatisticsNoMapping ast
			on			p.PARTYID = ast.Party_BK
			and			ast.System_BK = 'TMFF'
			left join	(
						select		FMPARTY_UNID
									, AxsfreightNo		=	min(try_cast(value as numeric)) 
						from		ODS.TMFF_FMPARTYCONSTANT
						where		CONTYPE = 'AXSFNO'
						and			SCD_ActiveFlag = 1
						and			SCD_IsDeleted = 0
						group by	FMPARTY_UNID
						) pc
			on			p.UNID = pc.FMPARTY_UNID
			left join	(
						select		FMPARTY_UNID
									, DunsNo		=	max(try_cast(value as numeric))  -- VB -using min instead of max as some values have wrong zeros in prefix
						from		ODS.TMFF_FMPARTYCONSTANT
						where		CONTYPE = 'DUNSNO'
						and			DEACTIVE = 0
						and			SCD_ActiveFlag = 1
						and			SCD_IsDeleted = 0
						group by	FMPARTY_UNID
						) dn
			on			p.UNID = dn.FMPARTY_UNID
			left join	ODS.Axsfreight_GRPCUST gcu
			on			gcu.CUSTNO = pc.AxsfreightNo
			and			gcu.SCD_ActiveFlag = 1
			and			gcu.SCD_IsDeleted = 0
			left join	ODS.Axsfreight_GRPCUST stat
			on			stat.CUSTNO = gcu.STATNO
			and			stat.SCD_ActiveFlag = 1
			and			stat.SCD_IsDeleted = 0
			left join	(
						select		  PARTYID
									, IsCustomer		=	max(case when PARTYTYPE in ('CONTROLPARTY') then 1 else 0 end)
									, IsConsignee		=	max(case when PARTYTYPE in ('REALCSGN') then 1 else 0 end)
									, IsPickUp			=	max(case when PARTYTYPE in ('PCF') then 1 else 0 end)
									, IsDelivery		=	max(case when PARTYTYPE in ('DEL') then 1 else 0 end)
									, IsNotify			=	max(case when PARTYTYPE in ('DEL',  'PCF', 'NOTIFY') then 1 else 0 end)
						from		ODS.TMFF_JOBPARTY
						where		PARTYID is not null
						and			PARTYTYPE in ('CONTROLPARTY', 'REALCSGN', 'PCF', 'DEL', 'NOTIFY')
						and			SCD_ActiveFlag = 1
						and			SCD_IsDeleted = 0
						group by	PARTYID 
						) lp
			on			lp.PARTYID	=	p.PARTYID
			left join	(
						select		Party_BK
									, IsCustomer		=	max(case when PartyType = 'PARTYID_CUST' then 1 else 0 end) 
									, IsConsignor		=	max(case when PartyType = 'PARTYID_CUST' then 1 else 0 end) 
									, IsConsignee		=	max(case when PartyType = 'PARTYID_CSGN' then 1 else 0 end) 
									, IsShipper			=	max(case when PartyType = 'PARTYID_SHPR' then 1 else 0 end) 
									, IsCarrier			=	max(case when PartyType in ('CARRIERCODE', 'CARRIERID') then 1 else 0 end) 
									, IsAgent			=	max(case when PartyType in ('OAGENT') then 1 else 0 end) 
						from (
									select  Party_BK, PartyType
									from	ODS.TMFF_JOB
									unpivot (
									Party_BK for PartyType in (PARTYID_SHPR, OAGENT, CARRIERCODE, CARRIERID, PARTYID_CSGN, PARTYID_CUST)
									) u
						where		SCD_ActiveFlag	= 1
						and			SCD_IsDeleted = 0
						) ti
						group by	Party_BK
						) t
			on			p.PARTYID = t.Party_BK
			left join	(
						select distinct 
									Party_BK				=	PARTYID_CSGNONWB
									, IsConsignee			=	1
						from		ODS.TMFF_JOBOTHER jo
						where		SCD_ActiveFlag	= 1
						and			SCD_IsDeleted		= 0
						) gp
			on			p.PARTYID = gp.Party_BK
			left join (
						select		  Party_BK			= PARTYID_COUNTERPARTY 
									, IsDebtor			= max(case when CHARGETYPE = 'REVENUE' then 1 else 0 end )
									, IsCreditor		= max(case when CHARGETYPE = 'COST' then 1 else 0 end )
						from		 CALC.TMFF_RecognitionEvents recog
						group by	PARTYID_COUNTERPARTY
					  ) deb
			on			p.PARTYID = deb.Party_BK
			where 		p.SCD_ActiveFlag = 1
			and			p.SCD_IsDeleted = 0
			) t
where		rn = 1
GO
/****** Object:  View [DW].[v_TMFF_dim_PaymentTerm]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-5241 (parent COBI-5201) --Objective attribute rename
--prevtask COBI-4443, hash = -2674087055867346159
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_TMFF_dim_PaymentTerm'
CREATE view [DW].[v_TMFF_dim_PaymentTerm]
as
select		  * 
			, PaymentTermDaysInterval010		=	cast(floor(PaymentTermDays/10) * 10 as varchar)   + '-' + cast(ceiling(PaymentTermDays/10) * 10 as varchar)
			, PaymentTermDaysInterval050		=	cast(floor(PaymentTermDays/50) * 50 as varchar)   + '-' + cast(ceiling(PaymentTermDays/50) * 50 as varchar)
			, PaymentTermDaysInterval100		=	cast(floor(PaymentTermDays/100) * 100 as varchar) + '-' + cast(ceiling(PaymentTermDays/100) * 100 as varchar)
			, PaymentTermDaysInterval010SortKey	=	floor(PaymentTermDays/10) * 10
			, PaymentTermDaysInterval050SortKey	=	floor(PaymentTermDays/50) * 50
			, PaymentTermDaysInterval100SortKey	=	floor(PaymentTermDays/100) * 100
from		(
			select		distinct
						  System_BK					= cast('TMFF'						as varchar(50))
						, PaymentTerm_BK			= cast(nullif(trim(fmc.Code),'')	as varchar(100))
						, PaymentTermClass			= cast(left(fmc.CODE,3)				as varchar(50))
						, PaymentTerm				= cast(fmc.DESCRIPTION 				as varchar(100))
						, PaymentTermDays			= try_cast(right(fmc.CODE,2)		as int)
						, UniqueRecordKey			= utilities.ufn_GetHashedUID('TMFF', fmc.Code, default, default, default)
						, DataAgeHOT				= fmc.SCD_UpdateDate
						, DataAgeCOLD				= cast((select max(v) from (values (fmc.SCD_UpdateDate)) as value(v)) as datetime)
						, RecordChangeDateTime		= cast(getdate() as datetime)
						, idx						= row_number()over(partition by fmc.Code order by SCD_UpdateDate desc)
			from		ODS.TMFF_FMCODE fmc
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			[TYPE] = 'CSIND'
			) x
GO
/****** Object:  View [DW].[v_TMFF_dim_Service]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-5242 (cobi-5205) --Objective rename attributes
--Prevtask COBI-5286, hash = -8854187340096838905
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_TMFF_dim_Service'
CREATE view [DW].[v_TMFF_dim_Service]
as
select		  ServiceCode			= cast(fmc.CODE									as varchar(50))
			, ServiceGroup			= cast(fmc.[DESCRIPTION]						as varchar(50))
			, Service				= cast(fmc.[DESCRIPTION]						as varchar(50))
			, ServiceCode_BK		= cast(fmc.CODE									as varchar(50))
			, Company_BK			= cast(oic.Company_BK							as varchar(50))
			, System_BK				= cast('TMFF'									as varchar(50))
			, UniqueRecordKey		= utilities.ufn_GetHashedUID('TMFF', oic.Company_BK, fmc.CODE, default, default)
			, DataAgeHOT			= fmc.SCD_UpdateDate
			, DataAgeCOLD			= (select max(v) from (values (fmc.UPDATEDATE), (oic.DataAgeCold)) x(v))
			, RecordChangeDateTime	= getdate()
from		ODS.TMFF_FMCODE fmc
cross join	(
			select		  Company_BK
						, DataAgeCold			=	max(DataAgeCold)
			from		CALC.TMFF_OwnerIdCompany
			group by	Company_BK
			) oic
where		fmc.TYPE = 'BZ'
GO
/****** Object:  View [DW].[v_TMFF_dim_ShipmentType]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-7058 --Adjusted TYPE condition
--prevtask COBI-6158, hash = 873629292
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_TMFF_dim_ShipmentType'
--select * from utilities.vCheckDefinitionSyncronization where objectname = 'v_TMFF_dim_ShipmentType'
CREATE view [DW].[v_TMFF_dim_ShipmentType]
as
select		  System_BK					= cast('TMFF'						as varchar(50))
			, ShipmentType_BK			= cast(fmc.CODE						as varchar(50))
			, ShipmentTypeCode			= cast(fmc.CODE						as varchar(50))
			, ShipmentType				= cast(fmc.[DESCRIPTION]			as varchar(50))
			, UniqueRecordKey			= utilities.ufn_GetHashedUID('TMFF', fmc.CODE, default, default, default)
			, DataAgeHOT				= fmc.SCD_UpdateDate
			, DataAgeCOLD				= fmc.SCD_UpdateDate
			, RecordChangeDateTime		= getdate()
from		ODS.TMFF_FMCODE fmc
where		fmc.[TYPE] in ('SP','LOADTERM','RFLOADTERM')
and			fmc.SCD_ActiveFlag = 1
and			fmc.SCD_IsDeleted = 0
union all
select	
			  System_BK					= cast('TMFF'						as varchar(50))
			, ShipmentType_BK			= cast('BCN'						as varchar(50))
			, ShipmentTypeCode			= cast('BCN'						as varchar(50))
			, ShipmentType				= cast('Buyers Consolidation'		as varchar(50))
			, UniqueRecordKey			= utilities.ufn_GetHashedUID('TMFF', 'BCN', default, default, default)
			, DataAgeHOT				= cast('20250804' as datetime)
			, DataAgeCOLD				= cast('20250804' as datetime)
			, RecordChangeDateTime		= getdate()
from		(select 'dummy' as dummy ) dummy 
where		not exists (select		fmc.CODE	 
						from		ODS.TMFF_FMCODE fmc
						where		fmc.[TYPE] in ('SP','LOADTERM','RFLOADTERM')
						and			fmc.SCD_ActiveFlag = 1
						and			fmc.SCD_IsDeleted = 0
						and 		fmc.CODE	= 'BCN')
GO
/****** Object:  View [DW].[v_TMFF_dim_VatCode]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




--COBI-4443
--PrevTask COBI-3551, hash = -4889531807827251458
--exec utilities.usp_ConvertViewToLoadComplex_simple 'DW','v_TMFF_dim_VatCode'


CREATE view [DW].[v_TMFF_dim_VatCode]
as
select		  System_BK				
			, VatCode_BK			
			, VatCodeName	
			, UniqueRecordKey	
			, DataAgeHOT			
			, DataAgeCOLD			
			, RecordChangeDateTime
from		(
			select		  System_BK				 = cast('TMFF'						as varchar(50))
						, VatCode_BK			 = cast(nullif(trim(fm.Code),'')	as varchar(50))
						, VatCodeName			 = cast(fm.Description				as varchar(50))
						, UniqueRecordKey		 = utilities.ufn_GetHashedUID('TMFF', fm.CODE, default, default, default)
						, DataAgeHOT			 = fm.SCD_UpdateDate
						, DataAgeCOLD			 = fm.SCD_UpdateDate
						, RecordChangeDateTime	 = getdate()
						, idx					 = row_number() over (partition by fm.code order by fm.SchemeCode)
			from		ODS.TMFF_FMCODE fm
			where		fm.SCD_ActiveFlag	=	1
			and			fm.SCD_IsDeleted	=	0
			and			fm.TYPE = 'VAT'
			) r
where		idx = 1
GO
/****** Object:  View [DW].[v_TMFF_fact_File]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-5678 --Objective Removal of dim_FileStatus
--Prevtask COBI-4979, hash = 520202960
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_TMFF_fact_File'
CREATE view [DW].[v_TMFF_fact_File]
as
select		  --Measures
			  FileCount									=	cast(1 as bigint)
			, ClosingCount								=	null
			, DaysToFirstInvoice						=	cast(datediff(day, CreateDate_BK, FirstInvoiceDate_BK)			as bigint)  							  
			--Dimension_BK
			, System_BK									=	cast(x.System_BK			as varchar(50))
			, Company_BK								=	cast(x.Company_BK			as varchar(50))
			, OperationalCompany_Bk						=	cast(x.Company_BK			as varchar(50))
			, FinancialCompany_Bk						=	cast(x.FinancialCompany_Bk	as varchar(50))
			, OperationalSystem_Bk						=	cast(x.System_BK			as varchar(50))
			, FinanceSystem_Bk							=	'ProjectOne'
			, File_BK									=	cast(x.File_BK	as varchar(50))
			--Dates--
			, CreateDate_BK								=	cast(CreateDate_BK				as date)
			, FirstInvoiceDate_BK						=	cast(FirstInvoiceDate_BK		as date)
			, FirstAccrualDate_BK						=	cast(FirstAccrualDate			as date)
			, FirstCostDate_BK							=	cast(FirstCostDate_BK			as date)
			, ActivityCompletedDate_BK					=	cast(ActivityCompletedDate_BK	as date)
			, FirstClosingDate_BK						=	cast(FirstClosingDate_BK		as date)
			---LifecycleDay---
			, FirstInvoiceDate_LifecycleDay_BK			=	cast(datediff(day, CreateDate_BK, FirstInvoiceDate_BK) + 1		as bigint)
			, FirstAccrualDate_LifecycleDay_BK			=	cast(datediff(day, CreateDate_BK, FirstAccrualDate) + 1			as bigint)
			, FirstCostDate_LifecycleDay_BK				=	cast(datediff(day, CreateDate_BK, FirstCostDate_BK) + 1			as bigint)
			, ActivityCompletedDate_LifecycleDay_BK		=	cast(datediff(day, CreateDate_BK, ActivityCompletedDate_BK) + 1	as bigint)
			, FirstClosingDate_LifecycleDay_BK			=	cast(datediff(day, CreateDate_BK, FirstClosingDate_BK) + 1		as bigint)

			, UniqueRecordKey							=	utilities.ufn_GetHashedUID('TMFF', Company_BK, File_BK, default, default)
			, [DataAgeHOT]								=	[DataAgeHOT]
			, [DataAgeCOLD]								=	[DataAgeCOLD]
			, [RecordChangeDateTime]					=	[RecordChangeDateTime]
from		(
			select
						  System_BK						=	cast('TMFF' as varchar(50))
						, Company_BK					=	cast(s.Company_BK as varchar(50))
						, FinancialCompany_Bk			=	cast(oc.GlobalCompanyCode as varchar(50))
						, File_BK						=	cast(s.File_BK as varchar(30))
						, CreateDate_BK					=	cast(s.CreateDate_BK	as date)
						, FirstInvoiceDate_BK			=   min(cast(ih.DOCDATE as date)) 
						, FirstCostDate_BK				=	null 
						, FirstAccrualDate				=	null
						, ActivityCompletedDate_BK		=	null
						, FirstClosingDate_BK			=   null
						, [DataAgeHOT]					=	s.DataAgeHOT
						, [DataAgeCOLD]					=	s.DataAgeCold
						, [RecordChangeDateTime]		=	getdate()
			from		CALC.TMFF_Shipment s
			left join	CALC.TMFF_OwnerIdCompany oc
			on			oc.Company_BK = s.Company_BK
			left join	ODS.TMFF_JOB j
			on			s.LocalShipmentId_BK = j.UNID
			and			j.SCD_IsDeleted = 0
			and			j.SCD_ActiveFlag = 1
			and			j.VOIDDATE is null
			left join	ODS.TMFF_IVJOB ij
			on			s.LocalShipmentId_BK = ij.JOB_UNID
			and			ij.SCD_ActiveFlag = 1
			and			ij.SCD_IsDeleted = 0
			left join	ODS.TMFF_IVHDR ih
			on			ij.IVHDR_UNID = ih.UNID
			and			ih.SCD_ActiveFlag = 1
			and			ih.SCD_IsDeleted = 0
			and			ih.VOIDDATE is null
			group by	  s.Company_BK
						, s.File_BK
						, s.CreateDate_BK
						, s.DataAgeHOT
						, s.DataAgeCOLD
						, j.CURRENTSTAGE
						, s.FileStatus_BK
						, oc.GlobalCompanyCode
			)x


GO
/****** Object:  View [DW].[v_TMFF_fact_FileTransaction]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--COBI-7518 --Objective Fallback on Date_Bk
--prevtask COBI-7330, hash = -1154806842
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_TMFF_fact_FileTransaction'
--select * from utilities.vCheckDefinitionSyncronization where objectname = 'v_TMFF_fact_FileTransaction'
CREATE   view [DW].[v_TMFF_fact_FileTransaction]
as
select		
			  FileRevenueTransaction						=	LineCalculation.RevMultiplier	* LineCalculation.IncludeMultiplier * jc.LineAmountTransaction
			, FileCostTransaction							=	LineCalculation.CostMultiplier	* LineCalculation.IncludeMultiplier * jc.LineAmountTransaction
			, FileAmountTransaction							=	LineCalculation.AmountSign		* jc.LineAmountTransaction
			, FileRevenueLocal								=	LineCalculation.RevMultiplier	* LineCalculation.IncludeMultiplier * jc.LineAmountLocal
			, FileCostLocal									=	LineCalculation.CostMultiplier	* LineCalculation.IncludeMultiplier * jc.LineAmountLocal
			, FileAmountLocal								=	LineCalculation.AmountSign		* jc.LineAmountLocal
			, EstimatedRevenueTransaction					=	LineCalculation.RevMultiplier	* LineCalculation.IncludeMultiplier * jc.EstimatedAmountTransaction		
			, EstimatedCostTransaction						=	LineCalculation.CostMultiplier	* LineCalculation.IncludeMultiplier * jc.EstimatedAmountTransaction		
			, EstimatedRevenueLocal							=	LineCalculation.RevMultiplier	* LineCalculation.IncludeMultiplier * jc.EstimatedAmountLocal			
			, EstimatedCostLocal							=	LineCalculation.CostMultiplier	* LineCalculation.IncludeMultiplier * jc.EstimatedAmountLocal			
			, ActualRevenueTransaction						=	LineCalculation.RevMultiplier	* LineCalculation.IncludeMultiplier * jc.ActualAmountTransaction		
			, ActualCostTransaction							=	LineCalculation.CostMultiplier	* LineCalculation.IncludeMultiplier * jc.ActualAmountTransaction			
			, ActualRevenueLocal							=	LineCalculation.RevMultiplier	* LineCalculation.IncludeMultiplier * jc.ActualAmountLocal			
			, ActualCostLocal								=	LineCalculation.CostMultiplier	* LineCalculation.IncludeMultiplier * jc.ActualAmountLocal				
			, RecognizedRevenueTransaction					=	LineCalculation.RevMultiplier	* LineCalculation.IncludeMultiplier * jc.RecognizedAmountTransaction	
			, RecognizedCostTransaction						=	LineCalculation.CostMultiplier	* LineCalculation.IncludeMultiplier * jc.RecognizedAmountTransaction		
			, RecognizedRevenueLocal						=	LineCalculation.RevMultiplier	* LineCalculation.IncludeMultiplier * jc.RecognizedAmountLocal		
			, RecognizedCostLocal							=	LineCalculation.CostMultiplier	* LineCalculation.IncludeMultiplier * jc.RecognizedAmountLocal			
			, FileRevenueTransactionTotal					=	LineCalculation.RevMultiplier	* LineCalculation.DutyIncludeMultiplier * jc.LineAmountTransaction
			, FileCostTransactionTotal						=	LineCalculation.CostMultiplier	* LineCalculation.DutyIncludeMultiplier * jc.LineAmountTransaction
			, FileAmountTransactionTotal					=	LineCalculation.AmountSign		* LineCalculation.DutyIncludeMultiplier * jc.LineAmountTransaction
			, FileRevenueLocalTotal							=	LineCalculation.RevMultiplier	* LineCalculation.DutyIncludeMultiplier * jc.LineAmountLocal
			, FileCostLocalTotal							=	LineCalculation.CostMultiplier	* LineCalculation.DutyIncludeMultiplier * jc.LineAmountLocal
			, FileAmountLocalTotal							=	LineCalculation.AmountSign		* LineCalculation.DutyIncludeMultiplier * jc.LineAmountLocal
			--Dimension BK's									
			, ARP_Account_BK								=	cast(jc.PartyId + ' | ' + case when jc.TableType = 'COST' then 'Creditor' else 'Debtor' end as varchar(50)) --so this is a bit of a bet, we might be right about the parties being the same, but there may be differences. Going with this for now, as it requires less resources
			, System_BK										=	cast('TMFF'			as varchar(50))
			, OperationalSystem_BK							=	cast('TMFF'			as varchar(50))
			, FinanceSystem_BK								=	cast('ProjectOne'	as varchar(50))
			, Company_BK									=	cast(s.Company_BK	as varchar(50))
			, OperationalCompany_BK							=	cast(s.Company_BK	as varchar(50))
			, FinancialCompany_BK							=	cast(s.GlobalCompanyCode as varchar(50))
			, BaseCurrency_BK								=	s.BaseCurrency_BK
			, ExchangeRatePeriod_BK							=	cast(year(coalesce(jc.RecognitionDate, jc.UPDATEDATE, jc.CREATEDATE)) * 100 + month(coalesce(jc.RecognitionDate, jc.UPDATEDATE, jc.CREATEDATE)) as varchar(50))
			, GlobalShipmentId_BK							=	s.GlobalShipmentId_BK
			, LocalShipmentId_BK							=	cast(jc.JOB_UNID	as varchar(50))
			, Currency_BK									=	cast(coalesce(jc.ActualCurrencyCode, jc.CurrencyCode) as varchar(50))
			, TurnOverGroup_BK								=	cast(null			as varchar(50)) 
			, SetOffLedgerAccount_BK						=	cast(null			as varchar(50)) --I am betting on this one being phased out.
			, Department_BK									=	s.Department_BK
			, COSTCENTER_BK									=	cast(null			as varchar(50))
			, File_BK										=	cast(jc.JOB_UNID	as varchar(50))
			, ExchangeRateCalculationMethod_BK				=	cast('PnL'			as varchar(50))
			, DutyOutlayBoolean_BK							=	cast(case when jc.ChrgCode= 'DUT' then '1' else '0' end as varchar(50))
			, LedgerAccount_BK								=	cast(ccm.MAPCODE	as varchar(50)) 
			, CreditorParty_BK								=	cast(case when jc.TableType = 'COST' then jc.PartyId else null end as varchar(50))
			, DebtorParty_BK								=	cast(case when jc.TableType = 'REVENUE'  then jc.PartyId else null end as varchar(50))			
			, CustomerParty_BK								=	s.CustomerParty_BK
			, Date_BK										=	cast(coalesce(jc.UpdateDate, jc.CreateDate)	as date)
			, EntryDate_BK									=	cast(jc.UpdateDate							as date)
			, VoucherDate_BK								=	cast(jc.DocDate								as date)
			, FinancialDate_BK								=	cast(jc.RecognitionDate						as date) 
			, FirstFinancialDate_BK							=	cast(min(jc.RecognitionDate) over (partition by s.Company_BK, jc.JOB_UNID) as date) 
			, CreateDate_BK									=	cast(jc.CreateDate	as date)
			, FileTransactionStatus_BK						=	cast(case when jc.RecognitionDate is not null then 'Closed' else 'Open' end as varchar(50))
			-----LifecycleDay------								
			, Date_LifecycleDay_BK							=	cast(datediff(day, s.CreateDate_BK, jc.UPDATEDATE) as bigint)
			, EntryDate_LifecycleDay_BK						=	cast(datediff(day, s.CreateDate_BK, jc.UPDATEDATE) as bigint)
			, VoucherDate_LifecycleDay_BK					=	cast(datediff(day, s.CreateDate_BK, jc.DOCDATE) as bigint)
			, FinancialDate_LifecycleDay_BK					=	cast(datediff(day, s.CreateDate_BK, jc.RecognitionDate) as bigint)
			, ShipmentDepartureDate_LifecycleDay_BK			=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDepartureDate_BK) as bigint)
			, ShipmentArrivalDate_LifecycleDay_BK			=	cast(datediff(day, s.CreateDate_BK, s.ShipmentArrivalDate_BK) as bigint)
			, MainTransportDepartureDate_LifecycleDay_BK	=	cast(datediff(day, s.CreateDate_BK, s.MainTransportDepartureDate_BK) as bigint)
			, MainTransportArrivalDate_LifecycleDay_BK		=	cast(datediff(day, s.CreateDate_BK, s.MainTransportArrivalDate_BK) as bigint)
			, ShipmentDate_LifecycleDay_BK					=	cast(datediff(day, s.CreateDate_BK, s.ShipmentDate_BK) as bigint)
 			------ Parameters ------							
			, PostingText									=	cast(jc.ChrgDesc as varchar(200))
			, ARP_Voucher									=	cast(jc.DocNo as varchar(50))
			, ARP_OriginalVoucher							=	cast(jc.DocNo as varchar(50))
			, ARP_Document_BK								=	cast(jc.DocNo as varchar(50))
			, UniqueRecordKey								=	utilities.ufn_GetHashedUID('TMFF', cast(jc.JOB_UNID as varchar),jc.JCSNO, jc.SNO, jc.TableType)
			, DataAgeHOT									=	jc.SCD_UpdateDate
			, DataAgeCOLD									=	(select max(v) from (values (jc.SCD_UpdateDate), (s.DataAgeCOLD)) x (v))
			, RecordChangeDateTime							=	getdate()
			--Reconciliation Columns
			--Since this operation is a little complicated, we need to have a way to assure that we are matched between RecognitionEvents and the output
			, Recog_JOB_UNID								=	jc.Recog_JOB_UNID
			, Recog_SNO										=	jc.Recog_SNO		
			, Recog_CHRGCODE								=	jc.Recog_CHRGCODE
from		(
			--This new version of the jc subquery now produces a line per recognitionevent CAL Table
			--this means we can get rid of the recon event part of the query, and recognitiondate is the recognitiondate
			select		  Job_Unid						=	coalesce(jc.JOB_UNID, recog.JOB_UNID)
						, JCSNO							=	jc.SNO
						, SNO							=	recog.SNO
						, ChrgCode						=	coalesce(jc.CHRGCODE, recog.CHRGCODE)
						, ChrgDesc						=	coalesce(jc.CHRGDESC, recog.CHRGDESC)
						, SCD_UpdateDate				=	jc.SCD_UpdateDate --explicitly selecting only from JC for performance reasons, as there is only very rarely data in the COST/REVENUE without a record in JC
						, LineAmountLocal				=	case when jc.job_unid is not null then jc.Fraction * recog.RECORDAMTLC * isnull(recog.AMTFC * jc.AMTLC / nullif(jc.AMTFC, 0) / nullif(recog.AMTLC, 0), 1) else recog.RECORDAMTLC end
						, EstimatedAmountLocal			=	case when jc.job_unid is not null then jc.Fraction * recog.RECORDAMTLC * isnull(recog.AMTFC * jc.AMTLC / nullif(jc.AMTFC, 0) / nullif(recog.AMTLC, 0), 1) else recog.RECORDAMTLC end
						, ActualAmountLocal				=	case when jc.job_unid is not null then jc.Fraction * recog.RECORDAMTLC * isnull(recog.AMTFC * jc.AMTLC / nullif(jc.AMTFC, 0) / nullif(recog.AMTLC, 0), 1) else recog.RECORDAMTLC end
						, RecognizedAmountLocal			=	case when jc.job_unid is not null then jc.Fraction * recog.RECORDAMTLC * isnull(recog.AMTFC * jc.AMTLC / nullif(jc.AMTFC, 0) / nullif(recog.AMTLC, 0), 1) else recog.RECORDAMTLC end * case when recog.RECOGNITIONDATE is null then 0 else 1 end
						, LineAmountTransaction			=	case when jc.job_unid is not null then jc.Fraction else 1 end * recog.RECORDAMTLC * isnull(recog.AMTFC / nullif(recog.AMTLC, 0), 1) 
						, EstimatedAmountTransaction	=	case when jc.job_unid is not null then jc.Fraction else 1 end * recog.RECORDAMTLC * isnull(recog.AMTFC / nullif(recog.AMTLC, 0), 1) 
						, ActualAmountTransaction		=	case when jc.job_unid is not null then jc.Fraction else 1 end * recog.RECORDAMTLC * isnull(recog.AMTFC / nullif(recog.AMTLC, 0), 1) 
						, RecognizedAmountTransaction	=	case when jc.job_unid is not null then jc.Fraction else 1 end * recog.RECORDAMTLC * isnull(recog.AMTFC / nullif(recog.AMTLC, 0), 1)  * case when recog.RECOGNITIONDATE is null then 0 else 1 end
						, RecognitionDate				=	recog.RECOGNITIONDATE 
						, TableType						=	recog.ChargeType
						, MapType						=	case
																--Caution! the case statement relies heavily on the order. Do not alter without a plan!
																when recog.CRI = 0 then 'GLEXTERNAL'  
																when recog.CRI = 1 then 'GLINTERCOMP'  
																when recog.CRI = 2 then 'GLINTEROFF' 
																when IsIC.OWNERID is null then 'GLEXTERNAL'
																when ownerCmp.val <> accCmp.val then 'GLINTERCOMP'
																when ownerCmp.val = accCmp.val then 'GLINTEROFF'
															end
						, DocDate						=	recog.DOCDATE
						, DocNo							=	recog.DOCNO
						, PartyId						=	recog.PARTYID_COUNTERPARTY
						, DocStatus						=	INVSTS
						, CurrencyCode					=	coalesce(jc.CURRCODE, recog.CURRCODE)
						, ActualCurrencyCode			=	coalesce(jc.ACTUALCURRCODE, recog.ACTUALCURRCODE)
						, CreateDate					=	recog.CREATEDATE
						, UpdateDate					=	recog.UPDATEDATE
						, Recog_JOB_UNID				=	recog.JOB_UNID
						, Recog_SNO						=	recog.SNO
						, Recog_CHRGCODE				=	recog.CHRGCODE
			from		CALC.TMFF_RecognitionEvents recog
			left join	(
			--this subquery messes up the possibility of optimizing selects, i think on SCD_UpdateDate. But that is the cost for now.
						select		  ChargeType		=	'COST'
									, JOB_UNID			=	jc.JOB_UNID
									, SNO				=	jc.SNO
									, SOURCEUNID		=	jc.SOURCEUNID
									, SOURCESNO			=	jc.SOURCESNO
									, CHRGDESC			=	jc.CHRGDESC
									, CHRGCODE			=	jc.CHRGCODE
									, AMTFC				=	jc.AMTFC
									, ACTUALAMTBC		=	jc.ACTUALAMTBC
									, AMTLC				=	jc.AMTLC
									, ACTUALAMTLC		=	jc.ACTUALAMTLC
									, CURRCODE			=	jc.CURRCODE
									, ACTUALCURRCODE	=	jc.ACTUALCURRCODE
									, SCD_UpdateDate	=	jc.SCD_UpdateDate
									, Fraction			=	AMTFC / isnull(nullif(sum(AMTFC) over (partition by SOURCEUNID, SOURCESNO), 0), count(*) over (partition by SOURCEUNID, SOURCESNO))
						from		ODS.TMFF_JCCOST jc
						join		ODS.TMFF_JOB j
						on			j.UNID = jc.JOB_UNID
						and			j.SHPTYPE in ('H', 'D')
						and			j.SCD_ActiveFlag = 1
						and			j.SCD_IsDeleted = 0
						where		jc.SCD_ActiveFlag = 1
						and			jc.SCD_IsDeleted = 0
						and			jc.SOURCETYPE = 'JB'
						and			jc.SOURCEUNID <> jc.JOB_UNID
						union all
						select		  ChargeType		=	'REVENUE'
									, JOB_UNID			=	jc.JOB_UNID
									, SNO				=	jc.SNO
									, SOURCEUNID		=	jc.SOURCEUNID
									, SOURCESNO			=	jc.SOURCESNO
									, CHRGDESC			=	jc.CHRGDESC
									, CHRGCODE			=	jc.CHRGCODE
									, AMTFC				=	jc.AMTFC
									, ACTUALAMTBC		=	jc.ACTUALAMTBC
									, AMTLC				=	jc.AMTLC
									, ACTUALAMTLC		=	jc.ACTUALAMTLC
									, CURRCODE			=	jc.CURRCODE
									, ACTUALCURRCODE	=	jc.ACTUALCURRCODE
									, SCD_UpdateDate	=	jc.SCD_UpdateDate
									, Fraction			=	AMTFC / isnull(nullif(sum(AMTFC) over (partition by SOURCEUNID, SOURCESNO), 0), count(*) over (partition by SOURCEUNID, SOURCESNO))
						from		ODS.TMFF_JCREVENUE jc
						join		ODS.TMFF_JOB j
						on			j.UNID = jc.JOB_UNID
						and			j.SHPTYPE in ('H', 'D')
						and			j.SCD_ActiveFlag = 1
						and			j.SCD_IsDeleted = 0
						where		jc.SCD_ActiveFlag = 1
						and			jc.SCD_IsDeleted = 0
						and			jc.SOURCETYPE = 'JB'
						and			jc.SOURCEUNID <> jc.JOB_UNID
						) jc
			on			recog.JOB_UNID = jc.SOURCEUNID
			and			recog.SNO = jc.SOURCESNO
			and			recog.ChargeType = jc.ChargeType
			join		ODS.TMFF_JOB j
			on			j.UNID = coalesce(jc.JOB_UNID, recog.JOB_UNID)
			and			j.SCD_ActiveFlag = 1
			and			j.SCD_IsDeleted = 0
			left join	ODS.TMFF_SYCOMPANY isIC
			on			IsIC.OWNERID = recog.PARTYID_COUNTERPARTY
			and			isIC.SCD_ActiveFlag = 1
			and			isIC.SCD_IsDeleted = 0
			left join	(
						select		  PARTYID
									, val = max([VALUE])
						from		ODS.TMFF_FMPARTYCONSTANT pc
						where		PC.CONTYPE = 'COMPANYCODE'
						and			pc.SCD_ActiveFlag =1
						and			pc.SCD_IsDeleted = 0
						group by	PARTYID 
						) accCmp
			on			accCmp.PARTYID = recog.PARTYID_COUNTERPARTY
			left join	(
						select		  PARTYID
									, val = max([VALUE])
						from		ODS.TMFF_FMPARTYCONSTANT pc
						where		PC.CONTYPE = 'COMPANYCODE'
						and			pc.SCD_ActiveFlag =1
						and			pc.SCD_IsDeleted = 0
						group by	PARTYID 
						) ownerCmp
			on			ownerCmp.PARTYID = j.OWNERID
			where		j.JOBSTAGECODE in ('B', 'N', 'S')
			and			j.VOIDDATE is null
			and			(	
						j.shptype not in  ('M', 'B')
						or	not exists	(
										select		1
										from		ODS.TMFF_JCCOST jcx
										where		jcx.JOB_UNID = j.UNID
										and			SCD_ActiveFlag = 1
										and			SCD_IsDeleted = 0
										)
						)
			) jc
join		CALC.TMFF_Shipment s
on			s.LocalShipmentId_BK = jc.JOB_UNID
left join	ODS.TMFF_FMCHARGECODE cc
on			cc.CHRGCODE = jc.ChrgCode
and			cc.BIZTYPE = s.BIZTYPE
and			cc.SchemeCode = s.CountrySchemeCode
and			cc.SCD_ActiveFlag = 1
and			cc.SCD_IsDeleted = 0
left join	ODS.TMFF_FMCHRGCODEMAP ccm
on			ccm.FMCHARGECODE_UNID = cc.UNID
and			ccm.MAPTYPE = jc.MAPTYPE
and			ccm.[TYPE] = left(jc.TableType, 1)
and			ccm.SCD_ActiveFlag = 1
and			ccm.SCD_IsDeleted = 0
cross apply	(
			--calculation of lineamount components
			select		--what sign do we use for FileAmount?
						  AmountSign			=	case 
														when jc.TableType = 'REVENUE' then 1 
														else -1 
													end
						--is it revenue?
						, RevMultiplier			=	case 
														when jc.TableType = 'REVENUE' then 1 
														else null 
													end
						--is it cost?
						, CostMultiplier		=	case 
														when jc.TableType = 'COST' then 1 
														else null 
													end
						--Should we even include the line? (we do not show for voided or deleted, nor for Duty and VAT) 
						--JISC: Have removed filter on Master as some masters should be included. (That is handled in the where clause in JC.)
						--20251209 VM: Still an open question: should we keep these rows, or can they be filtered out earlier? --COBI-6814
						, IncludeMultiplier		=	case 
														when cc.CHRGCODE in ('DUT','VAT','CPPD') or jc.DocStatus in ('v', 'd') then null
														else 1
													end
						, DutyIncludeMultiplier		=	case 
														when jc.DocStatus in ('v', 'd') then null
														else 1
													end
			) linecalculation
GO
/****** Object:  View [DW].[v_TMFF_fact_Invoice]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






--COBI-7396 --Add PaymentTerm_Bk
--prevtask COBI-6172, hash = -936507479
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_TMFF_fact_Invoice'
--select * from utilities.vCheckDefinitionSyncronization where objectname = 'v_TMFF_fact_Invoice'
CREATE view [DW].[v_TMFF_fact_Invoice]
as
select		--Measures--------------------------------------------------
			  DocumentCount								=	cast(1										as bigint) 
			, InvoiceCount								=	cast(case when i.DOCTYPE <> 'CN' then 1 else 0 end	as bigint)
			, InvoiceCountNet							=	cast(case when i.DOCTYPE <> 'CN' then 1 else -1 end	as bigint)
			, PaymentDays								=	cast(datediff(d, i.DOCDATE, i.DUEDATE)		as bigint)
			--Dimension Business Keys-----------------------------------
			, System_BK									=	cast('TMFF'									as varchar(50))
			, FinanceSystem_BK							=	cast('ProjectOne'							as varchar(50))
			, OperationalSystem_BK						=	cast('TMFF'									as varchar(50))
			, Company_BK								=	cast(co.Company_BK							as varchar(50))
			, FinancialCompany_BK						=	cast(co.GlobalCompanyCode					as varchar(50))
			, OperationalCompany_BK						=	cast(co.Company_BK							as varchar(50))
			, Currency_BK								=	cast(i.CURRCODE								as varchar(50))
			, File_BK									=	cast(s.File_BK								as varchar(50))
			, Department_BK								=	cast(s.Department_BK						as varchar(50))
			, CostCenter_BK								=	cast(null									as varchar(50))
			, PaymentTerm_Bk							=	cast(i.CRTERMCODE							as varchar(100))
			, InvoiceId_BK								=	cast(i.DOCNO						        as varchar(50))
			, InvoiceType_BK							=	cast(i.DOCTYPE								as varchar(50))
			, GlobalShipmentId_BK						=	s.GlobalShipmentId_BK
			, LocalShipmentId_BK						=	cast(ij.JOB_UNID							as varchar(50))
			, InvoicePaymentTerm_IntervalDay_BK			=	datediff(d,I.DOCDATE,I.DUEDATE)
			, ExchangeRateCalculationMethod_BK			=	cast('PnL'									as varchar(50))
			, CustomerParty_BK							=	cast(upper(trim(s.CustomerParty_BK))		as varchar(8000))
			, DebtorParty_BK							=	cast(upper(trim(i.PARTYID_CUST))			as varchar(8000))
			, ARP_Account_BK							=	cast(upper(trim(i.PARTYID_CUST))			as varchar(50)) + ' | ' + 'Debtor'
			----Date BK's--------------------------------------------------
			, InvoiceDate_BK							=	try_cast(I.DOCDATE							as date)
			, DueDate_BK								=	try_cast(I.DUEDATE							as date)
			, PrintDate_BK								=	try_cast(I.DOCDATE							as date)
			, Date_BK									=	try_cast(i.DOCDATE							as date)
			, FinancialDate_BK							=	try_cast(i.POSTDATE							as date)
			, CreateDate_BK								=	try_cast(i.CREATEDATE						as date)
			, Voucher_BK								=	cast(null									as varchar(50))
			, UniqueRecordKey							=	utilities.ufn_GetHashedUID('TMFF', i.UNID, default, default, default)
			, DataAgeHOT								=   i.SCD_UpdateDate
			, DataAgeCOLD								=   (select max(v) from (values (i.SCD_UpdateDate), (ij.SCD_UpdateDate), (s.DataAgeCOLD), (co.DataAgeCOLD)) as value(v))
			, RecordChangeDateTime						=	cast(getdate()								as datetime)
from		ODS.TMFF_IVHDR i
left join	CALC.TMFF_OwnerIdCompany co
on			i.OWNERID = co.OwnerOwnerId
inner join	ODS.TMFF_IVJOB ij
on			ij.IVHDR_UNID = i.UNID	
and			ij.SCD_ActiveFlag = 1
and			ij.SCD_IsDeleted = 0
inner join	CALC.TMFF_Shipment s
on			s.LocalShipmentId_BK = ij.JOB_UNID
where 		i.SCD_ActiveFlag = 1
and			i.SCD_IsDeleted = 0
and			i.VOIDDATE is null
and			i.STATUS = 'ORIGINAL'
GO
/****** Object:  View [DW].[v_TMFF_fact_InvoiceTransaction]    Script Date: 7/29/2026 1:44:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--COBI-7432 --Add ChargeLineCode
--prevtask COBI-7396, hash = 1941808041
--exec utilities.usp_ConvertViewToLoadComplex 'DW','v_TMFF_fact_InvoiceTransaction'
--select * from utilities.vCheckDefinitionSyncronization where objectname = 'v_TMFF_fact_InvoiceTransaction'
CREATE view [DW].[v_TMFF_fact_InvoiceTransaction]
as 
select		--Measures--------------------------------------------------
			  InvoicedAmountTransaction					=	case when i.DOCTYPE = 'CN' then -1 else 1 end * try_cast(it.AMTBC					as float)
			, VatAmountTransaction						=	case when i.DOCTYPE = 'CN' then -1 else 1 end * try_cast(it.VATAMT					as float)
			, DocumentAmountTransaction					=	case when i.DOCTYPE = 'CN' then -1 else 1 end * try_cast(it.AMTBC + it.VATAMT		as float)
			, InvoicedAmountLocal						=	case when i.DOCTYPE = 'CN' then -1 else 1 end * try_cast(it.AMTLC					as float)
			, VatAmountLocal							=	case when i.DOCTYPE = 'CN' then -1 else 1 end * try_cast(it.VATAMTLC				as float)
			, DocumentAmountLocal						=	case when i.DOCTYPE = 'CN' then -1 else 1 end * try_cast(it.AMTLC + it.VATAMTLC		as float)
			, InvoicedCurrAmountTransaction				=	case when i.DOCTYPE = 'CN' then -1 else 1 end * try_cast(it.AMTFC					as float)
			, DocumentCurrAmountTransaction				=	case when i.DOCTYPE = 'CN' then -1 else 1 end * try_cast(it.AMTFC					as float)
			, TransactionCount							=	try_cast(1																			as bigint)
			, OriginalVoucher							=	cast(i.DOCNO																		as varchar(150))
			, LineNumber								=	row_number() over (partition by it.IVJOB_SNO order by it.SNO)
			, ChargeLineText							=	cast(it.CHRGDESC																	as varchar(250))	
			, ChargeLineCode							=	cast(it.CHRGCODE																	as varchar(50))	
			--Dimension Business Keys-----------------------------------
			, System_BK									=	cast('TMFF'																			as varchar(50))
			, FinanceSystem_BK							=	cast('ProjectOne'																	as varchar(50))
			, OperationalSystem_BK						=	cast('TMFF'																			as varchar(50))
			, Company_BK								=	cast(s.Company_BK																	as varchar(50))
			, FinancialCompany_BK						=	cast(co.GlobalCompanyCode															as varchar(50))
			, OperationalCompany_BK						=	cast(s.Company_BK																	as varchar(50))
			, BaseCurrency_BK							=	cast(co.CompanyCurrency																as varchar(50))
			, ExchangeRatePeriod_BK						=	try_cast(year(try_cast(cast(i.DOCDATE as varchar) as date)) * 100 + month(try_cast(cast(i.DOCDATE as varchar) as date))	as int)
			, Currency_BK								=	cast(nullif(trim(i.CURRCODE), '')													as varchar(50))
			, TransactionOriginalCurrency_BK			=	cast(it.CURRCODE																	as varchar(50))
			, Department_BK								=	cast(s.Department_BK																as varchar(50))
			, File_BK									=	upper(cast(s.File_BK																as varchar(50)))
			, TurnoverGroup_BK							=	cast(null																			as varchar(50))
			, Item_BK									=	cast(i.BIZTYPE + CHRGCODE															as varchar(100))
			, LedgerAccount_BK							=	cast(null																			as varchar(50))
			, SetOffLedgerAccount_BK					=	cast(null																			as varchar(50))
			, CostCenter_BK								=	cast(null																			as varchar(50))
			, SetOffCostCenter_BK						=	cast(null																			as varchar(50))
			, PaymentTerm_Bk							=	cast(i.CRTERMCODE																	as varchar(100))
			, InvoiceId_BK								=	cast(i.DOCNO																		as varchar(50))
			, InvoiceType_BK							=	cast(i.DOCTYPE																		as varchar(50))
			, GlobalShipmentId_BK						=	s.GlobalShipmentId_BK
			, LocalShipmentId_BK						=	cast(s.LocalShipmentId_BK															as varchar(50))
			, InvoicePaymentTerm_IntervalDay_BK			=	datediff(d,i.DOCDATE,i.DUEDATE)
			, ExchangeRateCalculationMethod_BK			=	cast('PnL'																			as varchar(50))
			, VatReason_BK								=	cast(null																			as varchar(50))
			, CustomerParty_BK							=	cast(upper(trim(s.CustomerParty_BK))												as varchar(8000))
			, DebtorParty_BK							=	cast(upper(trim(i.PARTYID_CUST))													as varchar(8000))
			, ARP_Account_BK							=	cast(upper(trim(i.PARTYID_CUST)) as varchar(50)) + ' | ' + 'Debtor'
			, IsOverdueBoolean_BK						=	cast(null																			as varchar(50))
			, IsSettledBoolean_BK						=	cast(null																			as varchar(50))
			----Date BK's-------------------------------------------------
			, InvoiceDate_BK							=	try_cast(i.DOCDATE																	as date)
			, DueDate_BK								=	try_cast(i.DUEDATE																	as date)
			, PrintDate_BK								=	try_cast(i.PRINTDATE																as date)
			, Date_BK									=	try_cast(i.DOCDATE																	as date)
			, FinancialDate_BK							=	try_cast(i.POSTDATE																	as date)
			, CreateDate_BK								=	try_cast(i.CREATEDATE																as date)
			, Voucher_BK								=	cast(null																			as varchar(50))
			, UniqueRecordKey							=	utilities.ufn_GetHashedUID('TMFF', it.IVHDR_UNID,  it.IVJOB_SNO , it.SNO, s.File_BK)
			, DataAgeHOT								=   it.SCD_UpdateDate
			, DataAgeCOLD								=   (select max(v) from (values (it.SCD_UpdateDate), (i.SCD_UpdateDate), (co.DataAgeCOLD), (s.DataAgeCOLD), (ij.SCD_UpdateDate)) as x(v))
			, RecordChangeDateTime						=	getdate()
from		ODS.TMFF_IVDTL it
join		ODS.TMFF_IVHDR i
on			i.UNID = it.IVHDR_UNID
and			i.VOIDDATE is null
and			i.SCD_ActiveFlag = 1
and			i.SCD_IsDeleted = 0
left join	CALC.TMFF_OwnerIdCompany co
on			i.OWNERID = co.OwnerOwnerId
join		ODS.TMFF_IVJOB ij
on			it.ivhdr_unid = ij.IVHDR_UNID
and			it.IVJOB_SNO = ij.SNO
and			ij.SCD_ActiveFlag  = 1
and			ij.SCD_IsDeleted = 0
join		CALC.TMFF_Shipment s
on			s.LocalShipmentId_BK = it.SOURCEUNID
and			it.SOURCETYPE = 'JB'
where 		it.SCD_ActiveFlag = 1
and			it.SCD_IsDeleted = 0
and			i.STATUS = 'ORIGINAL'
GO
