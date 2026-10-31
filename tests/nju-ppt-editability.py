"""Check exported NJU callouts are independent slide shapes, not inherited art."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
from zipfile import ZipFile

NS = {
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
}


def shape_name(shape):
    return shape.find("p:nvSpPr/p:cNvPr", NS).get("name", "")


def check(pptx):
    checked = 0
    with ZipFile(pptx) as archive:
        for part in archive.namelist():
            if re.fullmatch(r"ppt/slideLayouts/slideLayout\d+\.xml", part):
                layout = ET.fromstring(archive.read(part))
                for shape in layout.findall(".//p:sp", NS):
                    assert not shape_name(shape).startswith(("takeaway-field", "takeaway-accent")), (
                        part, "callout background must not be inherited from Layout"
                    )
            if not re.fullmatch(r"ppt/slides/slide\d+\.xml", part):
                continue
            tree = ET.fromstring(archive.read(part)).find("p:cSld/p:spTree", NS)
            shapes = {shape_name(s): s for s in tree.findall("p:sp", NS)}
            text = shapes.get("takeaway-text Placeholder Carrier")
            if text is None:
                continue
            for name in ("takeaway-field", "takeaway-accent"):
                assert name in shapes, (part, name, "missing independent slide shape")
                shape = shapes[name]
                assert shape.find("p:nvSpPr/p:nvPr/p:ph", NS) is None, (part, name)
                assert not shape.findall(".//a:t", NS), (part, name, "text must remain separate")
                assert shape.find("p:spPr/a:prstGeom", NS).get("prst") == "rect", (part, name)
                for locks in shape.findall(".//a:spLocks", NS):
                    assert locks.get("noMove") not in ("1", "true"), (part, name)
                assert list(tree).index(shape) < list(tree).index(text), (part, name, "behind text")
            assert text.findall(".//a:t", NS), (part, "missing editable text")
            checked += 1
    assert checked, "No NJU callout slides were checked"
    print(f"PASS: {checked} callout slides; background, accent and text are separate slide objects")


if __name__ == "__main__":
    check(Path(sys.argv[1]))
