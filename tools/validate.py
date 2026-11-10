#!/usr/bin/env python3
"""
Muon Shaders - static validator.

There is no GLSL compiler available in CI for an OptiFine/Iris pack, so this
tool does the next best thing:

  * a faithful C-style preprocessor (#include, #if/#ifdef/#elif/#else/#endif,
    object-like and function-like #define, #undef)
  * include resolution against the shaders/ root
  * brace / paren / bracket balance checks
  * undefined function-call detection (the single most common GLSL mistake)
  * duplicate function detection
  * RENDERTARGETS / #version / main() presence checks
  * option cross-checks between settings.glsl and shaders.properties

Exit code is non-zero if any error was found.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field

SHADERS_DIR = "shaders"

IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
INCLUDE_RE = re.compile(r'^\s*#\s*include\s+"([^"]+)"')
DIRECTIVE_RE = re.compile(r"^\s*#\s*(\w+)\s*(.*)$")

KEYWORDS = {
    "if", "for", "while", "switch", "return", "else", "do", "case", "default",
    "break", "continue", "discard", "struct", "layout", "in", "out", "inout",
    "const", "uniform", "attribute", "varying", "flat", "smooth", "noperspective",
    "centroid", "precision", "highp", "mediump", "lowp", "void", "bool", "int",
    "uint", "float", "double", "true", "false", "defined", "sizeof", "using",
}

BUILTIN_TYPES = {
    "vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4",
    "bvec2", "bvec3", "bvec4", "dvec2", "dvec3", "dvec4",
    "mat2", "mat3", "mat4", "mat2x2", "mat2x3", "mat2x4", "mat3x2", "mat3x3",
    "mat3x4", "mat4x2", "mat4x3", "mat4x4",
    "float16_t", "f16vec2", "f16vec3", "f16vec4",
}

BUILTIN_FUNCS = {
    # angle / trig
    "radians", "degrees", "sin", "cos", "tan", "asin", "acos", "atan", "sinh",
    "cosh", "tanh", "asinh", "acosh", "atanh",
    # exponential
    "pow", "exp", "log", "exp2", "log2", "sqrt", "inversesqrt",
    # common
    "abs", "sign", "floor", "trunc", "round", "roundEven", "ceil", "fract",
    "mod", "modf", "min", "max", "clamp", "mix", "step", "smoothstep",
    "isnan", "isinf", "floatBitsToInt", "floatBitsToUint", "intBitsToFloat",
    "uintBitsToFloat", "fma", "frexp", "ldexp",
    # geometric
    "length", "distance", "dot", "cross", "normalize", "faceforward", "reflect",
    "refract", "matrixCompMult", "outerProduct", "transpose", "determinant",
    "inverse",
    # vector relational
    "lessThan", "lessThanEqual", "greaterThan", "greaterThanEqual", "equal",
    "notEqual", "any", "all", "not",
    # texture
    "texture", "textureProj", "textureLod", "textureOffset", "texelFetch",
    "texelFetchOffset", "textureProjOffset", "textureLodOffset",
    "textureProjLod", "textureProjLodOffset", "textureGrad", "textureGradOffset",
    "textureProjGrad", "textureProjGradOffset", "textureSize", "textureQueryLod",
    "textureQueryLevels", "textureSamples", "textureGather", "textureGatherOffset",
    "textureGatherOffsets",
    # derivatives
    "dFdx", "dFdy", "fwidth", "dFdxFine", "dFdyFine", "dFdxCoarse", "dFdyCoarse",
    # interpolation
    "interpolateAtCentroid", "interpolateAtSample", "interpolateAtOffset",
    # packing
    "packUnorm2x16", "packSnorm2x16", "packUnorm4x8", "packSnorm4x8",
    "unpackUnorm2x16", "unpackSnorm2x16", "unpackUnorm4x8", "unpackSnorm4x8",
    "packDouble2x32", "unpackDouble2x32", "packHalf2x16", "unpackHalf2x16",
    "bitfieldExtract", "bitfieldInsert", "bitfieldReverse", "bitCount",
    "findLSB", "findMSB", "uaddCarry", "usubBorrow", "umulExtended",
    "imulExtended", "atomicAdd", "atomicMin", "atomicMax", "atomicAnd",
    "atomicOr", "atomicXor", "atomicExchange", "atomicCompSwap", "memoryBarrier",
    "barrier", "groupMemoryBarrier", "imageLoad", "imageStore", "imageSize",
    "imageAtomicAdd", "imageAtomicMin", "imageAtomicMax", "imageAtomicAnd",
    "imageAtomicOr", "imageAtomicXor", "imageAtomicExchange", "imageAtomicCompSwap",
    "subgroupAdd", "subgroupBallot", "subgroupElect", "subgroupAll",
    "subgroupAny", "subgroupBroadcast",
    # compatibility profile built-ins
    "ftransform", "texture2D", "texture3D", "textureCube", "shadow2D", "shadow2DProj",
    # misc
    "int", "uint", "float", "bool",
}


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

@dataclass
class Line:
    text: str
    file: str
    lineno: int


@dataclass
class Program:
    path: str
    lines: list[Line] = field(default_factory=list)


class Preprocessor:
    def __init__(self, root: str, define_overrides: dict[str, str] | None = None):
        self.root = os.path.abspath(root)
        self.defines: dict[str, str] = {}
        self.func_macros: set[str] = set()
        self.errors: list[str] = []
        self.stack: list[str] = []
        if define_overrides:
            self.defines.update(define_overrides)

    # -- helpers ---------------------------------------------------------
    def resolve(self, current_file: str, target: str) -> str | None:
        if target.startswith("/"):
            cand = os.path.join(self.root, target.lstrip("/"))
        else:
            cand = os.path.join(os.path.dirname(current_file), target)
        cand = os.path.normpath(cand)
        if not cand.startswith(self.root):
            return None
        return cand if os.path.isfile(cand) else None

    def expand(self, text: str, depth: int = 0) -> str:
        """Expand object-like macros (one pass, repeated a few times)."""
        if depth > 8:
            return text
        out = text
        changed = True
        passes = 0
        while changed and passes < 8:
            changed = False
            passes += 1
            for name, value in self.defines.items():
                if name in ("__LINE__",):
                    continue
                pattern = re.compile(r"\b" + re.escape(name) + r"\b")
                new = pattern.sub(value, out)
                if new != out:
                    out = new
                    changed = True
        return out

    # -- expression evaluation -------------------------------------------
    def eval_condition(self, expr: str, where: str) -> bool:
        expr = expr.strip()

        def defined_sub(m: re.Match) -> str:
            name = m.group(1)
            return "1" if name in self.defines else "0"

        expr = re.sub(r"defined\s*\(\s*([A-Za-z_]\w*)\s*\)", defined_sub, expr)
        expr = re.sub(r"defined\s+([A-Za-z_]\w*)", defined_sub, expr)

        # expand macros
        for _ in range(6):
            new = self.expand(expr)
            if new == expr:
                break
            expr = new

        # unknown identifiers become 0, like the C preprocessor
        def unknown(m: re.Match) -> str:
            word = m.group(0)
            if word in ("and", "or", "not", "True", "False"):
                return word
            return "0"

        expr = re.sub(r"[A-Za-z_]\w*", unknown, expr)
        expr = expr.replace("&&", " and ").replace("||", " or ")
        expr = re.sub(r"!(?!=)", " not ", expr)
        expr = expr.replace("/", " / ")  # C integer division differs; our uses are floats
        try:
            return bool(eval(expr, {"__builtins__": {}}, {}))
        except Exception as exc:  # pragma: no cover - diagnostics only
            self.errors.append(f"{where}: cannot evaluate condition '{expr}' ({exc})")
            return False

    # -- main ------------------------------------------------------------
    def run(self, path: str) -> Program:
        program = Program(path=path)
        self._process_file(path, program, top=True)
        return program

    def _process_file(self, path: str, program: Program, top: bool = False) -> None:
        if path in self.stack:
            self.errors.append(f"circular include: {' -> '.join(self.stack + [path])}")
            return
        if not os.path.isfile(path):
            self.errors.append(f"missing file: {path}")
            return

        self.stack.append(path)

        # conditional stack: (parent_active, branch_taken, current_active)
        cond: list[list[bool]] = []

        def active() -> bool:
            return all(c[2] for c in cond)

        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            raw_text = handle.read()

        # Handle backslash line continuations before splitting into lines
        raw_text = raw_text.replace("\\\r\n", " ").replace("\\\n", " ")
        raw_lines = raw_text.splitlines()

        in_block_comment = False

        for lineno, raw in enumerate(raw_lines, start=1):
            text = raw
            where = f"{os.path.relpath(path, self.root)}:{lineno}"

            # Preserve the RENDERTARGETS / DRAWBUFFERS markers: they live inside
            # block comments that the analyser would otherwise drop.
            if "RENDERTARGETS" in text or "DRAWBUFFERS" in text:
                program.lines.append(Line(text, path, lineno))

            # strip comments but keep the line structure
            stripped, in_block_comment = self._strip_comments(text, in_block_comment)

            m = DIRECTIVE_RE.match(stripped)
            if m:
                directive = m.group(1)
                rest = m.group(2).strip()

                if directive == "if":
                    parent = active()
                    value = self.eval_condition(rest, where) if parent else False
                    cond.append([parent, value, parent and value])
                    continue
                if directive == "ifdef":
                    parent = active()
                    name = rest.split()[0] if rest else ""
                    value = name in self.defines
                    cond.append([parent, value, parent and value])
                    continue
                if directive == "ifndef":
                    parent = active()
                    name = rest.split()[0] if rest else ""
                    value = name not in self.defines
                    cond.append([parent, value, parent and value])
                    continue
                if directive == "elif":
                    if not cond:
                        self.errors.append(f"{where}: #elif without #if")
                        continue
                    parent, taken, _ = cond[-1]
                    value = self.eval_condition(rest, where) if parent and not taken else False
                    cond[-1] = [parent, taken or value, parent and not taken and value]
                    continue
                if directive == "else":
                    if not cond:
                        self.errors.append(f"{where}: #else without #if")
                        continue
                    parent, taken, _ = cond[-1]
                    cond[-1] = [parent, True, parent and not taken]
                    continue
                if directive == "endif":
                    if not cond:
                        self.errors.append(f"{where}: #endif without #if")
                        continue
                    cond.pop()
                    continue

                if not active():
                    continue

                if directive == "include":
                    inc = INCLUDE_RE.match(stripped)
                    if not inc:
                        self.errors.append(f"{where}: malformed #include")
                        continue
                    target = self.resolve(path, inc.group(1))
                    if target is None:
                        self.errors.append(f"{where}: cannot resolve include '{inc.group(1)}'")
                        continue
                    self._process_file(target, program)
                    continue

                if directive == "define":
                    self._handle_define(rest, where)
                    continue

                if directive == "undef":
                    name = rest.split()[0] if rest else ""
                    self.defines.pop(name, None)
                    continue

                if directive in ("version", "extension", "pragma", "error"):
                    if directive == "error":
                        self.errors.append(f"{where}: #error {rest}")
                    # keep version/extension lines in the output
                    if directive == "version":
                        program.lines.append(Line(f"#version {rest}", path, lineno))
                    elif directive == "extension":
                        program.lines.append(Line(f"#extension {rest}", path, lineno))
                    continue

                # any other directive is passed through
                program.lines.append(Line(stripped, path, lineno))
                continue

            if not active():
                continue

            program.lines.append(Line(stripped, path, lineno))

        if cond:
            self.errors.append(f"{os.path.relpath(path, self.root)}: unterminated #if")

        self.stack.pop()

    def _handle_define(self, rest: str, where: str) -> None:
        m = re.match(r"([A-Za-z_]\w*)(\([^)]*\))?\s*(.*)$", rest)
        if not m:
            self.errors.append(f"{where}: malformed #define")
            return
        name, params, value = m.group(1), m.group(2), m.group(3).strip()
        if params is not None:
            # function-like macro: register for call checking, keep a stub value
            self.func_macros.add(name)
            self.defines[name] = "0"
        else:
            self.defines[name] = value if value else "1"

    @staticmethod
    def _strip_comments(text: str, in_block: bool) -> tuple[str, bool]:
        out = []
        i = 0
        while i < len(text):
            if in_block:
                end = text.find("*/", i)
                if end == -1:
                    return "".join(out), True
                i = end + 2
                in_block = False
                out.append(" ")
                continue
            if text.startswith("//", i):
                break
            if text.startswith("/*", i):
                in_block = True
                i += 2
                continue
            out.append(text[i])
            i += 1
        return "".join(out), in_block


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

@dataclass
class Issue:
    severity: str
    where: str
    message: str


def analyse(program: Program, func_macros: set[str], structs: set[str]) -> list[Issue]:
    issues: list[Issue] = []

    # Build a source string with line mapping
    text_lines = [line.text for line in program.lines]
    text = "\n".join(text_lines)

    # Balance
    for open_ch, close_ch, name in (("{", "}", "brace"), ("(", ")", "paren"), ("[", "]", "bracket")):
        depth = 0
        open_line = 1
        for idx, line in enumerate(text_lines, start=1):
            for ch in line:
                if ch == open_ch:
                    depth += 1
                    if depth == 1:
                        open_line = idx
                elif ch == close_ch:
                    depth -= 1
                    if depth < 0:
                        loc = program.lines[idx - 1]
                        issues.append(Issue("error", f"{loc.file}:{loc.lineno}",
                                            f"unmatched '{close_ch}'"))
                        depth = 0
        if depth > 0:
            loc = program.lines[open_line - 1]
            issues.append(Issue("error", f"{loc.file}:{loc.lineno}",
                                f"{depth} unclosed '{open_ch}'"))

    # Declared functions. Overloads are legal in GLSL, so signatures (name +
    # normalised parameter type list) are what we de-duplicate on.
    decl_re = re.compile(
        r"\b(?:void|float|int|uint|bool|vec[234]|ivec[234]|uvec[234]|bvec[234]"
        r"|mat[234](?:x[234])?|MaterialData|[A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*\(([^;{}]*)\)\s*\{"
    )
    declared: dict[str, int] = {}
    signatures: dict[str, int] = {}
    arities: dict[str, set[int]] = {}
    for m in decl_re.finditer(text):
        name = m.group(1)
        if name in KEYWORDS:
            continue
        declared[name] = declared.get(name, 0) + 1

        params = m.group(2)
        # strip parameter names, keep types: "in vec3 a, float b" -> "vec3,float"
        types = []
        for part in params.split(","):
            part = part.strip()
            if not part or part == "void":
                continue
            part = re.sub(r"^\s*(in|out|inout|const|highp|mediump|lowp)\s+", "", part)
            tokens = part.split()
            types.append(tokens[0] if tokens else "?")
        signature = f"{name}({','.join(types)})"
        signatures[signature] = signatures.get(signature, 0) + 1
        arities.setdefault(name, set()).add(len(types))

    for signature, count in signatures.items():
        if count > 1:
            issues.append(Issue("error", program.path, f"function defined {count} times: {signature}"))

    known = set(declared) | BUILTIN_TYPES | BUILTIN_FUNCS | func_macros | structs | KEYWORDS

    # Calls
    call_re = re.compile(r"\b([A-Za-z_]\w*)\s*\(")
    reported: set[str] = set()
    for idx, line in enumerate(text_lines, start=1):
        for m in call_re.finditer(line):
            name = m.group(1)
            if name in known:
                continue
            if name in reported:
                continue
            # skip preprocessor lines
            if line.lstrip().startswith("#"):
                continue
            reported.add(name)
            loc = program.lines[idx - 1]
            issues.append(Issue("error", f"{loc.file}:{loc.lineno}",
                                f"call to undefined function '{name}'"))

    # Argument counts for user defined functions (single line calls only)
    for idx, line in enumerate(text_lines, start=1):
        if line.lstrip().startswith("#"):
            continue
        for m in call_re.finditer(line):
            name = m.group(1)
            if name not in arities or name in KEYWORDS:
                continue
            depth = 1
            i = m.end()
            commas = 0
            has_content = False
            balanced = False
            while i < len(line):
                ch = line[i]
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        balanced = True
                        break
                elif ch == "," and depth == 1:
                    commas += 1
                elif not ch.isspace() and depth >= 1:
                    has_content = True
                i += 1
            if not balanced:
                continue
            argc = 0 if not has_content else commas + 1
            if argc not in arities[name]:
                loc = program.lines[idx - 1] if idx - 1 < len(program.lines) else None
                where = f"{loc.file}:{loc.lineno}" if loc else program.path
                issues.append(Issue(
                    "error", where,
                    f"'{name}' called with {argc} argument(s), expected "
                    + " or ".join(str(a) for a in sorted(arities[name]))
                ))

    # Version + targets
    non_empty = [ln for ln in program.lines if ln.text.strip()]
    if non_empty and not non_empty[0].text.strip().startswith("#version"):
        issues.append(Issue("warning", program.path, "no #version directive on the first line"))

    if program.path.endswith(".fsh"):
        if "RENDERTARGETS" not in text:
            issues.append(Issue("warning", program.path, "no RENDERTARGETS directive"))
        if "void main" not in text and "voxy_emitFragment" not in text:
            issues.append(Issue("error", program.path, "no main() entry point"))

    if program.path.endswith(".vsh") and "void main" not in text:
        issues.append(Issue("error", program.path, "no main() entry point"))

    return issues


# ---------------------------------------------------------------------------
# Optional checks against settings.glsl / shaders.properties
# ---------------------------------------------------------------------------

def settings_options(root: str) -> tuple[dict[str, bool], dict[str, str]]:
    path = os.path.join(root, "settings.glsl")
    bools: dict[str, bool] = {}
    numbers: dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            m = re.match(r"#define\s+([A-Z_][A-Z0-9_]*)\s*(.*)$", line)
            if m:
                name, rest = m.group(1), m.group(2).strip()
                if rest.startswith("("):
                    continue
                if rest == "":
                    bools[name] = True
                else:
                    numbers[name] = rest
                continue

            # Loader-recognised constants also become sliders
            c = re.match(r"const\s+(?:int|float|bool)\s+([A-Za-z_]\w*)\s*=\s*([^;]+);", line)
            if c:
                numbers[c.group(1)] = c.group(2).strip()
    return bools, numbers


def check_properties(root: str, numbers: dict[str, str], bools: dict[str, bool]) -> list[Issue]:
    issues: list[Issue] = []
    path = os.path.join(root, "shaders.properties")
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()

    # every referenced option must exist
    scan = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        scan.append(line.split("#", 1)[0])
    scan_text = "\n".join(scan)

    for m in re.finditer(r"\b([A-Z][A-Z0-9_]{2,})\b", scan_text):
        name = m.group(1)
        if name in numbers or name in bools:
            continue
        if name in {"INFO", "SHADOW_PCF", "TAA", "FXAA", "CAS", "BLOOM", "DOF",
                    "MOTION_BLUR", "POM", "RT", "VL", "SSR", "HDR", "VOXY",
                    "DH", "TAAU", "IRIS", "SEPARATE_HARDWARE_SAMPLERS",
                    "CUSTOM_IMAGES", "ENTITY_TRANSLUCENT", "RGBA16F", "RGBA16",
                    "RGBA8", "RG16F", "RGB16F", "R32F", "RGB8", "RGBA32F",
                    "R11F_G11F_B10F", "DH_BLEND_DEPTH", "VOXY_SUPPORT",
                    "CLOUD_SHADOWMAP", "HDR_USE_FP16", "LDR", "ONE",
                    "ONE_MINUS_SRC_ALPHA", "SRC_ALPHA", "ZERO", "OFF"}:
            continue
        issues.append(Issue("warning", "shaders.properties", f"unknown option name '{name}'"))

    return issues


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="repository root containing shaders/")
    parser.add_argument("--dump", default=None, help="directory to write flattened programs to")
    parser.add_argument("--json", default=None, help="write machine readable results here")
    args = parser.parse_args()

    root = os.path.abspath(os.path.join(args.root, SHADERS_DIR))
    if not os.path.isdir(root):
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 2

    programs: list[str] = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in sorted(filenames):
            if name.endswith((".vsh", ".fsh", ".csh", ".gsh")):
                programs.append(os.path.join(dirpath, name))

    programs.sort()

    all_issues: list[Issue] = []
    results = {}

    for program in programs:
        pre = Preprocessor(root)
        parsed = pre.run(program)
        all_issues.extend(Issue("error", os.path.relpath(program, root), e) for e in pre.errors)

        # Collect struct names from the flattened source
        structs = set(re.findall(r"\bstruct\s+([A-Za-z_]\w*)", "\n".join(l.text for l in parsed.lines)))

        issues = analyse(parsed, pre.func_macros, structs)
        all_issues.extend(issues)
        results[os.path.relpath(program, root)] = {
            "lines": len(parsed.lines),
            "issues": [i.__dict__ for i in issues],
        }

        if args.dump:
            os.makedirs(args.dump, exist_ok=True)
            out = os.path.join(args.dump, os.path.relpath(program, root).replace(os.sep, "__"))
            with open(out, "w", encoding="utf-8") as handle:
                handle.write("\n".join(l.text for l in parsed.lines))

    # option cross checks
    try:
        bools, numbers = settings_options(root)
        all_issues.extend(check_properties(root, numbers, bools))

        # Keep the sliders line up to date
        props_path = os.path.join(root, "shaders.properties")
        with open(props_path, "r", encoding="utf-8") as handle:
            props = handle.read()
        sliders = " ".join(sorted(numbers.keys()))
        new_props, count = re.subn(r"^sliders\s*=.*$", f"sliders = {sliders}", props, flags=re.MULTILINE)
        if count == 0:
            new_props = props.replace("sliders = PLACEHOLDER", f"sliders = {sliders}")
            count = 1
        if new_props != props:
            with open(props_path, "w", encoding="utf-8") as handle:
                handle.write(new_props)
            print(f"updated sliders list ({len(numbers)} numeric options)")
    except FileNotFoundError as exc:
        all_issues.append(Issue("error", "settings.glsl", str(exc)))

    errors = [i for i in all_issues if i.severity == "error"]
    warnings = [i for i in all_issues if i.severity == "warning"]

    for issue in errors + warnings:
        print(f"{issue.severity.upper():7} {issue.where}: {issue.message}")

    total_lines = sum(r["lines"] for r in results.values())
    print(f"\n{len(programs)} programs, {total_lines} flattened lines, "
          f"{len(errors)} errors, {len(warnings)} warnings")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump({"results": results,
                       "errors": [i.__dict__ for i in errors],
                       "warnings": [i.__dict__ for i in warnings]}, handle, indent=2)

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
