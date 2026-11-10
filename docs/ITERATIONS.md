# Iterations

Muon uses semantic-ish versioning with a physics codename:

    v<major>.<minor>.<patch> "<codename>"

* **major** - a rewrite or an incompatible change to the settings layout
* **minor** - new features
* **patch** - fixes and tuning only

Codenames are subatomic particles / leptons in order: Ion, Tau, Sigma, Kaon,
Pion, Muon, ... (the pack is named after the muon, so it will eventually reach
its own name).

Every iteration gets a permanent archive. Nothing is ever overwritten.

---

## Archive layout

The archives live next to the repository folder (Muon/iterations/), not inside it.

```
iterations/
  v1.0.0/
    shaders/              full source snapshot
    Muon-v1.0.0.zip       the built pack (same bytes as release/)
    manifest.json         version, codename, build time, sha256, file count
```

`release/` always contains the zips for the **latest** iteration, ready to
attach to the GitHub release page.

## Releasing a new iteration

1. Bump `MUON_VERSION_MINOR` / `PATCH` and `MUON_CODENAME` in
   `shaders/settings.glsl`.
2. Add a `CHANGELOG.md` section.
3. Run:

   ```bash
   python tools/gen_programs.py
   python tools/gen_lang.py
   python tools/validate.py --root .
   python tools/build.py
   ```

4. Commit. Tag `v<version>`. The GitHub workflow rebuilds the zip and attaches
   it to the release.

## Version history

| Version | Codename | Theme |
| --- | --- | --- |
| 1.0.0 | Ion | First complete release: PBR, PCSS, GTAO, SSR, volumetrics, four cloud layers, path tracer, HDR |

---

## Uploading this folder to GitHub

This folder is the repository root; it contains no `.git` directory, so start
one:

```bash
cd repo
git init -b main
git add .
git commit -m "Muon v1.0.0 (Ion)"
git tag v1.0.0
git remote add origin https://github.com/<you>/muon.git
git push -u origin main --tags
```

`release/` (next to this folder) is git-ignored on purpose: those zips are meant
to be attached to the GitHub **Releases** page, not committed. The workflow in
`.github/workflows/release.yml` rebuilds the zip on every tag and attaches it
automatically.

`iterations/` (also next to this folder) holds the permanent per-version
archives and is intentionally *not* part of the repository. Copy it somewhere
safe, or add its zips to a release if you want them public.
