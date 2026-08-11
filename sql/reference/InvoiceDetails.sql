use SGLBI

select 
  AmountChargelineCurrency	= case when ivh.DOCTYPE = 'CN' then -1 else 1 end * try_cast(ivd.AMTFC as float)
, AmountInvoiceCurrency		= case when ivh.DOCTYPE = 'CN' then -1 else 1 end * try_cast(ivd.AMTBC as float)
, ChargeCode				= ivd.CHRGCODE
, ChargeCodeCategory		= fmc.DESCRIPTION
, ChargeCodeDescription		= fmcc.CHRGDESC
, ChargelineCurrencyCode	= ivh.CURRCODE
, CreditTerms				= ivh.CRTERMCODE
, DebtorCode				= ivh.PARTYID_CUST
, DebtorName				= ivh.CUSTNAME
, DebtorReference			= ''
, DocumentType				= ivh.DOCTYPE
, InvoiceCurrencyCode		= ivh.CURRCODE
, InvoiceDate				= ivh.DOCDATE
, DueDate					= ivh.DUEDATE
, InvoiceNumber				= ivh.PRINTSNO
, JOB_UNID					= ivd.SOURCEUNID
, ShipmentID				= j.GSHPID
from		ODS.TMFF_IVDTL ivd
left join	ODS.TMFF_IVHDR ivh
on			ivh.UNID = ivd.IVHDR_UNID
and			ivh.VOIDDATE is null
and			ivh.SCD_ActiveFlag = 1
and			ivh.SCD_IsDeleted = 0
join		ODS.TMFF_IVJOB ivj
on			ivd.ivhdr_unid = ivj.IVHDR_UNID
and			ivd.IVJOB_SNO = ivj.SNO
and			ivj.SCD_ActiveFlag  = 1
and			ivj.SCD_IsDeleted = 0
left join	ODS.TMFF_JOB j
on			ivd.SOURCEUNID = j.UNID
left join	ODS.TMFF_FMCHARGECODE fmcc
on			ivd.CHRGCODE = fmcc.CHRGCODE
and			j.BIZTYPE = fmcc.BIZTYPE
and			fmcc.SCHEMECODE = '*'
left join	ODS.TMFF_FMCODE fmc
on			fmcc.CATEGORYSVR = fmc.CODE
and			fmc.TYPE = 'CCT'
left join	ODS.TMFF_SYCOMPANY syc
on			ivh.OWNERID = syc.OWNERID
where 		ivd.SCD_ActiveFlag = 1
and			ivd.SCD_IsDeleted = 0
and			ivh.STATUS = 'ORIGINAL'
and			ivd.SOURCETYPE = 'JB'
and			syc.CTRYCODE = 'US'


union all

select 
  AmountChargelineCurrency	= coalesce(ivd.ForeignAmt, ivd.Amount)
, AmountInvoiceCurrency		= ivd.Amount
, ChargeCode				= ivd.ChrgCode
, ChargeCodeCategory		= cc.ReportsCategory
, ChargeCodeDescription		= ivd.ChrgDesc
, ChargelineCurrencyCode	= coalesce(cu.CurrencyType, 'USD')
, CreditTerms				= ivh.TermsCode
, DebtorCode				= cust.CustNo
, DebtorName				= cust.CustName
, DebtorReference			= ''
, DocumentType				= coalesce(it.InvoiceType,'Invoice')
, InvoiceCurrencyCode		= coalesce(cuh.CurrencyType, 'USD')
, InvoiceDate				= ivh.InvDate
, DueDate					= ivh.DueDate
, InvoiceNumber				= ivh.InvoiceID
, JOB_UNID					= ivh.rowguid_AWB
, ShipmentID				= left(awb.HWB,11)
from		ODS.NORAMOPSDW_tblAWBInvoiceDetail ivd
left join	ODS.NORAMOPSDW_tblAWBInvoice ivh
on			ivd.rowguid_AWBInvoice = ivh.rowguid_AWBInvoice
and			ivd.SCD_ActiveFlag = 1
and			ivd.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpChargeCode cc
on			cc.ChrgCode = ivd.ChrgCode
and			cc.LinkServer = 'TGOPSINTL'
left join	ODS.NORAMOPSDW_lkpCurrency cu
on			cu.rowguid_Currency = ivd.rowguid_Currency
and			cu.LinkServer = 'TGOPSINTL'
left join	ODS.NORAMOPSDW_lkpCurrency cuh
on			cu.rowguid_Currency = ivh.rowguid_Currency
and			cuh.LinkServer = 'TGOPSINTL'
left join	ODS.NORAMOPSDW_tblCustomer cust 
on			ivh.Rowguid_Customer = cust.Rowguid_Customer
and			cust.SCD_ActiveFlag = 1
and			cust.SCD_IsDeleted = 0
left join	ODS.NORAMOPSDW_lkpInvoiceType it
on			ivh.rowguid_InvoiceType = it.rowguid_InvoiceType
and			it.LinkServer = 'TGOPSINTL'
left join	ODS.NORAMOPSDW_tblAWB awb
on			ivh.rowguid_AWB = awb.rowguid_AWB
where		ivh.LinkServer = 'TGOPSINTL'