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
select		  JOB_UNID					=	cast(lvl1.JOB_UNID												as varchar(50))
			, System_BK					=	cast('TMFF'														as varchar(50))
			, ShipmentID				=	cast(lvl1.GSHPID												as varchar(50))
			, ChargeType				=	cast(lvl1.ChargeType											as varchar(10))
			, ChargeCode				=	cast(string_agg(cast(lvl1.CHRGCODE					as varchar(max)), ', ')	as varchar(100))
			, ChargeCodeDescription		=	cast(string_agg(cast(lvl1.CHRGDESC					as varchar(max)), ', ')	as varchar(500))
			, ChargeCodeCategory		=	cast(string_agg(cast(lvl1.CategoryDescription		as varchar(max)), ', ')	as varchar(500))
			, CurrencyCode				=	cast(lvl1.CURRCODE												as varchar(50))
			, AmountFC					=	sum(lvl1.AmountFC)
			, AmountLC					=	sum(lvl1.AmountLC)
			, ActualAmountFC			=	sum(lvl1.ActualAmountFC)
			, ActualAmountLC			=	sum(lvl1.ActualAmountLC)
			, RecognitionAmountFC		=	sum(lvl1.RecognitionAmountFC)
			, RecognitionAmountLC		=	sum(lvl1.RecognitionAmountLC)
			, VATAmountFC				=	sum(lvl1.VATAmountFC)
			, VATAmountLC				=	sum(lvl1.VATAmountLC)
			, VATActualAmountFC			=	sum(lvl1.VATActualAmountFC)
			, VATActualAmountLC			=	sum(lvl1.VATActualAmountLC)
			, CreditorCode				=	cast(case when lvl1.ChargeType = 'COST' then lvl1.PARTYID end		as varchar(50))
			, CreditorName				=	cast(case when lvl1.ChargeType = 'COST' then lvl1.FULLNAME end	as varchar(150))
			, DebtorCode				=	cast(case when lvl1.ChargeType = 'REVENUE' then lvl1.PARTYID end	as varchar(50))
			, DebtorName				=	cast(case when lvl1.ChargeType = 'REVENUE' then lvl1.FULLNAME end	as varchar(150))
			, VendorType				=	cast(null														as varchar(50))
from		(
			select		  j.JOB_UNID
						, j.GSHPID
						, j.ChargeType
						, j.CHRGCODE
						, CHRGDESC				=	fmcc.CHRGDESC
						, CategoryDescription	=	fmc.[DESCRIPTION]
						, j.CURRCODE
						, party.PARTYID
						, party.FULLNAME
						, AmountFC				=	sum(try_cast(j.AmountFC								as float))
						, AmountLC				=	sum(try_cast(j.AmountLC								as float))
						, ActualAmountFC		=	sum(try_cast(j.ActualAmountFC							as float))
						, ActualAmountLC		=	sum(try_cast(j.ActualAmountLC							as float))
						, RecognitionAmountFC	=	sum(try_cast(j.RecognitionAmountFC						as float))
						, RecognitionAmountLC	=	sum(try_cast(j.RecognitionAmountLC						as float))
						, VATAmountFC			=	sum(cast(j.VATAmountFC									as float))
						, VATAmountLC			=	sum(cast(j.VATAmountLC									as float))
						, VATActualAmountFC		=	sum(try_cast(j.VATActualAmountFC						as float))
						, VATActualAmountLC		=	sum(try_cast(j.VATActualAmountLC						as float))
			from		(
						select		  jsid.GSHPID
									, src.SNO
									, src.ChargeType
									, src.CHRGCODE
									, src.AmountFC
									, src.AmountLC
									, src.ActualAmountFC
									, src.ActualAmountLC
									, src.VATActualAmountFC
									, src.VATActualAmountLC
									, src.VATAmountFC
									, src.VATAmountLC
									, src.RecognitionAmountFC
									, src.RecognitionAmountLC
									, src.CURRCODE
									, src.ACTUALCURRCODE
									, src.PartyId
									, jsid.BIZTYPE
									, JOB_UNID				=	jsid.UNID
						from		(
									select		  JOB_UNID				=	r.JOB_UNID
												, SNO					=	r.SNO
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
												, ACTUALCURRCODE		=	r.ACTUALCURRCODE
												, PartyId				=	r.BILLING_PARTYID
									from		ODS.TMFF_REVENUE r
									where		r.SCD_ActiveFlag = 1
									and			r.SCD_IsDeleted = 0
									and			isnull(r.INVSTS, '') not in ('C', 'V')
									union all
									select		  JOB_UNID				=	c.JOB_UNID
												, SNO					=	c.SNO
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
												, ACTUALCURRCODE		=	c.ACTUALCURRCODE
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
			left join	ODS.TMFF_FMCHARGECODE fmcc
			on			fmcc.CHRGCODE = j.CHRGCODE
			and			fmcc.BIZTYPE = j.BIZTYPE
			and			fmcc.SCHEMECODE = '*'
			left join	ODS.TMFF_FMCODE fmc
			on			fmc.CODE = fmcc.CATEGORYSVR
			and			fmc.[TYPE] = 'CCT'
			group by	  j.JOB_UNID
						, j.GSHPID
						, j.ChargeType
						, j.CHRGCODE
						, fmcc.CHRGDESC
						, fmc.[DESCRIPTION]
						, j.CURRCODE
						, party.PARTYID
						, party.FULLNAME
			) lvl1
group by	  lvl1.JOB_UNID
			, lvl1.GSHPID
			, lvl1.ChargeType
			, lvl1.CURRCODE
			, cast(case when lvl1.ChargeType = 'COST' then lvl1.PARTYID end		as varchar(50))
			, cast(case when lvl1.ChargeType = 'COST' then lvl1.FULLNAME end	as varchar(150))
			, cast(case when lvl1.ChargeType = 'REVENUE' then lvl1.PARTYID end	as varchar(50))
			, cast(case when lvl1.ChargeType = 'REVENUE' then lvl1.FULLNAME end	as varchar(150))



union all


select		  JOB_UNID					=	cast(lvl1.rowguid_AWB											as varchar(50))
			, System_BK					=	cast('OPS'														as varchar(50))
			, ShipmentID				=	cast(left(lvl1.HWB, 11)										as varchar(50))
			, ChargeType				=	cast(lvl1.ChargeType											as varchar(10))
			, ChargeCode				=	cast(string_agg(cast(lvl1.ChrgCode			as varchar(max)), ', ')		as varchar(500))
			, ChargeCodeDescription		=	cast(string_agg(cast(lvl1.ChrgDesc			as varchar(max)), ', ')		as varchar(500))
			, ChargeCodeCategory		=	cast(string_agg(cast(lvl1.ReportsCategory	as varchar(max)), ', ')		as varchar(500))
			, CurrencyCode				=	cast(lvl1.CurrencyCode											as varchar(50))
			, AmountFC					=	sum(lvl1.AmountFC)
			, AmountLC					=	sum(lvl1.AmountLC)
			, ActualAmountFC			=	cast(null														as float)
			, ActualAmountLC			=	cast(null														as float)
			, RecognitionAmountFC		=	cast(null														as float)
			, RecognitionAmountLC		=	cast(null														as float)
			, VATAmountFC				=	cast(null														as float)
			, VATAmountLC				=	sum(lvl1.VATAmountLC)
			, VATActualAmountFC			=	cast(null														as float)
			, VATActualAmountLC			=	cast(null														as float)
			, CreditorCode				=	cast(case when lvl1.ChargeType = 'COST' then lvl1.AccountNo end	as varchar(50))
			, CreditorName				=	cast(case when lvl1.ChargeType = 'COST' then lvl1.NameFull end	as varchar(150))
			, DebtorCode				=	cast(case when lvl1.ChargeType = 'REVENUE' then lvl1.CustNo end	as varchar(50))
			, DebtorName				=	cast(case when lvl1.ChargeType = 'REVENUE' then lvl1.CustName end	as varchar(150))
			, VendorType				=	cast(null														as varchar(50))
from		(
			select		  a.rowguid_AWB
						, a.HWB
						, a.ChargeType
						, a.ChrgCode
						, a.ChrgDesc
						, cc.ReportsCategory
						, CurrencyCode		=	coalesce(cur.CurrencyType, 'USD')
						, pty.AccountNo
						, pty.NameFull
						, cust.CustNo
						, cust.CustName
						, AmountFC			=	sum(try_cast(coalesce(a.ForeignAmt, a.Amount)					as float))
						, AmountLC			=	sum(try_cast(a.Amount											as float))
						, VATAmountLC		=	sum(try_cast(case when a.ChargeType = 'REVENUE' then a.TaxAndDutyAmountTransaction_BI end	as float))
			from		(
						select		  rowguid_AWB						=	d.rowguid_AWB
									, a.HWB
									, ChargeType						=	cast('REVENUE' as varchar(10))
									, ChrgCode							=	d.ChrgCode
									, ChrgDesc							=	d.ChrgDesc
									, Amount							=	cast(d.Amount as money)
									, ForeignAmt						=	cast(d.ForeignAmt as money)
									, TaxAndDutyAmountTransaction_BI	=	d.TaxAndDutyAmountTransaction_BI
									, rowguid_Currency					=	d.rowguid_Currency
									, rowguid_Vendor					=	cast(null as uniqueidentifier)
									, rowguid_AWBInvoice				=	d.rowguid_AWBInvoice
						from		ODS.NORAMOPSDW_tblAWBInvoiceDetail d
						join		ODS.NORAMOPSDW_tblAWB a
						on			a.rowguid_AWB = d.rowguid_AWB
						and			a.SCD_ActiveFlag = 1
						and			a.SCD_IsDeleted = 0
						and			a.LinkServer = 'TGOPSINTL'
						where		d.SCD_ActiveFlag = 1
						and			d.SCD_IsDeleted = 0

						union all

						select		  rowguid_AWB						=	c.rowguid_AWB
									, a.HWB
									, ChargeType						=	cast('COST' as varchar(10))
									, ChrgCode							=	cast(c.ChrgCode as varchar(100))
									, ChrgDesc							=	cast(c.ChrgDesc as varchar(500))
									, Amount							=	cast(c.Amount as money)
									, ForeignAmt						=	cast(c.ForeignAmt as money)
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
						where		c.SCD_ActiveFlag = 1
						and			c.SCD_IsDeleted = 0
						) a
			left join	ODS.NORAMOPSDW_lkpChargeCode cc
			on			cc.ChrgCode = a.ChrgCode
			and			cc.LinkServer = 'TGOPSINTL'
			left join	ODS.NORAMOPSDW_lkpCurrency cur
			on			cur.rowguid_Currency = a.rowguid_Currency
			and			cur.LinkServer = 'TGOPSINTL'
			left join	ODS.NORAMOPSDW_tblAWBInvoice ai
			on			ai.rowguid_AWBInvoice = a.rowguid_AWBInvoice
			and			ai.SCD_ActiveFlag = 1
			and			ai.SCD_IsDeleted = 0
			left join	ODS.NORAMOPSDW_tblCustomer cust
			on			cust.rowguid_Customer = ai.rowguid_Customer
			and			cust.SCD_ActiveFlag = 1
			and			cust.SCD_IsDeleted = 0
			left join	ODS.NORAMOPSDW_tblShipmentParty sp
			on			sp.RowID = a.rowguid_Vendor
			and			sp.SCD_ActiveFlag = 1
			and			sp.SCD_IsDeleted = 0
			left join	CALC.v_NORAMOPSDW_Party pty
			on			pty.OriginalParty_BK = sp.Party_BK
			group by	  a.rowguid_AWB
						, a.HWB
						, a.ChargeType
						, a.ChrgCode
						, a.ChrgDesc
						, cc.ReportsCategory
						, coalesce(cur.CurrencyType, 'USD')
						, pty.AccountNo
						, pty.NameFull
						, cust.CustNo
						, cust.CustName
			) lvl1
group by	  lvl1.rowguid_AWB
			, lvl1.HWB
			, lvl1.ChargeType
			, lvl1.CurrencyCode
			, cast(case when lvl1.ChargeType = 'COST' then lvl1.AccountNo end		as varchar(50))
			, cast(case when lvl1.ChargeType = 'COST' then lvl1.NameFull end		as varchar(150))
			, cast(case when lvl1.ChargeType = 'REVENUE' then lvl1.CustNo end	as varchar(50))
			, cast(case when lvl1.ChargeType = 'REVENUE' then lvl1.CustName end	as varchar(150))
GO
