%dw 2.0
output application/json skipNullOn="everywhere"
import formatDate, getSystemDate, wrapValueInSingleQuoteWithoutSep, getLogMessage from modules::Utility
import wrapInToDate from modules::SQL
import * from dwl::common::txnAdmTagUtils
import * from dwl::common::messageCommonUtils
import * from dwl::patientInfoUpdate::doctorTablesUtils
import * from dwl::patientInfoUpdate::changeDoctorTypeUtils
import * from dwl::patientInfoUpdate::untagPackageUtils
import * from dwl::patientInfoUpdate::changePackageUtils

// Config properties
var slbUser = Mule::p('slb.user')

fun getDoctorById(doctorId) = (medicalTeam filter ($.ID == doctorId))[0]

fun getTransferType(prevNursingUnit, newNursingUnit, prevRoomNo, newRoomNo, newRoomCharge) = 
	if((prevNursingUnit != newNursingUnit and (vars.triggerEvent ~= Mule::p('transfer.events.transfer'))) or vars.triggerEvent ~= Mule::p('transfer.events.inpatient-to-outpatient'))
		Mule::p('transfer.type.nursing-unit')
	else if (prevNursingUnit ~= newNursingUnit and prevRoomNo ~= newRoomNo and vars.triggerEvent ~= Mule::p('transfer.events.transfer'))
		Mule::p('transfer.type.bed')
	else if (prevNursingUnit ~= newNursingUnit and vars.triggerEvent ~= Mule::p('transfer.events.transfer'))
		Mule::p('transfer.type.room')
	else if (prevNursingUnit ~= newNursingUnit and prevRoomNo ~= newRoomNo and !isEmpty(newRoomCharge))
		Mule::p('transfer.type.room-accommodation-change')
	else
		null

fun getRemarks(triggerEvent) = 
	if (triggerEvent ~= Mule::p('transfer.events.turned-inpatient'))
		"This is an Outpatient turned Inpatient."
	else if (triggerEvent ~= Mule::p('transfer.events.swap'))
		"Outpatient Transaction."
	else
		""
fun getOccupancyListIfA06(triggerEvent) =
	if (triggerEvent ~= Mule::p('transfer.events.turned-inpatient'))
		{
			"id": "HIBERNATE_SEQUENCE.nextval",
			"pin": payload..'PID'[0].'PID.3'.'CX.1',
			"visit_no": vars.visitNo,
			"patient_type": pv1.'PV1.2'[0],
			"confidential": vars.patientTransferPrerequisiteInfo.isConfidential,
			"redtag_flag": if (vars.patientTransferPrerequisiteInfo.redTagFlagExists) "Y" else "N",
			"death_type": null,
			"death_flag": "N",
			"endorsement_flag": if (vars.patientTransferPrerequisiteInfo.endorsementFlagExists) "Y" else "N",
			"package_rate_no": vars.patientTransferPrerequisiteInfo.packageRateNo,
			"status": "A",
		}
	else
		{}
		
fun wrapValueInSingleQuotes(value) =
	if (!isEmpty(value))
		if ((value contains("SELECT")) or (value contains("TO_DATE")))
			value ++ "||';'||"
		else
			"'" ++ value ++ "'" ++ "||';'||"
	else
		"';'||"
	
fun wrapValueInSingleQuotesLast(value) =
	if (!isEmpty(value))
		if ((value contains("SELECT")) or (value contains("TO_DATE")))
			value ++ "||';'"
		else
			"'" ++ value ++ "'" ++ "||';'"
	else
		"';'"

fun wrapInToChar(value) = 
	if (!isEmpty(value))
		"TO_CHAR(" ++ value ++ ", 'MM/DD/YYYY HH:MI:SS AM')"
	else
		""
		
fun getPbaPfId(admDoctorId) = 
	"(SELECT id FROM txn_pba_pf WHERE adm_doctor_id = " ++ admDoctorId ++ ")"

fun getAdmTagId(admDoctorId) =
	"(SELECT id FROM txn_adm_tag WHERE adm_doctor_id = " ++ admDoctorId ++ ")"
	
fun formatSQLMessage(value, substitueForId) =
	if (upper(value) contains(".NEXTVAL"))
		"'||" ++ substitueForId  ++ "||'"
	else if (upper(value) contains("SELECT"))
		"'||(" ++ value ++ ")||'"
	else if (upper(value) contains("TO_DATE"))
		"'||(TO_CHAR(" ++ value ++ ", 'MM/DD/YYYY HH:MI:SS AM'))||'"
	else
		value
		
		
fun buildDoctorsObject(doctors, doctorType, guarantorCode) =
	doctors default [] map {
		"DOCTOR_CODE": if (doctorType ~= Mule::p('doctor.type.co-managing')) $ else $.'XCN.1',
		"DOCTOR_TYPE": doctorType,
		"GUARANTOR_CODE": guarantorCode
	}
		
fun buildAuditLogsForAdmTag() = 
	medicalTeam."ADM_TAG" default [] map(item, index) ->
	using (systemDateAndTime = "(" ++ wrapInToDate(formatDate(now())) ++ ")") {
		"util_audit_log_adm_tag": {
			"id": "ESB_PC.UTIL_AUDIT_LOG_ADM_TAG_SEQ.nextval",
			"adm_doctor_id": item.'ADM_DOCTOR_ID',
			"change_type": Mule::p('audit.change.type.delete'),
			"activity": item.'ID' ++ " " ++ item.'ADM_DOCTOR_ID',
			"username": Mule::p('slb.user'),
			"log_datetime": systemDateAndTime
		}
	}

fun getDoctorSchedSms(schedSms) =
	if (!isEmpty(schedSms) and schedSms > 0)
		if ((now() as Time {format: "HH:mm"}) < |08:00|)
			wrapInToDate(getSystemDate(schedSms - 1))
		else
			wrapInToDate(getSystemDate(schedSms))
	else
		null	

fun validateSSEOrHEE(patientType) =
	isSSEOrHEEActive  and
	(
		(patientType ~= Mule::p('patient.type.inpatient')) or 
		(
			(patientType ~= Mule::p('patient.type.outpatient')) 
			and (referenceTables.specialNursingUnits contains(newNursingUnit))
		)
	)

fun validateCollectPF(doctorType) = 
	(Mule::p('patient.account-class.sse') ~= accountClass and validateSSEOrHEE(vars.patientType)) or 
	(doctorType ~= Mule::p('doctor.type.hmo-coordinator'))
//	([Mule::p('patient.account-class.hmo2'), Mule::p('patient.account-class.com2')] contains accountClass)

fun getPFInstructionAndAmount(doctorType, tableName) = 
	if (!isEmpty(dot6PfAmount) and doctorType ~= Mule::p('doctor.type.hmo-coordinator'))
		{
			("pf_instruction": if (dot6PfAmount > 0) Mule::p('doctor.pf.instruction.collect') else Mule::p('doctor.pf.instruction.default')) if (tableName ~= "txn_adm_doctors"),
			("pf_type": if (dot6PfAmount > 0) Mule::p('doctor.pf.instruction.collect') else Mule::p('doctor.pf.instruction.default')) if (tableName ~= "txn_pba_pf"),
			"pf_amount": dot6PfAmount,
		}
	else
		{
			("pf_type": if (validateSSEOrHEE(vars.patientType) and (Mule::p('patient.account-class.sse') ~= accountClass)) defaultPf else if (validateSSEOrHEE(vars.patientType) and (Mule::p('patient.account-class.hee') ~= accountClass)) Mule::p('doctor.pf.instruction.collect') else if (heeOrSseChangedAndActive) "NULL" else null) if (tableName ~= "txn_pba_pf"),
			"pf_amount": if (validateSSEOrHEE(vars.patientType)) pfAmount else if (heeOrSseChangedAndActive) "NULL" else null
		}
		
fun filterMedicalTeam(doctorType) = if (!isEmpty(medicalTeam)) 
    (medicalTeam filter ($.'DOCTOR_TYPE' ~= doctorType)) else {}
    
fun filterMedicalTeamWithDoctorCode(doctorType, doctorCode) = if (!isEmpty(medicalTeam)) 
    (medicalTeam filter ($.'DOCTOR_TYPE' ~= doctorType and $.'DOCTOR_CODE' ~= doctorCode)) else {}
    
fun getPbaPfAndAdmTagTables(patientDoctors) = 
patientDoctors default [] map(item, index) -> 
	using (existingDoctor = getDoctor(medicalTeam, item.'DOCTOR_TYPE', item.'DOCTOR_CODE'),
		isNewDoctor = isEmpty(existingDoctor),
		admDoctorId = if (isNewDoctor) getAdmDoctorId(vars.visitNo, item.'DOCTOR_CODE', item.'DOCTOR_TYPE')
					  else existingDoctor.ID,
		changedDoctorType = (changedDoctorTypes filter ($.DOCTOR_CODE ~= item.'DOCTOR_CODE'))[0] default {},
		pfColumnsForAdmDoctors = getPFInstructionAndAmount(item.'DOCTOR_TYPE', 'txn_adm_doctors'),
		pfColumnsForPbaPf = getPFInstructionAndAmount(item.'DOCTOR_TYPE', 'txn_pba_pf'),
		admTagInfo = (admTagPrerequisiteInfo filter($.doctorCode ~= item.'DOCTOR_CODE'))[0],
		txnPbaPfs = item.'TXN_PBA_PF') {
	"txn_adm_doctors": {
		"adm_doctor_id": admDoctorId,
		"doctor_type": item.'DOCTOR_TYPE',
		"doctor_code": item.'DOCTOR_CODE'
	},
	("txn_pba_pf": pfColumnsForPbaPf ++ {
		"isExisting": !isEmpty(item.'PBA_PF'),
		"id": "HIBERNATE_SEQUENCE.nextval",
		"adm_doctor_id": item.'ID',
		("created_by": Mule::p('slb.user')) if (isEmpty(item.'PBA_PF')),
		("updated_by": Mule::p('slb.user')) if (!isEmpty(item.'PBA_PF')),
		("created_datetime": msh7) if (isEmpty(item.'PBA_PF')),
		("updated_datetime": msh7) if (!isEmpty(item.'PBA_PF')),
		"remarks": "Patient transferred to MDPortal Unit",
		("validated_by": "") if (false),
		("validated_datetime": "") if (false),
		("pf_update_datetime": "") if (false)
	}) if (!(isEmpty(pfColumnsForPbaPf.pf_type) and isEmpty(pfColumnsForPbaPf.pf_amount))),
	("txn_adm_tag": {
			"isExisting": !isEmpty(item.'ADM_TAG'),
			"id": "TXN_ADM_TAG_SEQ.nextval",
			"visit_no": vars.visitNo,
			"adm_doctor_id": admDoctorId,
			"pf_entry_type": getAdmTagPfEntryType(admDoctorId),
			"pf_tag": getAdmTagPfTag(admDoctorId),
			"updated_by": slbUser,
			"updated_datetime": msh7,
			"mdp_net_pf": getAdmTagMdpNetPf(admDoctorId)
		}) if ((vars.billingFlag != 'Y') and !vars.dischargeOrder
			and ((!isEmpty(changedDoctorType) and !isEmpty(changedDoctorType.ADM_TAG))
				or (!isNewDoctor and !isEmpty(item.'ADM_TAG')))),
	("txn_adm_tag": {
		"isExisting": !isEmpty(item.'ADM_TAG'),
		"id": "ESB_PC.TXN_ADM_TAG_SEQ.nextval",
		"visit_no": vars.visitNo,
		"adm_doctor_id": admDoctorId,
		"tag_type": "MDN",
		"pf_entry_type": getAdmTagPfEntryType(admDoctorId),
		"pf_tag": getAdmTagPfTag(admDoctorId),
		"send_sms": "N",
		"tagged_by": null,
		"updated_datetime_tag": null,
		"sched_sms": if (validateSSEOrHEE(vars.patientType) or (item.'DOCTOR_TYPE' ~= Mule::p('doctor.type.hmo-coordinator'))) null else getDoctorSchedSms(admTagInfo.schedSms),
		"show_pf": admTagInfo.showPf,
		"collect_pf": getAdmTagCollectPf(vars.patientTransferPrerequisiteInfo.accountClass, isValidSSEOrHEE, item.'DOCTOR_TYPE', item.'DOCTOR_CODE', 
							dot6PfAmount, txnAdmEncounter.CLAIMED_HMO_CO_GUARANTOR, hmoInfo, txnPbaPfs) default "N",
		"counter": 0,
		("created_by": Mule::p('slb.user')) if (isEmpty(item.'ADM_TAG')),
		("created_datetime": msh7) if (isEmpty(item.'ADM_TAG')),
		("updated_by": Mule::p('slb.user')) if (!isEmpty(item.'ADM_TAG')),
		("updated_datetime": msh7) if (!isEmpty(item.'ADM_TAG')),
		"mdp_net_pf": getAdmTagMdpNetPf(admDoctorId),
		"vat_flag": admTagInfo.vatFlag
	}) if (!isEmpty(admTagPrerequisiteInfo) and isEmpty(item.'ADM_TAG'))
}

fun getPbaPfAndAdmTagTablesAuditLogs(doctorsTables) =
doctorsTables default [] map(item, index) -> 
	using (admDoctorId = item.'txn_adm_doctors'.'adm_doctor_id', 
		doctorType = item.'txn_adm_doctors'.'doctor_type',
		doctorCode = item.'txn_adm_doctors'.'doctor_code',
		systemDateAndTime = "(" ++ wrapInToDate(formatDate(now())) ++ ")") {
	("util_audit_log": {
		"id": "HIBERNATE_SEQUENCE.nextval",
		"entity_name": Mule::p('slb.user') ++ ".txn_pba_pf",
		"entity_pk": admDoctorId,
		"log_message": getLogMessage(item.'txn_pba_pf', filterMedicalTeam(doctorType)[0]."PBA_PF" default {}, getPbaPfId(admDoctorId)),
		"log_time": systemDateAndTime,
		"username": Mule::p('slb.user'),
		"operation": if (item.'txn_pba_pf'.'isExisting') "M" else "I"
	}) if (!isEmpty(item.'txn_pba_pf') and !isEmpty((removeAuditFields(item.'PBA_PF') default {} -- (filterMedicalTeam(doctorType)[0]."PBA_PF" default {})))),
	("util_audit_log_adm_tag": {
		"id": "UTIL_AUDIT_LOG_ADM_TAG_SEQ.nextval",
		"adm_doctor_id": admDoctorId,
		"change_type":  if (item.'txn_adm_tag'.'isExisting') "M" else "I",
		"activity": getLogMessage(item.'txn_adm_tag' filterObject ((value, key) -> !(key startsWith "updateConditions") and !(key startsWith "isExisting")) , 
								filterMedicalTeamWithDoctorCode(doctorType default getDoctorById(item.txn_adm_tag.adm_doctor_id).DOCTOR_TYPE, doctorCode)[0]."ADM_TAG" default {},
								if(!(item.txn_adm_tag.adm_doctor_id contains("SELECT")))
								"(SELECT ID FROM TXN_ADM_TAG WHERE VISIT_NO = '" ++ vars.visitNo ++ "' AND ADM_DOCTOR_ID = '" ++ item.txn_adm_tag.adm_doctor_id ++ "')"
								else
								"(SELECT ID FROM TXN_ADM_TAG WHERE VISIT_NO = '" ++ vars.visitNo ++ "' AND ADM_DOCTOR_ID = " ++ item.txn_adm_tag.adm_doctor_id ++ ")"),
		"username": Mule::p('slb.user'),
		"log_datetime": systemDateAndTime
	}) if (!isEmpty(item.'txn_adm_tag')),
	("util_audit_log_pba_pf": {
		"id": "UTIL_AUDIT_LOG_PBA_PF_SEQ.nextval",
		"adm_doctor_id": admDoctorId,
		"change_type": if (item.'txn_pba_pf'.'isExisting') "M" else "I",
		"activity": 
			wrapValueInSingleQuotes(item.'txn_adm_doctors'.'visit_no') ++ 
			wrapValueInSingleQuotes(item.'txn_adm_doctors'.'doctor_code') ++
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'adm_doctor_id') ++ 
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'pf_amount') ++ 
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'pf_type') ++ 
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'balance' default 0) ++
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'created_by') ++
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'updated_by') ++
			(if (!isEmpty(item.'txn_pba_pf'.'created_datetime')) wrapValueInSingleQuotes(wrapInToChar(item.'txn_pba_pf'.'created_datetime')) else "';'||") ++ 
			(if (!isEmpty(item.'txn_pba_pf'.'updated_datetime')) wrapValueInSingleQuotes(wrapInToChar(item.'txn_pba_pf'.'updated_datetime')) else "';'||") ++ 
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'remarks') ++
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'validated_by') ++
			(if (!isEmpty(item.'txn_pba_pf'.'validated_datetime')) wrapValueInSingleQuotes(wrapInToChar(item.'txn_pba_pf'.'validated_datetime')) else "';'||") ++ 
			(if (!isEmpty(item.'txn_pba_pf'.'pf_update_datetime')) wrapValueInSingleQuotes(wrapInToChar(item.'txn_pba_pf'.'pf_update_datetime')) else "';'||") ++ 
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'encoding_officer') ++ 
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'contingency_reason') ++
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'contingency') ++
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'instruction_manner') ++ 
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'instruction_received') ++ 
			wrapValueInSingleQuotes(item.'txn_pba_pf'.'pf_distribution') ++
			getPbaPfId(admDoctorId) ++ "||';'",
		"username": Mule::p('slb.user'),
		"log_datetime": systemDateAndTime
	}) if (!isEmpty(item.'txn_pba_pf'))
}

fun populateDoctorsTablesAndAuditLogs() = 
	if ([Mule::p('transfer.events.transfer'), Mule::p('transfer.events.turned-inpatient'), Mule::p('transfer.events.inpatient-to-outpatient')] contains(vars.triggerEvent))
		if (!isEmpty(admTagPrerequisiteInfo))
			using(doctorsTables = getPbaPfAndAdmTagTables(medicalTeam))
			(doctorsTables ++ getPbaPfAndAdmTagTablesAuditLogs(doctorsTables)) reduce((item, acc = {}) -> acc ++ item) default {}
		else
			(buildAuditLogsForAdmTag() default {}) reduce((item, acc = {}) -> acc ++ item)
	else
		{}

fun removeAuditFields(record) = 
	(record mapObject ((upper('$$')) : '$'))
		- "UPDATED_BY" 
		- "UPDATED_DATETIME" 
		- "CREATED_BY"
		- "CREATED_DATETIME" 
		- "ID"	
	
var evn6 = wrapInToDate(formatDate(payload..'EVN.6'[0].'TS.1'))
var msh7 = wrapInToDate(formatDate(payload..'MSH.7'[0].'TS.1'))
var pv1 = payload..'PV1'[0]
var pv2 = payload..'PV2'[0]
//added pid18 for SA-41373
var pid18 = payload..'PID.18'[0]
var obx = payload..*'OBX'

var prevNursingUnit = pv1.'PV1.6'.'PL.1'
var newNursingUnit = pv1.'PV1.3'.'PL.1'

var prevRoomNo = pv1.'PV1.6'.'PL.2'
var newRoomNo = pv1.'PV1.3'.'PL.2'

var newBedNo = pv1.'PV1.3'.'PL.3'

var newRoomCharge = pv2.'PV2.2'.'CE.1'

var roomAccommodation = pv2.'PV2.2'.'CE.1'

var referenceTables = vars.patientReferences.referenceTables

var refRoomChargingCode = pv2.'PV2.2'.'CE.1'
var roomBedStatus = vars.patientTransferPrerequisiteInfo.roomBedStatus

var patientType = payload..'PV1.2'[0]
var accountClass = payload..'PV1.20'[0].'FC.1'
var isAccountClassChange = (vars.patientTransferPrerequisiteInfo.txnAdmEncounter."GUARANTOR_FLAG" != "Y") default true
var iopsEncounterFlag = vars.patientTransferPrerequisiteInfo.txnAdmEncounter.'CREATED_BY' ~= Mule::p('order-pay.user')

var dot6PfAmount = vars.patientTransferPrerequisiteInfo.dot6PFAmount
var pfAmount = vars.patientTransferPrerequisiteInfo.pfAmount
var heeOrSseChangedAndActive = vars.patientTransferPrerequisiteInfo.heeOrSseChangedAndActive
var isSSEOrHEEActive = vars.patientTransferPrerequisiteInfo.isSSEOrHEEActive
var admTagPrerequisiteInfo = vars.patientTransferPrerequisiteInfo.admTagPrerequisiteInfo default []
var medicalTeam = vars.patientTransferPrerequisiteInfo.medicalTeam default []
var previousRoomCharge = vars.patientTransferPrerequisiteInfo.previousRoomCharge
var roomBedExists = vars.patientTransferPrerequisiteInfo.roomBedExists
var roomAccommodationExists =  vars.patientTransferPrerequisiteInfo.roomAccommodationExists
var defaultPf = vars.patientTransferPrerequisiteInfo.defaultPf
var isValidSSEOrHEE = validateSSEOrHEE(vars.patientType)
var hmoInfo = vars.patientTransferPrerequisiteInfo.hmoInfo
var txnAdmEncounter = vars.patientTransferPrerequisiteInfo.txnAdmEncounter



var admDateTime = 
	 if (!isEmpty(pv1.'PV1.44'.'TS.1'))
		wrapInToDate(formatDate(pv1.'PV1.44'.'TS.1'))
	else
		null

var patientDoctors = buildDoctorsObject(pv1.*'PV1.7', Mule::p('doctor.type.attending'), null) 
	++ buildDoctorsObject(pv1.*'PV1.9', Mule::p('doctor.type.referring'), null)
	++ buildDoctorsObject(pv1.*'PV1.51', Mule::p('doctor.type.co-managing'), null) 
	++ buildDoctorsObject(pv1.*'PV1.52', Mule::p('doctor.type.hmo-coordinator'), null)
	
var changedDoctorTypes = getChangedDoctorTypesNotHMO(medicalTeam, patientDoctors)
			
---
using (transferType = getTransferType(prevNursingUnit, newNursingUnit, prevRoomNo, newRoomNo, newRoomCharge)) 
{
	"scriptParameters": {
		"triggerEvent": vars.triggerEvent,
		"visitFacilityId": vars.visitFacilityId,
		"visitNo": vars.visitNo,
		"isInMDPortalUnits": !isEmpty(admTagPrerequisiteInfo),
		"roomBedExists": roomBedExists
	},
	("txn_adm_encounter": {
		("account_class": accountClass) if (isAccountClassChange),
		("patient_type": if (vars.triggerEvent ~= Mule::p('transfer.events.turned-inpatient')) "I" else "O") if ((vars.triggerEvent ~= Mule::p('transfer.events.turned-inpatient')) or (vars.triggerEvent ~= Mule::p('transfer.events.inpatient-to-outpatient'))),
		("adm_datetime": admDateTime) if (!isEmpty(admDateTime)),
		("turned_inpatient_flag": "Y") if (vars.triggerEvent ~= Mule::p('transfer.events.turned-inpatient')),
		"updated_by": Mule::p('slb.user'),
		"updated_datetime": evn6,
		"labnet_hospital": vars.labnetHospitalName
	}) if (((vars.triggerEvent ~= Mule::p('transfer.events.turned-inpatient')) or (vars.triggerEvent ~= Mule::p('transfer.events.inpatient-to-outpatient')) or (isAccountClassChange)) and (!iopsEncounterFlag)),
	//updated mapping
	("txn_adm_roomtran_rqst": 
		if (prevNursingUnit == '0386' and newNursingUnit == '0173')
		{
		"visit_no": pid18.'CX.1',
		"room_transfer_type": "TRF03",
		"prev_nursing_unit": "0386",
		"prev_room_charge": "RCHSP",
		"prev_roomno": pv1.'PV1.6'.'PL.2',
		"prev_bedno": pv1.'PV1.6'.'PL.3',
		"new_nursing_unit": "0173",
		"new_room_charge": "RCHSP",
		"new_roomno": pv1.'PV1.3'.'PL.2',
		"new_bedno": pv1.'PV1.3'.'PL.3',
		"rqst_status": "RQS04",
		"remarks": "Outpatient Transaction - UC to ECS",
		"created_by": "scm",
		"created_datetime": evn6,
		"id": "ESB_PC.HIBERNATE_SEQUENCE.nextval"
		}
		else if (prevNursingUnit == '0173' and newNursingUnit == '0386')
		{
		"visit_no": pid18.'CX.1',
		"room_transfer_type": 'TRF03',
		"prev_nursing_unit": '0173',
		"prev_room_charge": 'RCHSP',
		"prev_roomno": pv1.'PV1.6'.'PL.2',
		"prev_bedno": pv1.'PV1.6'.'PL.3',
		"new_nursing_unit": '0386',
		"new_room_charge": 'RCHSP',
		"new_roomno": pv1.'PV1.3'.'PL.2',
		"new_bedno": pv1.'PV1.3'.'PL.3',
		"rqst_status": 'RQS04',
		"remarks": 'Outpatient Transaction - ECS to UC',
		"created_by": 'scm',
		"created_datetime": evn6,
		"id": "ESB_PC.HIBERNATE_SEQUENCE.nextval",
		}
		else
		{
		"id": "ESB_PC.HIBERNATE_SEQUENCE.nextval",
		"visit_no": vars.visitNo,
		"room_transfer_type": transferType,
		"prev_nursing_unit": prevNursingUnit,
		"prev_room_charge": previousRoomCharge,
		"prev_roomno": prevRoomNo,
		"prev_bedno": pv1.'PV1.6'.'PL.3',
		"new_nursing_unit": newNursingUnit,
//		"new_room_charge": newRoomCharge,
		"new_room_charge": if (vars.roomAccommodation != null) (vars.roomAccommodation) else (vars.patientTransferPrerequisiteInfo.roomCharge),
		"new_roomno": newRoomNo,
		"new_bedno": newBedNo,
		"rqst_status": Mule::p('transfer.request'),
		("remarks": getRemarks(vars.triggerEvent)) if (vars.triggerEvent ~= Mule::p('transfer.events.turned-inpatient') or vars.triggerEvent ~= Mule::p('transfer.events.swap')),
		"created_by": Mule::p('slb.user'),
		"created_datetime": evn6,
		"updated_by": Mule::p('slb.user'),
		"updated_datetime": evn6
	}),
	("txn_adm_in": 
	if (prevNursingUnit == '0386' and newNursingUnit == '0173')
	{
		"visit_no": pid18.'CX.1',
		"admtype_code": pv1.'PV1.4',
		"nursing_unit": pv1.'PV1.3'.'PL.1',
		"room_charge": vars.patientTransferPrerequisiteInfo.roomChargeOS,
		"roomno": pv1.'PV1.3'.'PL.2',
		"bedno": pv1.'PV1.3'.'PL.3',
		"admstatus_code": "ADS01",
		"created_by": "scm",
		"created_datetime": evn6,
		"room_rate": vars.patientTransferPrerequisiteInfo.roomRate
	}
	else
	{
		("nursing_unit": newNursingUnit) if (!(transferType ~= Mule::p('transfer.type.room') or transferType ~= Mule::p('transfer.type.bed'))),
		"roomno": newRoomNo,
		"bedno": newBedNo,
//		"room_charge": vars.patientTransferPrerequisiteInfo.roomCharge,
		"room_charge": if (vars.roomAccommodation != null) (vars.roomAccommodation) else (vars.patientTransferPrerequisiteInfo.roomCharge),
		"room_rate": vars.patientTransferPrerequisiteInfo.roomRate,
		"updated_by": Mule::p('slb.user'),
		"updated_datetime": evn6
	}),
	("txn_adm_out": {
		"visit_no": pid18.'CX.1',
		"version": '1',
		"paid": if (vars.patientTransferPrerequisiteInfo.paid != null) "Y" else "N",
		"special_ancillary": "N",
		"org_code": pv1.'PV1.3'.'PL.1',
		"status": "A",
		"created_by": 'scm',
		"created_datetime": evn6,
		"for_payment": if (vars.patientTransferPrerequisiteInfo.forPayment != null) "Y" else "N",
		"admtype_code": pv1.'PV1.4',
		"admstatus_code": 'ADS01'
	}) if (prevNursingUnit == '0173' and newNursingUnit == '0386'),
//SA-41373	
	
	("txn_occupancy_list": {
		("nursing_unit": newNursingUnit) if (!(transferType ~= Mule::p('transfer.type.room') or transferType ~= Mule::p('transfer.type.bed'))),
		"roomno": newRoomNo,
		"bedno": newBedNo,
		"roomtran_rqst_status": Mule::p('transfer.request')
	} ++ getOccupancyListIfA06(vars.triggerEvent)) if (!(vars.triggerEvent ~= Mule::p('transfer.events.inpatient-to-outpatient') or vars.triggerEvent ~= Mule::p('transfer.events.swap'))),

	("ref_room_bed": {
		"org_structure": pv1.'PV1.3'.'PL.1',
		"room_charge": newRoomCharge,
		"roomno": newRoomNo,
		"bedno": newBedNo,
		"rb_status": "RBS30",
		"description": newRoomNo ++ " - " ++ newBedNo,
		"created_by": "scm",
		"created_datetime": evn6,
		"updated_by": "scm"
	}) if (!roomBedExists and (!isEmpty(newRoomNo) and !isEmpty(newBedNo))),
	("ref_room_bed": [{
		"roomno": newRoomNo,
		"bedno": newBedNo,
		"rb_status": if (roomBedStatus != "RBS30") "RBS04" else "RBS30",
		"updated_datetime": evn6,
		"updated_by": "scm"
	},
	{
		"rb_status": if (roomBedStatus != "RBS30") Mule::p('rb.status.available') else "RBS30",
		"updated_by": Mule::p('slb.user'),
		"updated_datetime": evn6
	}]) if (roomBedExists and (!isEmpty(newRoomNo) and !isEmpty(newBedNo))),
	("txn_adm_newborn": {
		"rooming_in_flag": vars.patientTransferPrerequisiteInfo.roomingIn,
		"updated_by": Mule::p('slb.user'),
		"updated_datetime": wrapInToDate(formatDate(payload..'MSH.7'[0].'TS.1'))
	}) if (!isEmpty(payload..*'PID.21'[0].'CX.1')),
	("ref_room_charging": {
		"id": "HIBERNATE_SEQUENCE.nextval",
		"code": refRoomChargingCode,
		"description": refRoomChargingCode,
		"room_class": "RCL02",
		"rms": "RCL02",
		"status": "A",
		"room_rate": "0"
	}) if (!roomAccommodationExists and !isEmpty(refRoomChargingCode))
} ++ 
populateDoctorsTablesAndAuditLogs()
