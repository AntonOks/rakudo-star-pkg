#!/usr/bin/env bash

# Change the working directory. In usage, this is the same as using cd,
# however,  it will make additional checks to ensure everything is going fine.
chgdir() {
	debug "Changing workdir to \"$1\""
	cd -- "$1" || die "Failed to change directory to \"$1\""
}

# Read a particular value from a key/value configuration file. Using this
# function introduces a dependency on awk.
config_etc_kv() {
	local value

	local file="$RSTARPKGR_BASEDIR/etc/$1"
	shift

	if [[ ! -f $file ]]; then
		crit "Tried to read value for $1 from $file, but $file does not exist"
		return
	fi

	debug "Reading value for $1 from $file"

	value="$(awk -F= '$1 == "'"$1"'" { print $NF }' "$file")"

	if [[ -z $value ]]; then
		crit "Empty value for $1 from $file?"
	fi

	printf "%s" "$value"
}

# Create a datetime stamp. This is a wrapper around the date utility, ensuring
# that the date being formatted is always in UTC and respect SOURCE_DATE_EPOCH,
# if it is set.
datetime() {
	local date_opts

	# Apply SOURCE_DATE_EPOCH as the date to base off of.
	if [[ $SOURCE_DATE_EPOCH ]]; then
		date_opts+=("-d@$SOURCE_DATE_EPOCH")
		date_opts+=("-u")
	fi

	date "${date_opts[@]}" +"${1:-%FT%T}"
}

# Log a message as error, and exit the program. This is intended for serious
# issues that prevent the script from running correctly. The exit code can be
# specified with -i, or will default to 1.
die() {
	local OPTIND
	local code

	while getopts ":i:" opt
	do
		case "$opt" in
			i) code=$OPTARG ;;
			*) alert "Unused argument specified: $opt" ;;
		esac
	done && shift $(( OPTIND -1 ))

	alert "$@"
	exit "${code:-1}"
}

# Fetch a file from an URL. Using this function introduces a dependency on curl.
fetch_http() {
	local OPTIND
	local buffer

	while getopts ":o:" opt
	do
		case "$opt" in
			o) buffer=$OPTARG ;;
			*) alert "Unused argument specified: $opt" ;;
		esac
	done

	shift $(( OPTIND -1 ))

	[[ -z $buffer ]] && buffer="$(tmpfile)"

	notice "Downloading $1 to $buffer"

	for util in curl wget ; do
		command -v "$util" > /dev/null || continue
		"fetch_http_$util" "$1" "$buffer" || continue
		local exit_code=$?

		printf "%s" "$buffer"
		return $exit_code
	done

	die "Unable to download file over HTTP!"
}

fetch_http_curl() {
	curl -Ls "$1" > "$2"
}

fetch_http_wget() {
	wget --quiet --output-document "$2" "$1"
}

# Check if the first argument given appears in the list of all following
# arguments.
in_args() {
	local needle="$1"
	shift

	for arg in "$@" ; do
		[[ $needle == "$arg" ]] && return 0
	done

	return 1
}

# Join a list of arguments into a single string. By default, this will join
# using a ",", but you can set a different character using -c. Note that this
# only joins with a single character, not a string of characters.
join_args() {
	local OPTIND
	local IFS=","

	while getopts ":c:" opt
	do
		case "$opt" in
			c) IFS="$OPTARG" ;;
			*) warn "Unused opt specified: $opt" ;;
		esac
	done

	shift $(( OPTIND - 1))

	printf "%s" "$*"
}

# Pretty print a duration between a starting point (in seconds) and an end
# point (in seconds). If no end point is given, the current time will be used.
# A good way to get a current timestamp in seconds is through date's "%s"
# format.
pp_duration() {
	local start=$1
	local end=$2
	local diff

	if [[ -z "$end" ]]; then
		end="$(date +%s)"
	fi

	diff=$((end - start))

	printf "%dh %02dm %02ds\n" \
		"$((diff / 60 / 60))" \
		"$((diff / 60 % 60))" \
		"$((diff % 60))"
}

# Create a temporary directory. Similar to tempfile, but you'll get a directory
# instead.
tmpdir() {
	local dir

	dir="$(mktemp -d)"

	# Ensure the file was created successfully
	if [[ ! -d "$dir" ]]; then
		die "Failed to create a temporary directory at $dir"
	fi

	debug "Temporary directory created at $dir"

	printf "%s" "$dir"
}

# Create a temporary file. In usage, this is no different from mktemp itself,
# however, it will apply additional checks to ensure everything is going
# correctly, and the files will be cleaned up automatically at the end.
tmpfile() {
	local file

	file="$(mktemp)"

	# Ensure the file was created successfully
	if [[ ! -f "$file" ]]; then
		die "Failed to create a temporary file at $file"
	fi

	debug "Temporary file created at $file"

	printf "%s" "$file"
}

# This function checks for the availability of (binary) utilities in the user's
# $PATH environment variable.
tool_check() {
	local missing=()
	local bindep_db

	for tool in "${RSTARPKGR_TOOLS[@]}"; do
		debug "Checking for availability of $tool"
		command -v "$tool" > /dev/null && continue

		missing+=("$tool")
	done

	if [[ ${missing[*]} ]]; then
		alert "Some required tools are missing:"

		for tool in "${missing[@]}"; do
			alert "  $tool"
		done

		return 1
	fi
}

init_vars() {

  # The Rakudo release filenames follow the pattern:
  #  `rakudo-[backend]-[version]-[build revision]-[OS]-[architecture]-[toolchain]`
  #  - `backend` is always `moar`
  #  - `version` represents the release month, i.e. "2025.12" or patched as "2022.06.1"
  #  - `build revision` is usually `01`
  #  - `OS` is `linux` or `win` or `macos`
  #  - `architecture` is `x86_64` for all 3 OS'es or `arm64` on "macos"
  #  - `toolchain` is `gcc` on "linux", `msvc` on "win" and `clang` on "macos"
  # We define similar variables
  export RSTARPKGR_BACKEND="moar"
  export RSTARPKGR_VERSION="${RSTARPKGR_VERSION:-"latest"}"
  export RSTARPKGR_REVISION="${RSTARPKGR_REVISION:-"01"}"
  export RSTARPKGR_OS="${RSTARPKGR_OS:-"linux"}"              # uname -s | awk '{print tolower($0)}'
  export RSTARPKGR_ARCH="${RSTARPKGR_ARCH:-"x86_64"}"         # uname -m
  export RSTARPKGR_TOOLCHAIN="${RSTARPKGR_TOOLCHAIN:-"gcc"}"

  # Rakudo-Star `rstar` release examples, to build an own binary release from:
  #  - https://www.rakudo.org/dl/star/rakudo-star-2025.12-01.tar.gz
  #  - https://www.rakudo.org/dl/star/rakudo-star-2022.06.1-01.tar.gz

  export RSTARPKGR_TMPDIR="${RSTARPKGR_TMPDIR:-"$(pwd -P)/tmp"}"
  export RSTARPKGR_DEBUG="${RSTARPKGR_DEBUG:-0}"
  export RSTARPKGR_CLEANUP="${RSTARPKGR_CLEANUP:-"0"}"
  export RSTARPKGR_xxxTMPDIR="$(tmpdir)"

  # If we want debug, we also ensure the rstar tool gets chatty
  export RSTAR_DEBUG=${RSTARPKGR_DEBUG}
}

rm_cache() {
  # Clean up downloaded sources
  local RSTARPKGR_V=$(echo "$1" | grep -Po "(\d+\.\d+)(\\.[0-9]+)?")
  if [[ "$1" != "all" ]] && [[ "$RSTARPKGR_V" == "" ]]; then crit "rm_cache: Unexpected parameter \"$1\""; return 5; fi
  case "$1" in
            "latest")   crit "Option \"-c\" requires either \"all\" or a Rakudo-Star release like \"2025.12\"" && exit 20 ;;
               "all")   debug "Cleaning cache dir \"${RSTARPKGR_TMPDIR}\"" && rm -rf -- "${RSTARPKGR_TMPDIR}/"* ;;
    "${RSTARPKGR_V}")   debug "Removing Rakudo-Star release \"${RSTARPKGR_V}\" from cache..." && rm -rf -- "${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_V}"* ;;
                   *)   alert "Unsupported \"-c\" argument specified: \"$1\"" && exit 20 ;;
  esac
  return
}

chk_cache() {
  debug "Checking for Rakudo-Star version \"$1\" in the cache dir \"${RSTARPKGR_TMPDIR}\"..."
  [[ -d "${RSTARPKGR_TMPDIR}/rakudo-star-${1}_bin" ]] && \
    crit "Rakudo-Star \"${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}\" exists in the local cache already, exiting..." && \
    exit 6
}

# Enforce some directories
mk_pkgr_dirs() {

  [[ "${RSTARPKGR_TMPDIR}" ]] || die "\$RSTARPKGR_TMPDIR\" is not set, dyeing..."

  # Maintain our own tempdir. We keep our downloaded sources there
  if [[ ! -d ${RSTARPKGR_TMPDIR} ]]; then
    mkdir -p -- "${RSTARPKGR_TMPDIR}" && \
      debug "\"\$RSTARPKGR_TMPDIR\" set to \"${RSTARPKGR_TMPDIR}\""
  fi
  
  if [[ ! -d ${RSTARPKGR_BASEDIR}/pkgs/ ]]; then
    mkdir -p -- ${RSTARPKGR_BASEDIR}/pkgs/ && \
      debug "\"${RSTARPKGR_BASEDIR}/pkgs/\" created..."
  fi
  
  # if [[ ! -d ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin/ ]]; then
  #   mkdir -p -- ${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin/ && \
  #     debug "\"${RSTARPKGR_TMPDIR}/rakudo-star-${RSTARPKGR_VERSION}-${RSTARPKGR_REVISION}_bin/\" created..."
  # fi

}


discover_system_arch() {
	uname -m
}

discover_system_os() {
	if command -v uname > /dev/null ; then
		printf "%s" "$(uname -s | awk '{print tolower($0)}' | sed 's@[/+ ]@_@g')"
		return
	fi
}
