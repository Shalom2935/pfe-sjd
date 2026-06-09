"""Patch the current AGL_FullLoop_DIAM4100.slx topology in place.

The file preserves the manually edited Diam4100_CCR subsystem and rewires
only the repeated loop part: cable sections, isolation transformers, loads,
surge placeholders and current probes.
"""

from __future__ import annotations

import csv
import re
import shutil
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET


THIS_DIR = Path(__file__).resolve().parent
OUT_DIR = THIS_DIR / "outputs"
TARGET_SLX = THIS_DIR / "AGL_FullLoop_DIAM4100.slx"

LOOP_LENGTH_M = 9007.0
REGARD_SPACING_M = 60.0
EQUIPPED_REGARD_COUNT = 49
MEASURED_MODULES = {1, 10, 20, 30, 40, 50, 51}


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


def set_instance_p(block: ET.Element, name: str, value: object) -> None:
    inst = block.find("InstanceData")
    if inst is None:
        inst = ET.SubElement(block, "InstanceData")
    for child in inst.findall("P"):
        if child.attrib.get("Name") == name:
            child.text = str(value)
            return
    inst.append(p(name, value))


def set_position(block: ET.Element, position: tuple[int, int, int, int]) -> None:
    set_p(block, "Position", f"[{position[0]}, {position[1]}, {position[2]}, {position[3]}]")


def block_sid(block: ET.Element) -> str:
    return block.attrib["SID"]


def make_line(src: str, dst: str, zorder: int, *, connection: bool = True) -> ET.Element:
    line = ET.Element("Line", {"LineType": "Connection"} if connection else {})
    line.append(p("ZOrder", zorder))
    line.append(p("Src", src))
    line.append(p("Dst", dst))
    return line


def build_loads(i_nom: float = 6.6) -> list[dict[str, object]]:
    groups = [
        ("F65", 3, 65, 150, "runway_light"),
        ("F39", 23, 39, 65, "runway_light"),
        ("F8", 13, 8, 25, "runway_light"),
        ("F23", 6, 23, 65, "runway_light"),
        ("F22", 2, 22, 65, "runway_light"),
    ]
    loads: list[dict[str, object]] = []
    for prefix, count, va, ti_w, kind in groups:
        for idx in range(1, count + 1):
            loads.append(
                {
                    "Name": f"{prefix}_{idx:02d}",
                    "Kind": kind,
                    "FixturePower_VA": va,
                    "TIPower_W": ti_w,
                    "SecondaryResistance_ohm": va / i_nom**2,
                }
            )
    for wc in range(1, 3):
        for branch in range(1, 3):
            loads.append(
                {
                    "Name": f"WINDCONE_{wc:02d}_TI_{branch}",
                    "Kind": "wind_cone_secondary_assumption",
                    "FixturePower_VA": 45,
                    "TIPower_W": 45,
                    "SecondaryResistance_ohm": 45 / i_nom**2,
                }
            )

    active_span_m = (EQUIPPED_REGARD_COUNT - 1) * REGARD_SPACING_M
    end_lead_m = (LOOP_LENGTH_M - active_span_m) / 2
    regard_index = 0
    current_wind_cone = ""
    for load in loads:
        wind_cone_match = re.match(r"^(WINDCONE_\d+)", str(load["Name"]))
        wind_cone_id = wind_cone_match.group(1) if wind_cone_match else ""
        if not wind_cone_id:
            regard_index += 1
            current_wind_cone = ""
        elif wind_cone_id != current_wind_cone:
            regard_index += 1
            current_wind_cone = wind_cone_id
        load["RegardIndex"] = regard_index
        load["ManholeIndex"] = regard_index
        load["Distance_m"] = end_lead_m + (regard_index - 1) * REGARD_SPACING_M

    if regard_index != EQUIPPED_REGARD_COUNT:
        raise RuntimeError(f"Expected {EQUIPPED_REGARD_COUNT} equipped regards, got {regard_index}.")
    return loads


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def grid(index: int) -> tuple[int, int]:
    x0, y0, dx, dy, wrap = 1040, 70, 250, 235, 8
    col = (index - 1) % wrap
    row = (index - 1) // wrap
    return x0 + col * dx, y0 + row * dy


def patch() -> None:
    OUT_DIR.mkdir(exist_ok=True)
    backup = TARGET_SLX.with_name("AGL_FullLoop_DIAM4100.before_regard_topology_fix.slx")
    shutil.copy2(TARGET_SLX, backup)

    with zipfile.ZipFile(TARGET_SLX, "r") as zin:
        contents = {name: zin.read(name) for name in zin.namelist()}

    root = ET.fromstring(contents["simulink/systems/system_root.xml"])
    blocks = {block.attrib.get("Name", ""): block for block in root.findall("Block")}

    diam = next((b for name, b in blocks.items() if "DIAM" in name.upper()), None)
    if diam is None:
        raise RuntimeError("Cannot find the DIAM4100 subsystem on the root diagram.")
    diam_sid = block_sid(diam)

    # Remove all existing root-level wires; the repeated loop is rebuilt from
    # the preserved blocks so the manually edited DIAM4100 subsystem remains.
    for line in list(root.findall("Line")):
        root.remove(line)

    # Keep the first 50 cable sections only: lead-in, 48 inter-regard
    # sections, and lead-out.
    for block in list(root.findall("Block")):
        name = block.attrib.get("Name", "")
        match = re.match(r"^Cable_(\d+)$", name)
        if match and int(match.group(1)) > 50:
            root.remove(block)

    blocks = {block.attrib.get("Name", ""): block for block in root.findall("Block")}
    loads = build_loads()
    site_modules: dict[int, list[int]] = {}
    for idx, load in enumerate(loads, start=1):
        site_modules.setdefault(int(load["RegardIndex"]), []).append(idx)

    active_span_m = (EQUIPPED_REGARD_COUNT - 1) * REGARD_SPACING_M
    end_lead_m = (LOOP_LENGTH_M - active_span_m) / 2
    segment_lengths = [end_lead_m] + [REGARD_SPACING_M] * (EQUIPPED_REGARD_COUNT - 1) + [end_lead_m]
    write_csv(
        OUT_DIR / "FullLoop_cable_segments.csv",
        [
            {
                "SegmentIndex": idx,
                "Length_m": length,
                "CumulativeDistance_m": sum(segment_lengths[:idx]),
            }
            for idx, length in enumerate(segment_lengths, start=1)
        ],
    )
    write_csv(OUT_DIR / "FullLoop_load_topology.csv", loads)

    surge_regards = [round(1 + i * (EQUIPPED_REGARD_COUNT - 1) / 14) for i in range(15)]
    write_csv(
        OUT_DIR / "FullLoop_surge_topology.csv",
        [
            {
                "Index": idx,
                "RegardIndex": regard,
                "ManholeIndex": regard,
                "Distance_m": end_lead_m + (regard - 1) * REGARD_SPACING_M,
            }
            for idx, regard in enumerate(surge_regards, start=1)
        ],
    )

    for idx, length in enumerate(segment_lengths, start=1):
        cable = blocks[f"Cable_{idx:03d}"]
        x, y = grid(idx)
        set_position(cable, (x, y + 95, x + 70, y + 131))
        set_instance_p(cable, "Length", f"FullLoop.segments.length_km({idx})")

    for idx, load in enumerate(loads, start=1):
        site = int(load["RegardIndex"])
        module_order = site_modules[site].index(idx)
        x, y = grid(site)
        y_offset = 0 if module_order == 0 else 88

        ti = blocks[f"TI_{idx:03d}_{load['Name']}"]
        lamp = blocks[f"LOAD_{idx:03d}_{load['Name']}"]
        set_position(ti, (x + 90, y + 5 + y_offset, x + 150, y + 76 + y_offset))
        set_position(lamp, (x + 205, y + 16 + y_offset, x + 245, y + 66 + y_offset))
        set_instance_p(ti, "NominalPower", f"FullLoop.tiModules({idx}).Pn_fn")
        set_instance_p(ti, "Winding1", f"FullLoop.tiModules({idx}).W1")
        set_instance_p(ti, "Winding2", f"FullLoop.tiModules({idx}).W2")
        set_instance_p(ti, "Saturation", f"FullLoop.tiModules({idx}).Sat")
        set_instance_p(lamp, "BranchType", "R")
        set_instance_p(lamp, "Resistance", f"FullLoop.loads({idx}).SecondaryResistance_ohm")

    for idx in MEASURED_MODULES:
        site = int(loads[idx - 1]["RegardIndex"])
        module_order = site_modules[site].index(idx)
        x, y = grid(site)
        y_offset = 0 if module_order == 0 else 88
        meas = blocks[f"I_MEAS_{idx:03d}"]
        sink = blocks[f"ToWorkspace_I_MEAS_{idx:03d}"]
        set_position(meas, (x + 80, y + 112 + y_offset, x + 105, y + 136 + y_offset))
        set_position(sink, (x + 135, y + 110 + y_offset, x + 230, y + 138 + y_offset))

    surge_blocks = sorted(
        [b for name, b in blocks.items() if re.match(r"^SA_\d+_placeholder$", name)],
        key=lambda b: int(re.search(r"SA_(\d+)_", b.attrib["Name"]).group(1)),
    )
    for block, regard in zip(surge_blocks, surge_regards):
        x, y = grid(regard)
        block.attrib["Name"] = f"SA_{regard:03d}_placeholder"
        set_position(block, (x + 5, y + 152, x + 110, y + 194))
        mask = block.find("Mask")
        if mask is not None:
            display = mask.find("Display")
            if display is not None:
                display.text = f"disp('Parafoudre regard {regard:03d}\\nopen')"

    zorder = 40000

    def add_conn(src: str, dst: str) -> None:
        nonlocal zorder
        root.append(make_line(src, dst, zorder, connection=True))
        zorder += 1

    def add_signal(src: str, dst: str) -> None:
        nonlocal zorder
        root.append(make_line(src, dst, zorder, connection=False))
        zorder += 1

    current_ref = f"{diam_sid}#rconn:1"
    for site in range(1, EQUIPPED_REGARD_COUNT + 1):
        cable = blocks[f"Cable_{site:03d}"]
        add_conn(current_ref, f"{block_sid(cable)}#lconn:1")
        current_ref = f"{block_sid(cable)}#rconn:1"

        for module_idx in site_modules[site]:
            if module_idx in MEASURED_MODULES:
                meas = blocks[f"I_MEAS_{module_idx:03d}"]
                sink = blocks[f"ToWorkspace_I_MEAS_{module_idx:03d}"]
                add_conn(current_ref, f"{block_sid(meas)}#lconn:1")
                current_ref = f"{block_sid(meas)}#rconn:1"
                add_signal(f"{block_sid(meas)}#out:1", f"{block_sid(sink)}#in:1")

            load = loads[module_idx - 1]
            ti = blocks[f"TI_{module_idx:03d}_{load['Name']}"]
            lamp = blocks[f"LOAD_{module_idx:03d}_{load['Name']}"]
            add_conn(current_ref, f"{block_sid(ti)}#lconn:1")
            add_conn(f"{block_sid(ti)}#rconn:1", f"{block_sid(lamp)}#lconn:1")
            add_conn(f"{block_sid(lamp)}#rconn:1", f"{block_sid(ti)}#rconn:2")
            current_ref = f"{block_sid(ti)}#lconn:2"

    final_cable = blocks["Cable_050"]
    add_conn(current_ref, f"{block_sid(final_cable)}#lconn:1")
    add_conn(f"{block_sid(final_cable)}#rconn:1", f"{diam_sid}#rconn:2")

    contents["simulink/systems/system_root.xml"] = ET.tostring(
        root, encoding="utf-8", xml_declaration=True
    )

    tmp = TARGET_SLX.with_suffix(".tmp.slx")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for name, data in contents.items():
            zout.writestr(name, data)
    tmp.replace(TARGET_SLX)
    print(f"Patched {TARGET_SLX}")
    print(f"Backup {backup}")


if __name__ == "__main__":
    patch()
