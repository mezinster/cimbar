#!/usr/bin/env python3
"""
test_pipeline.py — Orchestrate all automated CimBar tests.

Run from the project root:
    python tests/test_pipeline.py

Optional GIF path (skips test_gif.py when omitted):
    python tests/test_pipeline.py path/to/output.gif [expected_size]
"""
import subprocess
import sys


def run(cmd, label):
    print(f'\n─── {label} ───')
    result = subprocess.run(cmd, capture_output=False, text=True)
    return result.returncode == 0


def main():
    gif_path = sys.argv[1] if len(sys.argv) > 1 else None
    gif_size = sys.argv[2] if len(sys.argv) > 2 else '256'

    tests = [
        (['node', 'tests/test_symbols.js'], 'Symbol round-trip (Node.js)'),
        (['node', 'tests/test_rs.js'],      'Reed-Solomon (Node.js)'),
    ]
    if gif_path:
        tests.append(
            (['python', 'tests/test_gif.py', gif_path, gif_size],
             f'GIF structure check ({gif_path})')
        )

    results = {label: run(cmd, label) for cmd, label in tests}

    print('\n' + '=' * 40)
    print('SUMMARY')
    print('=' * 40)
    all_pass = True
    for label, ok in results.items():
        status = 'PASS' if ok else 'FAIL'
        print(f'  [{status}]  {label}')
        if not ok:
            all_pass = False

    sys.exit(0 if all_pass else 1)


if __name__ == '__main__':
    main()
