use SGLBI
GO

create or alter view Reports.v_ShipmentStatus
as

select		  System_BK							= cast('TMFF'														as varchar(50))
			, JOB_UNID								= cast(j.UNID													as varchar(100))
			, ShipmentID							= j.ShipmentID
			, StatusCode							= cast(st.REFNO1												as varchar(50))
			, StatusName							= cast(st.REFNO1												as varchar(200))	--no separate status-description lookup found for ODS.TMFF_JOBINTFEXPDTL.REFNO1; StatusCode/StatusName both taken from the same raw code, same convention used in Reports.v_ContainerStatus
			, StatusDateTime						= st.STATUSDATE
from		(
			select		  UNID
						, OWNERID
						, CREATEDATE
						, ShipmentID	=	cast(coalesce(
													case	when min(shpnoc.clean_SHPNO) over (partition by jsid.GSHPID) <> max(shpnoc.clean_SHPNO) over (partition by jsid.GSHPID)
															then first_value(shpnoc.clean_SHPNO) over (partition by jsid.GSHPID order by case when shpnoc.clean_SHPNO is null then 999 else 1 end asc, jsid.CREATEDATE asc)
														end
												, shpnoc.clean_SHPNO
												, 'TMFF|' + jsid.OWNERID + '|' + cast(jsid.UNID as varchar)
												) as varchar(150))
						, rn			=	ROW_NUMBER() over (partition by coalesce(cast(jsid.SHPNO as varchar(50)), jsid.OWNERID + '|' + cast(jsid.UNID as varchar)) order by jsid.CREATEDATE asc, jsid.UNID asc)
			from		ODS.TMFF_JOB jsid
			join		ODS.TMFF_SYCOMPANY sycw
			on			sycw.OWNERID = jsid.OWNERID
			and			sycw.CTRYCODE = 'US'
			and			sycw.SCD_ActiveFlag = 1
			and			sycw.SCD_IsDeleted = 0
			outer apply	(select CleanRaw = utilities.ufn_GetCleanGlobalShipmentId(jsid.SHPNO)) shpno
			cross apply	(select clean_SHPNO = case when replace(shpno.CleanRaw,'0','') = '' then null else shpno.CleanRaw end) shpnoc
			where		jsid.SCD_ActiveFlag = 1
			and			jsid.SCD_IsDeleted = 0
			and			jsid.VOIDDATE is null
			) j
left join	(
			select		  JOB_UNID
						, REFNO1
						, STATUSDATE
						, rn	=	row_number() over (partition by JOB_UNID order by STATUSDATE desc)
			from		ODS.TMFF_JOBINTFEXPDTL
			where		SCD_ActiveFlag = 1
			and			SCD_IsDeleted = 0
			and			REFNO1 is not null
			) st
on			st.JOB_UNID = j.UNID
and			st.rn = 1
where		j.rn = 1

union all

select		  System_BK							= cast('NORAMOPSDW'												as varchar(50))
			, JOB_UNID								= cast(awb.rowguid_AWB											as varchar(100))
			, ShipmentID							= shid.ShipmentId
			, StatusCode							= cast(null														as varchar(50))		--no confirmed source in OPS per Shipment Status tab (no Entity/EntityField given for either StatusCode or StatusName)
			, StatusName							= cast(null														as varchar(200))	--no confirmed source in OPS per Shipment Status tab
			, StatusDateTime						= cast(null														as datetime)		--no confirmed source in OPS per Shipment Status tab
from		ODS.NORAMOPSDW_tblAWB awb
left join	ODS.NORAMOPSDW_lkpDepartment ld
on			awb.DepartmentID = ld.DepartmentID
and			awb.LinkServer = ld.LinkServer
and			ld.SCD_ActiveFlag = 1
and			ld.SCD_IsDeleted = 0
and			ld.LinkServer = 'TGOPSINTL'
left join	(
			select		  rowguid_AWB					=	am.rowguid_AWB
						, MAWB							=	first_value(m.MAWB)					over(partition by am.rowguid_AWB order by m.LastEdit desc)
						, ix							=	row_number()						over(partition by am.rowguid_AWB order by m.LastEdit desc)
			from		ODS.NORAMOPSDW_tblMAWB m
			join		ODS.NORAMOPSDW_xrfMAWBAWB am
			on			m.rowguid_MAWB = am.rowguid_MAWB
			and			am.SCD_ActiveFlag = 1
			and			am.SCD_IsDeleted = 0
			where		m.SCD_ActiveFlag = 1
			and			m.SCD_IsDeleted = 0
			) maw
on			maw.rowguid_AWB = awb.rowguid_AWB
and			maw.ix = 1
cross apply	(
			select		  HouseNo						=	case	when ld.ImpExp = 'E' then left(awb.HWB,11)
																	when awb.ImportHWBNo is not null then awb.ImportHWBNo
																	when awb.HWB like '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9]%' then left(awb.HWB,11)
																	else awb.HWB
															end
						, MasterNoForGlobalShipment		=	cast(case	when ld.TransportMode_BK <> 'Air' then null
																	when replace(replace(maw.MAWB,'0',''),'-','') = '' then null
																	else nullif(nullif(trim(isnull(maw.MAWB,'')),''),'----') end	as varchar(100))
						, UniqueBookingIdentifier		=	cast('NORAMOPSDW|' + isnull(convert(varchar(16),awb.AWBID),'')	as varchar(100))
			) precalc
cross apply	(
			select		 HouseNoForGlobalShipment	=	case	when len(precalc.HouseNo)<4 then null
															when replace(precalc.HouseNo, '0','') = '' then null
															when precalc.HouseNo not like '%[0-9][0-9][0-9]%' then null
															else precalc.HouseNo
														end
						, MasterNoForGlobalShipment	=	case	when len(precalc.MasterNoForGlobalShipment)<4 then null
															when precalc.MasterNoForGlobalShipment not like '%[0-9][0-9][0-9]%' then null
															else precalc.MasterNoForGlobalShipment
														end
						, UniqueBookingIdentifier	=	precalc.UniqueBookingIdentifier
			) calc
cross apply ( select	ShipmentId					=	cast(utilities.ufn_GetCleanGlobalShipmentId(trim(coalesce(calc.HouseNoForGlobalShipment, calc.MasterNoForGlobalShipment, calc.UniqueBookingIdentifier)))	as varchar(150))
			) shid
where		awb.LinkServer = 'TGOPSINTL'
and			awb.AWBID is not null
and			awb.SCD_ActiveFlag = 1
and			awb.SCD_IsDeleted = 0
GO
