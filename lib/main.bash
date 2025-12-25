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
  #   `rakudo-[backend]-[version]-[build revision]-[OS]-[architecture]-[toolchain]`
  #   - `backend` is always `moar`
  #   - `version` represents the release month, i.e. "2025.12" or patched as "2022.06.1"
  #   - `build revision` is usually `01`
  #   - `OS` is `linux` or `win` or `macos`
  #   - `architecture` is `x86_64` for all 3 OS'es or `arm64` on "macos"
  #   - `toolchain` is `gcc` on "linux", `msvc` on "win" and `clang` on "macos"
  local RSTARPKGR_BACKEND="moar"
  local RSTARPKGR_VERSION="${RSTARPKGR_VERSION:-"latest"}"
  local RSTARPKGR_REVISION="${RSTARPKGR_REVISION:-"01"}"
  local RSTARPKGR_OS="${RSTARPKGR_OS:-"linux"}"				# uname -s | awk '{print tolower($0)}'
  local RSTARPKGR_ARCH="${RSTARPKGR_ARCH:-"x86_64"}"		# uname -m
  local RSTARPKGR_TOOLCHAIN="${RSTARPKGR_TOOLCHAIN:-"gcc"}"

  # Rakudo-Star `rstar` release examples to build a own binary release
  # - https://www.rakudo.org/dl/star/rakudo-star-2025.12-01.tar.gz
  # - https://www.rakudo.org/dl/star/rakudo-star-2022.06.1-01.tar.gz

  local RSTARPKGR_TMPDIR="${RSTARPKGR_TMPDIR:-"$(pwd -P)/tmp"}"
  local RSTARPKGR_DEBUG="${RSTARPKGR_DEBUG:-"0"}"
  local RSTARPKGR_CLEANUP="${RSTARPKGR_CLEANUP:-"0"}"




  while getopts ":V:R:O:A:T:D:C:d" opt
  do
    case "$opt" in
			V) RSTARPKGR_VERSION=$OPTARG ;;
			R) RSTARPKGR_REVISION=$OPTARG ;;
			O) RSTARPKGR_OS=$OPTARG ;;
			A) RSTARPKGR_ARCH=$OPTARG ;;
			T) RSTARPKGR_TOOLCHAIN=$OPTARG ;;
			D) RSTARPKGR_TMPDIR=$OPTARG ;;
			C) RSTARPKGR_CLEANUP=$OPTARG ;;
			d) RSTARPKGR_DEBUG=1 ;;
			*) emerg "Invalid option specified: $opt" ; RSTARPKGR_GETOPT_ERROR=1 ;;
    esac
  done

  shift $(( OPTIND - 1 ))

  if [ $RSTARPKGR_GETOPT_ERROR ]; then exit; fi

  # export RSTARPKGR_BACKEND RSTARPKGR_VERSION RSTARPKGR_REVISION RSTARPKGR_OS RSTARPKGR_ARCH RSTARPKGR_TOOLCHAIN
  # export RSTARPKGR_TMPDIR RSTARPKGR_DEBUG RSTARPKGR_CLEANUP



  # Maintain our own tempdir
  mkdir -p -- "$RSTARPKGR_TMPDIR"
  debug "\$RSTARPKGR_TMPDIR set to $RSTARPKGR_TMPDIR"


  # Get the Rakudo-Star source
  if [ $RSTARPKGR_VERSION == "latest" ]; then
    debug "Fetching Rakudo-Star source from https://rakudo.org/latest/star/src"
    curl -LsS https://rakudo.org/latest/star/src -o ${RSTARPKGR_TMPDIR}/rakudo-star.tar.gz
  else
    debug "Fetching Rakudo-Star source from https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz"
    curl -LsS https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz -o ${RSTARPKGR_TMPDIR}/rakudo-star.tar.gz
  fi  

  cd ${RSTARPKGR_TMPDIR}
  mkdir rstar_src && tar -xzf rakudo-star.tar.gz --directory rstar_src && rm -f rakudo-star.tar.gz
  cd rstar_src && mv rakudo-star-*/* .
  rm -fr rakudo-star-* && cd ..
  export RSTAR_DEBUG=$RSTARPKGR_DEBUG
  ./rstar_src/bin/rstar install -p $(pwd -P)/rstar_bin
  if [ $RSTARPKGR_ARCH == "x86_64" ]; then RSTARPKGR_ARCH="amd64"; fi

  # export the variables we use in the nfpm_vars.yaml file
  export RSTARPKGR_VERSION RSTARPKGR_REVISION RSTARPKGR_ARCH RSTARPKGR_OS
  for PKG in apk archlinux deb rpm; do
    sudo nfpm pkg --config $RSTARPKGR_BASEDIR/etc/nfpm_vars.yaml --packager $PKG --target $(pwd -P)/pkgs/
  done
  cd ..


	# Clean up if necessary
	if [[ -z $RSTARPKGR_CLEANUP ]]
	then
		debug "Cleaning up tempfiles at $RSTARPKGR_TMPDIR"
		rm -rf -- "$RSTARPKGR_TMPDIR"
	fi

}

usage() {
	cat <<EOF
Usage:
	rstarpkgr [-h] 


rstarpkgr is the entry point for all utilities to deal with the Rakudo-Star packager.

Actions:
	build-docker  Build a Docker image for Rakudo Star.
	              You can specify the tag of the resulting image using -T,
	              which will cause -d, -t, and -l to be ignored.
	              -n specifies the name of the image.
	              If -l is passed, a "latest" tag will also be made.
	              You can specify a specific backend with -b.
	clean         Clean up the repository.
	              If -s is given, the src directory will also be removed.
	dist          Create a distributable tarball of this repository.
	              If no version identifier is specified, it will assume
	              it should build on top of the latest RAKUDO release
	              and resolve "https://github.com/rakudo/rakudo/releases/latest"
	              for something like i.e. "2020.08" or "2020.08.1".
	              If the "RAKUDO latest" doesn't match, it will fallback
	              to "rakudo_version" from "etc/fetch_core.txt".
	fetch         Fetch all required sources.
	              If -l is given, the GitHub "latest" releases from all core
	              components (MoarVM, NQP, Rakudo) will be fetched.
	              If "GitHub component latest" doesn't fit, fallback to
	              components "version" and "url" from "etc/fetch_core.txt".
	install       Install Raku on this system.
	              By default, MoarVM will be used as the only backend, and
	              the Rakudo Star directory will be used as prefix.
	              If neither core nor modules are given as explicit targets,
	              all targets will be installed.
	sysinfo       Show information about your system.
	              Useful for debugging.
	test          Run tests on Raku and the bundled ecosystem modules.
	              If neither spectest nor modules are given as explicit
	              targets, all targets will be tested.

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

