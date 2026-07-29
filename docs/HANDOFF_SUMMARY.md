# Kontekst projektu: UP_Data_Model / widoki Job (SGLBI)

## Co to za projekt
Baza `SGLBI` (data warehouse), dwa systemy źródłowe zasilające ODS:
- **TMFF** — tabele `ODS.TMFF_*` (np. `TMFF_JOB`, `TMFF_JOBOTHER`, `TMFF_JCREVENUE`, `TMFF_JCCOST`, `TMFF_REVENUE`, `TMFF_COST`, `TMFF_FMPARTY`, `TMFF_FMPARTYADDR`, `TMFF_SEA`, `TMFF_AIR`, `TMFF_VEWMOTHERVESSEL` itd.)
- **OPS / NORAMOPSDW** — tabele `ODS.NORAMOPSDW_*` (np. `tblAWB`, `tblAWBConsignee`, `tblAWBShipper`, `tblMAWB`, `tblMAWBOcean`, `lkpVendor`, `lkpDepartment`, `lkpCurrency`, `lkpChargeCode`, `tblCustomer` itd.)

Excel `UP_Data_Model` dokumentuje, dla każdego pola biznesowego (UPDM field name), jaka jest jego encja/kolumna źródłowa w ODS, osobno dla TMFF i OPS. Zakładki: **Job**, **Shipment**, **Economy**, **Container**, **Invoice**.

## Przebieg pracy (chronologicznie)
1. Uzupełnialiśmy braki w Excelu dla zakładek **Economy** i **Shipment** — mapowanie pole→(Entity, EntityField), bazując na kodach istniejących widoków `v_TMFF_Shipment` / `v_NORAMOPSDW_Shipment` i innych (`v_TMFF_dim_Party`, `v_TMFF_JOBPARTY`, `v_NORAMOPSDW_MAWB`, `v_NORAMOPSDW_MAWBOcean` itd.).
2. Gdy dostałem realne DDL tabel (`TMFF_OPS.sql`), zweryfikowałem i poprawiłem sporo błędów w Excelu (patrz sekcja "Ważne ustalenia" niżej) oraz ujednoliciłem nazewnictwo encji.
3. **Zmiana kierunku**: zamiast dalej dokumentować mapowanie w Excelu, zaczęliśmy **budować nowe widoki SQL** `CALC.v_TMFF_Job` i `CALC.v_NORAMOPSDW_Job` (analogiczne do istniejących `v_TMFF_Shipment`/`v_NORAMOPSDW_Shipment`, ta sama granulacja: 1 wiersz = 1 JOB / 1 AWB), pokrywające dokładnie listę pól z zakładki **Job** w Excelu.
4. Pierwsza wersja widoków korzystała ze skrótów przez warstwę CALC (`CALC.TMFF_JOBPARTY`, `CALC.v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company`, `CALC.NORAMOPSDW_MAWB/MAWBOcean`, `CALC.BiRef_AirLineMapping`, `CALC.TMFF_OwnerIdCompany`).
5. Na żądanie: **przepisałem widoki tak, żeby bazowały wyłącznie na warstwie ODS**, żeby nie przenosić dalej ewentualnych uproszczeń/błędów z CALC. Przy okazji wyszły na jaw realne bugi (patrz niżej).
6. W trakcie ręcznej pracy użytkownika nad polami Consignee wyszło na jaw **kolejne, ważniejsze znalezisko**: oryginalny `v_TMFF_Shipment` wcale nie używa party mastera (`FMPARTY`/`FMPARTYADDR`) do wyświetlania danych Consignee/Shipper — używa pól tekstowych (snapshot) bezpośrednio na `JOB`/`JOBOTHER`. To jeszcze nie zostało w pełni przeniesione na cały widok — **to jest właściwy punkt startowy dla Claude Code**.

## Ważne ustalenia / pułapki (koniecznie uwzględnić)

### Consignee / Shipper / Customer — RÓŻNE wzorce (świeże odkrycie, kluczowe!)
- **Consignee i Shipper**: pełny snapshot adresowy istnieje wprost na `ODS.TMFF_JOBOTHER` — realne kolumny `CSGNADDR1-4`, `CSGNCTRYCODE`, `CSGNPOSTALCODE`, `CSGNSTATEPROV`, `CSGNONWBCITYNAME` (analogicznie `SHPRADDR1-4`, `SHPRCTRYCODE`, `SHPRPOSTALCODE`, `SHPRSTATEPROV`, `SHPRCITYNAME`), plus `JOB.CSGNNAME` / `JOBOTHER.CSGNNAMEONWB` (analogicznie `JOB.SHPRNAME`). **Używać tych pól bezpośrednio, NIE przez FMPARTY/FMPARTYADDR.**
- **Customer**: NIE ma snapshotu adresowego na JOB/JOBOTHER (tylko `JOB.CUSTNAME` — samo imię, bez adresu). Dla Customer jedynym źródłem adresu jest **FMPARTY/FMPARTYADDR przez `PARTYID_CUST` / `jp.CONTROLPARTY`**.
- `ConsigneeID`/`ShipperID` to nadal osobny klucz biznesowy: `coalesce(jp.REALCSGN, jo.PARTYID_CSGNONWB, j.PARTYID_CSGN)` dla Consignee, `j.PARTYID_SHPR` dla Shipper — to jest ID, nie źródło Name/Address.
- **Bug w oryginalnym `v_TMFF_Shipment`**: jego kolumny wyjściowe `CSGNADDR2/3/4` (i analogicznie `SHPRADDR2/3/4`) są MYLĄCO nazwane — w rzeczywistości zawierają `CSGNPOSTALCODE`/`CSGNONWBCITYNAME`/`CSGNCTRYCODE` (nie realne ADDR2/3/4!), a prawdziwe kolumny `CSGNADDR2/3/4` i `CSGNSTATEPROV` są w tym widoku całkowicie pomijane, mimo że istnieją w ODS. W nowym `v_TMFF_Job` trzeba użyć realnych kolumn wprost.

### FMPARTY — DDL było nieaktualne dla tej jednej tabeli
Otrzymany DDL dla `ODS.TMFF_FMPARTY` wyglądał jak log interfejsu EDI (kolumny typu `MSGFUNC`, `TRANSMISSIONDATE`) i nie miał `PARTYID`/`FULLNAME`. Ale realny, działający widok `DW.v_TMFF_dim_Party` jednoznacznie potwierdza, że `ODS.TMFF_FMPARTY` ma `PARTYID`, `FULLNAME`, `COUNTRY`, `CITY`, `UPDATEDATE`, `CREATEDATE`, `UNID`. **Ufać widokowi, nie temu konkretnemu fragmentowi DDL** (prawdopodobnie błąd eksportu/desync). Adresy do FMPARTY dociąga się przez `ODS.TMFF_FMPARTYADDR` (join po `FMPARTY_UNID` = `FMPARTY.UNID`, biorąc najświeższy wiersz per `PARTYID`).

### ShipmentID (TMFF) — nie `JOB.GSHPID` wprost
Prawdziwa logika biznesowa (`CALC.v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company`) czyści `SHPNO` (`utilities.ufn_GetCleanGlobalShipmentId`), a `GSHPID` służy tylko jako klucz grupujący do deduplikacji, gdy kilka jobów dzieli ten sam `GSHPID` — wtedy wybierany jest "najczystszy" `clean_SHPNO` z grupy (fallback: `'TMFF|' + OWNERID + '|' + UNID`). Ta logika została w pełni inline'owana w wersji ODS-only.

### ShipmentID (OPS) — nie `LEFT(AWB.HWB,11)` wprost
Prawdziwa logika (`utilities.ufn_GetCleanGlobalShipmentId`) bazuje na `HouseNoForGlobalShipment` / `MasterNoForGlobalShipment` / `UniqueBookingIdentifier` — cross apply logika już zinlinowana w `v_NORAMOPSDW_Job`.

### Inne poprawki z Economy tab (mogą się przydać jako kontekst)
- OPS `AmountFC` vs `AmountLC`: dwa różne pola (`tblAWBInvoiceDetail`/`tblAWBCost` mają `ForeignAmt` i `Amount`), wcześniej błędnie oba mapowane na `Amount`.
- OPS `CurrencyCode`: nie ma kolumny `CurrencyId` — trzeba przez `rowguid_Currency` → `lkpCurrency.CurrencyType`.
- TMFF `ChargeCodeCategory` = `FMCHARGECODE.CATEGORYSVR` (potwierdzone w DDL).
- TMFF `RecognitionAmountFC`: brak realnej kolumny FC (jest tylko `RECOGNITIONAMTLC`) — przybliżenie: `RECOGNITIONAMTLC*(AMTFC/AMTLC)`.
- OPS `ChargeableWeight`: FCL → `tblAWBPieces.ChgWght`, w innych przypadkach → `tblAWBCalcValues.AWBChrgWt`.
- OPS `CarrierCode`/`CarrierName`: przez `lkpVendor.VendorNo`/`VendorName`, dowiązane przez `tblMAWB.rowguid_CarrierVendor` → `xrfMawbAwb`.
- OPS `TEU`: liczone z `tblAWBPieces.CntSize` + `CnrtLoad='FCL'` (10ft→0.5, 20ft→1, 40ft→2, 45ft→2.25), nie jest gotową kolumną.
- TMFF `Pieces`: `JOB.TOTPCS` istnieje wprost jako kolumna (nie trzeba sumować `CARGOITEM`/`SEACONTITEM`/`LOADUNITITEM`).

## Warstwa CALC — co zostało zinlinowane/wycięte w wersji "ODS-only"
| Obiekt CALC | Co robił | Jak zastąpiony |
|---|---|---|
| `CALC.TMFF_JOBPARTY` (pivot) | Pivotuje `ODS.TMFF_JOBPARTY` po `PARTYTYPE` na ~40 kolumn | Inline: `MAX(CASE WHEN PARTYTYPE=... THEN PARTYID END)` tylko dla potrzebnych typów (`REALCSGN`, `CONTROLPARTY`) |
| `CALC.v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company` | Czyszczenie `SHPNO` + dedup po `GSHPID` | Logika wklejona wprost jako CTE na `ODS.TMFF_JOB` |
| `CALC.TMFF_OwnerIdCompany` | Rozwiązuje `Company_BK` przez hierarchię `TMFF_SYCOSTRUC` | Usunięty; fallback `ShipmentID` używa `OWNERID` bezpośrednio (dotyczy tylko rzadkiej gałęzi fallbacku) |
| `CALC.NORAMOPSDW_MAWB` / `MAWBOcean` | Dedup `first_value()... over(partition by rowguid_AWB order by LastEdit desc)` | Ten sam wzorzec dedup wklejony wprost na `ODS.NORAMOPSDW_tblMAWB`/`tblMAWBOcean`. **Uwaga**: oryginalne widoki CALC eksponowały dużo mniej kolumn niż zakładałem w pierwszej wersji (np. brak `VesselName`, `FlightNumber`, `MoveType`) — pierwsza wersja by się nie skompilowała, ODS-only to naprawia. |
| `CALC.BiRef_AirLineMapping` | Ręcznie utrzymywana tabela referencyjna IATA→kod przewoźnika, **brak źródła w ODS** | Usunięty całkowicie — gałąź fallbacku CarrierCode przez IATA/prefiks MAWB wypadła (CarrierCode może wyjść `NULL` w skrajnym przypadku) |
| `utilities.ufn_GetCleanGlobalShipmentId`, `utilities.ufn_GetHashedUID` | Funkcje pomocnicze (schemat `utilities`, nie CALC) | **Zostawione bez zmian** — nie mam ich definicji, nie chciałem zgadywać i cicho zmieniać wartości ID. Flagowane jako "czarna skrzynka" |

## Co jeszcze NIE zostało zrobione (start dla Claude Code)
1. **Poprawić cały `v_TMFF_Job`** zgodnie ze świeżym odkryciem: Consignee i Shipper na polach snapshot z `JOB`/`JOBOTHER` (nie FMPARTY), Customer zostaje na FMPARTY/FMPARTYADDR. Poprawiony fragment dla Consignee już przygotowany (patrz plik `consignee_block_fix.sql` — do podłączenia).
2. Sprawdzić, czy `v_NORAMOPSDW_Job` ma analogiczny problem (Consignee/Shipper w OPS idą przez `tblAWBConsignee`/`tblAWBShipper` — to już są dedykowane per-AWB tabele, więc raczej OK, ale warto zweryfikować że to nie jest kolejny "party master" skrót).
3. Ustalić czy `utilities.ufn_GetCleanGlobalShipmentId` też ma zostać zinlinowana (nie mam jej definicji — jeśli Claude Code ma do niej dostęp, można sprawdzić i ewentualnie rozpisać).
4. `POD`/`POL` w `v_NORAMOPSDW_Job` — skonsolidowałem kilka alternatywnych pól z Excela w jeden `COALESCE` z własną hierarchią ważności (priorytet dla dedykowanych kodów `PtDischCode`/`PtLoadCode`) — to była moja interpretacja, warto zweryfikować na danych.
5. `CarrierName` (TMFF) — nie znalazłem żadnego źródła (na `ODS.TMFF_JOB` jest tylko `CARRIERCODE`/`CARRIERID`, bez nazwy).
6. Rozważyć, czy fallback CarrierCode przez IATA/MAWB (usunięty razem z `CALC.BiRef_AirLineMapping`) jest w ogóle potrzebny biznesowo, czy `NULL` w tym skrajnym przypadku jest akceptowalny.

## Pliki, które użytkownik dołączy ponownie
- `TMFF_OPS.sql` — pełne DDL tabel ODS dla obu systemów (źródło prawdy dla nazw/istnienia kolumn)
- `OPS_views.sql` / `TMFF_views.sql` — aktualne definicje widoków (`v_TMFF_Shipment`, `v_NORAMOPSDW_Shipment`, `v_TMFF_dim_Party`, `v_TMFF_JOBPARTY`, `v_TMFF_Job_GlobalShipmentId_Weight_Volume_Company`, `v_NORAMOPSDW_MAWB`, `v_NORAMOPSDW_MAWBOcean`, `v_TMFF_OwnerIdCompany` i inne)
- `OPS_scrypts.sql` / `TMFF_scrypts.sql` — starsze wersje widoków (mniej aktualne niż powyższe, ale bywały pomocne przy porównaniach)
- `UP_Data_Model_*.xlsx` — kilka wersji Excela z mapowaniem pól (Job/Shipment/Economy/Container/Invoice zakładki); najnowsza to `UP_Data_Model_2907_-_copy.xlsx` (zakładka Job — lista docelowych pól)
- `v_Job_views.sql` — pierwsza wersja `v_TMFF_Job`/`v_NORAMOPSDW_Job` (korzysta z CALC, ma znany błąd w joinach do MAWB/MAWBOcean)
- `v_Job_views_ODS_only.sql` — wersja bez zależności od CALC (aktualniejsza, ale Consignee/Shipper w niej NADAL błędnie idą przez FMPARTY zamiast snapshot pól — patrz punkt 1 wyżej)

## Cel końcowy
Dwa gotowe, poprawne, skompilowalne widoki `CALC.v_TMFF_Job` i `CALC.v_NORAMOPSDW_Job` (schemat docelowy do potwierdzenia — może być inny niż CALC, skoro cel to "based on ODS layer"), pokrywające 1:1 listę pól z zakładki Job w Excelu, bazujące wyłącznie na tabelach `ODS.*` (żadnych widoków `CALC.*` poza ewentualnie utility functions), z logiką biznesową odzwierciedlającą to, co faktycznie robią istniejące widoki `v_TMFF_Shipment`/`v_NORAMOPSDW_Shipment` — a tam gdzie te widoki same zawierają uproszczenia/błędy (jak mislabeled CSGNADDR2-4), użyć realnych, poprawnych kolumn z ODS zamiast bezmyślnie kopiować.
