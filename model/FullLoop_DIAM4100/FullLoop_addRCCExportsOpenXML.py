"""Add RCC head voltage/current exports to AGL_FullLoop_DIAM4100.slx.

The complete-loop model already exports seven internal loop currents. This
patch adds explicit To Workspace exports at the DIAM4100 output head:

- i_RCC: instantaneous current measured by the existing output Current
  Measurement block inside Diam4100_CCR.
- u_RCC: instantaneous voltage measured between the + and - external ports of
  Diam4100_CCR.
"""

from __future__ import annotations

import copy
import shutil
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET


THIS_DIR = Path(__file__).resolve().parent
TARGET_SLX = THIS_DIR / "AGL_FullLoop_DIAM4100.slx"
DIAM_SYSTEM = "simulink/systems/system_1294.xml"


def p(name: str, text: object) -> ET.Element:
    node = ET.Element("P", {"Name": name})
    node.text = str(text)
    return node


def find_p(elem: ET.Element, name: str) -> ET.Element | None:
    for child in elem.findall("P"):
        if child.attrib.get("Name") == name:
            return child
    return None


def set_p(elem: ET.Element, name: str, value: object) -> None:
    node = find_p(elem, name)
    if node is None:
        elem.append(p(name, value))
    else:
        node.text = str(value)


def to_workspace_block(name: str, sid: int, variable: str, position: tuple[int, int, int, int]) -> ET.Element:
    block = ET.Element("Block", {"BlockType": "ToWorkspace", "Name": name, "SID": str(sid)})
    ET.SubElement(block, "PortCounts", {"in": "1"})
    block.extend(
        [
            p("Position", f"[{position[0]}, {position[1]}, {position[2]}, {position[3]}]"),
            p("ZOrder", sid + 27000),
            p("VariableName", variable),
            p("MaxDataPoints", "inf"),
            p("SaveFormat", "Timeseries"),
            p("FixptAsFi", "on"),
            p("SampleTime", "-1"),
        ]
    )
    return block


def make_line(src: str, dst: str, zorder: int, *, connection: bool = False) -> ET.Element:
    line = ET.Element("Line", {"LineType": "Connection"} if connection else {})
    line.append(p("ZOrder", zorder))
    line.append(p("Src", src))
    line.append(p("Dst", dst))
    return line


def max_sid(*systems: ET.Element) -> int:
    value = 0
    for system in systems:
        for block in system.findall(".//Block"):
            try:
                value = max(value, int(block.attrib.get("SID", "0")))
            except ValueError:
                pass
    return value


def block_by_name(system: ET.Element, name: str) -> ET.Element | None:
    return next((block for block in system.findall("Block") if block.attrib.get("Name") == name), None)


def remove_existing(system: ET.Element) -> None:
    names = {"RCC Voltage Measurement", "ToWorkspace_u_RCC", "ToWorkspace_i_RCC"}
    sids_to_remove: set[str] = set()
    for block in list(system.findall("Block")):
        if block.attrib.get("Name") in names:
            sids_to_remove.add(block.attrib.get("SID", ""))
            system.remove(block)

    for line in list(system.findall("Line")):
        refs: list[str] = []
        for node in line.iter("P"):
            if node.attrib.get("Name") in {"Src", "Dst"} and node.text:
                refs.append(node.text.split("#", 1)[0])
        if any(ref in sids_to_remove for ref in refs):
            system.remove(line)


def add_branch(system: ET.Element, src: str, dst: str, zorder: int) -> bool:
    for line in system.findall("Line"):
        src_node = find_p(line, "Src")
        if src_node is None or src_node.text != src:
            continue

        dst_node = find_p(line, "Dst")
        if dst_node is not None and dst_node.text == dst:
            return True

        existing_branch_dsts = [
            branch_dst.text
            for branch_dst in line.findall("Branch/P[@Name='Dst']")
            if branch_dst.text
        ]
        if dst in existing_branch_dsts:
            return True

        if dst_node is not None:
            original_dst = dst_node.text
            line.remove(dst_node)
            branch = ET.SubElement(line, "Branch")
            branch.append(p("ZOrder", zorder))
            branch.append(p("Dst", original_dst))
            zorder += 1

        branch = ET.SubElement(line, "Branch")
        branch.append(p("ZOrder", zorder))
        branch.append(p("Dst", dst))
        return True
    return False


def patch(target: Path = TARGET_SLX) -> None:
    backup = target.with_name("AGL_FullLoop_DIAM4100.before_RCC_exports.slx")
    shutil.copy2(target, backup)

    with zipfile.ZipFile(target, "r") as zin:
        contents = {name: zin.read(name) for name in zin.namelist()}

    root = ET.fromstring(contents["simulink/systems/system_root.xml"])
    diam = ET.fromstring(contents[DIAM_SYSTEM])
    remove_existing(diam)

    voltage_template = block_by_name(diam, "Voltage Measurement")
    if voltage_template is None:
        raise RuntimeError("Voltage Measurement template not found inside Diam4100_CCR.")

    next_sid = max_sid(root, diam) + 1
    voltage_sid, u_sink_sid, i_sink_sid = next_sid, next_sid + 1, next_sid + 2

    voltage = copy.deepcopy(voltage_template)
    voltage.attrib["Name"] = "RCC Voltage Measurement"
    voltage.attrib["SID"] = str(voltage_sid)
    set_p(voltage, "Position", "[470, 222, 495, 246]")
    set_p(voltage, "ZOrder", voltage_sid + 27000)

    u_sink = to_workspace_block("ToWorkspace_u_RCC", u_sink_sid, "u_RCC", (540, 218, 620, 248))
    i_sink = to_workspace_block("ToWorkspace_i_RCC", i_sink_sid, "i_RCC", (500, 112, 580, 142))
    diam.append(voltage)
    diam.append(u_sink)
    diam.append(i_sink)

    # Existing output current measurement signal. Keep RMS/Irms path and add
    # the instantaneous current export as a branch.
    if not add_branch(diam, "7#out:1", f"{i_sink_sid}#in:1", 40401):
        diam.append(make_line("7#out:1", f"{i_sink_sid}#in:1", 40401))

    # Voltage sensor across the two external DIAM4100 electrical ports.
    if not add_branch(diam, "7#rconn:1", f"{voltage_sid}#lconn:1", 40402):
        diam.append(make_line("7#rconn:1", f"{voltage_sid}#lconn:1", 40402, connection=True))
    if not add_branch(diam, "6#rconn:2", f"{voltage_sid}#lconn:2", 40403):
        diam.append(make_line("6#rconn:2", f"{voltage_sid}#lconn:2", 40403, connection=True))
    diam.append(make_line(f"{voltage_sid}#out:1", f"{u_sink_sid}#in:1", 40404))

    sid_high = find_p(root, "SIDHighWatermark")
    if sid_high is not None:
        sid_high.text = str(i_sink_sid + 5)

    contents["simulink/systems/system_root.xml"] = ET.tostring(
        root, encoding="utf-8", xml_declaration=True
    )
    contents[DIAM_SYSTEM] = ET.tostring(diam, encoding="utf-8", xml_declaration=True)

    tmp = target.with_suffix(".tmp.slx")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for name, data in contents.items():
            zout.writestr(name, data)
    tmp.replace(target)
    print(f"Patched {target}")
    print(f"Backup {backup}")


if __name__ == "__main__":
    patch()
