%dw 2.0
output application/xml
import standardDate from modules::Utility

ns udto http://slmc.com.ph/udto/
ns cs http://slmc.com.ph/slmc_cs/
ns slb http://slmc.com.ph/slb/

var orc = payload..'ORC'[0]
var pid = payload..'PID'[0]
var pv1 = payload..'PV1'[0]
var obr = payload..'OBR'[0]
var rxo = payload..'RXO'[0]
var msh = payload..'MSH'[0]
var obx = payload..*'OBX'

var msh7 = standardDate(payload..'MSH.7'[0].'TS.1')


var iodineDosageAttribute = obx filter (upper(p('obx-identifier.iodine-dosage')) contains (upper($.'OBX.3'.'CE.1')))
var pdlPkAttribute = obx filter (upper(p('obx-identifier.pdl-pk-att')) contains (upper($.'OBX.3'.'CE.1')))
var pigmentAttribute = obx filter (upper(p('obx-identifier.pigment-laser')) contains (upper($.'OBX.3'.'CE.1')))
var ivigAttribute = obx filter (upper(p('obx-identifier.ivig-treat')) contains (upper($.'OBX.3'.'CE.1')))
var priceAttribute = obx filter (p('order-price-attributes') contains (upper($.'OBX.3'.'CE.1')))
var guestRoomNo =  (obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.reg-room-number'))))[0].'OBX.5' default ''

var doctorName = (orc.'ORC.12'.'XCN.2'.'FN.1' default '') ++ (if(!isEmpty(orc.'ORC.12'.'XCN.2'.'FN.1')) ", " else "") ++ (orc.'ORC.12'.'XCN.3' default '') ++ " " ++ (orc.'ORC.12'.'XCN.4' default '')

var isGuestOrder = vars.isGuestOrder
var guestRoomDesc = if(isGuestOrder) (vars.prerequisiteInfo.mServiceDescription ++ ' - ' ++  guestRoomNo) else ''

var isStatPortable = vars.isStatPortable
var portableAttribute = if (isStatPortable) [{ 'OBX.3': { 'CE.1': 'STAT-Portable' }, 'OBX.5': 'Y' }] else obx filter (upper(p('obx-identifier.portable')) contains (upper($.'OBX.3'.'CE.1')))

var suppressCharge = ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.suppressed-charge'))))[0].'OBX.5') default ''

var performingUnit = if (obr.'OBR.4'.'CE.1' ~= p('obr-identifier.chrg-fnd-sp')) p('performing-unit.food-and-nutrition')
					else ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.performing-unit'))))[0].'OBX.5')
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
							slb#adj_cancelled_order: {
								slb#adj_can_document_no: orc.'ORC.16'.'CE.1',
								slb#adj_order_dtl_no: orc.'ORC.2'.'EI.1',
								slb#adj_quantity: if(!isGuestOrder) orc.'ORC.7'.'TQ.1'.'CQ.1' else ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.reg-rate-multiplier'))))[0].'OBX.5'),
								slb#adj_reason: orc.'ORC.16'.'CE.2',
								slb#validated_datetime: if (!isEmpty(orc.'ORC.9'.'TS.1')) standardDate(orc.'ORC.9'.'TS.1') else '',
								slb#adj_type: "ADJ01",
								slb#cm_flag: "",
								slb#scm_order_status: orc.'ORC.5'
							},
							slb#order: {
								slb#performing_unit: if(!isGuestOrder) performingUnit else pv1.'PV1.3'.'PL.1',
								slb#req_doctor: if(!isGuestOrder) orc.'ORC.12'.'XCN.1' else pv1.'PV1.7'.'XCN.1',
								slb#req_doctor_name: doctorName,
								slb#order_dtl: {
									slb#mservice_code: if(!isGuestOrder) vars.serviceCode else ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.reg-accommodation-rate'))))[0].'OBX.5'),
									slb#description: if(!isGuestOrder) vars.description else guestRoomDesc,
									slb#laterality: ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.nsg-laterality'))))[0].'OBX.5'),
									slb#frequency_code: vars.prerequisiteInfo.frequencyCode,
									slb#start_datetime: if (!isEmpty(orc.'ORC.7'.'TQ.4'.'TS.1')) standardDate(orc.'ORC.7'.'TQ.4'.'TS.1') else '',
									slb#end_datetime: if (!isEmpty(orc.'ORC.7'.'TQ.5'.'TS.1')) standardDate(orc.'ORC.7'.'TQ.5'.'TS.1') else '',
									slb#priority_code: if(!isStatPortable) orc.'ORC.7'.'TQ.6' else '',
									slb#uom_code: rxo.'RXO.4'.'CE.1',
									slb#dose: rxo.'RXO.2',
									slb#route_code: ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.route-code'))))[0].'OBX.5'),
									slb#liter_per_minute:  ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.liter-per-minute'))))[0].'OBX.5'),
									slb#fio:  ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.fio'))))[0].'OBX.5'),
									slb#send_out:  ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.send-out'))))[0].'OBX.5'),
									slb#suppressed_charge:  if(['Y', 'YES'] contains upper(suppressCharge)) 'Y' else 'N',
									slb#prev_order_no:  ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.prev-order-no'))))[0].'OBX.5'),
									slb#or_ci:  ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.or-ci'))))[0].'OBX.5'),
									slb#adv_payment: if(!isEmpty(obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.slb-reason')) and upper($.'OBX.5') ~= upper(p('obx-identifier.adv-payment'))))) 'Y' else 'N',
									slb#package_id:  ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.charge-package-id'))))[0].'OBX.5'),
									slb#price: ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.charge-cost-price'))))[0].'OBX.5'),
									slb#order_setid: ((obx filter (upper($.'OBX.3'.'CE.1') ~= upper(p('obx-identifier.order-set')) and upper($.'OBX.3'.'CE.2') ~= upper(p('obx-identifier-text.order-set-id'))))[0].'OBX.5'),
									slb#attributes: {
										(priceAttribute map {
										slb#attribute: {
											slb#attribute_id: $.'OBX.3'.'CE.1',
											slb#attribute_value: $.'OBX.5'
											}
										}
							  		),
								  		(iodineDosageAttribute map {
											slb#attribute: {
												slb#attribute_id: p('attribute-type.dosage'),
												slb#attribute_value: $.'OBX.5'
											}
										}
								  			
								  		),
								  		(pdlPkAttribute map {
											slb#attribute: {
												slb#attribute_id: p('attribute-type.pulse'),
												slb#attribute_value: $.'OBX.5'
											}
										}
								  			
								  		),
								  		( pigmentAttribute map{
											slb#attribute: {
												slb#attribute_id: p('attribute-type.pigment'),
												slb#attribute_value: $.'OBX.5'
											}
										}
								  			
								  		),
								  		( ivigAttribute map{
											slb#attribute: {
												slb#attribute_id: p('attribute-type.ivig'),
												slb#attribute_value: $.'OBX.5'
											}
										}
								  			
								  		),
										( portableAttribute map {
											slb#attribute: {
												slb#attribute_id: if (isStatPortable) $.'OBX.3'.'CE.1' else p('attribute-type.portable'),
												slb#attribute_value: $.'OBX.5'
											}
										}
									
										)
							  		}
								}
							}
						}
					}
				}
			}
		},
		udto#EventKey: Mule::p('event-keys.emr-to-slb-adjcan-order')
	}
}