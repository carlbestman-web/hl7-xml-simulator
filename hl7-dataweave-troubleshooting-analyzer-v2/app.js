"use strict";

class Hl7Error extends Error {}

class Hl7 {
  constructor(text){
    const cleaned = text.replace(/[\x0b\x1c]/g,"").replace(/\r\n/g,"\n").replace(/\r/g,"\n").trim();
    this.lines = cleaned.split("\n").map(x=>x.trim()).filter(Boolean);
    if(!this.lines.length || !this.lines[0].startsWith("MSH|")) throw new Hl7Error("Message must begin with MSH|.");
  }
  segments(name){ return this.lines.filter(x=>x.startsWith(name+"|")); }
  first(name){ return this.segments(name)[0] || ""; }
  fieldFrom(segment,n){
    if(!segment) return "";
    const a=segment.split("|");
    if(segment.startsWith("MSH|")){ if(n===1) return "|"; return a[n-1] ?? ""; }
    return a[n] ?? "";
  }
  field(seg,n){ return this.fieldFrom(this.first(seg),n); }
  comp(value,n){ return (value||"").split("^")[n-1] ?? ""; }
  sub(value,n){ return (value||"").split("&")[n-1] ?? ""; }
  c(seg,field,comp){ return this.comp(this.field(seg,field),comp); }
  cs(seg,field,comp,sub){ return this.sub(this.comp(this.field(seg,field),comp),sub); }
  all(seg,field,comp){ return this.segments(seg).map(s=> comp ? this.comp(this.fieldFrom(s,field),comp) : this.fieldFrom(s,field)); }
  obxById(id){ return this.segments("OBX").find(s=>this.comp(this.fieldFrom(s,3),1).toUpperCase()===String(id).toUpperCase()) || ""; }
  messageType(){ return this.comp(this.field("MSH",9),1); }
  trigger(){ return this.comp(this.field("MSH",9),2); }
  event(){ return `${this.messageType()}_${this.trigger()}`; }
}

const mappings={
  patientTransfer:{file:"patientTransferMapping.dwl",label:"Patient Transfer / ADT",events:["ADT_A02","ADT_A06","ADT_A07","ADT_A08"],description:"Consumes PV1-3 as new location and PV1-6 as previous location; builds transfer/encounter DB payloads."},
  newOrder:{file:"billingNewOrderMapping.dwl",label:"ORM New Order",events:["ORM_O01"],orc:["NW"],description:"Builds SLB new-order XML from PID/PV1/ORC/OBR/RXO/OBX plus prerequisite Mule variables."},
  cancelOrder:{file:"billingCancelOrderMapping.dwl",label:"ORM Cancel Order",events:["ORM_O01"],orc:["CA"],description:"Builds SLB adjustment/cancellation XML with ADJ04."},
  adjustedOrder:{file:"billingAdjustedOrderMapping.dwl",label:"ORM Adjusted Order",events:["ORM_O01"],orc:["XO"],description:"Builds SLB adjusted-order XML with ADJ01 plus updated order detail fields."},
  officialResult:{file:"officialResultMapping.dwl",label:"ORU Official Result",events:["ORU_R01"],description:"Builds official-result XML and correlates result to order detail number/service code."},
  dft:{file:"finalChargesMapping.dwl",label:"DFT Final Charges",events:["DFT_P03"],description:"Maps every FT1 charge into SLB charge XML; also reads selected OBX/ZC1 values."}
};

function chooseMapping(h){
  const ev=h.event();
  if(ev==="ORM_O01"){
    const oc=h.c("ORC",1,1) || h.field("ORC",1);
    if(oc==="CA") return mappings.cancelOrder;
    if(oc==="XO") return mappings.adjustedOrder;
    return mappings.newOrder;
  }
  if(ev==="ORU_R01") return mappings.officialResult;
  if(ev==="DFT_P03") return mappings.dft;
  if(ev.startsWith("ADT_")) return mappings.patientTransfer;
  return null;
}

function row(path,value,dw,use,status="ok",note=""){ return {path,value:value??"",dw,use,status,note}; }
function missing(v){ return v===undefined || v===null || String(v).trim()===""; }
function looksDescription(v){ return /[A-Za-z ]/.test(v||"") && !/^\d+$/.test((v||"").trim()); }
function esc(s){ return String(s??"").replace(/[&<>\"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c])); }
function xmlTag(name,val,indent="  "){ return `${indent}<${name}>${esc(val)}</${name}>`; }

function common(h){
  const pid18=h.field("PID",18), pv119=h.field("PV1",19);
  return {pin:h.c("PID",3,1),visit:h.comp(pid18,1)||h.comp(pv119,1),facility:h.comp(pid18,4),eventDate:h.field("MSH",7),control:h.field("MSH",10)};
}

function analyzeTransfer(h){
  const c=common(h), prevNU=h.c("PV1",6,1), newNU=h.c("PV1",3,1), prevRoom=h.c("PV1",6,2), newRoom=h.c("PV1",3,2), newBed=h.c("PV1",3,3), ptype=h.field("PV1",2);
  const rows=[
    row("PV1-6.1",prevNU,"var prevNursingUnit = pv1.'PV1.6'.'PL.1'","getTransferType(); txn_adm_roomtran_rqst.prev_nursing_unit",missing(prevNU)?"warn":(looksDescription(prevNU)?"warn":"ok")),
    row("PV1-3.1",newNU,"var newNursingUnit = pv1.'PV1.3'.'PL.1'","getTransferType(); txn_adm_roomtran_rqst.new_nursing_unit; txn_adm_in.nursing_unit",missing(newNU)?"error":"ok"),
    row("PV1-6.2",prevRoom,"var prevRoomNo = pv1.'PV1.6'.'PL.2'","Previous room",missing(prevRoom)?"info":"ok"),
    row("PV1-3.2",newRoom,"var newRoomNo = pv1.'PV1.3'.'PL.2'","New room",missing(newRoom)?"info":"ok"),
    row("PV1-3.3",newBed,"var newBedNo = pv1.'PV1.3'.'PL.3'","New bed",missing(newBed)?"info":"ok"),
    row("PV1-2",ptype,"var patientType = payload..'PV1.2'[0]","Patient type / encounter logic",missing(ptype)?"warn":"ok"),
    row("PID-18.1 / PV1-19.1",c.visit,"vars.visitNo (prepared by flow)","Visit correlation",missing(c.visit)?"error":"ok")
  ];
  const f=[];
  if(missing(newNU)) f.push({level:"error",title:"New nursing unit is empty",detail:"patientTransferMapping.dwl reads PV1-3.1 as newNursingUnit and uses it in transfer/room transaction updates."});
  if(!missing(prevNU)&&looksDescription(prevNU)) f.push({level:"warn",title:`Review PV1-6.1 value: “${prevNU}”`,detail:"The mapping does not treat PV1-6.1 as free text. It assigns it directly to prevNursingUnit, compares it in getTransferType(), and can write it to prev_nursing_unit. Confirm this value exists in the SLB nursing-unit/reference context. A description such as PORTAL GC can therefore affect transfer processing even though the later ORU mapping does not read PV1-6."});
  if(!missing(prevNU)&&!missing(newNU)&&prevNU!==newNU) f.push({level:"warn",title:"Previous and new nursing units differ",detail:`DataWeave sees a movement from ${prevNU} to ${newNU}. For transfer events, getTransferType() can classify this as a nursing-unit transfer.`});
  if(!f.length) f.push({level:"ok",title:"No obvious transfer-field issue detected",detail:"The key PV1 location fields consumed by patientTransferMapping.dwl are populated. Continue with generated DB payload/log validation if the transaction still fails."});
  const out=JSON.stringify({mapping:"patientTransferMapping.dwl",scriptParameters:{triggerEvent:h.event(),visitNo:c.visit},derived:{prevNursingUnit:prevNU,newNursingUnit:newNU,prevRoomNo:prevRoom,newRoomNo:newRoom,newBedNo:newBed,patientType:ptype},txn_adm_roomtran_rqst:{visit_no:c.visit,prev_nursing_unit:prevNU,prev_roomno:prevRoom,new_nursing_unit:newNU,new_roomno:newRoom,new_bedno:newBed}},null,2);
  return {rows,findings:f,output:out};
}

function analyzeOfficial(h){
  const c=common(h), order=h.c("ORC",2,1)||h.c("OBR",2,1), svc=h.c("OBR",4,1), od=h.c("ORC",9,1), obr32=h.field("OBR",32), sig=h.sub(h.comp(obr32,1),1);
  const rows=[
    row("MSH-7.1",c.eventDate,"msh7 = standardDate(MSH.7.TS.1)","cs:eventDateTime",missing(c.eventDate)?"error":"ok"),
    row("PID-3.1",c.pin,"pid.'PID.3'.'CX.1'","cs:pin",missing(c.pin)?"error":"ok"),
    row("PID-18.1 → PV1-19.1 fallback",c.visit,"filter non-null; take [0]","cs:visit_no",missing(c.visit)?"error":"ok"),
    row("PID-18.4.1",c.facility,"pid.'PID.18'.'CX.4'.'HD.1'","cs:facility",missing(c.facility)?"error":"ok"),
    row("ORC-2.1 → OBR-2.1 fallback",order,"filter non-null; take [0]","official_order_dtl_no",missing(order)?"error":"ok"),
    row("OBR-4.1",svc,"obr.'OBR.4'.'CE.1'","official_service_code",missing(svc)?"error":"ok"),
    row("ORC-9.1",od,"standardDate(orc.'ORC.9'.'TS.1')","official_date",missing(od)?"warn":"ok"),
    row("OBR-32.1.1",sig,"obr.'OBR.32'.'NDL.1'.'CNN.1'","official_assigned_signatory2",missing(sig)?"warn":"ok")
  ];
  const f=[];
  rows.filter(r=>r.status==="error").forEach(r=>f.push({level:"error",title:`Missing ${r.use}`,detail:`${r.path} is empty but officialResultMapping.dwl uses it to build the official-result payload.`}));
  if(missing(sig)) f.push({level:"warn",title:"OBR-32 signatory path is empty",detail:"The mapping explicitly reads OBR-32.1.1 for official_assigned_signatory2. If SLB requires a signatory, verify the source ORU and generated XML."});
  if(!f.length) f.push({level:"ok",title:"Core ORU mapping fields are populated",detail:"Order, visit, facility and service code are available to officialResultMapping.dwl. Compare the service code/order detail against the original ORM and SLB record if rejection persists."});
  const out=`<official_result>\n${xmlTag("official_order_dtl_no",order,"  ")}\n${xmlTag("official_service_code",svc,"  ")}\n${xmlTag("official_date",od,"  ")}\n${xmlTag("official_assigned_signatory2",sig,"  ")}\n</official_result>`;
  return {rows,findings:f,output:out};
}

function analyzeNewOrder(h,mode){
  const c=common(h), order=h.c("ORC",2,1), reqUnit=h.c("PV1",3,1), doctor=h.c("ORC",12,1), status=h.field("ORC",5), qty=h.c("ORC",7,1), obrSvc=h.c("OBR",4,1)||h.c("RXO",1,1), reasonCode=h.c("ORC",16,1), reasonText=h.c("ORC",16,2);
  const base=[
    row("PID-3.1",c.pin,"pid.'PID.3'.'CX.1'","cs:pin",missing(c.pin)?"error":"ok"),
    row("PID-18.1 → PV1-19.1 fallback",c.visit,"filter non-null; take [0]","cs:visit_no",missing(c.visit)?"error":"ok"),
    row("PID-18.4.1",c.facility,"pid.'PID.18'.'CX.4'.'HD.1'","cs:facility",missing(c.facility)?"error":"ok"),
    row("ORC-2.1",order,"orc.'ORC.2'.'EI.1'",mode==="new"?"ci_no / order_grp_no / order_dtl_no":"adj_order_dtl_no",missing(order)?"error":"ok"),
    row("PV1-3.1",reqUnit,"pv1.'PV1.3'.'PL.1'","requesting_unit (new order) / guest performing unit",missing(reqUnit)?"warn":"ok"),
    row("ORC-12.1",doctor,"orc.'ORC.12'.'XCN.1'","requesting doctor",missing(doctor)?"warn":"ok"),
    row("ORC-5",status,"orc.'ORC.5'","scm_order_status",missing(status)?"warn":"ok")
  ];
  if(mode==="new"){
    base.push(row("OBR-4.1 / RXO-1.1",obrSvc,"flow derives vars.serviceCode before DWL","mservice_code = vars.serviceCode","info","Requires Mule prerequisite/routing context"));
    base.push(row("ORC-7.1",qty,"orc.'ORC.7'.'TQ.1'.'CQ.1'","quantity",missing(qty)?"warn":"ok"));
  } else {
    base.push(row("ORC-16.1",reasonCode,"orc.'ORC.16'.'CE.1'","adj_can_document_no",missing(reasonCode)?"warn":"ok"));
    base.push(row("ORC-16.2",reasonText,"orc.'ORC.16'.'CE.2'","adj_reason",missing(reasonText)?"warn":"ok"));
  }
  const f=[];
  base.filter(r=>r.status==="error").forEach(r=>f.push({level:"error",title:`Missing ${r.use}`,detail:`${r.path} is empty in a field directly consumed by the mapping.`}));
  if(mode==="new" && missing(doctor)) f.push({level:"warn",title:"Requesting doctor is empty",detail:"For a normal non-guest order, billingNewOrderMapping.dwl uses ORC-12.1 as req_doctor."});
  if(mode==="new") f.push({level:"warn",title:"Service code cannot be fully reproduced from HL7 alone",detail:`The DataWeave output uses vars.serviceCode, which is prepared by the Mule flow/prerequisite logic. HL7 candidate OBR-4.1/RXO-1.1 is “${obrSvc||"(empty)"}”. Compare this with the runtime Billing New Order XML or prerequisite response.`});
  if(!f.some(x=>x.level==="error") && mode!=="new") f.push({level:"ok",title:"Core adjustment/cancellation correlation fields are available",detail:"Order/visit/facility can be mapped. Review ORC-16 reason/document values and the existing SLB order state for business rejection."});
  const out= mode==="new" ? `<orders>\n${xmlTag("control_id",c.control,"  ")}\n  <order>\n${xmlTag("ci_no",order,"    ")}\n${xmlTag("order_grp_no",order,"    ")}\n${xmlTag("requesting_unit",reqUnit,"    ")}\n${xmlTag("req_doctor",doctor,"    ")}\n    <order_dtl>\n${xmlTag("order_dtl_no",order,"      ")}\n${xmlTag("mservice_code","[vars.serviceCode - requires Mule context]","      ")}\n${xmlTag("scm_order_status",status,"      ")}\n${xmlTag("quantity",qty,"      ")}\n    </order_dtl>\n  </order>\n</orders>` : `<adj_cancelled_order>\n${xmlTag("adj_can_document_no",reasonCode,"  ")}\n${xmlTag("adj_order_dtl_no",order,"  ")}\n${xmlTag("adj_reason",reasonText,"  ")}\n${xmlTag("adj_type",mode==="cancel"?"ADJ04":"ADJ01","  ")}\n${xmlTag("scm_order_status",status,"  ")}\n</adj_cancelled_order>`;
  return {rows:base,findings:f,output:out};
}

function analyzeDft(h){
  const c=common(h), ft1s=h.segments("FT1");
  const rows=[
    row("PID-3.1",c.pin,"pid.'PID.3'.'CX.1'","cs:pin",missing(c.pin)?"error":"ok"),
    row("PID-18.1 → PID-19 fallback",h.c("PID",18,1)||h.field("PID",19),"PID-18.1 else PID-19","cs:visit_no",missing(h.c("PID",18,1)||h.field("PID",19))?"error":"ok"),
    row("PID-18.4.1",c.facility,"pid.'PID.18'.'CX.4'.'HD.1'","cs:facility",missing(c.facility)?"error":"ok"),
    row("MSH-10",c.control,"payload..'MSH.10'[0]","charges.control_id",missing(c.control)?"warn":"ok")
  ];
  ft1s.forEach((s,i)=>{
    const n=i+1;
    [[6,"charge_flag"],[7,"charge_mservice_code",1],[10,"charge_quantity"],[11,"charge_amount",1],[12,"charge_unit_price",1],[13,"charge_dept_code",1],[16,"charge_patient_loc",1],[23,"charge_order_no",1],[25,"charge_proc_code",1]].forEach(([f,use,co])=>{
      const v=co?h.comp(h.fieldFrom(s,f),co):h.fieldFrom(s,f);
      rows.push(row(`FT1[${n}]-${f}${co?`.${co}`:""}`,v,`$.'FT1.${f}'${co?" component "+co:""}`,use,([7,23].includes(f)&&missing(v))?"error":(missing(v)?"info":"ok")));
    });
  });
  const f=[];
  if(!ft1s.length) f.push({level:"error",title:"No FT1 segment found",detail:"finalChargesMapping.dwl maps payload..*'FT1'. Without FT1 there is no SLB charge to create."});
  rows.filter(r=>r.status==="error").slice(0,8).forEach(r=>f.push({level:"error",title:`Missing ${r.use}`,detail:`${r.path} is empty in a DFT charge mapping.`}));
  f.push({level:"warn",title:"OBX-derived start/stop/LPM values depend on configuration",detail:"finalChargesMapping.dwl filters OBX-3 using Mule properties for start-date-time, stop-date-time and liter-per-minute. The sanitized project does not contain the production identifiers, so this browser analyzer does not guess them."});
  if(ft1s.length && !f.some(x=>x.level==="error")) f.unshift({level:"ok",title:`${ft1s.length} FT1 charge segment(s) detected`,detail:"Core DFT charge fields can be traced. Review each FT1 row below and compare the reconstructed values with the generated SLB XML/log."});
  const charges=ft1s.map(s=>({charge_flag:h.fieldFrom(s,6),charge_mservice_code:h.comp(h.fieldFrom(s,7),1),charge_alt_desc:h.comp(h.fieldFrom(s,7),2)||h.fieldFrom(s,8),charge_quantity:h.fieldFrom(s,10),charge_amount:h.comp(h.fieldFrom(s,11),1),charge_unit_price:h.comp(h.fieldFrom(s,12),1),charge_dept_code:h.comp(h.fieldFrom(s,13),1),charge_patient_loc:h.comp(h.fieldFrom(s,16),1),charge_order_no:h.comp(h.fieldFrom(s,23),1),charge_proc_code:h.comp(h.fieldFrom(s,25),1)}));
  return {rows,findings:f,output:JSON.stringify({mapping:"finalChargesMapping.dwl",pin:c.pin,visit_no:h.c("PID",18,1)||h.field("PID",19),facility:c.facility,control_id:c.control,charges},null,2)};
}

function analyze(h,m){
  if(m===mappings.patientTransfer) return analyzeTransfer(h);
  if(m===mappings.officialResult) return analyzeOfficial(h);
  if(m===mappings.dft) return analyzeDft(h);
  if(m===mappings.cancelOrder) return analyzeNewOrder(h,"cancel");
  if(m===mappings.adjustedOrder) return analyzeNewOrder(h,"adjust");
  return analyzeNewOrder(h,"new");
}

const $=id=>document.getElementById(id);
const els={input:$("hl7Input"),status:$("status"),summary:$("summaryPanel"),cards:$("summaryCards"),findingsPanel:$("findingsPanel"),findings:$("findings"),tracePanel:$("tracePanel"),traceBody:$("traceBody"),outputPanel:$("outputPanel"),output:$("mappingOutput"),sourcePanel:$("sourcePanel"),source:$("sourceRef")};
let lastTrace="";

function showPanels(){ [els.summary,els.findingsPanel,els.tracePanel,els.outputPanel,els.sourcePanel].forEach(x=>x.classList.remove("hidden")); }
function pill(status){ const txt={ok:"OK",warn:"REVIEW",error:"MISSING",info:"CONTEXT"}[status]||status; return `<span class="pill ${status}">${txt}</span>`; }
function render(){
  try{
    const h=new Hl7(els.input.value), m=chooseMapping(h);
    if(!m) throw new Hl7Error(`No mapping configured yet for ${h.event()}. Current v2 covers ADT transfer, ORM NW/CA/XO, ORU R01 and DFT P03.`);
    const r=analyze(h,m); showPanels();
    const c=common(h);
    els.cards.innerHTML=[['Message',h.event()],['Mapping',m.file],['Visit',c.visit||'(empty)'],['Order / Control',h.c('ORC',2,1)||c.control||'(empty)']].map(([a,b])=>`<div class="summary-card"><div class="label">${esc(a)}</div><div class="value">${esc(b)}</div></div>`).join('');
    els.findings.innerHTML=r.findings.map(x=>`<div class="finding ${x.level}"><div class="title">${esc(x.title)}</div><div class="detail">${esc(x.detail)}</div></div>`).join('');
    els.traceBody.innerHTML=r.rows.map(x=>`<tr><td><code>${esc(x.path)}</code></td><td><code>${esc(x.value||'(empty)')}</code></td><td><code>${esc(x.dw)}</code></td><td>${esc(x.use)}${x.note?`<br><small>${esc(x.note)}</small>`:''}</td><td>${pill(x.status)}</td></tr>`).join('');
    lastTrace=r.rows.map(x=>`${x.path}\t${x.value||'(empty)'}\t${x.dw}\t${x.use}\t${x.status}`).join('\n');
    els.output.textContent=r.output;
    els.source.textContent=`Detected: ${h.event()}\nMapping: mappings/${m.file}\n\n${m.description}\n\nTroubleshooting method:\n1. Find the suspicious HL7 field.\n2. Follow the DataWeave variable/expression shown in the trace.\n3. Follow where that value is written or used.\n4. Compare with the generated Mule payload / SLB DB or rejection log.\n\nImportant: this static tool reproduces visible field mappings and selected conditions. It does not execute Mule DataWeave, private property values, prerequisite HTTP calls, cache data, or database state.`;
    els.status.textContent=`Analyzed with ${m.file}`; els.status.className='status ok';
  }catch(e){ els.status.textContent=e.message||'Analysis failed'; els.status.className='status bad'; }
}

$("analyzeBtn").addEventListener("click",render);
$("clearBtn").addEventListener("click",()=>{els.input.value='';els.status.textContent='';[els.summary,els.findingsPanel,els.tracePanel,els.outputPanel,els.sourcePanel].forEach(x=>x.classList.add('hidden'));els.input.focus();});
$("copyTraceBtn").addEventListener("click",()=>navigator.clipboard.writeText(lastTrace));
$("copyOutputBtn").addEventListener("click",()=>navigator.clipboard.writeText(els.output.textContent));
$("sampleBtn").addEventListener("click",()=>{els.input.value=`MSH|^~\\&|SCM|SCM|HL7ADT_OUT||20260902175132||ADT^A02|SYNTH0001|P|2.5\rEVN|A02|20260902175124\rPID||SYNTH001^^^EPI|SYNTH001^^^MRN||TEST^PATIENT||||||||||||||VISIT001^^^2\rPV1||O|0005^^^2|||PORTAL GC^^^2|||||||||||||VISIT001^^^2`;render();});
