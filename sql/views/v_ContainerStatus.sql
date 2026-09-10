use SGLBI
GO

create or alter view Reports.v_ContainerStatus
as

select		  System_BK
			, ContainerNo
			, JOB_UNID
			, ShipmentID
			, StatusCode
			, StatusName
			, StatusDateTime
from (
		select		  System_BK						= cast('NORAMOPSDW'											as varchar(50))
					, ContainerNo						= piec.ContainerNo
					, JOB_UNID							= cast(awb.rowguid_AWB										as varchar(100))
					, ShipmentID						= shid.ShipmentId
					, StatusCode						= cast(null												as varchar(50))		--no confirmed source in OPS per Container Status tab (no Entity/EntityField given)
					, StatusName						= cast(null												as varchar(200))	--no confirmed source in OPS per Container Status tab
					, StatusDateTime					= cast(null												as datetime)		--no confirmed source in OPS per Container Status tab
					, rn								= row_number() over (partition by piec.ContainerNo, shid.ShipmentId order by awb.EntryDate desc)
		from	ODS.NORAMOPSDW_tblAWB awb
				join (
						select		  rowguid_AWB			=	ap.rowguid_AWB
									, ContainerNo			=	ap.CnrtNo
						from		ODS.NORAMOPSDW_tblAWBPieces ap
						where		ap.SCD_ActiveFlag = 1
						and			ap.SCD_IsDeleted = 0
						and			ap.CnrtNo is not null
						group by	ap.CnrtNo
									, ap.rowguid_AWB
					) piec
		on			piec.rowguid_AWB = awb.rowguid_AWB
		and			awb.LinkServer = 'TGOPSINTL'
		and			awb.AWBID	is not null
		and			awb.SCD_ActiveFlag = 1
		and			awb.SCD_IsDeleted = 0
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
		union all
		select		  System_BK							= cast('TMFF'														as varchar(50))
					, ContainerNo							= c.CONTNO
					, JOB_UNID								= cast(j.UNID													as varchar(100))
					, ShipmentID							= shipID.clean_ShipmentID
					, StatusCode							= cast(c.CONTSTATUS												as varchar(50))
					, StatusName							= cast(c.CONTSTATUS												as varchar(200))	--Container Status tab maps StatusName to the same source field as StatusCode (CONTAINER.CONTSTATUS); no separate description lookup confirmed
					, StatusDateTime						= cast(null													as datetime)		--no confirmed source per Container Status tab
					, rn									= row_number() over (partition by c.CONTNO, shipID.clean_ShipmentID order by j.CreateDate desc)
		from		ODS.TMFF_CONTAINER  c
		join		ODS.TMFF_SYCOMPANY sycw
		on			sycw.OWNERID = c.OWNERID
		and			sycw.CTRYCODE = 'US'
		and			sycw.SCD_ActiveFlag = 1
		and			sycw.SCD_IsDeleted = 0
		join		ODS.TMFF_JOB j
		on			c.JOB_UNID = j.UNID
		and			j.SCD_ActiveFlag = 1
		and			j.SCD_IsDeleted = 0
		outer apply	(select CleanRaw				= utilities.ufn_GetCleanGlobalShipmentId(j.SHPNO)) shpno
		cross apply	(select clean_SHPNO				= case when replace(shpno.CleanRaw,'0','') = '' then null else shpno.CleanRaw end) shpnoc
		cross apply (select clean_ShipmentID		= cast(coalesce(
														case	when min(shpnoc.clean_SHPNO) over (partition by j.GSHPID) <> max(shpnoc.clean_SHPNO) over (partition by j.GSHPID)
																then first_value(shpnoc.clean_SHPNO) over (partition by j.GSHPID order by case when shpnoc.clean_SHPNO is null then 999 else 1 end asc, j.CREATEDATE asc)
														end
														, shpnoc.clean_SHPNO
														, 'TMFF|' + j.OWNERID + '|' + cast(j.UNID as varchar)
														) as varchar(150))) shipID
		where 		c.SCD_ActiveFlag = 1
		and			c.SCD_IsDeleted = 0
		and			CONTNO is not null
) t
where		rn = 1
GO
