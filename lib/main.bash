#!/usr/bin/env bash

# set -x 

# shellcheck source=lib/util.bash
source "$(dirname "${BASH_SOURCE[0]}")/util.bash"

# shellcheck source=lib/logging.bash
source "$(dirname "${BASH_SOURCE[0]}")/logging.bash"

# Define required tools
RSTARPKGR_TOOLS+=(
  git
  gcc
  curl
  tar
  mktemp
  tput
  nfpm
  envsubst
)

main() {

  # Ensure all required tools are available
  tool_check || return 3

  # Set our variables
  init_vars   || return 4

  while getopts ":V:R:O:A:T:D:c:dh" opt
  do
    case $opt in
			V) RSTARPKGR_VERSION=$OPTARG ;;
			R) RSTARPKGR_REVISION=$OPTARG ;;
			O) RSTARPKGR_OS=$OPTARG ;;
			A) RSTARPKGR_ARCH=$OPTARG ;;
			T) RSTARPKGR_TOOLCHAIN=$OPTARG ;;
			D) RSTARPKGR_TMPDIR=$OPTARG ;;
			c) RSTARPKGR_CLEANUP=$OPTARG ;;
			d) RSTARPKGR_DEBUG=1 ;;
			h) usage ; exit 0 ;;
			*) emerg "Invalid option specified: $opt" ; usage ; return 5 ;;
    esac
  done
  shift $(( OPTIND - 1 ))

  # If any other CLI option is given, assume it's meant to be the Rakudo-Star version
  # This has priority over the -V option, if also given!
  [[ "$1" ]] && RSTARPKGR_VERSION=$(echo $1 | grep -Po "(\d+\.\d+)(\\.[0-9]+)?") && shift

  # Check for unexpected additional parameters
  if [[ $# -gt 0 ]]; then
    emerg "Unexpected argument(s): $@"
    usage
    exit 5
  fi

  export RSTARPKGR_BACKEND RSTARPKGR_VERSION RSTARPKGR_REVISION RSTARPKGR_OS RSTARPKGR_ARCH RSTARPKGR_TOOLCHAIN
  export RSTARPKGR_TMPDIR RSTARPKGR_xxxTMPDIR RSTARPKGR_DEBUG RSTARPKGR_CLEANUP

  # If we want debug, we also ensure the rstar tool gets chatty
  export RSTAR_DEBUG=${RSTARPKGR_DEBUG} || unset RSTAR_DEBUG


  if [[ "${RSTARPKGR_CLEANUP}" != 0 ]]; then
   debug "Calling \"rm_cache\" with \"${RSTARPKGR_CLEANUP}\""
   rm_cache "${RSTARPKGR_CLEANUP}"
   return
  fi

  # If a specific Rakudo-Star version is given, we check out our cache for it
  # otherwise, we will check the cache once we derived the version from the `latest` tar.gz download
  [[ ${RSTARPKGR_VERSION} == "latest" ]] || chk_cache "${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}"

  mk_pkgr_dirs || return 7


  # Get the Rakudo-Star source
  if [[ "${RSTARPKGR_VERSION}" == "latest" ]]; then
    debug "Fetching Rakudo-Star source from \"https://rakudo.org/latest/star/src\""
    (chgdir "${RSTARPKGR_xxxTMPDIR}" && curl -Ls https://rakudo.org/latest/star/src | tar -xzf -)
    RSTARPKGR_VERSION=$(ls -1d "${RSTARPKGR_xxxTMPDIR}"/rakudo-star* | grep -Po "(\d+\.\d+)(\\.[0-9]+)?")
    debug "Rakudo-Star \"latest\" is \"$RSTARPKGR_VERSION\""

    # We now know the `latest` Rakudo-Star version. Lets first check our cache for it
    chk_cache "${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}"
  else
    debug "Fetching Rakudo-Star source from \"https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz\""
    (chgdir "${RSTARPKGR_xxxTMPDIR}" && curl -Ls https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz | tar -xzf - 2>/dev/null )
    if [[ "$?" != "0" ]]; then
	    crit "Couldn't download https://www.rakudo.org/dl/star/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}.tar.gz"
      crit "Visit https://www.rakudo.org/downloads/star and make sure such a release is available! Or..."
	    crit "... verify your \$RSTARPKGR_VERSION (\"${RSTARPKGR_VERSION}\") and \$RSTARPKGR_REVISION (\"${RSTARPKGR_REVISION}\") system variables or..."
      crit "... adopt your command line options [-V] and [-R] to an available rakudo.org version."
	    return 10
	  fi
  fi

  mv -f -- "${RSTARPKGR_xxxTMPDIR}/rakudo-star-${RSTARPKGR_VERSION}" "${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src" && rmdir -- "${RSTARPKGR_xxxTMPDIR}"

  chgdir "${RSTARPKGR_TMPDIR}"

  # We use the Rakudo-Star `rstar` bash tool to compile and install Rakudo-Star
  # We expect the file `etc/fetch_core.txt` of the downloaded $RSTARPKGR_VERSION
  #  is correct as it will be used by the `rstar` tool internally
  debug "Building Rakudo-Star with \"${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src/bin/rstar install -p ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin\""

  ### For debugging, where a long running build isn't the issue, uncomment the 2x below lines to exit here...
  # read -p 'Press "y" to continue or any other key to exit...' YN
  # [[ "$YN" == y* ]] || exit
  
  [[ -x "${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src/bin/rstar" ]] || die "Couldn't find the \"rstar\" tool, please investigate"
  if [[ "${RSTARPKGR_DEBUG}" ]]; then
    ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src/bin/rstar install -p ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin
  else
    ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_src/bin/rstar install -p ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin > /dev/null 2>&1
  fi

  if [[ $? == "0" ]]; then
    debug "Creating the \"rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_${RSTARPKGR_ARCH}-linux-relocatable.tar.gz\""
    tar -czf ${RSTARPKGR_BASEDIR}/pkgs/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_${RSTARPKGR_ARCH}-linux-relocatable.tar.gz -C ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin/ .
  else
    crit "\"rstar\" tool couldn't install Rakudo, please investigate why..."
    return 15
  fi

  # export the variables we use in the `nfpm.yaml_temp` template file
  [[ ${RSTARPKGR_ARCH} == "x86_64" ]] && RSTARPKGR_ARCH="amd64"
  export RSTARPKGR_VERSION RSTARPKGR_REVISION RSTARPKGR_ARCH RSTARPKGR_OS
  debug "Variables we use with nfpm are: RSTARPKGR_VERSION=\"${RSTARPKGR_VERSION}\", RSTARPKGR_REVISION=\"${RSTARPKGR_REVISION}\", RSTARPKGR_ARCH=\"${RSTARPKGR_ARCH}\", RSTARPKGR_OS=\"${RSTARPKGR_OS}\""
  
  # seems like nfpm cannot handle a combination of variables properly
  # we work around with `envsubst`
  envsubst < ${RSTARPKGR_BASEDIR}/etc/nfpm.yaml_temp > ${RSTARPKGR_BASEDIR}/etc/nfpm.yaml 
  
  # now let's build the packages
  debug "Building \"apk archlinux deb ipk rpm\" packages with \"nfpm\"."
  for PKG in apk archlinux deb ipk rpm; do
    if [[ "${RSTARPKGR_DEBUG}" ]]; then
      nfpm pkg --config ${RSTARPKGR_BASEDIR}/etc/nfpm.yaml --packager $PKG --target ${RSTARPKGR_BASEDIR}/pkgs/
    else
      $(nfpm pkg --config ${RSTARPKGR_BASEDIR}/etc/nfpm.yaml --packager $PKG --target ${RSTARPKGR_BASEDIR}/pkgs/) > /dev/null 2>&1
    fi
  done

  chgdir "${RSTARPKGR_BASEDIR}"

  # TODO
  # source /etc/os-release
  # for PKG in ${RSTARPKGR_BASEDIR}/pkgs/rakudo-star*${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}* ; do
  #   if [[ "$PKG" == *tar* ]]; then
  #     mv "$PKG" "${PKG%.tar.*}-${VERSION_CODENAME}.tar.${PKG#*tar.*}"
  #   else
  #     mv "$PKG" "${PKG%.*}-${VERSION_CODENAME}.${PKG##*.}"
  #   fi
  # done

}

usage() {
	cat <<EOF

'rstarpkgr' is the utility to create binary Rakudo-Star packages.

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

EOF
}


cleanup() {
  [[ -d "${RSTARPKGR_xxxTMPDIR}" ]] && \
    rm -fr -- "${RSTARPKGR_xxxTMPDIR}" &&
    debug "trap cleaned up \"${RSTARPKGR_xxxTMPDIR}\" directory"
}
# If any command fails cleanup is executed
trap 'cleanup' ERR INT TERM ABRT QUIT EXIT

### let's go ###

main "$@"
