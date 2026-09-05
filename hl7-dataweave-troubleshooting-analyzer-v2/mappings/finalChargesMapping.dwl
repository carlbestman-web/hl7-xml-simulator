%dw 2.0
output application/xml skipNullOn="everywhere"
import standardDate from modules::Utility
import valueSet from dw::core::Objects


ns udto http://slmc.com.ph/udto/
ns cs http://slmc.com.ph/slmc_cs/
ns slb http://slmc.com.ph/slb/

var slbDateFormat = p('date-format.slb-db')

var zc1 = payload..'ZC1'[0]
var pid = payload..'PID'[0]
var obx = payload..'OBX'[0]
var startDateTime = (payload..*'OBX' filter upper($.'OBX.3'.'CE.1') ~= upper((Mule::p('obx-identifier.start-date-time'))))[0].'OBX.5'
var endDateTime = (payload..*'OBX' filter upper($.'OBX.3'.'CE.1') ~= upper((Mule::p('obx-identifier.stop-date-time'))))[0].'OBX.5'
var literPerMinute = (payload..*'OBX' filter upper($.'OBX.3'.'CE.1') ~= upper((Mule::p('obx-identifier.liter-per-minute'))))[0].'OBX.5'
var startLocalDateTime = if (startDateTime != null) startDateTime as LocalDateTime {format: "yyyy-MM-dd HH:mm:ss"} as LocalDateTime {format: "yyyyMMddHH:mm:ss"} else ""
var endLocalDateTime =if (endDateTime != null) endDateTime as LocalDateTime {format: "yyyy-MM-dd HH:mm:ss"} as LocalDateTime {format: "yyyyMMddHH:mm:ss"} else ""
---
udto#UDTO: {
	udto#OriginalRequest: {
		udto#OriginalRequestPayload: {
			udto#slmc_cs: {
				cs#common: {
					cs#eventDateTime: standardDate(payload..'FT1'[0].'FT1.4'.'DR.1'.'TS.1'),
					cs#pin: pid.'PID.3'.'CX.1',
					cs#visit_no: if(!isEmpty(pid.'PID.18'.'CX.1'))pid.'PID.18'.'CX.1' else pid.'PID.19',
					cs#facility: pid.'PID.18'.'CX.4'.'HD.1'
				},
				cs#slb: {
					slb#charges: {
						(payload..*'FT1' default [] map {
							slb#charge: {
								slb#charge_flag: $.'FT1.6',
								slb#charge_mservice_code: $.'FT1.7'.'CE.1',
								slb#charge_alt_desc: if (!isEmpty($.'FT1.7'.'CE.2')) $.'FT1.7'.'CE.2' else $.'FT1.8',
								slb#charge_quantity: if (!isEmpty(startDateTime) and !isEmpty(endDateTime) and !isEmpty(literPerMinute)) (endLocalDateTime - startLocalDateTime) as Number {unit: "minutes"}
													 else $.'FT1.10',
								slb#charge_amount: $.'FT1.11'.'CP.1'.'MO.1',
								slb#charge_unit_price: $.'FT1.12'.'CP.1'.'MO.1',
								slb#charge_dept_code: $.'FT1.13'.'CE.1',
								slb#charge_patient_loc: $.'FT1.16'.'PL.1',
								slb#charge_order_no: $.'FT1.23'.'EI.1',
								slb#charge_proc_code: $.'FT1.25'.'CE.1',
								(slb#charge_proc_code_modifier: (valueSet($.'FT1.26')) joinBy "~") if (!isEmpty($.'FT1.26')),
								(slb#bill_process: zc1.'ZC1.5') if(upper(zc1.'ZC1.3') ~= Mule::p('obx-identifier.bill-process')),
								slb#charge_start_datetime: startLocalDateTime as String {format : slbDateFormat},
								slb#charge_end_datetime: endLocalDateTime as String {format : slbDateFormat},
								slb#charge_lpm: literPerMinute
							}
						}),
						slb#control_id: payload..'MSH.10'[0],
						slb#sending_app: payload..'MSH.3'[0].'HD.1'
					}
				}
			}
		}
	},
	udto#EventKey: Mule::p('event-keys.dft')
}