#!/usr/bin/env python3
"""
build_syncthing_harmonyos.py

Cross-compile Syncthing (Go) to a shared library for HarmonyOS Next.
Based on syncthing-android's build-syncthing.py, adapted for HarmonyOS OHOS target.

Build targets:
  - arm64-v8a (aarch64-linux-ohos)
  - x86_64 (for HarmonyOS emulator, x86_64-linux-ohos)

Prerequisites:
  - Go 1.25+ installed
  - HarmonyOS NDK (llvm toolchain)
  - Zig cc for CGo cross-compilation (optional, for static musl builds)

Usage:
  python build_syncthing_harmonyos.py [--target arm64|x86_64|all]

Output:

  entry/src/main/libs/<abi>/libsyncthingnative.so
"""

import os
import sys
import subprocess
import shutil
import argparse
import platform
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
SYNCTHING_SRC = SCRIPT_DIR.parent / "syncthing"
PROJECT_ROOT = SCRIPT_DIR
ENTRY_DIR = PROJECT_ROOT / "entry" / "src" / "main"
LIBS_DIR = ENTRY_DIR / "libs"
WORKSPACE_ROOT = PROJECT_ROOT.parent
TOOLCHAIN_ROOT = Path(os.environ.get("SYNCTHING_HARMONY_TOOLCHAIN_ROOT", WORKSPACE_ROOT / ".toolchains"))
CACHE_ROOT = Path(os.environ.get("SYNCTHING_HARMONY_CACHE_ROOT", WORKSPACE_ROOT / ".cache"))
TMP_ROOT = Path(os.environ.get("SYNCTHING_HARMONY_TMP_ROOT", WORKSPACE_ROOT / "tmp"))

TARGETS = {
    "arm64": {
        "goarch": "arm64",
        "goos": "linux",
        "abi": "arm64-v8a",
    },
    "x86_64": {
        "goarch": "amd64",
        "goos": "linux",
        "abi": "x86_64",
    },
}

def run_cmd(cmd, cwd=None, env=None):
    print(f"[CMD] {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[ERROR] {result.stderr}")
        sys.exit(result.returncode)
    print(result.stdout)
    return result.stdout

def prepare_e_drive_environment(env):
    """Keep Go module/build caches and temporary files out of the C drive."""
    paths = [
        TOOLCHAIN_ROOT / "go" / "env",
        TOOLCHAIN_ROOT / "go" / "path" / "pkg" / "mod",
        CACHE_ROOT / "go-build",
        TMP_ROOT,
    ]
    for path in paths:
        path.mkdir(parents=True, exist_ok=True)

    gopath = TOOLCHAIN_ROOT / "go" / "path"
    goroot = TOOLCHAIN_ROOT / "go" / "sdk"
    env.setdefault("GOPATH", str(gopath))
    if (goroot / "bin").exists():
        env["GOROOT"] = str(goroot)
        env["PATH"] = str(goroot / "bin") + os.pathsep + env.get("PATH", "")
    env.setdefault("GOMODCACHE", str(gopath / "pkg" / "mod"))
    env.setdefault("GOCACHE", str(CACHE_ROOT / "go-build"))
    env.setdefault("GOENV", str(TOOLCHAIN_ROOT / "go" / "env" / "go.env"))
    env.setdefault("GOTMPDIR", str(TMP_ROOT))
    env.setdefault("TMP", str(TMP_ROOT))
    env.setdefault("TEMP", str(TMP_ROOT))
    return env

def get_go_path():
    e_drive_go = TOOLCHAIN_ROOT / "go" / "sdk" / "bin" / ("go.exe" if platform.system() == "Windows" else "go")
    go_bin = str(e_drive_go) if e_drive_go.exists() else shutil.which("go")
    if not go_bin:
        print("[ERROR] Go not found. Install Go 1.25+ first.")
        sys.exit(1)
    go_path = Path(go_bin).resolve()
    print(f"[INFO] Using Go at: {go_path}")
    return go_path

def build_target(target, go_exe):
    config = TARGETS[target]
    abi = config["abi"]
    goarch = config["goarch"]
    goos = config["goos"]

    print(f"\n{'='*60}")
    print(f"[BUILD] Building for {abi} ({goos}/{goarch})")
    print(f"{'='*60}")

    output_dir = LIBS_DIR / abi
    output_dir.mkdir(parents=True, exist_ok=True)

    output_file = output_dir / "libsyncthingnative.so"

    env = prepare_e_drive_environment(os.environ.copy())
    env["CGO_ENABLED"] = "1"
    env["GOOS"] = goos
    env["GOARCH"] = goarch

    ohos_ndk = env.get("OHOS_NDK_HOME", str(WORKSPACE_ROOT / "OpenHarmony" / "Sdk" / "20" / "native"))
    ohos_target = "aarch64-unknown-linux-ohos" if goarch == "arm64" else "x86_64-unknown-linux-ohos"
    ohos_clang = f"{ohos_ndk}/llvm/bin/{ohos_target}-clang"
    ohos_clang_exe = Path(ohos_ndk) / "llvm" / "bin" / "clang.exe"

    if Path(ohos_clang).exists() or ohos_clang_exe.exists():
        if platform.system() == "Windows":
            wrapper_dir = TOOLCHAIN_ROOT / "ohos-clang"
            wrapper_dir.mkdir(parents=True, exist_ok=True)
            wrapper = wrapper_dir / f"{ohos_target}-clang.cmd"
            sysroot = Path(ohos_ndk) / "sysroot"
            wrapper.write_text(
                f'@echo off\r\n"{ohos_clang_exe}" --target={ohos_target} --sysroot="{sysroot}" %*\r\n',
                encoding="utf-8",
            )
            env["CC"] = str(wrapper)
        else:
            env["CC"] = ohos_clang
        print(f"[INFO] Using HarmonyOS NDK compiler: {env['CC']}")
    else:
        print(f"[WARN] HarmonyOS NDK not found at {ohos_ndk}")
        print("[INFO] Attempting with Zig cc for musl cross-compilation")
        env["CC"] = "zig cc -target aarch64-linux-musl"

    cmd = [
        str(go_exe), "build",
        "-buildmode=c-shared",
        "-tags", "harmonyos,purego,noassets",
        "-ldflags", "-w -s",
        "-o", str(output_file),
        "./cmd/syncthing",
    ]

    run_cmd(cmd, cwd=str(SYNCTHING_SRC), env=env)

    if output_file.exists():
        size_mb = output_file.stat().st_size / (1024 * 1024)
        print(f"[SUCCESS] Built: {output_file} ({size_mb:.1f} MB)")
    else:
        print(f"[ERROR] Build failed - output not found: {output_file}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Build Syncthing for HarmonyOS")
    parser.add_argument("--target", choices=["arm64", "x86_64", "all"],
                        default="arm64", help="Build target architecture")
    parser.add_argument("--syncthing-src", help="Path to syncthing source",
                        default=str(SYNCTHING_SRC))
    args = parser.parse_args()

    if not SYNCTHING_SRC.exists():
        print(f"[ERROR] Syncthing source not found at: {SYNCTHING_SRC}")
        print("Clone syncthing first: git clone https://github.com/syncthing/syncthing.git")
        sys.exit(1)

    go_exe = get_go_path()

    if args.target == "all":
        for target in TARGETS:
            build_target(target, go_exe)
    else:
        build_target(args.target, go_exe)

    print("\n[COMPLETE] All targets built successfully!")
    print(f"[INFO] Libraries are in: {LIBS_DIR}")

if __name__ == "__main__":
    main()
