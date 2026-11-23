#!/usr/bin/env python3
"""Build only the requested local evaluation slice; never signs or uploads."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REVISION = "44d50873b56b568c28ef2ad8d6445069feaa9fbd"


def run(command):
    subprocess.run([str(x) for x in command], cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("slice", choices=["host", "ios", "sim", "package"])
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 8:
        parser.error("jobs must be 1–8")
    if args.slice == "package":
        command = ["xcodebuild", "-create-xcframework"]
        for kind in ["ios", "sim"]:
            directory = ROOT / "build" / ("runtime-" + kind)
            libraries = sorted(directory.rglob("lib*.a"))
            if not libraries or not any(p.name == "libcritique-bridge.a" for p in libraries):
                raise RuntimeError("Complete the " + kind + " bridge build first")
            combined = ROOT / "build" / ("libCritiqueRuntime-" + kind + ".a")
            run(["xcrun", "libtool", "-static", "-o", combined] + libraries)
            command.extend(["-library", combined, "-headers", ROOT / "Runtime/include"])
        output = ROOT / "build/CritiqueRuntime.xcframework"
        if output.exists():
            raise RuntimeError("Preserve the existing XCFramework; choose a deliberate replacement before packaging again")
        run(command + ["-output", output])
        return
    cmake = shutil.which("cmake")
    if not cmake:
        raise RuntimeError("Install/provide CMake on PATH before building")
    source = ROOT / "local/vendor" / ("llama.cpp-" + REVISION)
    if not (source / "include/llama.h").is_file():
        raise RuntimeError("Retrieve and verify the pinned source before building")
    build = ROOT / "build" / ("runtime-" + args.slice)
    command = [cmake, "-S", source, "-B", build,
               "-DCMAKE_PROJECT_INCLUDE=" + str(ROOT / "Runtime/CMakeHook.cmake"),
               "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=OFF", "-DGGML_OPENMP=OFF"]
    for option in ["APP", "COMMON", "TESTS", "EXAMPLES", "TOOLS", "SERVER", "MTMD"]:
        command.append("-DLLAMA_BUILD_" + option + "=OFF")
    if args.slice == "host":
        command.extend(["-DGGML_METAL=OFF"])
        target = "critique-coach"
    else:
        simulator = args.slice == "sim"
        command.extend(["-G", "Xcode", "-DCMAKE_SYSTEM_NAME=iOS",
                        "-DCMAKE_OSX_ARCHITECTURES=" + ("x86_64" if simulator else "arm64"),
                        "-DCMAKE_OSX_SYSROOT=" + ("iphonesimulator" if simulator else "iphoneos"),
                        "-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0",
                        "-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO", "-DGGML_NATIVE=OFF",
                        "-DGGML_METAL=" + ("OFF" if simulator else "ON"), "-DGGML_METAL_EMBED_LIBRARY=ON"])
        target = "critique-bridge"
    run(command)
    run([cmake, "--build", build, "--config", "Release", "--target", target, "-j", str(args.jobs)])


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
