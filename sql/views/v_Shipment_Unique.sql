USE [SGLBI]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =====================================================================================================
-- View:    Reports.v_Shipment_Unique
-- Purpose: 1 row = 1 unique shipment, deduplicated from Reports.v_Shipment (which is 1 row per
--          JOB/AWB) by House number. Per business decision: dedup happens separately within each
--          source system (TMFF House = SHPNO, OPS House = HWB) - a TMFF SHPNO and an OPS HWB that
--          happen to share the same text are NOT treated as the same shipment, since they're two
--          unrelated numbering schemes. When several JOB/AWB rows share the same House within a
--          system, the one with the earliest CreateDate wins (JOB_UNID as a deterministic tie-break
--          for same-timestamp rows) and ALL of its columns are carried through as-is - this is a
--          representative-row pick, not an aggregation of Weight/Volume/Pieces/etc. across the group.
--
-- Rows with a NULL House are never collapsed into each other: the partition key falls back to
-- JOB_UNID (always unique) for those rows, so each one stays its own "shipment" instead of every
-- NULL-House row being treated as one giant duplicate group.
-- =====================================================================================================
create view [Reports].[v_Shipment_Unique]
as
select		JOB_UNID, System_BK, Branch, CarrierCode, CarrierName, ChargeableWeight, ClosingDate
			, ConsigneeID, ConsigneeName, ConsigneeAddress1, ConsigneeAddress2, ConsigneeAddress3, ConsigneeAddress4
			, ConsigneeCity, ConsigneeState, ConsigneePostalCode, ConsigneeCountryCode
			, CreateDate
			, CustomerID, CustomerName, CustomerCode, CustomerContact, CustomerPhone
			, CustomerAddress1, CustomerAddress2, CustomerAddress3, CustomerAddress4
			, CustomerCity, CustomerState, CustomerPostalCode, CustomerCountryCode
			, DeliveryLocationCode, Department, FinalDestinationLocationCode, FinalDestinationDate
			, FlightNumber, FreightDescription, House, JobNo, Master, ModeOfTransport, Pieces
			, POD, PODETADate, POL, POLETDDate, POR, PORETDDate
			, ServiceLevel, ServiceType, ShipmentID
			, ShipperID, ShipperName, ShipperAddress1, ShipperAddress2, ShipperAddress3, ShipperAddress4
			, ShipperCity, ShipperState, ShipperPostalCode, ShipperCountryCode
			, TEU, TSP, VesselName, VIA, Volume, VoyageNo, Weight, Weight_UT
			, UniqueRecordKey, DataAgeHOT, DataAgeCOLD, RecordChangeDateTime
from		(
			select		  *
						, rn	=	row_number() over (
											partition by	System_BK, coalesce(House, JOB_UNID)
											order by		CreateDate asc, JOB_UNID asc
										)
			from		Reports.v_Shipment
			) x
where		rn = 1
GO
