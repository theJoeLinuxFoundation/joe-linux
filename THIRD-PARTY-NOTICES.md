# Third-party notices

joe Linux's own files are under the MIT License in [LICENSE](LICENSE). This
file lists what is not, or not only, covered by it: files in this repository
that carry another licence, work this repository is derived from, and the
software that joe Linux builds but does not contain.

## Files in this repository under another licence

| Files | Licence | Why |
|-------|---------|-----|
| `packages/linux/joe-lsm/joe.c`, `Kconfig`, `Makefile` | GPL-2.0-only | The joe security module is compiled into the Linux kernel. Each file states its licence in an SPDX line. |
| `packages/bash/joe-sealed-scripts.patch` | GPL-3.0-or-later | A change to GNU Bash, Copyright © Free Software Foundation, Inc. |
| `packages/fastfetch/joe-dave-packages.patch`, `packages/fastfetch/joe-logo.patch` | MIT | Changes to fastfetch, copyright © 2021–2023 Linus Dierheimer and © 2022–2026 Carter Li. |
| `packages/python/joe-sealed-code.patch` | PSF-2.0 | A change to CPython, Copyright © Python Software Foundation. |
| `packages/pour/joe-installer.patch` | BSD-3-Clause | A change to pour, Copyright © 2026 Maja Wittbrodt; every contribution to pour is BSD-3-Clause. |

The patches contain lines of the programs they change and are distributed
under those programs' licences. The licence texts are in
[LICENSES/](LICENSES/) and [LICENSE](LICENSE).

## Linux From Scratch and Beyond Linux From Scratch

The bootstrap (`bootstrap/stage1.sh`, `bootstrap/stage2.sh`) and the recipes
(`packages/*/build.sh`, `packages/*/package.zon`) follow the build
instructions of [Linux From Scratch](https://www.linuxfromscratch.org/lfs/)
and [Beyond Linux From Scratch](https://www.linuxfromscratch.org/blfs/),
systemd editions. Both books allow their computer instructions to be extracted
under the MIT License:

> Copyright © 1999-2026 Gerard Beekmans (Linux From Scratch)
>
> Copyright © 1999-2026 The BLFS Development Team (Beyond Linux From Scratch)
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

The text of the books is under a Creative Commons licence and is not
reproduced here. `packages/.build/book.py` downloads pages of the books into
`build/`, which is not part of this repository.

## PubGrub

dave's solver (`dave/src/solver/`) implements the PubGrub algorithm in Zig,
after Natalie Weizenbaum's description in
[dart-lang/pub](https://github.com/dart-lang/pub/blob/master/doc/solver.md)
and the structure of
[pubgrub-rs](https://github.com/pubgrub-rs/pubgrub). It contains no source
code of either project.

## Software that joe Linux builds

This repository contains no source code or binaries of the packages it builds.
Each recipe names its sources by URL and SHA-256, and they are downloaded when
the package is built. The 72 recipes marked `.network = true` can also fetch build
dependencies, including Rust crates, Go modules, npm packages, Maven
artifacts and Haskell packages.

Every recipe states its package's licence as an SPDX expression in the
`.license` field of `packages/NAME/package.zon`. To list them:

```
grep -H '\.license' packages/*/package.zon
```

The repository has about 1,430 package recipes. Each image contains a
selection of those packages, each under its own licence. Distributors
must meet the terms of the packages they distribute: for the many GPL and LGPL
packages, among them the Linux kernel, that includes providing the
corresponding source. The build machine publishes the source archive of
every package beside the installation medium (`joe-build iso`, in
`sources/`). Some packages need more care than their licence expression
shows:

- **Firefox** is built with Mozilla's unofficial branding (it calls itself
  "Nightly", and its desktop entry is "Web Browser"), because Mozilla's
  trademark policy restricts distributing builds under the Firefox name and
  logo. Official branding (`--enable-official-branding`) needs Mozilla's
  agreement.
- **7-Zip** includes its RAR decoder, whose licence forbids using the code to
  recreate the RAR compression algorithm.
- **FFmpeg, x264 and x265** implement formats (H.264, H.265, AAC and others)
  that are covered by patents in some countries.
- **TypeScript** is not built from source: the recipe installs upstream's
  compiled release. It is used only to build other packages and is not part of
  any image.
- **Julia and bun** are repackaged upstream binaries. The installation
  medium includes Julia to run pour.
- **Rust, Go, GHC and OpenJDK** use prebuilt compilers to bootstrap their
  source builds. Rust, Go and GHC use upstream binaries. OpenJDK uses the
  bootstrap JDK distributed by Beyond Linux From Scratch.
- The scaffold test image (`image/mkscaffold*.sh`) downloads an Arch Linux
  bootstrap archive. It is used for testing only.

## Trademarks

Linux is a registered trademark of Linus Torvalds. Firefox is a trademark of
the Mozilla Foundation. GNOME is a trademark of the GNOME Foundation. Other
names belong to their owners. joe Linux is not affiliated with or endorsed by
any of these projects.
