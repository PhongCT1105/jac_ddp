"""Preserve Python's stdlib ``platform`` API for JacGrid's platform package.

JacHammer places the repository root first on ``sys.path``.  Because this
monorepo already has a top-level directory named ``platform``, imports from
dependencies such as PyMongo resolve here instead of to Python's
``platform.py``.  Execute the stdlib module in this package namespace so calls
such as ``platform.system()`` continue to work while JacGrid keeps its existing
directory layout.
"""

import os as _os

_stdlib_platform_file = _os.path.join(
    _os.path.dirname(_os.__file__),
    "platform.py",
)

with open(_stdlib_platform_file, "rb") as _stdlib_platform_source:
    exec(
        compile(
            _stdlib_platform_source.read(),
            _stdlib_platform_file,
            "exec",
        ),
        globals(),
        globals(),
    )
