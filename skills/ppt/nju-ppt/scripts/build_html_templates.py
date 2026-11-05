"""Regenerate HTML geometry and backgrounds from the bundled, trusted SVG templates."""

import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SVG = "{http://www.w3.org/2000/svg}"
ET.register_namespace("", SVG[1:-1])


def build():
    out = ROOT / "assets/html"
    out.mkdir(parents=True, exist_ok=True)
    pages = []
    for path in sorted((ROOT / "assets/nju-academic-ginkgo/templates").glob("*.svg")):
        tree = ET.parse(path)
        root = tree.getroot()
        fields = []
        slots = {}
        for group in list(root):
            if "data-pptx-placeholder" not in group.attrib:
                continue
            bounds = [float(x) for x in group.attrib["data-pptx-bounds"].split()]
            if group.attrib.get("data-pptx-placeholder") in ("chart", "table"):
                slots[group.attrib["data-pptx-placeholder"]] = bounds
            for text in group.iter(SVG + "text"):
                x = float(text.attrib["x"])
                y = float(text.attrib["y"])
                size = float(text.attrib.get("font-size", 20))
                parts = [(text.text or "", x, y)]
                for span in text:
                    x = float(span.attrib.get("x", x))
                    y = float(span.attrib.get("y", y)) + float(span.attrib.get("dy", 0))
                    parts.append((span.text or "", x, y))
                for value, x, y in parts:
                    match = re.fullmatch(r"\{\{([A-Z0-9_]+)\}\}", value)
                    if match:
                        fields.append({
                            "key": match[1], "x": bounds[0], "y": y - size * .86,
                            "width": bounds[2], "height": size * 1.3,
                            "size": size, "color": text.attrib.get("fill", "#404040"),
                            "weight": text.attrib.get("font-weight", "normal"),
                            "align": {"end": "right", "middle": "center"}.get(text.attrib.get("text-anchor"), "left"),
                        })
            root.remove(group)
        for use in list(root.iter(SVG + "use")):
            icon = use.attrib.pop("data-icon", None)
            if icon:
                use.tag = SVG + "image"
                use.set("href", "../icons/" + icon + ".svg")
        for image in root.iter(SVG + "image"):
            image.set("href", "assets/nju/" + image.attrib["href"].removeprefix("../"))
        name = path.stem.split("_", 1)[1]
        pages.append({"name": name, "backgroundSvg": ET.tostring(root, encoding="unicode"), "fields": fields, "slots": slots})
    assert len(pages) == 11 and all(p["fields"] for p in pages)
    (out / "templates.json").write_text(json.dumps(pages, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Built {len(pages)} HTML page definitions from bundled SVGs")


if __name__ == "__main__":
    build()
