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
  tput
  nfpm
  envsubst
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
  local RSTARPKGR_OS="${RSTARPKGR_OS:-"linux"}"              # uname -s | awk '{print tolower($0)}'
  local RSTARPKGR_ARCH="${RSTARPKGR_ARCH:-"x86_64"}"         # uname -m
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

  if [ ${RSTARPKGR_GETOPT_ERROR} ]; then usage ; exit 3; fi

  export RSTAR_DEBUG=${RSTARPKGR_DEBUG}

  # Maintain our own tempdir
  if ! [[ -d ${RSTARPKGR_TMPDIR} ]]; then mkdir -p -- "${RSTARPKGR_TMPDIR}"; fi
  debug "\"\$RSTARPKGR_TMPDIR\" set to \"${RSTARPKGR_TMPDIR}\""

  # Get the Rakudo-Star source
  if [[ "${RSTARPKGR_VERSION}" == "latest" ]]; then
    debug "Fetching Rakudo-Star source from \"https://rakudo.org/latest/star/src\""
    curl -LsS https://rakudo.org/latest/star/src -o ${RSTARPKGR_TMPDIR}/rakudo-star.tar.gz
  else
    # TODO: check if the Rakudo release was already downloaded before and still exists...
    #       if so, we can skip plenty of steps
    debug "Fetching Rakudo-Star source from \"https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz\""
    if [[ $(curl -LsS https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz -o ${RSTARPKGR_TMPDIR}/rakudo-star.tar.gz) ]]; then
	    crit "Couldn't download https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz"
	    crit "You may need to verify your \$RSTARPKGR_VERSION (\"${RSTARPKGR_VERSION}\") and \$RSTARPKGR_REVISION (\"${RSTARPKGR_REVISION}\") system variables"
      crit "or"
      crit "your command line options [-V] and [-R]."
	    exit 5
	  fi
  fi


  # get the downloaded Rakudo-Star sources into the right directory structure
  cd ${RSTARPKGR_TMPDIR}
  mkdir -p -- ${RSTARPKGR_TMPDIR}/rstar_src && tar -xzf rakudo-star.tar.gz --directory ${RSTARPKGR_TMPDIR}/rstar_src && rm -f -- rakudo-star.tar.gz
  if [[ ${RSTARPKGR_VERSION} == "latest" ]]; then
	  RSTARPKGR_VERSION="$(ls -d ${RSTARPKGR_TMPDIR}/rstar_src/rakudo-star-* | grep -Po "(\d+\.\d+)(\\.[0-9]+)?")"
    debug "Changed \$RSTARPKGR_VERSION from \"latest\" to \"${RSTARPKGR_VERSION}\""
  fi
  
  mv -- ${RSTARPKGR_TMPDIR}/rstar_src ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src && cd ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src
  mv -f -- rakudo-star-*/* .
  rm -fr -- rakudo-star-*
  cd ${RSTARPKGR_TMPDIR}

  # enforce some directories
  if ! [[ -d ${RSTARPKGR_BASEDIR}/pkgs/ ]]; then mkdir -p -- ${RSTARPKGR_BASEDIR}/pkgs/; fi
  if ! [[ -d ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin/ ]]; then mkdir -p -- ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin/; fi

  # we use the Rakudo-Star `rstar` bash tool to compile and install Rakudo-Star
  # we expect the file `etc/fetch_core.txt` of the dowloaded $RSTARPKGR_VERSION
  #  is correct as it will be used by the `rstar` tool internally
  debug "Building Rakudo-Star with \"./rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src/bin/rstar install -p ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin\""
  if [[ "${RSTARPKGR_DEBUG}" ]]; then
    ./rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src/bin/rstar install -p ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin
  else
    ./rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src/bin/rstar install -p ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin > /dev/null 2>&1
  fi

  if [[ $? == "0" ]]; then
    debug "Creating the \"rakudo-star-linux-relocable-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_${RSTARPKGR_ARCH}.tar.gz\""
    tar -czf ${RSTARPKGR_BASEDIR}/pkgs/rakudo-star-linux-relocable-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_${RSTARPKGR_ARCH}.tar.gz -C ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin/ .
  else
    crit "\"rstar\" couldn't install Rakudo, please investigate why..."
    exit 10
  fi

  # export the variables we use in the `nfpm.yaml_temp` template file
  if [[ ${RSTARPKGR_ARCH} == "x86_64" ]]; then RSTARPKGR_ARCH="amd64"; fi
  export RSTARPKGR_VERSION RSTARPKGR_REVISION RSTARPKGR_ARCH RSTARPKGR_OS
  debug "Variables we use with nfpm are: RSTARPKGR_VERSION=\"${RSTARPKGR_VERSION}\", RSTARPKGR_REVISION=\"${RSTARPKGR_REVISION}\", RSTARPKGR_ARCH=\"${RSTARPKGR_ARCH}\", RSTARPKGR_OS=\"${RSTARPKGR_OS}\""
  
  # seems like nfpm cannot handle a combination of variables properly
  # we work arround with `envsubst`
  envsubst < ${RSTARPKGR_BASEDIR}/etc/nfpm.yaml_temp > ${RSTARPKGR_BASEDIR}/etc/nfpm.yaml 
  
  # now let's build the packages
  debug "Building \"apk archlinux deb rpm\" packages with \"nfpm\"."
  for PKG in apk archlinux deb rpm; do
    if [[ "${RSTARPKGR_DEBUG}" ]]; then
      nfpm pkg --config ${RSTARPKGR_BASEDIR}/etc/nfpm.yaml --packager $PKG --target ${RSTARPKGR_BASEDIR}/pkgs/
    else
      nfpm pkg --config ${RSTARPKGR_BASEDIR}/etc/nfpm.yaml --packager $PKG --target ${RSTARPKGR_BASEDIR}/pkgs/ > /dev/null
    fi
  done
  cd ${RSTARPKGR_BASEDIR}

  # Clean up if necessary
  if [[ -z ${RSTARPKGR_CLEANUP} ]]; then
    debug "Removing temp dir \"${RSTARPKGR_TMPDIR}\""
    rm -rf -- "${RSTARPKGR_TMPDIR}"

    debug "Cleaning up files in pkgs dir \"${RSTARPKGR_BASEDIR}/pkgs/\""
    rm -f -- "${RSTARPKGR_BASEDIR}/pkgs/*"
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
  RSTARPKGR_BACKEND     Rakudo backend, only "moar" is supported by Rakudo.
                        DEFAULT="moar"
  RSTARPKGR_VERSION     Rakudo-Star version to build pkgs for.
                        DEFAULT="latest"
  RSTARPKGR_REVISION    Rakudo-Star revisions.
                        DEFAULT="01"
  RSTARPKGR_OS          DEFAULT="linux"     # uname -s | awk '{print tolower(\$0)}'
  RSTARPKGR_ARCH        DEFAULT="x86_64"    # uname -m
  RSTARPKGR_TOOLCHAIN   On Linux it's allways gcc.
  RSTARPKGR_TMPDIR      Temp. directory.
                        DEAULT="./tmp"
  RSTARPKGR_CLEANUP     Cleanup $RSTARPKGR_TMPDIR
  RSTARPKGR_DEBUG       Show more (debug) informations.
                        DEFAULT="0"
  GPG_FINGERPRINT       The fingerprint of the key to use for signing release files.

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
