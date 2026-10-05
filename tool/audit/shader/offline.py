#!/usr/bin/env python3
"""Offline gate for the runtime-effect shaders: no device, no GPU.

Compiles every runtime .frag of the package (and the frozen baseline in
example/shader_audit/baseline) with the SDK's impellerc for the three
runtime stages the engine loads - Vulkan (SPIR-V), Metal (MSL) and GLES 3
(GLSL ES) - and counts what each backend's driver receives: SPIR-V
instructions (spirv-dis from the Android NDK), RelaxedPrecision
decorations, transcendental and divide instructions, texture samples, and
the MSL / GLSL lines and calls. Static counts are a proxy, not cycles:
Arm's malioc (Mobile Studio) gives Mali-G78 cycles and registers when it is
installed (`MALIOC=<path>`), and is run on the GLES source and the SPIR-V.

    tool/audit/shader/offline.py              # live vs baseline table
    tool/audit/shader/offline.py --json out.json
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
FLUTTER = os.path.dirname(os.path.dirname(os.path.realpath(shutil.which('flutter'))))
ENGINE = os.path.join(FLUTTER, 'bin', 'cache', 'artifacts', 'engine', 'darwin-x64')
IMPELLERC = os.path.join(ENGINE, 'impellerc')
SHADER_LIB = os.path.join(ENGINE, 'shader_lib')
NDK = os.path.expanduser('~/Library/Android/sdk/ndk')
TREES = {
    'live': os.path.join(ROOT, 'lib/src/glass/renderer/shaders'),
    'baseline': os.path.join(ROOT, 'example/shader_audit/baseline'),
}
ENTRIES = [
    'liquid_glass_final_render.frag',
    'liquid_glass_final_render_tint.frag',
    'liquid_glass_final_render_material.frag',
    'fake_glass_surface.frag',
]
EXT = ['Pow', 'Exp2', 'Log2', 'Exp', 'Log', 'Sin', 'Cos', 'Atan2', 'Atan',
       'Sqrt', 'InverseSqrt', 'Normalize', 'Length', 'SmoothStep', 'FMix']


def spirv_dis():
    for version in sorted(os.listdir(NDK)) if os.path.isdir(NDK) else []:
        tool = os.path.join(NDK, version, 'shader-tools', 'darwin-x86_64', 'spirv-dis')
        if os.path.exists(tool):
            return tool
    return shutil.which('spirv-dis')


def compile_stage(tree, entry, stage, out):
    sl = os.path.join(out, f'{entry}.{stage}.iplr')
    spv = os.path.join(out, f'{entry}.{stage}.spv')
    subprocess.run([IMPELLERC, f'--runtime-stage-{stage}', f'--input={os.path.join(tree, entry)}',
                    f'--sl={sl}', f'--spirv={spv}', f'--include={SHADER_LIB}', f'--include={tree}'],
                   check=True, capture_output=True)
    return open(sl, 'rb').read()


def embedded_spirv(blob):
    i = blob.find(b'\x03\x02\x23\x07')
    if i == 0:
        return blob
    length = int.from_bytes(blob[i - 4:i], 'little')
    return blob[i:i + length]


def embedded_text(blob):
    text = max(re.findall(rb'[\x09\x0a\x0d\x20-\x7e]{200,}', blob), key=len)
    return text.decode()


def spirv_counts(data, dis):
    with tempfile.NamedTemporaryFile(suffix='.spv') as f:
        f.write(data)
        f.flush()
        asm = subprocess.run([dis, '--no-header', '--raw-id', f.name], check=True,
                             capture_output=True, text=True).stdout
    lines = [l for l in asm.splitlines() if l.strip() and not l.strip().startswith(';')]
    body = [l for l in lines if re.search(r'\bOp(?!Decorate|MemberDecorate|Name|MemberName|'
                                          r'Source|Extension|ExtInstImport|Capability|'
                                          r'MemoryModel|EntryPoint|ExecutionMode|Type|Constant|'
                                          r'Variable|Function\b|FunctionEnd|Label|String|Line|'
                                          r'NoLine|ModuleProcessed)', l)]
    ext = {}
    for name in EXT:
        n = sum(1 for l in lines if re.search(rf'ExtInst %\w+ %\w+ {name}\b', l))
        if n:
            ext[name] = n
    return {
        'instructions': len(body),
        'relaxed': sum(1 for l in lines if 'RelaxedPrecision' in l),
        'fdiv': sum(1 for l in lines if 'OpFDiv' in l),
        'samples': sum(1 for l in lines if re.search(r'OpImage(Sample|Fetch)', l)),
        'branches': sum(1 for l in lines if 'OpBranchConditional' in l),
        'select': sum(1 for l in lines if 'OpSelect' in l),
        'ext': ext,
    }


def text_counts(text):
    code = [l for l in text.splitlines() if l.strip() and not l.strip().startswith('//')]
    joined = '\n'.join(code)
    calls = {}
    for name in ['pow', 'exp2', 'log2', 'sqrt', 'rsqrt', 'inversesqrt', 'normalize', 'length',
                 'atan', 'atan2', 'sin', 'cos', 'smoothstep', 'half']:
        n = len(re.findall(rf'\b{name}\b\s*\(?', joined))
        if n:
            calls[name] = n
    return {'lines': len(code), 'divides': joined.count(' / '), 'calls': calls}


def malioc(path, kind):
    tool = os.environ.get('MALIOC') or shutil.which('malioc')
    if not tool:
        return None
    args = [tool, '--core', 'Mali-G78', '--fragment']
    if kind == 'spirv':
        args += ['--vulkan']
    result = subprocess.run(args + [path], capture_output=True, text=True)
    return result.stdout


def main():
    dis = spirv_dis()
    report = {}
    with tempfile.TemporaryDirectory() as out:
        for tree_name, tree in TREES.items():
            if not os.path.isdir(tree):
                continue
            for entry in ENTRIES:
                key = f'{tree_name}/{entry}'
                row = {}
                vk = compile_stage(tree, entry, 'vulkan', out)
                spirv = embedded_spirv(vk)
                if dis:
                    row['vulkan'] = spirv_counts(spirv, dis)
                row['metal'] = text_counts(embedded_text(compile_stage(tree, entry, 'metal', out)))
                gles_text = embedded_text(compile_stage(tree, entry, 'gles3', out))
                row['gles3'] = text_counts(gles_text)
                gles_path = os.path.join(out, f'{tree_name}-{entry}.frag')
                open(gles_path, 'w').write(gles_text)
                spv_path = os.path.join(out, f'{tree_name}-{entry}.spv')
                open(spv_path, 'wb').write(spirv)
                mali = malioc(gles_path, 'gles')
                if mali is not None:
                    row['malioc_gles'] = mali
                    row['malioc_vulkan'] = malioc(spv_path, 'spirv')
                report[key] = row
    if '--json' in sys.argv:
        json.dump(report, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=2)
    print(f'{"shader":58} {"vk ops":>7} {"relax":>5} {"fdiv":>4} {"tex":>3} '
          f'{"ext":>4} {"msl":>5} {"gles":>5}')
    for key, row in report.items():
        vk = row.get('vulkan', {})
        print(f'{key:58} {vk.get("instructions", "-"):>7} {vk.get("relaxed", "-"):>5} '
              f'{vk.get("fdiv", "-"):>4} {vk.get("samples", "-"):>3} '
              f'{sum(vk.get("ext", {}).values()):>4} {row["metal"]["lines"]:>5} '
              f'{row["gles3"]["lines"]:>5}')
        for kind in ('malioc_gles', 'malioc_vulkan'):
            if row.get(kind):
                print(row[kind])
    if not (os.environ.get('MALIOC') or shutil.which('malioc')):
        print('malioc not installed: no Mali-G78 cycle counts (Arm Mobile Studio, MALIOC=<path>)')


if __name__ == '__main__':
    main()
