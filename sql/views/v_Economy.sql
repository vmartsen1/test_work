USE [SGLBI]
GO

/****** Object:  View [Reports].[v_Economy] ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



--COBI-XXXX --Objective New object (P&L / charge-line fact: one row per revenue or cost line)
--prevtask , hash =
--exec utilities.usp_ConvertViewToLoadComplex 'Reports','v_Economy'
CREATE view [Reports].[v_Economy]
as
select		  JOB_UNID					=	cast(j.JOB_UNID													as varchar(50))
			, System_BK					=	cast('TMFF'														as varchar(50))
			, ShipmentID				=	cast(j.GSHPID													as varchar(50))
			, ChargeType				=	cast(j.ChargeType												as varchar(10))
			, ChargeCode				=	cast(j.CHRGCODE													as varchar(50))
			, ChargeCodeDescription		=	cast(fmcc.CHRGDESC												as varchar(100))	--canonical lookup description, not the line's own inline copy (per InvoiceDetails.sql)
			, ChargeCodeCategory		=	cast(fmc.[DESCRIPTION]											as varchar(100))
			, CurrencyCode				=	cast(j.CURRCODE													as varchar(50))
			, AmountFC					=	try_cast(j.AMTFC												as float)
			, AmountLC					=	try_cast(j.AMTLC												as float)
			, ActualAmountFC			=	try_cast(j.ACTUALAMTBC											as float)
			, ActualAmountLC			=	try_cast(j.ACTUALAMTLC											as float)
			, RecognitionAmountFC		=	try_cast(j.RECOGNITIONAMTLC * (j.AMTFC / nullif(j.AMTLC, 0))	as float)
			, RecognitionAmountLC		=	try_cast(j.RECOGNITIONAMTLC										as float)
			, VATAmountFC				=	cast(null														as float)	--no confirmed source column on TMFF_REVENUE/TMFF_COST
			, VATAmountLC				=	cast(null														as float)	--no confirmed "booked" (non-actual) VAT column on TMFF_REVENUE/TMFF_COST
			, VATActualAmountFC			=	cast(null														as float)	--no confirmed source column on TMFF_REVENUE/TMFF_COST
			, VATActualAmountLC			=	try_cast(j.ACTUALVATAMTLC										as float)
			, CreditorCode				=	cast(case when j.ChargeType = 'COST' then party.PARTYID end	as varchar(50))
			, CreditorName				=	cast(case when j.ChargeType = 'COST' then party.FULLNAME end	as varchar(150))
			, DebtorCode				=	cast(case when j.ChargeType = 'REVENUE' then party.PARTYID end	as varchar(50))
			, DebtorName				=	cast(case when j.ChargeType = 'REVENUE' then party.FULLNAME end	as varchar(150))
			, VendorType				=	cast(null														as varchar(50))	--no confirmed source column for TMFF or OPS
from		(
			select		  jsid.UNID
						, jsid.GSHPID
						, src.SNO
						, src.ChargeType
						, src.CHRGCODE
						, src.AMTFC
						, src.AMTLC
						, src.ACTUALAMTBC
						, src.ACTUALAMTLC
						, src.ACTUALVATAMTLC
						, src.CURRCODE
						, src.ACTUALCURRCODE
						, src.RECOGNITIONAMTLC
						, src.PartyId
						, jsid.BIZTYPE
						, JOB_UNID				=	jsid.UNID
			from		(
						select		  JOB_UNID			=	r.JOB_UNID
									, SNO				=	r.SNO
									, ChargeType		=	cast('REVENUE' as varchar(10))
									, CHRGCODE			=	r.CHRGCODE
									, AMTFC				=	r.AMTFC
									, AMTLC				=	r.AMTLC
									, ACTUALAMTBC		=	r.ACTUALAMTBC
									, ACTUALAMTLC		=	r.ACTUALAMTLC
									, ACTUALVATAMTLC	=	r.ACTUALVATAMTLC
									, CURRCODE			=	r.CURRCODE
									, ACTUALCURRCODE	=	r.ACTUALCURRCODE
									, RECOGNITIONAMTLC	=	r.RECOGNITIONAMTLC
									, PartyId			=	r.BILLING_PARTYID
						from		ODS.TMFF_REVENUE r
						where		r.SCD_ActiveFlag = 1
						and			r.SCD_IsDeleted = 0
						and			isnull(r.INVSTS, '') not in ('C', 'V')	--exclude voided/credited lines, replaced by new charge lines (per CALC.v_TMFF_RecognitionEvents convention)
						union all
						select		  JOB_UNID			=	c.JOB_UNID
									, SNO				=	c.SNO
									, ChargeType		=	cast('COST' as varchar(10))
									, CHRGCODE			=	c.CHRGCODE
									, AMTFC				=	c.AMTFC
									, AMTLC				=	c.AMTLC
									, ACTUALAMTBC		=	c.ACTUALAMTBC
									, ACTUALAMTLC		=	c.ACTUALAMTLC
									, ACTUALVATAMTLC	=	c.ACTUALVATAMTLC
									, CURRCODE			=	c.CURRCODE
									, ACTUALCURRCODE	=	c.ACTUALCURRCODE
									, RECOGNITIONAMTLC	=	c.RECOGNITIONAMTLC
									, PartyId			=	c.PAYEE_PARTYID
						from		ODS.TMFF_COST c
						where		c.SCD_ActiveFlag = 1
						and			c.SCD_IsDeleted = 0
						and			isnull(c.INVSTS, '') not in ('C', 'V')	--exclude voided/credited lines, replaced by new charge lines (per CALC.v_TMFF_RecognitionEvents convention)
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


union all


select		  JOB_UNID					=	cast(a.rowguid_AWB												as varchar(50))
			, System_BK					=	cast('OPS'														as varchar(50))
			, ShipmentID				=	cast(left(a.HWB, 11)											as varchar(50))
			, ChargeType				=	cast(a.ChargeType												as varchar(10))
			, ChargeCode				=	cast(a.ChrgCode													as varchar(50))
			, ChargeCodeDescription		=	cast(a.ChrgDesc													as varchar(100))
			, ChargeCodeCategory		=	cast(cc.ReportsCategory											as varchar(100))
			, CurrencyCode				=	cast(coalesce(cur.CurrencyType, 'USD')							as varchar(50))
			, AmountFC					=	try_cast(coalesce(a.ForeignAmt, a.Amount)						as float)
			, AmountLC					=	try_cast(a.Amount												as float)
			, ActualAmountFC			=	cast(null														as float)	--OPS has no separate booked/actual split; Amount is already the actual charge
			, ActualAmountLC			=	cast(null														as float)
			, RecognitionAmountFC		=	cast(null														as float)	--no revenue-recognition concept confirmed for OPS
			, RecognitionAmountLC		=	cast(null														as float)
			, VATAmountFC				=	cast(null														as float)	--no confirmed source column
			, VATAmountLC				=	try_cast(case when a.ChargeType = 'REVENUE' then a.TaxAndDutyAmountTransaction_BI end	as float)	--tblAWBCost has no VAT/tax column
			, VATActualAmountFC			=	cast(null														as float)
			, VATActualAmountLC			=	cast(null														as float)	--OPS has no separate booked/actual split for VAT
			, CreditorCode				=	cast(case when a.ChargeType = 'COST' then pty.AccountNo end	as varchar(50))
			, CreditorName				=	cast(case when a.ChargeType = 'COST' then pty.NameFull end	as varchar(150))
			, DebtorCode				=	cast(case when a.ChargeType = 'REVENUE' then cust.CustNo end	as varchar(50))
			, DebtorName				=	cast(case when a.ChargeType = 'REVENUE' then cust.CustName end	as varchar(150))
			, VendorType				=	cast(null														as varchar(50))	--no confirmed source column for TMFF or OPS
from		(
			select		  a.rowguid_AWB
						, a.HWB
						, src.ChargeType
						, src.ChrgCode
						, src.ChrgDesc
						, src.Amount
						, src.ForeignAmt
						, src.TaxAndDutyAmountTransaction_BI
						, src.rowguid_Currency
						, src.rowguid_Vendor
						, src.rowguid_AWBInvoice
			from		(
						select		  rowguid_AWB						=	d.rowguid_AWB
									, ChargeType						=	cast('REVENUE' as varchar(10))
									, ChrgCode							=	d.ChrgCode
									, ChrgDesc							=	d.ChrgDesc
									, Amount							=	d.Amount
									, ForeignAmt						=	d.ForeignAmt
									, TaxAndDutyAmountTransaction_BI	=	d.TaxAndDutyAmountTransaction_BI
									, rowguid_Currency					=	d.rowguid_Currency
									, rowguid_Vendor					=	cast(null as uniqueidentifier)
									, rowguid_AWBInvoice				=	d.rowguid_AWBInvoice
						from		ODS.NORAMOPSDW_tblAWBInvoiceDetail d
						where		d.SCD_ActiveFlag = 1
						and			d.SCD_IsDeleted = 0
						union all
						select		  rowguid_AWB						=	c.rowguid_AWB
									, ChargeType						=	cast('COST' as varchar(10))
									, ChrgCode							=	c.ChrgCode
									, ChrgDesc							=	c.ChrgDesc
									, Amount							=	c.Amount
									, ForeignAmt						=	c.ForeignAmt
									, TaxAndDutyAmountTransaction_BI	=	cast(null as money)
									, rowguid_Currency					=	c.rowguid_Currency
									, rowguid_Vendor					=	c.rowguid_Vendor
									, rowguid_AWBInvoice				=	cast(null as uniqueidentifier)
						from		ODS.NORAMOPSDW_tblAWBCost c
						where		c.SCD_ActiveFlag = 1
						and			c.SCD_IsDeleted = 0
						) src
			join		ODS.NORAMOPSDW_tblAWB a
			on			a.rowguid_AWB = src.rowguid_AWB
			and			a.SCD_ActiveFlag = 1
			and			a.SCD_IsDeleted = 0
			and			a.LinkServer = 'TGOPSINTL'
			) a
left join	ODS.NORAMOPSDW_lkpChargeCode cc
on			cc.ChrgCode = a.ChrgCode
and			cc.LinkServer = 'TGOPSINTL'
left join	ODS.NORAMOPSDW_lkpCurrency cur
on			cur.rowguid_Currency = a.rowguid_Currency
and			cur.LinkServer = 'TGOPSINTL'
left join	ODS.NORAMOPSDW_tblAWBInvoice ai		--revenue-only header, for Debtor/Customer
on			ai.rowguid_AWBInvoice = a.rowguid_AWBInvoice
and			ai.SCD_ActiveFlag = 1
and			ai.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblCustomer cust
on			cust.rowguid_Customer = ai.rowguid_Customer
and			cust.SCD_ActiveFlag = 1
and			cust.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_tblShipmentParty sp		--cost-only, vendor-to-party bridge
on			sp.RowID = a.rowguid_Vendor
and			sp.SCD_ActiveFlag = 1
and			sp.SCD_IsDeleted = 0
left join	CALC.v_NORAMOPSDW_Party pty
on			pty.OriginalParty_BK = sp.Party_BK
GO
