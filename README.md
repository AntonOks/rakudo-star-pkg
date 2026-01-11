# rakudo-star-pkg

## Rakudo-Star Packager

Provides the `rstartpkgr` tool, which
1. uses the `rstar` tool to install a specified Rakudo-Star release locally and then
2. uses the `nfpm` tools to build 
   `apk`, `archlinux`, `deb`, `rpm` and a general `relocatable tar.gz` packages

### Usage

```bash
bin/rstarpkgr -h

Usage:
	rstarpkgr [-h] [-V <version>] [-R <revision>] [-O <os>] [-A <architecture>] [-T <compiler toolchain>] [-D <temp dir>] [-c ] [-d]

rstarpkgr is the utility to create buinary Rakudo-Star packages.

Options:
  -h                    Print the usage help.
  -V "YYYY.MM[.#]"      Rakudo-Star version to build binary packages for.
                        Usually Rakudo-Star versions look like "2025.12",
                        sometimes there are patched versions like "2022.06.1".
  -R "##"               The revisions is almost always 01.
  -O "operating system" We only build on and for Linux.
  -A "architecture"     Mainly x86_64, which is also known as amd64.
  -T "compiler"         GCC on Linux.
  -D "dir"              Your own temp. directory, if desired.
  -c                    Cleanup the "temp" directory and all downloaded and
                        compliled files.
  -d                    Debug mode. Plenty of additional informations.

Environment variables:
  RSTARPKGR_BACKEND     Rakudo backend, only "moar" is supported by Rakudo.
                        DEFAULT="moar"
  RSTARPKGR_VERSION     Rakudo-Star version to build pkgs for.
                        DEFAULT="latest"
  RSTARPKGR_REVISION    Rakudo-Star revisions.
                        DEFAULT="01"
  RSTARPKGR_OS          DEFAULT="linux"
  RSTARPKGR_ARCH        DEFAULT="x86_64"
  RSTARPKGR_TOOLCHAIN   On Linux it's allways gcc.
  RSTARPKGR_TMPDIR      Temp. directory.
                        DEAULT="./tmp"
  RSTARPKGR_CLEANUP     Cleanup /home/anton/temp/Git/Github/_working_/AntonOks_rakudo-star-pkg/tmp
  RSTARPKGR_DEBUG       Show more (debug) informations.
                        DEFAULT="0"
  GPG_FINGERPRINT       The fingerprint of the key to use for signing release files.

```

## License

The software in this repository is distributed under the terms of the Artistic
License 2.0, same as [Rakudo Star](https://github.com/rakudo/star) and [Rakudo](https://github.com/rakudo/rakudo), unless specified otherwise.
