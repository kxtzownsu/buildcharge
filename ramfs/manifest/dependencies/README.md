# manifest dependencies
these are intended for depencencies which are ONLY for building packages (e.g: libtsm for frecon)

each one lives in `<id>/manifest.json` with `"type": "dependency"` and gets pulled in by `common.json` using `_include`.
