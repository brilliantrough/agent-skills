#!/usr/bin/env python3
"""One lightweight regression check; no test framework or sample artwork required."""
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile

from convert import xml, svg_size, check_self_contained, odg_to_odp
from native import validate_svg


def rejected(call):
    try:
        call()
    except ValueError:
        return
    raise AssertionError('Unsupported input was accepted')


svg = b'''<svg xmlns="http://www.w3.org/2000/svg" width="192" height="96" viewBox="0 0 200 100">
<path fill="#fff" d="M 0 0 L 200 0 200 100 Z"/>
</svg>'''
root = xml(svg)
assert svg_size(root) == (2, 1)
check_self_contained(root)
validate_svg(root, 2, 1)
rejected(lambda: xml(b'<!DOCTYPE svg><svg/>'))
rejected(lambda: check_self_contained(xml(svg.replace(b'<path ', b'<path onclick="x()" '))))
rejected(lambda: validate_svg(xml(svg.replace(b'<path ', b'<path clip-path="url(#clip)" ')), 2, 1))
rejected(lambda: validate_svg(xml(svg.replace(b'<path ', b'<path transform="translate(1 0)" ')), 2, 1))
rejected(lambda: validate_svg(xml(svg.replace(b'200 100 Z', b'200 100 Z M 5 5 L 6 6 Z')), 2, 1))
with TemporaryDirectory() as temp:
    source, target = Path(temp)/'a.odg', Path(temp)/'a.odp'
    with ZipFile(source, 'w') as z:
        z.writestr('mimetype', 'application/vnd.oasis.opendocument.graphics')
        z.writestr('content.xml', '<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"><office:body><office:drawing><draw:page/></office:drawing></office:body></office:document-content>')
        z.writestr('Pictures/a.bin', b'unchanged')
    odg_to_odp(source, target)
    with ZipFile(target) as z:
        assert z.read('mimetype') == b'application/vnd.oasis.opendocument.presentation'
        assert xml(z.read('content.xml')).find('{*}body/{*}presentation/{*}page') is not None
        assert z.read('Pictures/a.bin') == b'unchanged'
print('PASS: dimensions, unsupported-input guards, ODF document-kind conversion')
