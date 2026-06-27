"""Wrapper to invoke dbt CLI via Python API.

Windows workaround: dbt.exe entry point silently fails (exit code 1, no output)
on some Windows Python 3.12 installations. This script calls dbt through the
Python API directly, which works reliably.
"""
import sys
from dbt.cli.main import dbtRunner

if __name__ == "__main__":
    runner = dbtRunner()
    result = runner.invoke(sys.argv[1:])
    sys.exit(0 if result.success else 1)
