"""Runs the server tests in supabase/tests against a Supabase project, safely.

Each test file runs in one transaction together with every migration, and ends by
raising its TEST SUMMARY as an error, so nothing is ever kept in the project, even
on an empty one. Needs the Supabase CLI, signed in with an account that can run SQL
on the project (SUPABASE_CLI points at it when it is not on PATH).

    python tool/server_tests.py <project ref>
"""
import glob
import os
import re
import subprocess
import sys
import tempfile


def main(ref: str) -> int:
    cli = os.environ.get('SUPABASE_CLI', 'supabase')
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    migrations = ''.join(
        open(p, encoding='utf-8').read() + '\n'
        for p in sorted(glob.glob(os.path.join(root, 'supabase', 'migrations', '*.sql'))))
    failed = False
    for test in sorted(glob.glob(os.path.join(root, 'supabase', 'tests', '*.sql'))):
        body = open(test, encoding='utf-8').read()
        if 'TEST SUMMARY' not in body:
            print(f'{test}: must end by raising its TEST SUMMARY')
            return 1
        body = re.sub(r'^begin;\s*$', '', body, count=1, flags=re.M)
        with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False,
                                         encoding='utf-8', newline='\n') as f:
            f.write('begin;\n' + migrations + '\n' + body)
        try:
            run = subprocess.run([cli, 'db', 'query', f'--remote={ref}', '--yes', '-f', f.name],
                                 capture_output=True, text=True, encoding='utf-8')
        finally:
            os.unlink(f.name)
        # The summary comes back as an error message, JSON-escaped twice.
        text = (run.stdout + run.stderr).replace('\\n', '\n').replace('\n', '\n').replace('\\"', '"')
        m = re.search(r'TEST SUMMARY (\S+): passed=(\d+) failed=(\d+)(.*?)CONTEXT:', text, re.S)
        if not m:
            print(f'{os.path.basename(test)}: did not finish\n{text[-3000:]}')
            failed = True
            continue
        print(f'{m[1]}: {m[2]} passed, {m[3]} failed')
        if int(m[3]):
            print(m[4].strip())
            failed = True
    return 1 if failed else 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
