#!/usr/bin/env python3
"""Freezes the package's liquid final pass as the shader parity baseline.

The parity oracle (example/test/shader_parity_host_test.dart and the device
harness) renders example/shader_audit/baseline next to the live shaders and
expects identical pixels. Freeze it again only after a deliberate change of
the final pass's output or of its uniform interface, from a commit whose
output other oracles have verified, and name that commit in the message.

    tool/audit/shader/freeze_baseline.py

Copies lib/src/glass/renderer/shaders (the entry and every include) into
the baseline, writes one entry per matte variant of LiquidShaderVariant
with its WITH_<switch> defines (what hook/build.dart passes impellerc), and
rewrites the example pubspec's list of baseline shaders.
"""

import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
SHADERS = os.path.join(ROOT, 'lib/src/glass/renderer/shaders')
VARIANTS = os.path.join(ROOT, 'lib/src/glass/renderer/liquid_shader_variants.dart')
BASELINE = os.path.join(ROOT, 'example/shader_audit/baseline')
PUBSPEC = os.path.join(ROOT, 'example/pubspec.yaml')
ENTRY = 'liquid_glass_final_render.frag'

SWITCHES = {
    'shapeAppearance': 'SHAPE_APPEARANCE',
    'shapeTint': 'SHAPE_TINT',
    'directModel': 'DIRECT_MODEL',
    'ios27Models': 'IOS27_MODELS',
    'analyticGeometry': 'ANALYTIC_GEOMETRY',
    'fused': 'ANALYTIC_FUSED',
    'frost': 'FROST',
}
DEFAULTS = {name: False for name in SWITCHES}
DEFAULTS['frost'] = True


def variants():
    source = open(VARIANTS).read()
    body = source[source.index('enum LiquidShaderVariant'):]
    body = body[:body.index(';')]
    found = []
    for name, args in re.findall(r'\b([a-z][A-Za-z0-9]*)\(([^)]*)\)', body):
        on = dict(DEFAULTS)
        for key, value in re.findall(r'(\w+):\s*(true|false)', args):
            if key not in SWITCHES:
                sys.exit(f'unknown switch {key} in {name}')
            on[key] = value == 'true'
        found.append((name, on))
    if not found:
        sys.exit('no variants found')
    return found


def file_name(on):
    parts = ['liquid_glass_final_render']
    if on['analyticGeometry']:
        parts.append('_analytic')
    if on['fused']:
        parts.append('_fused')
    if on['shapeAppearance']:
        parts.append('_material')
    if on['shapeTint']:
        parts.append('_tint')
    if on['ios27Models'] and not on['directModel']:
        parts.append('_ios27')
    if not on['frost']:
        parts.append('_unfrosted')
    return ''.join(parts)


def main():
    matte = [(name, on) for name, on in variants()
             if not on['analyticGeometry']]
    shutil.rmtree(BASELINE, ignore_errors=True)
    shutil.copytree(SHADERS, BASELINE,
                    ignore=shutil.ignore_patterns('glass_shadow.frag'))
    entry = open(os.path.join(BASELINE, ENTRY)).read()
    version = entry.index('\n', entry.index('#version')) + 1
    os.remove(os.path.join(BASELINE, ENTRY))
    names = []
    for _, on in matte:
        defines = ''.join(f'#define WITH_{SWITCHES[key]}\n'
                          for key in SWITCHES if on[key])
        name = file_name(on)
        with open(os.path.join(BASELINE, f'{name}.frag'), 'w') as out:
            out.write(entry[:version] + defines + entry[version:])
        names.append(name)

    pubspec = open(PUBSPEC).read()
    listed = re.compile(r'(  shaders:\n)((?:    - shader_audit/baseline/[^\n]*\n)+)')
    if not listed.search(pubspec):
        sys.exit('no baseline shader list in example/pubspec.yaml')
    lines = ''.join(f'    - shader_audit/baseline/{n}.frag\n' for n in names)
    open(PUBSPEC, 'w').write(listed.sub(lambda m: m.group(1) + lines, pubspec))
    print(f'froze {len(names)} matte variants: {", ".join(names)}')


if __name__ == '__main__':
    main()
