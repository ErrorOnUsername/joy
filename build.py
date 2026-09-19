#!/usr/bin/env python3

import subprocess
import sys

usage = """
    usage: build [mode]

    mode - one of: demo, debug (default: demo)
"""

mode = "demo"

def invalid_args():
    print("invalid argument format")
    print(usage)
    sys.exit(1)

if len(sys.argv) > 2:
    print("too many args")
    invalid_args()

if len(sys.argv) == 2:
    pass_mode = sys.argv[1]
    if pass_mode == "demo":
        mode = "demo"
    elif pass_mode == "debug":
        mode = "debug"
    else:
        print(f"'{pass_mode}' is not a valid build mode")
        invalid_args()

output_path = "joy"
if sys.platform == "win32":
    output_path += ".exe"

args = [ "odin", "build", "code", f"-out:{output_path}" ]

if mode == "demo":
    subprocess.run(args, check = True)
    subprocess.run([ f"./{output_path}", "run"], check = True)
elif mode == "debug":
    subprocess.run(args + [ "-debug" ], check = True)
else:
    assert False, f"{mode} is not a build mode"
