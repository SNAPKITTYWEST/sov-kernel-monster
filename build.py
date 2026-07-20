import argparse
import subprocess
import sys
import shutil
from pathlib import Path
from typing import List, Optional, Callable
from dataclasses import dataclass
from enum import Enum


class Color:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    WHITE = "\033[37m"
    GRAY = "\033[90m"


class Language(Enum):
    CMAKE = "cmake"
    RUST = "rust"
    FORTRAN = "fortran"
    JULIA = "julia"
    ELIXIR = "elixir"
    R = "r"
    LEAN4 = "lean4"
    GO = "go"

    @classmethod
    def from_string(cls, s: str) -> "Language":
        try:
            return cls(s.lower())
        except ValueError:
            raise ValueError(f"Unknown language: {s}. Valid: {[l.value for l in cls]}")


@dataclass
class BuildConfig:
    root: Path
    release: bool = False
    run_tests: bool = False
    single_lang: Optional[Language] = None
    build_all: bool = False

    @property
    def cmake_build_dir(self) -> Path:
        return self.root / "build" / ("release" if self.release else "debug")

    @property
    def cargo_profile(self) -> str:
        return "release" if self.release else "dev"


def print_header(msg: str) -> None:
    print(f"\n{Color.BOLD}{Color.CYAN}{'='*60}{Color.RESET}")
    print(f"{Color.BOLD}{Color.CYAN}  {msg}{Color.RESET}")
    print(f"{Color.BOLD}{Color.CYAN}{'='*60}{Color.RESET}\n")


def print_step(msg: str) -> None:
    print(f"{Color.BOLD}{Color.BLUE}▶ {msg}{Color.RESET}")


def print_success(msg: str) -> None:
    print(f"{Color.GREEN}✓ {msg}{Color.RESET}")


def print_warning(msg: str) -> None:
    print(f"{Color.YELLOW}⚠ {msg}{Color.RESET}")


def print_error(msg: str) -> None:
    print(f"{Color.RED}✗ {msg}{Color.RESET}")


def print_info(msg: str) -> None:
    print(f"{Color.GRAY}  {msg}{Color.RESET}")


def run_cmd(
    cmd: List[str],
    cwd: Optional[Path] = None,
    env: Optional[dict] = None,
    capture: bool = False,
) -> subprocess.CompletedProcess:
    """Run command with colored output."""
    cmd_str = " ".join(cmd)
    print_info(f"$ {cmd_str}")
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            env=env,
            capture_output=capture,
            text=True,
            check=False,
        )
        if capture and result.stdout:
            print(result.stdout)
        if capture and result.stderr:
            print(result.stderr, file=sys.stderr)
        return result
    except FileNotFoundError:
        print_error(f"Command not found: {cmd[0]}")
        return subprocess.CompletedProcess(cmd, 127, "", f"Command not found: {cmd[0]}")
    except Exception as e:
        print_error(f"Failed to execute: {e}")
        return subprocess.CompletedProcess(cmd, 1, "", str(e))


def check_tool(tool: str, version_flag: str = "--version") -> bool:
    """Check if a tool is available."""
    result = run_cmd([tool, version_flag], capture=True)
    return result.returncode == 0


# ═══════════════════════════════════════════════════════════════════════════
# BUILD FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

def build_cmake(config: BuildConfig) -> bool:
    """Build libbob_quantum.so via CMake."""
    print_header("BUILD: CMake (libbob_quantum.so)")

    if not check_tool("cmake"):
        print_error("cmake not found in PATH")
        return False

    build_dir = config.cmake_build_dir
    build_dir.mkdir(parents=True, exist_ok=True)

    cmake_args = [
        "cmake",
        f"-DCMAKE_BUILD_TYPE={'Release' if config.release else 'Debug'}",
        "-DBUILD_SHARED_LIBS=ON",
        "-DBOB_BUILD_TESTS=ON" if config.run_tests else "-DBOB_BUILD_TESTS=OFF",
        str(config.root),
    ]

    result = run_cmd(cmake_args, cwd=build_dir)
    if result.returncode != 0:
        print_error("CMake configure failed")
        return False

    build_args = ["cmake", "--build", ".", "--config", "Release" if config.release else "Debug"]
    if config.run_tests:
        build_args.extend(["--target", "test"])

    result = run_cmd(build_args, cwd=build_dir)
    if result.returncode != 0:
        print_error("CMake build failed")
        return False

    # Verify library exists
    lib_name = "libbob_quantum.so"
    if sys.platform == "darwin":
        lib_name = "libbob_quantum.dylib"
    elif sys.platform == "win32":
        lib_name = "bob_quantum.dll"

    lib_path = build_dir / lib_name
    if lib_path.exists():
        print_success(f"Built {lib_path}")
        return True
    else:
        print_warning(f"Library not found at {lib_path} (may be in subdirectory)")
        return True


def build_rust(config: BuildConfig) -> bool:
    """Build Rust crate via Cargo."""
    print_header("BUILD: Cargo (Rust)")

    if not check_tool("cargo"):
        print_error("cargo not found in PATH")
        return False

    rust_dir = config.root / "rust"
    if not rust_dir.exists():
        print_warning(f"Rust directory not found: {rust_dir}")
        return True

    cmd = ["cargo", "build"]
    if config.release:
        cmd.append("--release")
    if config.run_tests:
        cmd.extend(["--tests"])

    result = run_cmd(cmd, cwd=rust_dir)
    if result.returncode != 0:
        print_error("Cargo build failed")
        return False

    if config.run_tests:
        test_cmd = ["cargo", "test"]
        if config.release:
            test_cmd.append("--release")
        result = run_cmd(test_cmd, cwd=rust_dir)
        if result.returncode != 0:
            print_error("Cargo tests failed")
            return False

    print_success("Rust build complete")
    return True


def build_fortran(config: BuildConfig) -> bool:
    """Build Fortran tests via fpm."""
    print_header("BUILD: fpm (Fortran)")

    if not check_tool("fpm"):
        print_error("fpm not found in PATH")
        return False

    fortran_dir = config.root / "fortran"
    if not fortran_dir.exists():
        print_warning(f"Fortran directory not found: {fortran_dir}")
        return True

    profile = "release" if config.release else "debug"
    cmd = ["fpm", "build", "--profile", profile]
    result = run_cmd(cmd, cwd=fortran_dir)
    if result.returncode != 0:
        print_error("fpm build failed")
        return False

    if config.run_tests:
        test_cmd = ["fpm", "test", "--profile", profile]
        result = run_cmd(test_cmd, cwd=fortran_dir)
        if result.returncode != 0:
            print_error("fpm tests failed")
            return False

    print_success("Fortran build complete")
    return True


def build_julia(config: BuildConfig) -> bool:
    """Test Julia package."""
    print_header("BUILD: Julia (Package Test)")

    if not check_tool("julia"):
        print_error("julia not found in PATH")
        return False

    julia_dir = config.root / "julia"
    if not julia_dir.exists():
        print_warning(f"Julia directory not found: {julia_dir}")
        return True

    # Instantiate dependencies
    result = run_cmd(["julia", "--project", "-e", "using Pkg; Pkg.instantiate()"], cwd=julia_dir)
    if result.returncode != 0:
        print_error("Julia Pkg.instantiate() failed")
        return False

    # Run tests
    test_cmd = ["julia", "--project", "-e", "using Pkg; Pkg.test()"]
    if config.release:
        test_cmd = ["julia", "--project", "-O3", "-e", "using Pkg; Pkg.test()"]

    result = run_cmd(test_cmd, cwd=julia_dir)
    if result.returncode != 0:
        print_error("Julia tests failed")
        return False

    print_success("Julia package test complete")
    return True


def build_elixir(config: BuildConfig) -> bool:
    """Compile Elixir project via mix."""
    print_header("BUILD: Elixir (mix compile)")

    if not check_tool("mix"):
        print_error("mix not found in PATH")
        return False

    elixir_dir = config.root / "elixir"
    if not elixir_dir.exists():
        print_warning(f"Elixir directory not found: {elixir_dir}")
        return True

    # Get dependencies
    result = run_cmd(["mix", "deps.get"], cwd=elixir_dir)
    if result.returncode != 0:
        print_error("mix deps.get failed")
        return False

    # Compile
    mix_env = "prod" if config.release else "dev"
    env = {**os.environ, "MIX_ENV": mix_env} if "os" in globals() else {"MIX_ENV": mix_env}
    result = run_cmd(["mix", "compile"], cwd=elixir_dir, env=env)
    if result.returncode != 0:
        print_error("mix compile failed")
        return False

    if config.run_tests:
        result = run_cmd(["mix", "test"], cwd=elixir_dir, env=env)
        if result.returncode != 0:
            print_error("mix test failed")
            return False

    print_success("Elixir build complete")
    return True


def build_r(config: BuildConfig) -> bool:
    """Build R package via R CMD build/check."""
    print_header("BUILD: R (CMD build/check)")

    if not check_tool("R"):
        print_error("R not found in PATH")
        return False

    r_dir = config.root / "r"
    if not r_dir.exists():
        print_warning(f"R directory not found: {r_dir}")
        return True

    # Build package
    result = run_cmd(["R", "CMD", "build", "."], cwd=r_dir)
    if result.returncode != 0:
        print_error("R CMD build failed")
        return False

    # Find built tarball
    tarballs = list(r_dir.parent.glob("*.tar.gz"))
    if not tarballs:
        print_error("No package tarball found after build")
        return False

    tarball = max(tarballs, key=lambda p: p.stat().st_mtime)
    print_info(f"Built package: {tarball.name}")

    if config.run_tests:
        result = run_cmd(["R", "CMD", "check", str(tarball)], cwd=r_dir.parent)
        if result.returncode != 0:
            print_error("R CMD check failed")
            return False

    print_success("R package build complete")
    return True


def build_lean4(config: BuildConfig) -> bool:
    """Build Lean 4 project via lake."""
    print_header("BUILD: Lean 4 (lake build)")

    if not check_tool("lake"):
        print_error("lake not found in PATH")
        return False

    lean_dir = config.root / "lean4"
    if not lean_dir.exists():
        print_warning(f"Lean 4 directory not found: {lean_dir}")
        return True

    # Update dependencies
    result = run_cmd(["lake", "update"], cwd=lean_dir)
    if result.returncode != 0:
        print_warning("lake update failed (continuing)")

    # Build
    build_cmd = ["lake", "build"]
    if config.release:
        build_cmd.append("--release")
    result = run_cmd(build_cmd, cwd=lean_dir)
    if result.returncode != 0:
        print_error("lake build failed")
        return False

    if config.run_tests:
        result = run_cmd(["lake", "test"], cwd=lean_dir)
        if result.returncode != 0:
            print_error("lake test failed")
            return False

    print_success("Lean 4 build complete")
    return True


def build_go(config: BuildConfig) -> bool:
    """Build Go NATS project."""
    print_header("BUILD: Go (NATS)")

    if not check_tool("go"):
        print_error("go not found in PATH")
        return False

    go_dir = config.root / "go"
    if not go_dir.exists():
        print_warning(f"Go directory not found: {go_dir}")
        return True

    # Download dependencies
    result = run_cmd(["go", "mod", "download"], cwd=go_dir)
    if result.returncode != 0:
        print_error("go mod download failed")
        return False

    # Build
    build_cmd = ["go", "build"]
    if config.release:
        build_cmd.extend(["-ldflags", "-s -w"])
    result = run_cmd(build_cmd, cwd=go_dir)
    if result.returncode != 0:
        print_error("go build failed")
        return False

    if config.run_tests:
        test_cmd = ["go", "test", "./..."]
        if config.release:
            test_cmd.extend(["-count=1"])
        result = run_cmd(test_cmd, cwd=go_dir)
        if result.returncode != 0:
            print_error("go test failed")
            return False

    print_success("Go build complete")
    return True


# ═══════════════════════════════════════════════════════════════════════════
# MAIN ORCHESTRATOR
# ═══════════════════════════════════════════════════════════════════════════

BUILDERS: dict[Language, Callable[[BuildConfig], bool]] = {
    Language.CMAKE: build_cmake,
    Language.RUST: build_rust,
    Language.FORTRAN: build_fortran,
    Language.JULIA: build_julia,
    Language.ELIXIR: build_elixir,
    Language.R: build_r,
    Language.LEAN4: build_lean4,
    Language.GO: build_go,
}

LANG_ORDER = [
    Language.CMAKE,
    Language.RUST,
    Language.FORTRAN,
    Language.JULIA,
    Language.ELIXIR,
    Language.R,
    Language.LEAN4,
    Language.GO,
]


def parse_args() -> BuildConfig:
    parser = argparse.ArgumentParser(
        description="BOB Quantum Civilization Engine — Master Build Orchestrator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --all                    # Build all languages (debug, no tests)
  %(prog)s --all --release --test   # Build all (release + tests)
  %(prog)s --lang rust --release    # Build only Rust in release mode
  %(prog)s --lang cmake --test      # Build CMake + run tests
        """,
    )
    parser.add_argument(
        "--release",
        action="store_true",
        help="Build in release/optimized mode",
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="Run tests after building",
    )
    parser.add_argument(
        "--lang",
        type=str,
        choices=[l.value for l in Language],
        help="Build only a single language",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Build all languages (default if --lang not specified)",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="Project root directory (default: cwd)",
    )

    args = parser.parse_args()

    if args.lang and args.all:
        parser.error("Cannot use --lang and --all together")

    single_lang = Language.from_string(args.lang) if args.lang else None
    build_all = args.all or (not args.lang and not args.all)

    return BuildConfig(
        root=args.root.resolve(),
        release=args.release,
        run_tests=args.test,
        single_lang=single_lang,
        build_all=build_all,
    )


def main() -> int:
    import os  # for env in elixir

    config = parse_args()

    print_header("BOB QUANTUM CIVILIZATION ENGINE — BUILD ORCHESTRATOR")
    print_info(f"Root: {config.root}")
    print_info(f"Mode: {'Release' if config.release else 'Debug'}")
    print_info(f"Tests: {'Enabled' if config.run_tests else 'Disabled'}")
    print_info(f"Target: {config.single_lang.value if config.single_lang else 'ALL'}")

    if not config.root.exists():
        print_error(f"Project root does not exist: {config.root}")
        return 1

    # Determine which languages to build
    if config.single_lang:
        langs = [config.single_lang]
    else:
        langs = LANG_ORDER

    results: dict[Language, bool] = {}

    for lang in langs:
        builder = BUILDERS[lang]
        try:
            success = builder(config)
            results[lang] = success
        except KeyboardInterrupt:
            print_error(f"\nBuild interrupted during {lang.value}")
            return 130
        except Exception as e:
            print_error(f"Unexpected error in {lang.value}: {e}")
            results[lang] = False

    # Summary
    print_header("BUILD SUMMARY")
    all_ok = True
    for lang, ok in results.items():
        status = f"{Color.GREEN}PASS{Color.RESET}" if ok else f"{Color.RED}FAIL{Color.RESET}"
        print(f"  {lang.value:10} : {status}")
        if not ok:
            all_ok = False

    if all_ok:
        print_success("\nAll builds completed successfully!")
        return 0
    else:
        print_error("\nSome builds failed.")
        return 1


if __name__ == "__main__":
    sys.exit(main())