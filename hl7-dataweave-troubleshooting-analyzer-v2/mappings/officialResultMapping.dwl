%dw 2.0
output application/xml
import standardDate from modules::Utility

ns udto http://slmc.com.ph/udto/
ns cs http://slmc.com.ph/slmc_cs/
ns slb http://slmc.com.ph/slb/

var pid = payload..'PID'[0]
var pv1 = payload..'PV1'[0]
var orc = payload..'ORC'[0]
var obr = payload..'OBR'[0]
var obx = payload..'OBX'[0]
var msh7 = standardDate(payload..'MSH.7'[0].'TS.1')
---
{
	udto#UDTO: {
		udto#OriginalRequest: {
			udto#OriginalRequestPayload: {
				udto#slmc_cs: {
					cs#common: {
						cs#eventDateTime: msh7,
						cs#pin: pid.'PID.3'.'CX.1',
						cs#visit_no: ([pid.'PID.18'.'CX.1', pv1.'PV1.19'.'CX.1'] filter ($ != null))[0],
						cs#facility: pid.'PID.18'.'CX.4'.'HD.1'
					},
					cs#slb: {
						slb#official_result: {
							slb#official_order_dtl_no: ([orc.'ORC.2'.'EI.1', obr.'OBR.2'.'EI.1'] filter ($ != null))[0],
							slb#official_service_code: obr.'OBR.4'.'CE.1',
							slb#official_date: standardDate(orc.'ORC.9'.'TS.1'),
							slb#official_assigned_signatory2: obr.'OBR.32'.'NDL.1'.'CNN.1'
						}
					}
				}
			}
		},
		udto#EventKey: Mule::p('event-keys.emr-to-slb-official-results')
	}
}