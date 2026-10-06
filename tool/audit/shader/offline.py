#!/usr/bin/env python3
"""Offline gate for the glass shaders: no device, no GPU.

Compiles every runtime .frag of the package (and the frozen baseline in
example/shader_audit/baseline) with the SDK's impellerc for the three
runtime stages the engine loads - Vulkan (SPIR-V), Metal (MSL) and GLES 3
(GLSL ES) - and the Flutter GPU bundle fragments (geometry, field, material)
for Vulkan and GLES 3.00 as the build hook does, then reports:

- static counts of what each backend's driver receives: SPIR-V instructions
  (spirv-dis from the Android NDK), RelaxedPrecision decorations, divides,
  texture samples, extended instructions, MSL / GLSL lines;
- Arm's malioc for the Mali-G78 (the Pixel 6a's GPU), on the GLES source
  and on the SPIR-V: arithmetic / load-store / texture cycles per fragment
  on the longest and shortest path and in total, work and uniform
  registers, thread occupancy, stack spilling and whether the shader holds
  uniform-only computation (the driver runs that once per draw, so it costs
  uniform registers, not per-fragment cycles).

    tool/audit/shader/offline.py                  # every tree, every shader
    tool/audit/shader/offline.py --json out.json  # the full report
    tool/audit/shader/offline.py --tree before=<dir> --tree after=<dir>
                                                  # any shader trees instead
                                                  # (copies of lib/src/glass/
                                                  # renderer/shaders)
    tool/audit/shader/offline.py --only final     # names containing 'final'
    tool/audit/shader/offline.py --define NAME=V  # extra define (repeatable)

malioc comes from PATH or MALIOC=<path>; without it only the static counts
print. Cycle counts are a model of the Mali-G78 r1p1 with driver r51p0, not
a measurement: a change that does not move them is not worth a device run,
a change that does still needs the device bench.
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
RUNTIME = [
    'liquid_glass_final_render.frag',
    'liquid_glass_final_render_ios27.frag',
    'liquid_glass_final_render_tint.frag',
    'liquid_glass_final_render_tint_ios27.frag',
    'liquid_glass_final_render_material.frag',
    'fake_glass_surface.frag',
]
BUNDLE = [
    'gpu/geometry_fragment.glsl',
    'gpu/geometry_field_fragment.glsl',
    'gpu/material_gradient_fragment.glsl',
    'gpu/material_tint_gradient_fragment.glsl',
]
EXT = ['Pow', 'Exp2', 'Log2', 'Exp', 'Log', 'Sin', 'Cos', 'Atan2', 'Atan',
       'Sqrt', 'InverseSqrt', 'Normalize', 'Length', 'SmoothStep', 'FMix']
PIPES = {'arith_total': 'A', 'load_store': 'LS', 'texture': 'T'}


def spirv_dis():
    for version in sorted(os.listdir(NDK)) if os.path.isdir(NDK) else []:
        tool = os.path.join(NDK, version, 'shader-tools', 'darwin-x86_64', 'spirv-dis')
        if os.path.exists(tool):
            return tool
    return shutil.which('spirv-dis')


def malioc_tool():
    return os.environ.get('MALIOC') or shutil.which('malioc')


def impellerc(args, tree):
    subprocess.run([IMPELLERC] + args + [f'--include={SHADER_LIB}', f'--include={tree}',
                                         f'--include={os.path.join(tree, "gpu")}'],
                   check=True, capture_output=True)


def compile_runtime(tree, entry, stage, out, defines):
    base = os.path.join(out, f'{os.path.basename(entry)}.{stage}')
    impellerc([f'--runtime-stage-{stage}', f'--input={os.path.join(tree, entry)}',
               f'--sl={base}.iplr', f'--spirv={base}.spv'] + defines, tree)
    return open(f'{base}.iplr', 'rb').read()


def compile_bundle(tree, entry, platform, out, defines):
    base = os.path.join(out, f'{os.path.basename(entry)}.{platform}')
    args = ['--input-type=frag', f'--input={os.path.join(tree, entry)}', f'--sl={base}.sl',
            f'--spirv={base}.spv']
    if platform == 'gles':
        args = ['--opengl-es', '--gles-language-version=300'] + args
    else:
        args = ['--vulkan'] + args
    impellerc(args + defines, tree)
    return base


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


def malioc(path, api):
    """Mali-G78 figures of one fragment shader, or None without malioc."""
    tool = malioc_tool()
    if not tool:
        return None
    result = subprocess.run([tool, '--core', 'Mali-G78', '--fragment', f'--{api}',
                             '--format', 'json', path], capture_output=True, text=True)
    try:
        shader = json.loads(result.stdout)['shaders'][0]
    except (ValueError, KeyError, IndexError):
        return {'error': (result.stdout + result.stderr).strip()[-400:]}
    variant = shader['variants'][0]
    perf = variant['performance']
    props = {p['name']: p['value'] for p in variant['properties']}

    def cycles(kind):
        counts = perf[kind]['cycle_count']
        return {short: (None if counts[perf['pipelines'].index(name)] is None
                        else round(counts[perf['pipelines'].index(name)], 3))
                for name, short in PIPES.items()} | {
                    'bound': '+'.join(PIPES.get(b, b) for b in perf[kind]['bound_pipelines'] if b)}

    return {
        'work_registers': props.get('work_registers_used'),
        'uniform_registers': props.get('uniform_registers_used'),
        'occupancy': props.get('thread_occupancy'),
        'spilling': props.get('has_stack_spilling'),
        'spill_bytes': props.get('stack_spill_bytes'),
        'fp16': props.get('fp16_arithmetic'),
        'uniform_computation': {p['name']: p['value'] for p in shader['properties']}.get(
            'has_uniform_computation'),
        'longest': cycles('longest_path_cycles'),
        'shortest': cycles('shortest_path_cycles'),
        'total': cycles('total_cycles'),
    }


def analyze_runtime(tree, entry, out, defines, dis):
    row = {}
    spirv = embedded_spirv(compile_runtime(tree, entry, 'vulkan', out, defines))
    if dis:
        row['vulkan'] = spirv_counts(spirv, dis)
    row['metal'] = text_counts(embedded_text(compile_runtime(tree, entry, 'metal', out, defines)))
    gles_text = embedded_text(compile_runtime(tree, entry, 'gles3', out, defines))
    row['gles3'] = text_counts(gles_text)
    gles_path = os.path.join(out, 'runtime.frag')
    open(gles_path, 'w').write(gles_text)
    spv_path = os.path.join(out, 'runtime.spv')
    open(spv_path, 'wb').write(spirv)
    row['malioc_gles'] = malioc(gles_path, 'opengles')
    row['malioc_vulkan'] = malioc(spv_path, 'vulkan')
    return row


def analyze_bundle(tree, entry, out, defines, dis):
    row = {}
    vk = compile_bundle(tree, entry, 'vulkan', out, defines)
    if dis:
        row['vulkan'] = spirv_counts(open(f'{vk}.spv', 'rb').read(), dis)
    gles = compile_bundle(tree, entry, 'gles', out, defines)
    row['gles3'] = text_counts(open(f'{gles}.sl').read())
    gles_path = f'{gles}.frag'
    shutil.copy(f'{gles}.sl', gles_path)
    row['malioc_gles'] = malioc(gles_path, 'opengles')
    row['malioc_vulkan'] = malioc(f'{vk}.spv', 'vulkan')
    return row


def fmt(value):
    if value is None:
        return '-'
    if isinstance(value, float):
        return f'{value:g}'
    return str(value)


def print_tables(report):
    print(f'{"shader":58} {"vk ops":>7} {"relax":>5} {"fdiv":>4} {"tex":>3} '
          f'{"ext":>4} {"msl":>5} {"gles":>5}')
    for key, row in report.items():
        vk = row.get('vulkan', {})
        msl = row['metal']['lines'] if 'metal' in row else '-'
        print(f'{key:58} {fmt(vk.get("instructions")):>7} {fmt(vk.get("relaxed")):>5} '
              f'{fmt(vk.get("fdiv")):>4} {fmt(vk.get("samples")):>3} '
              f'{sum(vk.get("ext", {}).values()):>4} {msl:>5} {row["gles3"]["lines"]:>5}')
    if not malioc_tool():
        print('malioc not installed: no Mali-G78 figures (Arm Mobile Studio, MALIOC=<path>)')
        return
    print()
    print('Mali-G78 (malioc): cycles per fragment A / LS / T, work and uniform registers, '
          'occupancy %, spill bytes, uniform computation')
    print(f'{"shader":58} {"api":4} {"longest A/LS/T":>19} {"shortest A/LS/T":>17} '
          f'{"total A":>7} {"wr":>3} {"ur":>3} {"occ":>3} {"spill":>5} {"uc":>2}')
    for key, row in report.items():
        for api in ('gles', 'vulkan'):
            m = row.get(f'malioc_{api}')
            if not m:
                continue
            if 'error' in m:
                print(f'{key:58} {api[:4]:4} {m["error"][:60]}')
                continue
            lp, sp, tp = m['longest'], m['shortest'], m['total']
            longest = f'{fmt(lp["A"])}/{fmt(lp["LS"])}/{fmt(lp["T"])}'
            shortest = f'{fmt(sp["A"])}/{fmt(sp["LS"])}/{fmt(sp["T"])}'
            print(f'{key:58} {api[:4]:4} {longest:>19} {shortest:>17} {fmt(tp["A"]):>7} '
                  f'{fmt(m["work_registers"]):>3} {fmt(m["uniform_registers"]):>3} '
                  f'{fmt(m["occupancy"]):>3} {fmt(m["spill_bytes"]):>5} '
                  f'{"y" if m["uniform_computation"] else "n":>2}')


def main():
    argv = sys.argv[1:]
    trees = {}
    defines = []
    only = None
    json_out = None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == '--tree':
            name, path = argv[i + 1].split('=', 1)
            trees[name] = os.path.abspath(path)
            i += 2
        elif arg == '--define':
            defines.append(f'--define={argv[i + 1]}')
            i += 2
        elif arg == '--only':
            only = argv[i + 1]
            i += 2
        elif arg == '--json':
            json_out = argv[i + 1]
            i += 2
        else:
            print(__doc__)
            return 2
    trees = trees or TREES
    dis = spirv_dis()
    report = {}
    with tempfile.TemporaryDirectory() as out:
        for tree_name, tree in trees.items():
            if not os.path.isdir(tree):
                continue
            for entry in RUNTIME + BUNDLE:
                if only and only not in entry:
                    continue
                if not os.path.exists(os.path.join(tree, entry)):
                    continue
                analyze = analyze_bundle if entry in BUNDLE else analyze_runtime
                report[f'{tree_name}/{entry}'] = analyze(tree, entry, out, defines, dis)
    if json_out:
        json.dump(report, open(json_out, 'w'), indent=2)
    print_tables(report)
    return 0


if __name__ == '__main__':
    sys.exit(main())
