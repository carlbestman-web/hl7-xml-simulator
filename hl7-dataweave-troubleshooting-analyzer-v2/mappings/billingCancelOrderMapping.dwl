%dw 2.0
output application/xml
import standardDate from modules::Utility

ns udto http://slmc.com.ph/udto/
ns cs http://slmc.com.ph/slmc_cs/
ns slb http://slmc.com.ph/slb/

var orc = payload..'ORC'[0]
var pid = payload..'PID'[0]
var pv1 = payload..'PV1'[0]
var msh = payload..'MSH'[0]
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
						slb#orders: {
							slb#control_id: msh.'MSH.10',
							slb#req_doctor: orc.'ORC.12'.'XCN.1',
							slb#adj_cancelled_order: {
								slb#adj_can_document_no: orc.'ORC.16'.'CE.1',
								slb#adj_order_dtl_no: orc.'ORC.2'.'EI.1',
								slb#adj_reason: orc.'ORC.16'.'CE.2',
								slb#adj_type: "ADJ04",
								slb#cm_flag: "",
								slb#scm_order_status: orc.'ORC.5'
							}
						}
					}
				}
			}
		},
		udto#EventKey: Mule::p('event-keys.emr-to-slb-adjcan-order')
	}
}