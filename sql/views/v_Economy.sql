USE [SGLBI]
GO

/****** Object:  View [Reports].[v_Economy] ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



--COBI-XXXX --Objective New object (P&L fact: one row per Job/Shipment + ChargeType)
--prevtask , hash =
--exec utilities.usp_ConvertViewToLoadComplex 'Reports','v_Economy'
CREATE view [Reports].[v_Economy]
as
select		  JOB_UNID					=	cast(j.JOB_UNID													as varchar(50))
			, System_BK					=	cast('TMFF'														as varchar(50))
			, ShipmentID				=	cast(j.GSHPID													as varchar(50))
			, ChargeType				=	cast(j.ChargeType												as varchar(10))
			, ChargeCode				=	cast(string_agg(cast(j.CHRGCODE				as varchar(max))	, ', ')	as varchar(100))
			, ChargeCodeDescription		=	cast(string_agg(cast(ChargeCodeDescription	as varchar(max))	, ', ')	as varchar(500))
			, ChargeCodeCategory		=	cast(string_agg(cast(ChargeCodeCategory		as varchar(max))	, ', ')	as varchar(500))
			, CurrencyCode				=	cast(j.CURRCODE													as varchar(50))
			, AmountFC					=	sum(try_cast(j.AmountFC											as float))
			, AmountLC					=	sum(try_cast(j.AmountLC											as float))
			, ActualAmountFC			=	sum(try_cast(j.ActualAmountFC									as float))
			, ActualAmountLC			=	sum(try_cast(j.ActualAmountLC									as float))
			, RecognitionAmountFC		=	sum(try_cast(RecognitionAmountFC								as float))
			, RecognitionAmountLC		=	sum(try_cast(j.RecognitionAmountLC								as float))
			, VATAmountFC				=	sum(cast(VATAmountFC											as float))
			, VATAmountLC				=	sum(cast(VATAmountLC											as float))
			, VATActualAmountFC			=	sum(try_cast(j.VATActualAmountFC								as float))
			, VATActualAmountLC			=	sum(try_cast(j.VATActualAmountLC								as float))
			, CreditorCode				=	cast(case when j.ChargeType = 'COST' then party.PARTYID end		as varchar(50))
			, CreditorName				=	cast(case when j.ChargeType = 'COST' then party.FULLNAME end	as varchar(150))
			, DebtorCode				=	cast(case when j.ChargeType = 'REVENUE' then party.PARTYID end	as varchar(50))
			, DebtorName				=	cast(case when j.ChargeType = 'REVENUE' then party.FULLNAME end	as varchar(150))
			, VendorType				=	cast(null														as varchar(50))
from		(
			select		  jsid.GSHPID
						, src.ChargeType
						, src.CHRGCODE
						, ChargeCodeDescription	=	fmcc.CHRGDESC
						, ChargeCodeCategory	=	fmc.[DESCRIPTION]
						, AmountFC				=	sum(src.AmountFC)
						, AmountLC				=	sum(src.AmountLC)
						, ActualAmountFC		=	sum(src.ActualAmountFC)
						, ActualAmountLC		=	sum(src.ActualAmountLC)
						, VATActualAmountFC		=	sum(src.VATActualAmountFC)
						, VATActualAmountLC		=	sum(src.VATActualAmountLC)
						, VATAmountFC			=	sum(src.VATAmountFC)
						, VATAmountLC			=	sum(src.VATAmountLC)
						, RecognitionAmountFC	=	sum(src.RecognitionAmountFC)
						, RecognitionAmountLC	=	sum(src.RecognitionAmountLC)
						, CURRCODE				=	src.CURRCODE
						, src.PartyId
						, src.JOB_UNID
			from		(
						select		  JOB_UNID				=	r.JOB_UNID
									, ChargeType			=	cast('REVENUE' as varchar(10))
									, CHRGCODE				=	r.CHRGCODE
									, AmountFC				=	r.AMTFC
									, AmountLC				=	r.AMTLC
									, ActualAmountFC		=	r.ACTUALAMTBC
									, ActualAmountLC		=	r.ACTUALAMTLC
									, VATActualAmountFC		=	r.ACTUALVATAMTBC
									, VATActualAmountLC		=	r.ACTUALVATAMTLC
									, VATAmountFC			=	r.ACTUALVATAMTBC
									, VATAmountLC			=	r.VATAMTLC --VATAMT
									, RecognitionAmountFC	=	try_cast(r.RECOGNITIONAMTLC * (r.AMTFC / nullif(r.AMTLC, 0))	as float)
									, RecognitionAmountLC	=	r.RECOGNITIONAMTLC
									, CURRCODE				=	r.CURRCODE
									, PartyId				=	r.BILLING_PARTYID
						from		ODS.TMFF_REVENUE r
						where		r.SCD_ActiveFlag = 1
						and			r.SCD_IsDeleted = 0
						and			isnull(r.INVSTS, '') not in ('C', 'V')
						union all
						select		  JOB_UNID				=	c.JOB_UNID
									, ChargeType			=	cast('COST' as varchar(10))
									, CHRGCODE				=	c.CHRGCODE
									, AmountFC				=	c.AMTFC
									, AmountLC				=	c.AMTLC
									, ActualAmountFC		=	c.ACTUALAMTBC
									, ActualAmountLC		=	c.ACTUALAMTLC
									, VATActualAmountFC		=	c.ACTUALVATAMTBC
									, VATActualAmountLC		=	c.ACTUALVATAMTLC
									, VATAmountFC			=	c.ACTUALVATAMTBC
									, VATAmountLC			=	c.VATAMTLC
									, RecognitionAmountFC	=	try_cast(c.RECOGNITIONAMTLC * (c.AMTFC / nullif(c.AMTLC, 0))	as float)
									, RecognitionAmountLC	=	c.RECOGNITIONAMTLC
									, CURRCODE				=	c.CURRCODE
									, PartyId				=	c.PAYEE_PARTYID
						from		ODS.TMFF_COST c
						where		c.SCD_ActiveFlag = 1
						and			c.SCD_IsDeleted = 0
						and			isnull(c.INVSTS, '') not in ('C', 'V')
						) src
			join		ODS.TMFF_JOB jsid
			on			jsid.UNID = src.JOB_UNID
			and			jsid.SCD_ActiveFlag = 1
			and			jsid.SCD_IsDeleted = 0
			join		ODS.TMFF_SYCOMPANY sycw
			on			sycw.OWNERID = jsid.OWNERID
			and			sycw.CTRYCODE = 'US'
			left join	ODS.TMFF_FMCHARGECODE fmcc
			on			fmcc.CHRGCODE = src.CHRGCODE
			and			fmcc.BIZTYPE = jsid.BIZTYPE
			and			fmcc.SCHEMECODE = '*'
			left join	ODS.TMFF_FMCODE fmc
			on			fmc.CODE = fmcc.CATEGORYSVR
			and			fmc.[TYPE] = 'CCT'
			group by	  jsid.GSHPID
						, src.ChargeType
						, src.CHRGCODE
						, fmcc.CHRGDESC
						, fmc.[DESCRIPTION]
						, src.CURRCODE
						, src.PartyId
						, src.JOB_UNID
			) j
left join	(
			select		*
			from		(
						select		  PARTYID
									, FULLNAME
									, rn	=	row_number() over (partition by PARTYID order by SCD_UpdateDate desc)
						from		ODS.TMFF_FMPARTY
						where		SCD_ActiveFlag = 1
						and			SCD_IsDeleted = 0
						) x
			where		rn = 1
			) party
on			party.PARTYID = j.PartyId
group by	  j.JOB_UNID
			, j.GSHPID
			, j.ChargeType
			, j.CURRCODE
			, cast(case when j.ChargeType = 'COST' then party.PARTYID end		as varchar(50))
			, cast(case when j.ChargeType = 'COST' then party.FULLNAME end	as varchar(150))
			, cast(case when j.ChargeType = 'REVENUE' then party.PARTYID end	as varchar(50))
			, cast(case when j.ChargeType = 'REVENUE' then party.FULLNAME end	as varchar(150))



union all


select		  JOB_UNID					=	cast(a.rowguid_AWB												as varchar(50))
			, System_BK					=	cast('OPS'														as varchar(50))
			, ShipmentID				=	cast(left(a.HWB, 11)											as varchar(50))
			, ChargeType				=	cast(a.ChargeType												as varchar(10))
			, ChargeCode				=	cast(string_agg(cast(a.ChrgCode	as varchar(max))	, ', ')			as varchar(100))
			, ChargeCodeDescription		=	cast(string_agg(cast(a.ChrgDesc	as varchar(max))	, ', ')			as varchar(500))
			, ChargeCodeCategory		=	cast(string_agg(cast(a.ChargeCodeCategory	as varchar(max))	, ', ')	as varchar(500))
			, CurrencyCode				=	cast(coalesce(cur.CurrencyType, 'USD')							as varchar(50))
			, AmountFC					=	sum(try_cast(coalesce(a.ForeignAmt, a.Amount)					as float))
			, AmountLC					=	sum(try_cast(a.Amount											as float))
			, ActualAmountFC			=	cast(null														as float)
			, ActualAmountLC			=	cast(null														as float)
			, RecognitionAmountFC		=	cast(null														as float)
			, RecognitionAmountLC		=	cast(null														as float)
			, VATAmountFC				=	cast(null														as float)
			, VATAmountLC				=	sum(try_cast(case when a.ChargeType = 'REVENUE' then a.TaxAndDutyAmountTransaction_BI end	as float))
			, VATActualAmountFC			=	cast(null														as float)
			, VATActualAmountLC			=	cast(null														as float)
			, CreditorCode				=	cast(case when a.ChargeType = 'COST' then pty.AccountNo end	as varchar(50))
			, CreditorName				=	cast(case when a.ChargeType = 'COST' then pty.NameFull end	as varchar(150))
			, DebtorCode				=	cast(case when a.ChargeType = 'REVENUE' then cust.CustNo end	as varchar(50))
			, DebtorName				=	cast(case when a.ChargeType = 'REVENUE' then cust.CustName end	as varchar(150))
			, VendorType				=	cast(null														as varchar(50))
from		(
			select		  rowguid_AWB						=	d.rowguid_AWB
						, a.HWB
						, ChargeType						=	cast('REVENUE' as varchar(10))
						, ChrgCode							=	d.ChrgCode
						, ChrgDesc							=	d.ChrgDesc
						, ChargeCodeCategory				=	cc.ReportsCategory
						, Amount							=	sum(cast(d.Amount as money))
						, ForeignAmt						=	sum(cast(d.ForeignAmt as money))
						, TaxAndDutyAmountTransaction_BI	=	sum(d.TaxAndDutyAmountTransaction_BI)
						, rowguid_Currency					=	d.rowguid_Currency
						, rowguid_Vendor					=	cast(null as uniqueidentifier)
						, rowguid_AWBInvoice				=	d.rowguid_AWBInvoice
			from		ODS.NORAMOPSDW_tblAWBInvoiceDetail d
			join		ODS.NORAMOPSDW_tblAWB a
			on			a.rowguid_AWB = d.rowguid_AWB
			and			a.SCD_ActiveFlag = 1
			and			a.SCD_IsDeleted = 0
			and			a.LinkServer = 'TGOPSINTL'
			left join	ODS.NORAMOPSDW_lkpChargeCode cc
			on			cc.ChrgCode = d.ChrgCode
			and			cc.LinkServer = 'TGOPSINTL'
			where		d.SCD_ActiveFlag = 1
			and			d.SCD_IsDeleted = 0
			group by	  d.rowguid_AWB
						, a.HWB
						, d.ChrgCode
						, d.ChrgDesc
						, cc.ReportsCategory
						, d.rowguid_Currency
						, d.rowguid_AWBInvoice

			union all

			select		  rowguid_AWB						=	c.rowguid_AWB
						, a.HWB
						, ChargeType						=	cast('COST' as varchar(10))
						, ChrgCode							=	c.ChrgCode
						, ChrgDesc							=	c.ChrgDesc
						, ChargeCodeCategory				=	cc.ReportsCategory
						, Amount							=	sum(cast(c.Amount as money))
						, ForeignAmt						=	sum(cast(c.ForeignAmt as money))
						, TaxAndDutyAmountTransaction_BI	=	cast(null as money)
						, rowguid_Currency					=	c.rowguid_Currency
						, rowguid_Vendor					=	c.rowguid_Vendor
						, rowguid_AWBInvoice				=	cast(null as uniqueidentifier)
			from		ODS.NORAMOPSDW_tblAWBCost c
			join		ODS.NORAMOPSDW_tblAWB a
			on			a.rowguid_AWB = c.rowguid_AWB
			and			a.SCD_ActiveFlag = 1
			and			a.SCD_IsDeleted = 0
			and			a.LinkServer = 'TGOPSINTL'
			left join	ODS.NORAMOPSDW_lkpChargeCode cc
			on			cc.ChrgCode = c.ChrgCode
			and			cc.LinkServer = 'TGOPSINTL'
			where		c.SCD_ActiveFlag = 1
			and			c.SCD_IsDeleted = 0
			group by	  c.rowguid_AWB
						, a.HWB
						, c.ChrgCode
						, c.ChrgDesc
						, cc.ReportsCategory
						, c.rowguid_Currency
						, c.rowguid_Vendor
			) a
left join	ODS.NORAMOPSDW_lkpCurrency cur
on			cur.rowguid_Currency = a.rowguid_Currency
and			cur.LinkServer = 'TGOPSINTL'
left join	ODS.NORAMOPSDW_tblAWBInvoice ai		--resolves rowguid_AWBInvoice to the customer's rowguid; no SCD filter here since this specific historical invoice row may since have been superseded (matches InvoiceDetails.sql's ivh join)
on			ai.rowguid_AWBInvoice = a.rowguid_AWBInvoice
left join	ODS.NORAMOPSDW_tblCustomer cust
on			cust.rowguid_Customer = ai.rowguid_Customer
and			cust.SCD_ActiveFlag = 1
and			cust.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblShipmentParty sp		--resolves rowguid_Vendor to the vendor's business key (Party_BK); no SCD filter here since this specific historical row may since have been superseded
on			sp.RowID = a.rowguid_Vendor
left join	(
			select		*
			from		(
						select		  Party_BK
									, AccountNo
									, NameFull
									, rn	=	row_number() over (partition by Party_BK order by SCD_UpdateDate desc)
						from		ODS.NORAMOPSDW_tblShipmentParty
						where		SCD_ActiveFlag = 1
						and			SCD_IsDeleted = 0
						) x
			where		rn = 1
			) pty								--re-resolves that business key to its current (latest active) version, in case sp itself is stale
on			pty.Party_BK = sp.Party_BK
group by	  a.rowguid_AWB
			, left(a.HWB, 11)
			, a.ChargeType
			, coalesce(cur.CurrencyType, 'USD')
			, case when a.ChargeType = 'COST' then pty.AccountNo end
			, case when a.ChargeType = 'COST' then pty.NameFull end
			, case when a.ChargeType = 'REVENUE' then cust.CustNo end
			, case when a.ChargeType = 'REVENUE' then cust.CustName end
GO
