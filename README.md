# rakudo-star-pkg

## Rakudo-Star Packager

Provides the `rstartpkgr` tool, which
1. uses the `rstar` tool to install a specified Rakudo-Star release locally and then
2. uses the `nfpm` tools to build 
   `apk`, `archlinux`, `deb`, `rpm` and a general `relocatable tar.gz` packages

### Usage

```bash
'rstarpkgr' is the utility to create binary Rakudo-Star packages.

bin/rstarpkgr -h

Usage:

  rstarpkgr [-h] [-V <version>] [-R <revision>] [-O <os>] [-A <architecture>] [-T <compiler toolchain>] [-D <temp dir>] [-c <all | version>] [-d] [<version>]

Options:
  -h                           Print the usage help.
  -V "YYYY.MM[.#]"             Rakudo-Star version to build binary packages for.
                               Usually Rakudo-Star versions look like '2025.12',
                               sometimes there are patched versions like '2022.06.1'.
  -R "##"                      The revision is almost always 01.
  -O "operating system"        We only build on and for Linux.
  -A "architecture"            Mainly x86_64, which is also known as amd64.
  -T "compiler"                GCC on Linux.
  -D "dir"                     Your own temp. directory, if desired.
  -c ["all" | "YYYY.MM[.#]"]   Cleanup the local cache directory.
                               Specify 'all' to delete all Rakudo-Star source and binary
                               directories or provide a specific release version.
  -d                           Debug mode. Plenty of additional information.

Optional:
  ["YYYY.MM[.#]"]              If an additional CLI option is given after all the parameters,
                               it's expected to be the really desired Rakudo-Start version.
                               ATTENTION: This will overwrite any previous -V option parameter!

Environment variables:
  RSTARPKGR_BACKEND     Rakudo backend, only "moar" is supported by Rakudo.
                        DEFAULT="moar"
  RSTARPKGR_VERSION     Rakudo-Star version to build pkgs for.
                        DEFAULT="latest"
  RSTARPKGR_REVISION    Rakudo-Star revisions.
                        DEFAULT="01"
  RSTARPKGR_OS          DEFAULT="linux"     # uname -s | awk '{print tolower(\$0)}'
  RSTARPKGR_ARCH        DEFAULT="x86_64"    # uname -m
  RSTARPKGR_TOOLCHAIN   On Linux it's always gcc.
  RSTARPKGR_TMPDIR      Temp. directory.
                        DEFAULT="./tmp"
  RSTARPKGR_CLEANUP     Cleanup local cache at '$RSTARPKGR_TMPDIR'
  RSTARPKGR_DEBUG       Show more (debug) information.
                        DEFAULT="0"
  GPG_FINGERPRINT       The fingerprint of the key to use for signing release files.

```

## License

The software in this repository is distributed under the terms of the Artistic
License 2.0, same as [Rakudo Star](https://github.com/rakudo/star) and [Rakudo](https://github.com/rakudo/rakudo), unless specified otherwise.
