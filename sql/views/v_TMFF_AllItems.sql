use SGLBI
GO



--COBI-7494 --Objective SEACONTITEM fix
--Prevtask=COBI-7445 , hash=419123951
--exec utilities.usp_ConvertViewToLoadComplex 'CALC','v_TMFF_AllItems'
--select * from utilities.vCheckDefinitionSyncronization_ext where ObjectName = 'v_TMFF_AllItems'
create or alter view [CALC].[v_TMFF_AllItems]
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
