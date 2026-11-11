#!/usr/bin/env python3
"""
Muon Shaders - tools/validate.py

Static validation for the shader pack. It is not a GLSL compiler; it is the
safety net that catches the failure modes a shader pack actually has:

  * a missing or misspelled #include
  * a function used before it is declared (GLSL requires declaration order)
  * an undeclared identifier used as a function
  * unbalanced braces or parentheses
  * a fragment stage that declares an input its vertex stage does not output
  * a uniform declared twice with different types
  * a fragment pass with outputs but no RENDERTARGETS directive
  * an option used in shaders.properties that does not exist in settings.glsl
  * a profile or slider that names an unknown option
  * a missing preset, or the wrong preset order
  * leftover placeholder markers
  * referenced textures that do not exist or have the wrong dimensions

Usage:
    python tools/validate.py [--verbose]
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHADERS = ROOT / "shaders"

GLSL_BUILTINS = {
    # types
    "float", "int", "uint", "bool", "double", "vec2", "vec3", "vec4", "ivec2",
    "ivec3", "ivec4", "uvec2", "uvec3", "uvec4", "bvec2", "bvec3", "bvec4",
    "mat2", "mat3", "mat4", "mat2x2", "mat2x3", "mat2x4", "mat3x2", "mat3x3",
    "mat3x4", "mat4x2", "mat4x3", "mat4x4", "sampler1D", "sampler2D",
    "sampler3D", "samplerCube", "sampler2DShadow", "sampler2DArray",
    # constructors / conversion
    "vec2", "vec3", "vec4", "texture", "textureLod", "textureGrad", "texelFetch",
    "textureSize", "textureOffset", "textureProj", "texture2D", "texture2DLod",
    # maths
    "abs", "acos", "acosh", "all", "any", "asin", "asinh", "atan", "atanh",
    "ceil", "clamp", "cos", "cosh", "cross", "degrees", "determinant", "distance",
    "dot", "equal", "exp", "exp2", "faceforward", "floor", "fma", "fract",
    "greaterThan", "greaterThanEqual", "inverse", "inversesqrt", "isinf", "isnan",
    "length", "lessThan", "lessThanEqual", "log", "log2", "matrixCompMult", "max",
    "min", "mix", "mod", "modf", "normalize", "not", "notEqual", "pow",
    "radians", "reflect", "refract", "round", "roundEven", "sign", "sin", "sinh",
    "smoothstep", "sqrt", "step", "tan", "tanh", "transpose", "trunc",
    "dFdx", "dFdy", "fwidth", "packHalf2x16", "unpackHalf2x16", "floatBitsToInt",
    "intBitsToFloat", "uintBitsToFloat", "floatBitsToUint", "bitCount",
    "findLSB", "findMSB", "outerProduct", "ldexp", "frexp", "interpolateAtCentroid",
    "ftransform", "shadow2D", "texture2DProj", "texture3D", "textureCube", "vec2", "vec3", "vec4",
}

GLSL_KEYWORDS = {
    "if", "else", "for", "while", "do", "switch", "case", "default", "break",
    "continue", "return", "discard", "struct", "in", "out", "inout", "uniform",
    "const", "flat", "smooth", "noperspective", "layout", "location", "highp",
    "mediump", "lowp", "precision", "void", "true", "false", "defined", "buffer",
    "shared", "coherent", "volatile", "restrict", "readonly", "writeonly",
}


@dataclass
class Diagnostic:
    severity: str
    path: str
    line: int
    message: str

    def __str__(self) -> str:
        return f"{self.severity}: {self.path}:{self.line}: {self.message}"


@dataclass
class Preprocessor:
    """A small C-style preprocessor sufficient for a shader pack."""

    macros: dict[str, str] = field(default_factory=dict)
    macro_params: dict[str, int] = field(default_factory=dict)
    diagnostics: list[Diagnostic] = field(default_factory=list)
    included: set[str] = field(default_factory=set)

    def resolve_include(self, spec: str, current: Path) -> Path | None:
        if spec.startswith("/"):
            candidate = SHADERS / spec[1:]
        else:
            candidate = current.parent / spec
        if candidate.exists():
            return candidate
        return None

    def expand_object_macros(self, text: str, depth: int = 0) -> str:
        if depth > 8:
            return text

        def replace(match: re.Match[str]) -> str:
            name = match.group(0)
            if name in self.macros:
                return self.expand_object_macros(self.macros[name], depth + 1)
            return name

        return re.sub(r"\b[A-Z_][A-Z0-9_]*\b", replace, text)

    def evaluate(self, expression: str) -> bool:
        expr = expression.strip()

        def defined_paren(match: re.Match[str]) -> str:
            return "1" if match.group(1) in self.macros else "0"

        def defined_plain(match: re.Match[str]) -> str:
            return "1" if match.group(1) in self.macros else "0"

        expr = re.sub(r"defined\s*\(\s*(\w+)\s*\)", defined_paren, expr)
        expr = re.sub(r"defined\s+(\w+)", defined_plain, expr)
        expr = self.expand_object_macros(expr)

        def substitute_identifiers(match: re.Match[str]) -> str:
            name = match.group(1)
            if name in self.macro_params:
                return name
            return "1" if name in self.macros else "0"

        expr = re.sub(r"\b([A-Za-z_]\w*)\b", substitute_identifiers, expr)
        expr = expr.replace("&&", " and ").replace("||", " or ")
        expr = re.sub(r"!(?!=)", " not ", expr)
        if not expr.strip():
            return True
        try:
            return bool(eval(expr, {"__builtins__": {}}, {}))  # noqa: S307
        except Exception:
            self.diagnostics.append(
                Diagnostic("error", "shaders.properties", 0, f"cannot evaluate condition: {expression!r}")
            )
            return False

    def process(self, path: Path, stack: list[str] | None = None) -> list[tuple[int, str]]:
        stack = stack or []
        key = str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)
        if key in stack:
            chain = " -> ".join(stack + [key])
            self.diagnostics.append(Diagnostic("error", key, 0, f"include cycle: {chain}"))
            return []
        if path not in self.included:
            self.included.add(str(path))

        try:
            raw = path.read_text(encoding="utf-8")
        except OSError:
            self.diagnostics.append(Diagnostic("error", key, 0, "cannot read file"))
            return []

        output: list[tuple[int, str]] = []
        # (parent_active, this_branch_taken)
        conditions: list[tuple[bool, bool]] = []
        active = True

        for number, line in enumerate(raw.splitlines(), start=1):
            stripped = line.strip()

            if stripped.startswith("#if"):
                if stripped.startswith("#ifdef"):
                    name = stripped[6:].strip()
                    value = name in self.macros
                elif stripped.startswith("#ifndef"):
                    name = stripped[7:].strip()
                    value = name not in self.macros
                else:
                    value = self.evaluate(stripped[3:])
                conditions.append((active, value))
                active = active and value
                continue

            if stripped.startswith("#elif"):
                if not conditions:
                    continue
                parent, taken = conditions[-1]
                value = (not taken) and self.evaluate(stripped[5:])
                conditions[-1] = (parent, taken or value)
                active = parent and value
                continue

            if stripped.startswith("#else"):
                if not conditions:
                    continue
                parent, taken = conditions[-1]
                conditions[-1] = (parent, True)
                active = parent and not taken
                continue

            if stripped.startswith("#endif"):
                if conditions:
                    parent, _ = conditions.pop()
                    active = parent
                continue

            if not active:
                continue

            if stripped.startswith("#include"):
                match = re.match(r'#include\s+"([^"]+)"', stripped)
                if not match:
                    self.diagnostics.append(Diagnostic("error", key, number, "malformed #include"))
                    continue
                target = self.resolve_include(match.group(1), path)
                if target is None:
                    self.diagnostics.append(
                        Diagnostic("error", key, number, f"missing include {match.group(1)!r}")
                    )
                    continue
                output.extend(self.process(target, stack + [key]))
                continue

            if stripped.startswith("#define"):
                body = stripped[7:].strip()
                match = re.match(r"([A-Za-z_]\w*)(\(([^)]*)\))?\s*(.*)", body)
                if match:
                    name = match.group(1)
                    params = match.group(3)
                    value = match.group(4).strip()
                    # Drop trailing option annotations such as "// [1 2 3]";
                    # they are UI metadata, not part of the value.
                    value = re.sub(r"//.*$", "", value).strip()
                    value = re.sub(r"/\*.*?\*/", "", value).strip()
                    if params is not None:
                        self.macro_params[name] = len([p for p in params.split(",") if p.strip()])
                        self.macros[name] = value
                    else:
                        self.macros[name] = value
                continue

            if stripped.startswith("#undef"):
                name = stripped[6:].strip()
                self.macros.pop(name, None)
                continue

            if stripped.startswith("#version") or stripped.startswith("#extension"):
                output.append((number, line))
                continue

            output.append((number, line))

        return output


# ------------------------------------------------------------------------------
#  Source checks
# ------------------------------------------------------------------------------

FUNCTION_DEFINITION = re.compile(
    r"^\s*(?:[A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*\((?:[^;{}]*)\)\s*\{?",
    re.MULTILINE,
)
CALL_SITE = re.compile(r"\b([A-Za-z_]\w*)\s*\(")


def strip_comments(text: str) -> str:
    """Blanks out comments while preserving offsets."""
    out = list(text)
    i = 0
    while i < len(text):
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = len(text) if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = len(text) if j == -1 else j + 2
            for k in range(i, min(j, len(text))):
                if out[k] != "\n":
                    out[k] = " "
            i = j
        else:
            i += 1
    return "".join(out)


DECLARATION = re.compile(r"(?m)^[ \t]*(?:[A-Za-z_]\w*[ \t]+)+([A-Za-z_]\w*)[ \t]*\(")


def check_source(path: Path, lines: list[tuple[int, str]], diags: list[Diagnostic], macros: Preprocessor) -> None:
    rel = str(path.relative_to(ROOT))
    text = "\n".join(line for _, line in lines)

    # --- balance -----------------------------------------------------------
    for opener, closer, label in (("{", "}", "braces"), ("(", ")", "parentheses"), ("[", "]", "brackets")):
        if text.count(opener) != text.count(closer):
            diags.append(
                Diagnostic(
                    "error",
                    rel,
                    0,
                    f"unbalanced {label}: {text.count(opener)} {opener} vs {text.count(closer)} {closer}",
                )
            )

    clean = strip_comments(text)
    structs = set(re.findall(r"\bstruct\s+([A-Za-z_]\w*)", clean))

    # --- declarations, with offsets ---------------------------------------
    declared_at: dict[str, list[int]] = {}
    for match in DECLARATION.finditer(clean):
        name = match.group(1)
        if name in GLSL_KEYWORDS:
            continue
        declared_at.setdefault(name, []).append(match.start())

    # --- calls must resolve against an earlier declaration -----------------
    reported: set[str] = set()
    for match in CALL_SITE.finditer(clean):
        name = match.group(1)
        if name in GLSL_KEYWORDS or name in GLSL_BUILTINS or name in structs or name in macros.macros:
            continue
        if name in reported:
            continue
        positions = declared_at.get(name)
        if not positions:
            diags.append(Diagnostic("error", rel, 0, f"call to undeclared function {name!r}"))
            reported.add(name)
        elif min(positions) > match.start():
            diags.append(Diagnostic("error", rel, 0, f"function {name!r} used before its declaration"))
            reported.add(name)

    # --- duplicate definitions --------------------------------------------
    signature_re = re.compile(r"(?m)^[ \t]*(?:[A-Za-z_]\w*[ \t]+)+([A-Za-z_]\w*)[ \t]*\(([^)]*)\)[ \t]*\{")
    signatures: dict[str, int] = {}
    for match in signature_re.finditer(clean):
        name = match.group(1)
        if name in GLSL_KEYWORDS:
            continue
        key = f"{name}({re.sub(r'[ \t]+', ' ', match.group(2)).strip()})"
        signatures[key] = signatures.get(key, 0) + 1
    for key, count in signatures.items():
        if count > 1:
            diags.append(Diagnostic("error", rel, 0, f"duplicate definition of {key}"))


TYPE_NAMES = (
    "float|int|uint|bool|double|void|"
    "vec2|vec3|vec4|ivec2|ivec3|ivec4|uvec2|uvec3|uvec4|bvec2|bvec3|bvec4|"
    "mat2|mat3|mat4|mat2x3|mat3x2|mat3x4|mat4x2|mat4x3|"
    "sampler1D|sampler2D|sampler3D|samplerCube|"
    "MuonFrame|MuonMaterial|MuonWave|MuonAO|MuonReflection|MuonVolumetric|"
    "MuonCloudWeather|MuonCloudSample|MuonGISample|MuonSpecular|MuonFogSample|"
    "MuonSunScreen"
)
DECLARED_NAME = re.compile(r"(?:" + TYPE_NAMES + r")\s+([A-Za-z_]\w*)")
PACK_IDENTIFIER = re.compile(r"\b((?:muon|MUON)_[A-Za-z0-9_]+)\b")


SAMPLER_USE = re.compile(r"\b(?:texture|textureLod|textureGrad|texelFetch|textureSize|textureOffset|textureProj)\s*\(\s*([A-Za-z_]\w*)")


def _read_parens(text: str, start: int) -> tuple[str, int]:
    """Returns the contents of the parenthesised group starting at `start`."""
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return text[start + 1 : index], index
        index += 1
    return "", len(text)


def _split_args(inner: str) -> list[str]:
    if not inner.strip():
        return []
    parts: list[str] = []
    depth = 0
    current = []
    for char in inner:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append("".join(current))
            current = []
            continue
        current.append(char)
    parts.append("".join(current))
    return [part for part in parts if part.strip()]


def check_call_arity(path: Path, lines: list[tuple[int, str]], diags: list[Diagnostic], macros: Preprocessor) -> None:
    """Validates the argument count of calls to functions defined in the pack.

    Signature drift is the most common bug left behind by a refactor, and GLSL
    reports it as a type error far from the cause.
    """
    rel = str(path.relative_to(ROOT))
    text = "\n".join(line for _, line in lines)
    clean = strip_comments(text)

    arities: dict[str, set[int]] = {}
    for match in DECLARATION.finditer(clean):
        name = match.group(1)
        if name in GLSL_KEYWORDS:
            continue
        open_paren = clean.find("(", match.end() - 1)
        if open_paren == -1:
            continue
        inner, _ = _read_parens(clean, open_paren)
        arities.setdefault(name, set()).add(len(_split_args(inner)))

    structs = set(re.findall(r"\bstruct\s+([A-Za-z_]\w*)", clean))

    reported: set[str] = set()
    for match in CALL_SITE.finditer(clean):
        name = match.group(1)
        if name in GLSL_KEYWORDS or name in GLSL_BUILTINS or name in structs or name in macros.macros:
            continue
        if name not in arities:
            continue
        open_paren = match.end() - 1
        inner, _ = _read_parens(clean, open_paren)
        count = len(_split_args(inner))
        if count not in arities[name]:
            key = f"{name}/{count}"
            if key in reported:
                continue
            reported.add(key)
            diags.append(
                Diagnostic(
                    "error",
                    rel,
                    0,
                    f"{name}() called with {count} argument(s), declared with {sorted(arities[name])}",
                )
            )


def check_sampler_usage(path: Path, lines: list[tuple[int, str]], diags: list[Diagnostic]) -> None:
    """Every sampler that is sampled must be declared in the program.

    This exists because a declaration can go missing during a refactor without
    any syntax error: the shader simply reads a default black texture.
    """
    rel = str(path.relative_to(ROOT))
    text = "\n".join(line for _, line in lines)
    clean = strip_comments(text)

    declared = set(
        re.findall(r"^\s*uniform\s+sampler\w*\s+([A-Za-z_]\w*)\s*;", clean, re.MULTILINE)
    )
    # Opaque types may also be function parameters (the GI tracer takes its
    # radiance field as a sampler argument).
    declared |= set(re.findall(r"sampler\w*\s+([A-Za-z_]\w*)\s*[,)]", clean))

    reported: set[str] = set()
    for match in SAMPLER_USE.finditer(clean):
        name = match.group(1)
        if name in declared or name in reported:
            continue
        reported.add(name)
        diags.append(Diagnostic("error", rel, 0, f"sampler {name!r} is sampled but never declared"))


def check_identifiers(path: Path, lines: list[tuple[int, str]], diags: list[Diagnostic], macros: Preprocessor) -> None:
    """Every muon_/MUON_ identifier must be declared somewhere in the program.

    A general scope analysis would need a GLSL front end; checking only the
    pack's own prefix keeps the false-positive rate at zero while still catching
    typos and symbols left behind by a refactor.
    """
    rel = str(path.relative_to(ROOT))
    text = "\n".join(line for _, line in lines)
    clean = strip_comments(text)

    known: set[str] = set(macros.macros) | set(macros.macro_params)
    known |= set(re.findall(r"\bstruct\s+([A-Za-z_]\w*)", clean))
    known |= {match.group(1) for match in DECLARATION.finditer(clean)}
    known |= {match.group(1) for match in DECLARED_NAME.finditer(clean)}

    reported: set[str] = set()
    for match in PACK_IDENTIFIER.finditer(clean):
        name = match.group(1)
        if name in known or name in reported:
            continue
        reported.add(name)
        diags.append(Diagnostic("error", rel, 0, f"undeclared identifier {name!r}"))


# Identifiers the loader injects itself. Declaring one of these is a duplicate
# definition on the driver, so it is an error here.
INJECTED_BY_LOADER = {
    "dhMaterialId",  # Iris' Distant Horizons integration
}


def check_uniforms(path: Path, lines: list[tuple[int, str]], diags: list[Diagnostic]) -> None:
    rel = str(path.relative_to(ROOT))
    declared: dict[str, str] = {}
    for _, line in lines:
        match = re.match(r"^\s*uniform\s+(?:(?:lowp|mediump|highp)\s+)?(\w+)\s+(\w+)\s*(\[[^\]]*\])?\s*;", line)
        if not match:
            continue
        type_name, name = match.group(1), match.group(2)
        if name in INJECTED_BY_LOADER:
            diags.append(
                Diagnostic(
                    "error",
                    rel,
                    0,
                    f"uniform {name!r} is injected by the loader and must not be declared",
                )
            )
            continue
        if name in declared:
            if declared[name] != type_name:
                diags.append(
                    Diagnostic(
                        "error",
                        rel,
                        0,
                        f"uniform {name!r} declared as {declared[name]} and {type_name}",
                    )
                )
            else:
                # Identical re-declaration is still rejected by NVIDIA's
                # front end (C1038), so it is an error here too.
                diags.append(
                    Diagnostic("error", rel, 0, f"uniform {name!r} declared more than once")
                )
        declared[name] = type_name


def check_outputs(path: Path, lines: list[tuple[int, str]], diags: list[Diagnostic]) -> None:
    rel = str(path.relative_to(ROOT))
    text = "\n".join(line for _, line in lines)

    locations = [int(m) for m in re.findall(r"layout\s*\(\s*location\s*=\s*(\d+)\s*\)\s*out\s", text)]
    target_match = re.search(r"RENDERTARGETS:\s*([0-9,\s]+)", text)

    if locations and not target_match and not path.name.startswith("final"):
        if "gbuffers_sky" not in path.name and "voxy" not in path.name:
            diags.append(Diagnostic("error", rel, 0, "fragment stage writes outputs but has no RENDERTARGETS"))
        return

    if not target_match:
        return

    targets = [int(value) for value in re.findall(r"\d+", target_match.group(1))]
    if len(targets) != len(locations):
        diags.append(
            Diagnostic(
                "error",
                rel,
                0,
                f"RENDERTARGETS lists {len(targets)} buffers but the stage declares {len(locations)} outputs",
            )
        )
    for target in targets:
        if target < 0 or target > 15:
            diags.append(Diagnostic("error", rel, 0, f"RENDERTARGETS references colortex{target}, which does not exist"))


# ------------------------------------------------------------------------------
#  Stage pairing
# ------------------------------------------------------------------------------

def extract_interface(path: Path, pre: Preprocessor, direction: str) -> dict[str, tuple[str, str]]:
    lines = pre.process(path)
    result: dict[str, tuple[str, str]] = {}
    for _, line in lines:
        match = re.match(
            r"^\s*(flat\s+)?(?:in|out)\s+(?:(?:lowp|mediump|highp)\s+)?(\w+)\s+(\w+)\s*;", line
        )
        if not match:
            continue
        qualifier = "flat" if match.group(1) else ""
        prefix = line.strip().split()[0]
        if (direction == "in" and prefix.startswith("in")) or (
            direction == "out" and prefix.startswith("out")
        ):
            result[match.group(3)] = (match.group(2), qualifier)
    return result


# ------------------------------------------------------------------------------
#  shaders.properties
# ------------------------------------------------------------------------------

def validate_properties(diags: list[Diagnostic]) -> None:
    path = SHADERS / "shaders.properties"
    if not path.exists():
        diags.append(Diagnostic("error", "shaders/shaders.properties", 0, "missing"))
        return

    text = path.read_text(encoding="utf-8")
    options = parse_settings_options()

    profiles: list[str] = []
    for match in re.finditer(r"^profile\.(\w+)\s*=\s*(.+)$", text, re.MULTILINE):
        name, body = match.group(1), match.group(2)
        if name == "comment" or name.endswith("comment"):
            continue
        profiles.append(name)
        for token in body.split():
            token = token.lstrip("!").split("=")[0]
            if not token or token in {"true", "false"}:
                continue
            if token not in options and token not in {"shadowMapResolution", "shadowDistance", "sunPathRotation"}:
                diags.append(Diagnostic("error", "shaders/shaders.properties", 0, f"profile {name}: unknown option {token}"))

    expected = ["low", "medium", "high", "ultra", "raytraced", "rtgi", "ptgi"]
    if profiles != expected:
        diags.append(
            Diagnostic(
                "error",
                "shaders/shaders.properties",
                0,
                f"profile order is {profiles}, expected {expected}",
            )
        )

    # Every option referenced from a screen must exist.
    screen_names: set[str] = set()
    referenced: set[str] = set()
    for match in re.finditer(r"^screen(?:\.(\w+))?\s*=\s*(.+)$", text, re.MULTILINE):
        name = match.group(1)
        if name:
            screen_names.add(name)
        body = match.group(2)
        for token in body.split():
            if token.startswith("[") or token.startswith("<"):
                continue
            if token.isupper() or re.fullmatch(r"[A-Z][A-Z0-9_]*", token):
                referenced.add(token)

    for name in sorted(screen_names):
        if name not in {"columns"} and f"screen.{name}.columns" not in text:
            # Subscreens referenced from a parent screen must exist.
            if f"[{name}]" not in text:
                diags.append(Diagnostic("warning", "shaders/shaders.properties", 0, f"screen {name!r} is never linked"))

    for token in sorted(referenced):
        if token not in options and token not in {"shadowMapResolution", "shadowDistance", "sunPathRotation"}:
            diags.append(Diagnostic("error", "shaders/shaders.properties", 0, f"screen references unknown option {token}"))

    slider_match = re.search(r"^sliders\s*=\s*(.+)$", text, re.MULTILINE)
    if slider_match:
        for token in slider_match.group(1).split():
            if token not in options and token not in {"shadowMapResolution", "shadowDistance", "sunPathRotation"}:
                diags.append(Diagnostic("error", "shaders/shaders.properties", 0, f"slider {token!r} is not an option"))

    # Subscreens must be reachable from the root screen.
    root = re.search(r"^screen\s*=\s*(.+)$", text, re.MULTILINE)
    if root:
        reachable = set(re.findall(r"\[(\w+)\]", root.group(1)))
        changed = True
        while changed:
            changed = False
            for name in list(reachable):
                body = re.search(rf"^screen\.{name}\s*=\s*(.+)$", text, re.MULTILINE)
                if body:
                    for child in re.findall(r"\[(\w+)\]", body.group(1)):
                        if child not in reachable:
                            reachable.add(child)
                            changed = True
        for name in sorted(screen_names):
            if name not in reachable and name != "columns":
                diags.append(Diagnostic("warning", "shaders/shaders.properties", 0, f"subscreen {name!r} is unreachable"))

    # Textures referenced by the properties must exist with the stated size.
    for match in re.finditer(r"^texture\.[\w.]+(?:\s*=\s*)(\S+)(.*)$", text, re.MULTILINE):
        relative = match.group(1)
        if relative.startswith("minecraft:"):
            continue
        target = SHADERS / relative
        if not target.exists():
            diags.append(Diagnostic("error", "shaders/shaders.properties", 0, f"missing texture {relative}"))
            continue
        rest = match.group(2).split()
        if rest and rest[0] == "TEXTURE_3D" and len(rest) >= 5:
            try:
                size = int(rest[2]) * int(rest[3]) * int(rest[4])
            except ValueError:
                continue
            if target.stat().st_size != size:
                diags.append(
                    Diagnostic(
                        "error",
                        "shaders/shaders.properties",
                        0,
                        f"{relative}: expected {size} bytes for the declared dimensions, found {target.stat().st_size}",
                    )
                )


def parse_settings_options() -> set[str]:
    path = SHADERS / "settings.glsl"
    options: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\s*(?://)?\s*#define\s+([A-Z][A-Z0-9_]*)", line)
        if match:
            options.add(match.group(1))
        const = re.match(r"^\s*const\s+\w+\s+(\w+)\s*=", line)
        if const:
            options.add(const.group(1))
    return options


# ------------------------------------------------------------------------------
#  Entry point
# ------------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    diags: list[Diagnostic] = []
    programs = sorted(
        [p for p in SHADERS.glob("*.vsh")] + [p for p in SHADERS.glob("*.fsh")]
    )

    if not programs:
        diags.append(Diagnostic("error", "shaders/", 0, "no programs found"))
        return 1

    for program in programs:
        pre = Preprocessor()
        lines = pre.process(program)
        diags.extend(pre.diagnostics)
        pre.diagnostics.clear()

        check_source(program, lines, diags, pre)
        check_uniforms(program, lines, diags)
        check_identifiers(program, lines, diags, pre)
        check_sampler_usage(program, lines, diags)
        check_call_arity(program, lines, diags, pre)
        if program.suffix == ".fsh":
            check_outputs(program, lines, diags)

        if args.verbose:
            print(f"  checked {program.name} ({len(lines)} lines after preprocessing)")

    # Stage pairing: every fragment input needs a vertex output.
    for fsh in sorted(SHADERS.glob("*.fsh")):
        vsh = fsh.with_suffix(".vsh")
        if not vsh.exists():
            diags.append(Diagnostic("error", fsh.name, 0, "no matching vertex shader"))
            continue
        pre_f = Preprocessor()
        pre_v = Preprocessor()
        fragment_inputs = extract_interface(fsh, pre_f, "in")
        vertex_outputs = extract_interface(vsh, pre_v, "out")
        for name, (type_name, qualifier) in fragment_inputs.items():
            if name not in vertex_outputs:
                diags.append(
                    Diagnostic("error", fsh.name, 0, f"input {name!r} has no matching vertex output")
                )
            else:
                other_type, other_qualifier = vertex_outputs[name]
                if other_type != type_name:
                    diags.append(
                        Diagnostic("error", fsh.name, 0, f"input {name!r} is {type_name} but output is {other_type}")
                    )
                if qualifier != other_qualifier:
                    diags.append(
                        Diagnostic("error", fsh.name, 0, f"input {name!r} qualifier mismatch (flat)")
                    )

    validate_properties(diags)

    # Placeholder scan
    markers = ("TODO", "FIXME", "code goes here", "placeholder", "XXX:")
    for path in list(SHADERS.rglob("*.glsl")) + list(SHADERS.rglob("*.vsh")) + list(SHADERS.rglob("*.fsh")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for marker in markers:
            if marker in text:
                diags.append(Diagnostic("error", str(path.relative_to(ROOT)), 0, f"placeholder marker {marker!r}"))

    errors = [d for d in diags if d.severity == "error"]
    warnings = [d for d in diags if d.severity == "warning"]

    for diag in sorted(diags, key=lambda d: (d.path, d.line)):
        print(diag)

    print()
    print(f"{len(programs)} programs, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
