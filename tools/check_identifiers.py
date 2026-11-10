#!/usr/bin/env python3
"""
Muon Shaders - undefined identifier finder.

validate.py checks function calls; this catches the other common mistake:
using a variable that was never declared (or was renamed). It works on the
preprocessed output, so includes and conditional compilation are already
resolved.

It is intentionally approximate: GLSL has no easy way to parse scopes without a
real parser, so declarations are collected globally. That means it will never
report a false positive for a name that is declared *somewhere*, but it can miss
use-before-declaration in a different scope. In practice it catches typos and
renamed variables, which is what we want.

Run: python tools/check_identifiers.py
Exit code 1 if undefined identifiers were found.
"""

from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from validate import BUILTIN_FUNCS, BUILTIN_TYPES, KEYWORDS, Preprocessor  # noqa: E402

TYPE_WORDS = set(BUILTIN_TYPES) | {
    "void", "float", "int", "uint", "bool", "double",
    "sampler2D", "sampler3D", "sampler2DShadow", "samplerCube",
}

# Words that are legal to use without declaration
EXTRA_OK = {
    "gl_Position", "gl_FragCoord", "gl_FragData", "gl_Vertex", "gl_Normal",
    "gl_Color", "gl_MultiTexCoord0", "gl_MultiTexCoord1", "gl_TextureMatrix",
    "gl_ModelViewMatrix", "gl_ModelViewProjectionMatrix", "gl_ProjectionMatrix",
    "gl_NormalMatrix", "gl_FrontFacing", "gl_PointCoord", "gl_InstanceID",
    "gl_VertexID", "flat", "smooth", "noperspective", "centroid",
    "layout", "location", "binding", "main", "defined", "include",
    "version", "extension", "pragma", "line", "if", "else", "elif", "endif",
    # provided by the Distant Horizons / Voxy compatibility layer at compile time
    "dhProjection", "dhProjectionInverse", "dhModelView", "dhModelViewInverse",
    "dhDepthTex0", "dhDepthTex1", "dhNearPlane", "dhFarPlane",
    "dhRenderDistance", "dhSunDir", "vxDepthTexOpaque", "vxDepthTexTrans",
    "ifdef", "ifndef", "define", "undef", "error",
}

DECL_PATTERNS = [
    # uniform / in / out / attribute declarations, with any qualifiers
    re.compile(
        r"(?:uniform|attribute|in|out|inout|varying|const|flat|centroid|smooth)\s+"
        r"(?:[A-Za-z_]\w*\s+)?([A-Za-z_]\w*)\s*(?=[;=,\[])"
    ),
    # ordinary declarations: <type> <name>
    re.compile(
        r"\b(?:void|float|int|uint|bool|double|vec[234]|ivec[234]|uvec[234]|"
        r"bvec[234]|mat[234](?:x[234])?|sampler\w*|[A-Z]\w*)\s+([A-Za-z_]\w*)\s*(?=[;=,\)\[\{])"
    ),
    # for loop counters
    re.compile(r"for\s*\(\s*(?:int|float|uint)\s+([A-Za-z_]\w*)\s*="),
    # struct members
    re.compile(r"^\s*(?:float|int|uint|bool|vec[234]|mat[234]|ivec[234]|uvec[234])\s+([A-Za-z_]\w*)\s*;"),
    # function parameters (name after a type)
    re.compile(r"[\(\,]\s*(?:in|out|inout|const)?\s*(?:float|int|uint|bool|vec[234]|ivec[234]|uvec[234]|mat[234]|sampler\w*|[A-Z]\w*)\s+([A-Za-z_]\w*)\s*(?=[,\)])"),
]

USE_RE = re.compile(r"(?<![\w.])([A-Za-z_]\w*)\b(?!\s*\()")


def main() -> int:
    root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shaders")
    programs = []
    for base, _dirs, files in os.walk(root):
        for name in files:
            if name.endswith((".vsh", ".fsh")):
                programs.append(os.path.join(base, name))

    total = 0
    for path in sorted(programs):
        pre = Preprocessor(root)
        parsed = pre.run(path)
        text = "\n".join(line.text for line in parsed.lines)

        declared = set()
        for pattern in DECL_PATTERNS:
            for m in pattern.finditer(text):
                declared.add(m.group(1))

        # function names and struct names are also "declared"
        declared |= set(re.findall(r"\b([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{", text))
        declared |= set(re.findall(r"\bstruct\s+([A-Za-z_]\w*)", text))
        declared |= set(re.findall(r"#define\s+([A-Za-z_]\w*)", text))
        declared |= pre.func_macros

        known = declared | TYPE_WORDS | BUILTIN_FUNCS | KEYWORDS | EXTRA_OK | set(pre.defines)

        unknown = {}
        for lineno, line in enumerate(parsed.lines, start=1):
            source = line.text
            if source.lstrip().startswith(("#", "/*", "*", "//")) or "RENDERTARGETS" in source:
                continue
            for m in USE_RE.finditer(source):
                word = m.group(1)
                if word in known:
                    continue
                # skip swizzles and struct members
                idx = m.start()
                if idx > 0 and source[idx - 1] == ".":
                    continue
                unknown.setdefault(word, (line.file, line.lineno))

        if unknown:
            total += len(unknown)
            print(f"\n{os.path.relpath(path, root)}")
            for word, (file, lineno) in sorted(unknown.items()):
                print(f"  {word:32} {os.path.relpath(file, root)}:{lineno}")

    print(f"\n{total} candidate undefined identifiers")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
