#!/usr/bin/env bash

# set -x 

# shellcheck source=lib/util.bash
#source "$(dirname "${BASH_SOURCE[0]}")/util.bash"

# shellcheck source=lib/logging.bash
source "$(dirname "${BASH_SOURCE[0]}")/logging.bash"

# Define required tools
RSTARPKGR_TOOLS+=(
  git
  gcc
  curl
  tar
  nfpm
)

main() {

  # Ensure all required tools are available
  tool_check || exit 3

  # The Rakudo release filenames follow the pattern:
  #  `rakudo-[backend]-[version]-[build revision]-[OS]-[architecture]-[toolchain]`
  #  - `backend` is always `moar`
  #  - `version` represents the release month, i.e. "2025.12" or patched as "2022.06.1"
  #  - `build revision` is usually `01`
  #  - `OS` is `linux` or `win` or `macos`
  #  - `architecture` is `x86_64` for all 3 OS'es or `arm64` on "macos"
  #  - `toolchain` is `gcc` on "linux", `msvc` on "win" and `clang` on "macos"
  # We define similar variables
  local RSTARPKGR_BACKEND="moar"
  local RSTARPKGR_VERSION="${RSTARPKGR_VERSION:-"latest"}"
  local RSTARPKGR_REVISION="${RSTARPKGR_REVISION:-"01"}"
  local RSTARPKGR_OS="${RSTARPKGR_OS:-"linux"}"				# uname -s | awk '{print tolower($0)}'
  local RSTARPKGR_ARCH="${RSTARPKGR_ARCH:-"x86_64"}"		# uname -m
  local RSTARPKGR_TOOLCHAIN="${RSTARPKGR_TOOLCHAIN:-"gcc"}"

  # Rakudo-Star `rstar` release examples, to build an own binary release from:
  #  - https://www.rakudo.org/dl/star/rakudo-star-2025.12-01.tar.gz
  #  - https://www.rakudo.org/dl/star/rakudo-star-2022.06.1-01.tar.gz

  local RSTARPKGR_TMPDIR="${RSTARPKGR_TMPDIR:-"$(pwd -P)/tmp"}"
  local RSTARPKGR_DEBUG="${RSTARPKGR_DEBUG:-0}"
  local RSTARPKGR_CLEANUP="${RSTARPKGR_CLEANUP:-0}"

  while getopts ":V:R:O:A:T:D:cdh" opt
  do
    case "$opt" in
			V) RSTARPKGR_VERSION=$OPTARG ;;
			R) RSTARPKGR_REVISION=$OPTARG ;;
			O) RSTARPKGR_OS=$OPTARG ;;
			A) RSTARPKGR_ARCH=$OPTARG ;;
			T) RSTARPKGR_TOOLCHAIN=$OPTARG ;;
			D) RSTARPKGR_TMPDIR=$OPTARG ;;
			c) RSTARPKGR_CLEANUP=$OPTARG ;;
			d) RSTARPKGR_DEBUG=1 ;;
			h) usage ; exit 0 ;;
			*) emerg "Invalid option specified: $opt" ; RSTARPKGR_GETOPT_ERROR=1 ;;
    esac
  done
  shift $(( OPTIND - 1 ))

  if [ $RSTARPKGR_GETOPT_ERROR ]; then usage ; exit; fi

  # Maintain our own tempdir
  mkdir -p -- "$RSTARPKGR_TMPDIR"
  debug "\$RSTARPKGR_TMPDIR set to $RSTARPKGR_TMPDIR"


  # Get the Rakudo-Star source
  if [ $RSTARPKGR_VERSION == "latest" ]; then
    debug "Fetching Rakudo-Star source from https://rakudo.org/latest/star/src"
    curl -LsS https://rakudo.org/latest/star/src -o ${RSTARPKGR_TMPDIR}/rakudo-star.tar.gz
  else
    debug "Fetching Rakudo-Star source from https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz"
    if [[ $(curl -LsS https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz -o ${RSTARPKGR_TMPDIR}/rakudo-star.tar.gz) ]]; then
	    crit "Couldn't download https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz"
	    crit "You may need to verify your \"$RSTARPKGR_VERSION\" and or \"$RSTARPKGR_REVISION\" system variables or command line options."
	    exit 5
	  fi
  fi

  cd ${RSTARPKGR_TMPDIR}

  mkdir -p -- rstar_src && tar -xzf rakudo-star.tar.gz --directory rstar_src && rm -f rakudo-star.tar.gz && cd rstar_src
  if [ $RSTARPKGR_VERSION == "latest" ]; then
	  RSTARPKGR_VERSION="$(ls -d rakudo-star-* | grep -Po "(\d+\.\d+)(\\.[0-9]+)?")"
    debug "Changing \$RSTARPKGR_VERSION from \"latest\" to \"$RSTARPKGR_VERSION\""
  fi
  mv rakudo-star-*/* .
  rm -fr rakudo-star-* && cd ..

  export RSTAR_DEBUG=$RSTARPKGR_DEBUG
  debug "Building Rakudo-Star with \"./rstar_src/bin/rstar install -p $(pwd -P)/rstar_bin\""
  echo "LINE 104: running \"./rstar_src/bin/rstar install -p $(pwd -P)/rstar_bin\""
  
  # export the variables we use in the nfpm_vars.yaml file
  if [ $RSTARPKGR_ARCH == "x86_64" ]; then RSTARPKGR_ARCH="amd64"; fi
    export RSTARPKGR_VERSION RSTARPKGR_REVISION RSTARPKGR_ARCH RSTARPKGR_OS
    debug "Variables used with nfpm are: RSTARPKGR_VERSION=\"$RSTARPKGR_VERSION\", RSTARPKGR_REVISION=\"$RSTARPKGR_REVISION\", RSTARPKGR_ARCH=\"$RSTARPKGR_ARCH\", RSTARPKGR_OS=\"$RSTARPKGR_OS\""
    for PKG in apk archlinux deb rpm; do
      nfpm pkg --config $RSTARPKGR_BASEDIR/etc/nfpm.yaml --packager $PKG --target $RSTARPKGR_BASEDIR/pkgs/
    done
  cd $RSTARPKGR_BASEDIR

  # Clean up if necessary
  if [[ -z $RSTARPKGR_CLEANUP ]]; then
    debug "Cleaning up temp. dir \"$RSTARPKGR_TMPDIR\""
    rm -rf -- "$RSTARPKGR_TMPDIR"
  fi

}

usage() {
	cat <<EOF
Usage:
	rstarpkgr [-h] [-V <version>] [-R <revision>] [-O <os>] [-A <architecture>] [-T <compiler toolchain>] [-D <temp dir>] [-c ] [-d]

rstarpkgr is the utility to create buinary Rakudo-Star packages.

Options:
  -h                    Print the usage help.
  -V "YYYY.MM[.#]"      Rakudo-Star version to build binary packages for.
                        Usually Rakudo-Star versions look like "2025.12",
                        sometimes there are patched verions like "2022.06.1".
  -R "##"               The revisions is almost always 01.
  -O "operating system" We only build on and for Linux.
  -A "architecture"     Mainly x86_64, which is also known as amd64.
  -T "compiler"         GCC on Linux.
  -D "dir"              Your own temp. directory, if desired.
  -c                    Cleanup the "temp" directory and all downloaded and
                        compliled files.
  -d                    Debug mode. Plenty of additional informations.

Environment variables:
	RSTARPKGR_DEBUG
		            Show more (debug) informations.
	GPG_FINGERPRINT
                	The fingerprint of the key to use for signing release files.

EOF
}

# This function checks for the availability of (binary) utilities in the user's
# $PATH environment variable.
tool_check() {
	local missing=()
	local bindep_db

	for tool in "${RSTARPKGR_TOOLS[@]}"
	do
		debug "Checking for availability of $tool"
		command -v "$tool" > /dev/null && continue

		missing+=("$tool")
	done

	if [[ ${missing[*]} ]]
	then
		alert "Some required tools are missing:"

		for tool in "${missing[@]}"
		do
			alert "  $tool"
		done

		return 1
	fi
}


discover_system_arch() {
	uname -m
}

discover_system_os() {
	if command -v uname > /dev/null
	then
		printf "%s" "$(uname -s | awk '{print tolower($0)}' | sed 's@[/+ ]@_@g')"
		return
	fi
}

main "$@"
