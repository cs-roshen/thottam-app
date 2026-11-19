"""Runs the server tests in supabase/tests against a Supabase project, safely.

Each test file runs in one transaction together with every migration the project
has not applied yet, and ends by raising its TEST SUMMARY as an error, so nothing
is ever kept in the project. Applied migrations are never edited (add a new one),
so the project's schema is what they made. Needs the Supabase CLI, signed in with an account that can run SQL
on the project (SUPABASE_CLI points at it when it is not on PATH).

    python tool/server_tests.py <project ref>
"""
import glob
import os
import re
import subprocess
import sys
import tempfile


def applied(cli: str, ref: str) -> set:
    """Versions in the project's migration history; none on an empty project."""
    run = subprocess.run([cli, 'db', 'query', f'--remote={ref}', '--yes',
                          "select coalesce(string_agg(version, ','), '') as v "
                          'from supabase_migrations.schema_migrations'],
                         capture_output=True, text=True, encoding='utf-8')
    m = re.search(r'"v": "([^"]*)"', run.stdout + run.stderr)
    if m:
        return set(filter(None, m[1].split(',')))
    if 'does not exist' in run.stdout + run.stderr:
        return set()
    sys.exit(f'could not read the migration history:\n{(run.stdout + run.stderr)[-2000:]}')


def main(ref: str) -> int:
    cli = os.environ.get('SUPABASE_CLI', 'supabase')
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    done = applied(cli, ref)
    files = sorted(glob.glob(os.path.join(root, 'supabase', 'migrations', '*.sql')))
    pending = [p for p in files if os.path.basename(p).split('_', 1)[0] not in done]
    print(f'applied in the project: {len(files) - len(pending)}; '
          f'run with the tests: {", ".join(os.path.basename(p) for p in pending) or "none"}')
    migrations = ''.join(open(p, encoding='utf-8').read() + '\n' for p in pending)
    failed = False
    for test in sorted(glob.glob(os.path.join(root, 'supabase', 'tests', '*.sql'))):
        body = open(test, encoding='utf-8').read()
        if 'TEST SUMMARY' not in body:
            print(f'{test}: must end by raising its TEST SUMMARY')
            return 1
        body = re.sub(r'^begin;\s*$', '', body, count=1, flags=re.M)
        body = re.sub(r'^rollback;\s*\Z', '', body.rstrip() + '\n', flags=re.M)
        # Anything that could end the transaction early would let the test data stay.
        ender = re.compile(r'^\s*(commit|rollback|abort|end\s+(transaction|work)|begin\s*;)', re.I | re.M)
        if ender.search(body) or ender.search(migrations):
            print(f'{test}: must not begin or end transactions itself')
            return 1
        with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False,
                                         encoding='utf-8', newline='\n') as f:
            # The guard raises if a test ever stops raising its own summary.
            f.write('begin;\n' + migrations + '\n' + body +
                    "\ndo $$ begin raise exception 'test did not raise its summary'; end $$;\n")
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
