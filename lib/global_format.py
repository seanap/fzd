#!/usr/bin/env python3
"""Optional byte-preserving snapshot formatter; Bash remains the fallback.

Input is NUL-delimited filesystem paths. Arguments are cap, directory/file/reset
colors, root count, roots, then simple exclusion globs. Bash dispatches complex
patterns to its original formatter so their semantics remain unchanged.
"""
import base64
import fnmatch
import os
import re
import stat
import sys


def main():
    cap = int(sys.argv[1])
    directory_color, file_color, reset = map(os.fsencode, sys.argv[2:5])
    root_count = int(sys.argv[5])
    roots = list(map(os.fsencode, sys.argv[6:6+root_count]))
    exclusions = []
    for value in sys.argv[6+root_count:]:
        pattern = os.fsencode(value)
        if pattern.endswith(b"/"):
            pattern = pattern[:-1]
        if pattern:
            exclusions.append(re.compile(fnmatch.translate((b"*/"+pattern+b"/*").decode("latin1"))))
    replacements = {code: (b"\\x%02x" % code) for code in range(1, 32)}
    replacements.update({9: b"\\t", 10: b"\\n", 13: b"\\r", 27: b"\\e",
                         92: b"\\\\", 127: b"\\x7f"})
    controls = re.compile(rb"[\x01-\x1f\x7f\\]")
    pending = b""
    batch = []
    count = 0
    try:
        while True:
            block = os.read(0, 65536)
            if not block:
                break
            paths = (pending+block).split(b"\0")
            pending = paths.pop()
            for path in paths:
                if path != b"/" and path.endswith(b"/"):
                    path = path[:-1]
                if not any(root == b"/" or path == root or path.startswith(root+b"/") for root in roots):
                    continue
                candidate = (path+b"/").decode("latin1")
                if any(pattern.match(candidate) for pattern in exclusions):
                    continue
                try:
                    mode = os.stat(path).st_mode
                except OSError:
                    mode = 0
                if stat.S_ISDIR(mode):
                    color, suffix = directory_color, b"/"
                elif stat.S_ISREG(mode) or os.path.islink(path):
                    color, suffix = file_color, b""
                else:
                    continue
                name = path.rsplit(b"/", 1)[-1] or b"/"
                name = controls.sub(lambda match: replacements[match[0][0]], name)
                batch.append(base64.b64encode(path)+b"\t"+color+name+suffix+reset+b"\n")
                count += 1
                if count == 1 or len(batch) == 128 or count == cap:
                    sys.stdout.buffer.write(b"".join(batch))
                    sys.stdout.buffer.flush()
                    batch.clear()
                if count == cap:
                    return
        if batch:
            sys.stdout.buffer.write(b"".join(batch))
            sys.stdout.buffer.flush()
    except BrokenPipeError:
        # Closing a picker while its list is arriving is ordinary cancellation.
        os.dup2(os.open(os.devnull, os.O_WRONLY), 1)


if __name__ == "__main__":
    main()
