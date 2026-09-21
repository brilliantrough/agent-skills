#!/usr/bin/env python3
"""SVG → text/vector PDF → native editable PPTX, for the profile in SKILL.md."""
import argparse
import glob
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
from zipfile import ZipFile, ZIP_STORED

import lxml.etree as ET


def require(condition, message):
    if not condition:
        raise ValueError(message)


def xml(data):
    require(b'<!DOCTYPE' not in data.upper(), 'DTD is not supported')
    return ET.fromstring(data, ET.XMLParser(resolve_entities=False, no_network=True,
                                           remove_comments=True, remove_pis=True))


def svg_size(root):
    def pixels(value):
        m = re.fullmatch(r'\s*([\d.]+)\s*(px|in|cm|mm|pt|pc)?\s*', value or '')
        if m is None:
            raise ValueError('SVG needs explicit numeric width/height (px, in, cm, mm, pt, pc)')
        return float(m[1]) * {'px': 1, 'in': 96, 'cm': 96/2.54, 'mm': 96/25.4,
                             'pt': 96/72, 'pc': 16}[m[2] or 'px']
    width, height = pixels(root.get('width')), pixels(root.get('height'))
    require(all(math.isfinite(n) and n > 0 for n in (width, height)), 'Invalid SVG size')
    return width / 96, height / 96


def check_self_contained(root):
    require(ET.QName(root).localname == 'svg', 'Expected SVG root')
    for e in root.iter():
        require(ET.QName(e).localname not in ('script', 'foreignObject'), 'Active SVG content is not supported')
        for key, value in e.attrib.items():
            name = ET.QName(key).localname
            require(not name.lower().startswith('on'), 'SVG event handlers are not supported')
            if name in ('href', 'src'):
                require(value.startswith('#'), 'External/embedded image references are not supported')
        css = e.get('style', '') + (e.text or '' if ET.QName(e).localname == 'style' else '')
        require('@import' not in css.lower(), 'External CSS is not supported')
        for value in list(e.attrib.values()) + [css]:
            for target in re.findall(r'url\((.*?)\)', value, re.I):
                require(target.strip(" \t\"'").startswith('#'), 'External URL in SVG is not supported')


def run(args, work, env=None):
    """Bounded foreground jobs, no shell or persistent UNO server."""
    command = [str(a) for a in args]
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, env=env, start_new_session=True) as process:
        try:
            stdout, stderr = process.communicate(timeout=180)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            with (work / 'commands.log').open('a') as log:
                log.write(json.dumps(command) + '\nINTERRUPTED\n' + stdout + stderr + '\n')
            raise
    with (work / 'commands.log').open('a') as log:
        log.write(json.dumps(command) + '\n' + stdout + stderr + '\n')
    require(process.returncode == 0, f'{args[0]} failed; see {work / "commands.log"}')
    return stdout


def odg_to_odp(source, target):
    with ZipFile(source) as src, ZipFile(target, 'w') as dst:
        for item in src.infolist():
            data = src.read(item.filename)
            if item.filename in ('mimetype', 'META-INF/manifest.xml'):
                data = data.replace(b'application/vnd.oasis.opendocument.graphics',
                                    b'application/vnd.oasis.opendocument.presentation')
            elif item.filename == 'content.xml':
                root = xml(data)
                drawing = root.find('{*}body/{*}drawing')
                require(drawing is not None, 'ODG has no drawing body')
                require(len(drawing.findall('{*}page')) == 1, 'Only single-page figures are supported')
                drawing.tag = '{urn:oasis:names:tc:opendocument:xmlns:office:1.0}presentation'
                data = ET.tostring(root, xml_declaration=True, encoding='UTF-8')
            if item.filename == 'mimetype':
                item.compress_type = ZIP_STORED
            dst.writestr(item, data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('svg', type=Path)
    parser.add_argument('--output-dir', type=Path, help='New directory; never overwrite existing work')
    parser.add_argument('--format', choices=['pdf', 'pptx', 'both'], default='both')
    parser.add_argument('--no-sandbox', action='store_true', help='Disable Chrome sandbox only in a trusted isolated environment')
    args = parser.parse_args()
    source = args.svg.resolve(strict=True)
    root = xml(source.read_bytes())
    check_self_contained(root)
    width, height = svg_size(root)
    if args.format != 'pdf':
        from native import validate_svg
        validate_svg(root, width, height)
    chrome = next((shutil.which(n) for n in ['google-chrome', 'chromium', 'chromium-browser'] if shutil.which(n)), None)
    require(chrome is not None, 'Chrome/Chromium not found')
    tools = ['mutool'] + ([] if args.format == 'pdf' else ['soffice', 'pdfimages', 'pdftoppm'])
    for tool in tools:
        require(shutil.which(tool), f'Missing command: {tool}')
    output = (args.output_dir or source.with_name(source.stem + '_editable')).resolve()
    output.mkdir(parents=True, exist_ok=False)
    work = output / 'work'
    work.mkdir()
    (work / 'input.svg').write_bytes(ET.tostring(root, xml_declaration=True, encoding='UTF-8'))
    wrapper = work / 'page.html'
    wrapper.write_text(f'''<!doctype html><meta charset="utf-8"><title>Editable vector figure</title>
<style>@page {{size:{width}in {height}in;margin:0}} html,body {{margin:0;padding:0}}
img {{display:block;width:{width}in;height:{height}in}}</style><img src="input.svg">''')
    pdf = output / (source.stem + '.pdf')
    flags = ['--no-sandbox'] if args.no_sandbox else []
    run([chrome, '--headless', '--disable-gpu', '--disable-extensions', '--no-first-run',
         '--allow-file-access-from-files', '--no-pdf-header-footer',
         '--user-data-dir=' + str(work / 'chrome-profile'), *flags,
         '--print-to-pdf=' + str(pdf), wrapper.as_uri()], work)
    require(pdf.exists(), 'Chrome did not create a PDF')
    tracefile = work / 'trace.xml'
    run(['mutool', 'draw', '-F', 'trace', '-o', tracefile, pdf], work)
    trace = xml(tracefile.read_bytes())
    pages = trace.findall('page')
    require(len(pages) == 1, 'PDF is not a single page')
    box = [float(v) for v in pages[0].get('mediabox').split()]
    require(abs(box[2]-box[0]-width*72) < 1 and abs(box[3]-box[1]-height*72) < 1,
            'PDF page size differs from SVG')
    if any(''.join(e.itertext()).strip() for e in root.findall('.//{*}text')):
        require(trace.findall('.//fill_text'), 'SVG text was not preserved as PDF text')
    report = {'source': str(source), 'size_inches': [width, height], 'pdf': str(pdf),
              'pdf_text_spans': len(trace.findall('.//fill_text')), 'pdf_images': len(trace.findall('.//fill_image'))}
    if args.format != 'pdf':
        from native import build
        # Keep this local workaround out of the user's global environment.
        env = dict(os.environ)
        # soffice is a wrapper script; find its program dir for the libreglo workaround.
        lo_bin = shutil.which('soffice')
        candidates = [str(Path(lo_bin).resolve().parent)] if lo_bin else []
        candidates += [p for pattern in ('/usr/lib*/libreoffice/program',
                                         '/opt/libreoffice*/program',
                                         '/snap/libreoffice/current/usr/lib/libreoffice/program')
                       for p in glob.glob(pattern)]
        lib = next((Path(d) for d in candidates if (Path(d) / 'soffice.bin').exists()), None)
        if lib is not None:
            env['LD_LIBRARY_PATH'] = str(lib) + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
        lo = ['soffice', '-env:UserInstallation=' + (work / 'lo-profile').as_uri(), '--headless', '--norestore']
        run([*lo, '--convert-to', 'odg', '--outdir', work, pdf], work, env)
        odg, odp = work / (source.stem + '.odg'), work / (source.stem + '.odp')
        require(odg.exists(), 'PDF import did not create an ODG')
        odg_to_odp(odg, odp)
        run([*lo, '--convert-to', 'pptx:Impress MS PowerPoint 2007 XML', '--outdir', work, odp], work, env)
        template = work / (source.stem + '.pptx')
        require(template.exists(), 'Impress did not create a text template')
        pptx = output / (source.stem + '.pptx')
        report.update(build(root, template, pdf, trace, pptx, work, run))
        preview = work / 'preview'
        preview.mkdir()
        run([*lo, '--convert-to', 'pdf', '--outdir', preview, pptx], work, env)
        rendered = preview / (source.stem + '.pdf')
        require(rendered.exists(), 'PPTX round-trip rendering failed')
        run(['pdftoppm', '-scale-to', '1800', '-singlefile', '-png', rendered, output / 'preview'], work)
        run(['pdftoppm', '-scale-to', '1800', '-singlefile', '-png', pdf, output / 'reference'], work)
        report['preview'] = str(output / 'preview.png')
        report['visual_review'] = 'Required: compare preview.png and reference.png; not tested in Microsoft PowerPoint'
    (output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
