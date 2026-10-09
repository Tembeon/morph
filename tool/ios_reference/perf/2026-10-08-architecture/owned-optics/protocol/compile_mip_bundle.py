"""Build the example-only GPU bundle before building mip_stage_bench.dart."""

import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[4]
    compiler = args.sdk / 'bin/cache/artifacts/engine/darwin-x64/impellerc'
    output = root / 'example/perf_assets/mip.shaderbundle'
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = root / 'example/lib/perf/shaders/mip.shaderbundle.json'
    subprocess.run([str(compiler), '--vulkan', '--sl=' + str(output),
                    '--shader-bundle=' + json.dumps(json.loads(manifest.read_text())),
                    '--gles-language-version=300'], cwd=root, check=True)
    print(output)


if __name__ == '__main__':
    main()
