# manifest packages
these are for full packages which will get added to the initramfs (e.g: frecon, busybox)

each one lives in `<id>/manifest.json` with `"type": "package"` and gets pulled in by `common.json` using `_include`.
