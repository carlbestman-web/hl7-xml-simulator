"use strict";

class InvalidHl7Error extends Error {}

class ParsedHl7 {
    constructor(segments) {
        this.allSegments = segments;
    }

    firstSegment(segmentName) {
        return this.allSegments.find(segment => segment.startsWith(`${segmentName}|`)) || "";
    }

    segments(segmentName) {
        return this.allSegments.filter(segment => segment.startsWith(`${segmentName}|`));
    }

    field(segmentName, fieldNumber) {
        return this.fieldFromSegment(this.firstSegment(segmentName), fieldNumber);
    }

    fieldFromSegment(segment, fieldNumber) {
        if (!segment || !segment.trim()) return "";
        const fields = segment.split("|");

        // MSH-1 is the field separator. Because the separator itself is not a
        // normal split field, MSH fields after it use fieldNumber - 1.
        if (segment.startsWith("MSH|")) {
            if (fieldNumber === 1) return "|";
            const index = fieldNumber - 1;
            return index >= 0 && index < fields.length ? fields[index] : "";
        }

        return fieldNumber >= 0 && fieldNumber < fields.length ? fields[fieldNumber] : "";
    }

    component(fieldValue, componentNumber) {
        if (!fieldValue || !fieldValue.trim()) return "";
        const components = fieldValue.split("^");
        const index = componentNumber - 1;
        return index >= 0 && index < components.length ? components[index] : "";
    }

    obxValue(identifier) {
        for (const obx of this.segments("OBX")) {
            const obx3 = this.fieldFromSegment(obx, 3);
            const obx31 = this.component(obx3, 1);
            if (identifier.toLowerCase() === obx31.toLowerCase()) {
                return this.fieldFromSegment(obx, 5);
            }
        }
        return "";
    }
}

function parseHl7(hl7) {
    if (typeof hl7 !== "string" || !hl7.trim()) {
        throw new InvalidHl7Error("HL7 message is empty.");
    }

    const normalized = hl7.replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim();
    const lines = normalized.split("\n");
    if (!lines.length || !lines[0].startsWith("MSH|")) {
        throw new InvalidHl7Error("HL7 message must start with an MSH segment.");
    }

    return new ParsedHl7(lines.map(line => line.trim()).filter(Boolean));
}

function xmlEscape(value) {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&apos;");
}

function transformOrm(hl7) {
    const parsed = parseHl7(hl7);
    const controlId = parsed.field("MSH", 10);
    const pin = parsed.component(parsed.field("PID", 3), 1);
    const pid18 = parsed.field("PID", 18);
    const pv119 = parsed.field("PV1", 19);
    const visitNo = parsed.component(pid18, 1) || parsed.component(pv119, 1);
    const facility = parsed.component(pid18, 4);
    const ciNo = parsed.component(parsed.field("ORC", 2), 1);
    const requestingUnit = parsed.component(parsed.field("PV1", 3), 1);
    const orderStatus = parsed.field("ORC", 5);
    const compoundOrderId = parsed.obxValue("CHRG_SLB_COMPOUND_ID");

    return `<?xml version="1.0" encoding="UTF-8"?>
<udto:UDTO xmlns:udto="http://slmc.com.ph/udto/"
           xmlns:cs="http://slmc.com.ph/slmc_cs/"
           xmlns:slb="http://slmc.com.ph/slb/">
  <udto:OriginalRequest>
    <udto:OriginalRequestPayload>
      <udto:slmc_cs>
        <cs:common>
          <cs:pin>${xmlEscape(pin)}</cs:pin>
          <cs:visit_no>${xmlEscape(visitNo)}</cs:visit_no>
          <cs:facility>${xmlEscape(facility)}</cs:facility>
        </cs:common>
        <cs:slb>
          <slb:orders>
            <slb:control_id>${xmlEscape(controlId)}</slb:control_id>
            <slb:order>
              <slb:ci_no>${xmlEscape(ciNo)}</slb:ci_no>
              <slb:order_grp_no>${xmlEscape(ciNo)}</slb:order_grp_no>
              <slb:requesting_unit>${xmlEscape(requestingUnit)}</slb:requesting_unit>
              <slb:order_dtl>
                <slb:scm_order_status>${xmlEscape(orderStatus)}</slb:scm_order_status>
              </slb:order_dtl>
            </slb:order>
          </slb:orders>
        </cs:slb>

        <study_only_generic_supplies>
          <compound_order_id>${xmlEscape(compoundOrderId)}</compound_order_id>
        </study_only_generic_supplies>

      </udto:slmc_cs>
    </udto:OriginalRequestPayload>
  </udto:OriginalRequest>
  <udto:EventKey>emr-to-slb-new-order</udto:EventKey>
</udto:UDTO>`;
}

const input = document.getElementById("hl7Input");
const output = document.getElementById("xmlOutput");
const status = document.getElementById("status");
const copyButton = document.getElementById("copyButton");

document.getElementById("transformButton").addEventListener("click", () => {
    status.textContent = "Transforming...";
    status.className = "";
    output.textContent = "";
    copyButton.disabled = true;

    try {
        output.textContent = transformOrm(input.value);
        status.textContent = "Transformation successful.";
        status.className = "success";
        copyButton.disabled = false;
    } catch (error) {
        status.textContent = error instanceof InvalidHl7Error ? error.message : "Transformation failed.";
        status.className = "error";
    }
});

document.getElementById("clearButton").addEventListener("click", () => {
    input.value = "";
    output.textContent = "";
    status.textContent = "";
    status.className = "";
    copyButton.disabled = true;
    input.focus();
});

copyButton.addEventListener("click", async () => {
    try {
        await navigator.clipboard.writeText(output.textContent);
        status.textContent = "XML copied to clipboard.";
        status.className = "success";
    } catch {
        status.textContent = "Copy was blocked by the browser. Select the XML and copy it manually.";
        status.className = "error";
    }
});
