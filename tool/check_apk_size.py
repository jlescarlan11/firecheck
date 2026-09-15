#!/usr/bin/env python3
"""Measure APK download bytes and enforce per-architecture release budgets."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import sys
import zipfile


def inspect_apk(path):
    groups = collections.defaultdict(int)
    abis = set()
    compressed_native_libraries = []
    with zipfile.ZipFile(path) as apk:
        for entry in apk.infolist():
            parts = entry.filename.split('/')
            group = parts[0]
            if group == 'lib' and len(parts) >= 3:
                abis.add(parts[1])
                group = '/'.join(parts[:2])
                if entry.filename.endswith('.so') and entry.compress_type != zipfile.ZIP_STORED:
                    compressed_native_libraries.append(entry.filename)
            groups[group] += entry.compress_size
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return {
        'path': str(path),
        'bytes': path.stat().st_size,
        'sha256': digest.hexdigest(),
        'abis': sorted(abis),
        'compressed_native_libraries': compressed_native_libraries,
        'zip_entry_bytes': dict(sorted(groups.items())),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apks', nargs='+', type=Path)
    parser.add_argument('--max-mb', type=float, default=55,
                        help='Maximum decimal MB per APK (default: 55)')
    parser.add_argument('--allow-universal', action='store_true')
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    results = []
    failed = False
    baseline_bytes = args.baseline.stat().st_size if args.baseline else None
    for path in args.apks:
        result = inspect_apk(path)
        errors = []
        if result['bytes'] > args.max_mb * 1_000_000:
            errors.append(f'exceeds {args.max_mb:g} MB budget')
        if not result['abis']:
            errors.append('missing native libraries')
        elif len(result['abis']) != 1 and not args.allow_universal:
            errors.append('contains multiple processor architectures')
        if result['compressed_native_libraries']:
            errors.append('compressed native libraries increase installed storage')
        result['errors'] = errors
        if baseline_bytes:
            result['reduction_percent'] = round(
                100 * (1 - result['bytes'] / baseline_bytes), 2)
        results.append(result)
        failed |= bool(errors)
        print(f"{path.name}: {result['bytes'] / 1_000_000:.2f} MB "
              f"({', '.join(result['abis'])}) "
              f"{'FAIL: ' + '; '.join(errors) if errors else 'PASS'}")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(results, indent=2) + '\n')
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
