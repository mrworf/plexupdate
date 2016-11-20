#!/bin/bash
#
# Plex Linux Server download tool
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# This tool will download the latest version of Plex Media
# Server for Linux. It supports both the public versions
# as well as the PlexPass versions.
#
# PlexPass users:
#   Create a separate .plexupdate file in your home directory with these
#   values:
#
#   EMAIL='<whatever your plexpass email was>'
#   PASS='<whatever password you used>'
#   DOWNLOADDIR='<where you would like to save the downloaded package>'
#
# See https://github.com/mrworf/plexupdate for more details.
#
# Returns 0 on success
#         1 on error
#         2 if file already downloaded
#         3 if page layout has changed.
#         4 if download fails
#         5 if version already installed
#         6 if update was deferred due to usage
#
# All other return values not documented.
#
# Call program with -h for available options
#
# Enjoy!
#
# Check out https://github.com/mrworf/plexupdate for latest version
# and also what's new.
#
####################################################################
# Quick-check before we allow bad things to happen
if [ -z "${BASH_VERSINFO}" ]; then
	echo "ERROR: You must execute this script with BASH" >&2
	exit 255
fi

#################################################################
# Don't change anything below this point, use a .plexupdate file
# in your home directory to override this section.
# DOWNLOADDIR is the full directory path you would like the download to go.
#
EMAIL=
PASS=
DOWNLOADDIR="."
PLEXSERVER=
PLEXPORT=32400

# Defaults
# (aka "Advanced" settings, can be overriden with config file)
FORCE=no
FORCEALL=no
PUBLIC=yes
AUTOINSTALL=no
AUTODELETE=no
AUTOUPDATE=no
AUTOSTART=no
ARCH=$(uname -m)
IGNOREAUTOUPDATE=no
SHOWPROGRESS=no
WGETOPTIONS=""	# extra options for wget. Used for progress bar.
CHECKUPDATE=yes

# Default options for package managers, override if needed
REDHAT_INSTALL="yum -y install"
DEBIAN_INSTALL="dpkg -i"
DISTRO_INSTALL=""

# Current pages we need - Do not change unless Plex.tv changes again
URL_LOGIN='https://plex.tv/users/sign_in.json'
URL_DOWNLOAD='https://plex.tv/api/downloads/1.json?channel=plexpass'
URL_DOWNLOAD_PUBLIC='https://plex.tv/api/downloads/1.json'

FILE_POSTDATA=$(mktemp /tmp/plexupdate.postdata.XXXX)
FILE_RAW=$(mktemp /tmp/plexupdate.raw.XXXX)
FILE_FAILCAUSE=$(mktemp /tmp/plexupdate.failcause.XXXX)
FILE_KAKA=$(mktemp /tmp/plexupdate.kaka.XXXX)
FILE_SHA=$(mktemp /tmp/plexupdate.sha.XXXX)
FILE_WGETLOG=$(mktemp /tmp/plexupdate.wget.XXXX)
FILE_LOCAL=$(mktemp /tmp/plexupdate.local.XXXX)
FILE_REMOTE=$(mktemp /tmp/plexupdate.remote.XXXX)

######################################################################
# Functions for rest of script

warn() {
	echo "WARNING: $@" >&1
}

info() {
	echo "$@" >&1
}

error() {
	echo "ERROR: $@" >&2
}

usage() {
	echo "Usage: $(basename $0) [-acdfFhlpPqsuU] [<long options>]"
	echo ""
	echo ""
	echo "    -a Auto install if download was successful (requires root)"
	echo "    -d Auto delete after auto install"
	echo "    -f Force download even if it's the same version or file"
	echo "       already exists unless checksum passes"
	echo "    -F Force download always"
	echo "    -h This help"
	echo "    -l List available builds and distros"
	echo "    -p Public Plex Media Server version"
	echo "    -P Show progressbar when downloading big files"
	echo "    -r Print download URL and exit"
	echo "    -s Auto start (needed for some distros)"
	echo "    -u Auto update plexupdate.sh before running it (experimental)"
	echo "    -U Do not autoupdate plexupdate.sh (experimental, default)"
	echo "    -v Show additional debug information (cannot be saved or set via config)"
	echo ""
	echo "    Long Argument Options:"
	echo "    --config <path/to/config/file> Configuration file to use"
	echo "    --dldir <path/to/download/dir> Download directory to use"
	echo "    --email <plex.tv email> Plex.TV email address"
	echo "    --pass <plex.tv password> Plex.TV password"
	echo "    --server <Plex server address> Address of Plex Server"
	echo "    --port <Plex server port> Port for Plex Server. Used with --server"
	echo "    --saveconfig Save the configuration to config file"
	echo
	exit 0
}

running() {
	local DATA="$(wget --no-check-certificate -q -O - https://$1:$3/status/sessions?X-Plex-Token=$2)"
	local RET=$?
	if [ ${RET} -eq 0 ]; then
		if [ -z "${DATA}" ]; then
			# Odd, but usually means noone is watching
			return 1
		fi
		echo "${DATA}" | grep -q '<MediaContainer size="0">'
		if [ $? -eq 1 ]; then
			# not found means that one or more medias are being played
			return 0
		fi
		return 1
	elif [ ${RET} -eq 4 ]; then
		# No response, assume not running
		return 1
	else
		# We do not know what this means...
		warn "Unknown response (${RET}) from server >>>"
		warn "${DATA}"
		return 0
	fi
}

trimQuotes() {
	local __buffer=$1

	# Remove leading single quote
	__buffer=${__buffer#\'}
	# Remove ending single quote
	__buffer=${__buffer%\'}

	echo $__buffer
}

# Useful functions
rawurlencode() {
	local string="${1}"
	local strlen=${#string}
	local encoded=""

	for (( pos=0 ; pos<strlen ; pos++ )); do
		c=${string:$pos:1}
		case "$c" in
		[-_.~a-zA-Z0-9] ) o="${c}" ;;
		* )               printf -v o '%%%02x' "'$c"
	esac
	encoded+="${o}"
	done
	echo "${encoded}"
}

keypair() {
	local key="$( rawurlencode "$1" )"
	local val="$( rawurlencode "$2" )"

	echo "${key}=${val}"
}

# Setup an exit handler so we cleanup
cleanup() {
	for F in "${FILE_RAW}" "${FILE_FAILCAUSE}" "${FILE_POSTDATA}" "${FILE_KAKA}" "${FILE_SHA}" "${FILE_LOCAL}" "${FILE_REMOTE}" "${FILE_WGETLOG}"; do
		rm "$F" 2>/dev/null >/dev/null
	done
}
trap cleanup EXIT

if [ ! $# -eq 0 ]; then
	HASCFG="${@: -1}"
	if [ ! -z "${HASCFG}" -a ! "${HASCFG:0:1}" = "-" -a ! "${@:(-2):1}" = "--config" ]; then
		if [ -f "${HASCFG}" ]; then
			warn "Specifying config file as last argument is deprecated. Use --config <path> instead."
			CONFIGFILE=${HASCFG}
		fi
	fi
fi

# Parse commandline
ALLARGS=( "$@" )
optstring="acCdfFhlpPqrSsuUv -l config:,dldir:,email:,pass:,server:,port:,saveconfig"
getopt -T >/dev/null
if [ $? -eq 4 ]; then
	optstring="-o $optstring"
fi
GETOPTRES=$(getopt $optstring -- "$@")
if [ $? -eq 1 ]; then
	exit 1
fi

set -- ${GETOPTRES}
while true;
do
	case "$1" in
		(-h) usage;;
		(-a) AUTOINSTALL_CL=yes;;
		(-c) error "CRON option is deprecated, please use cronwrapper (see README.md)"; exit 255;;
		(-C) error "CRON option is deprecated, please use cronwrapper (see README.md)"; exit 255;;
		(-d) AUTODELETE_CL=yes;;
		(-f) FORCE_CL=yes;;
		(-F) FORCEALL_CL=yes;;
		(-l) LISTOPTS=yes;;
		(-p) PUBLIC_CL=yes;;
		(-P) SHOWPROGRESS=yes;;
		(-q) error "QUIET option is deprecated, please redirect to /dev/null instead"; exit 255;;
		(-r) PRINT_URL=yes;;
		(-s) AUTOSTART_CL=yes;;
		(-u) AUTOUPDATE_CL=yes;;
		(-U) IGNOREAUTOUPDATE=yes;;
		(-v) VERBOSE_CL=yes;;

		(--config) shift; CONFIGFILE="$1"; CONFIGFILE=$(trimQuotes ${CONFIGFILE});;
		(--dldir) shift; DOWNLOADDIR_CL="$1"; DOWNLOADDIR_CL=$(trimQuotes ${DOWNLOADDIR_CL});;
		(--email) shift; EMAIL_CL="$1"; EMAIL_CL=$(trimQuotes ${EMAIL_CL});;
		(--pass) shift; PASS_CL="$1"; PASS_CL=$(trimQuotes ${PASS_CL});;
		(--server) shift; PLEXSERVER_CL="$1"; PLEXSERVER_CL=$(trimQuotes ${PLEXSERVER_CL});;
		(--port) shift; PLEXPORT_CL="$1"; PLEXPORT_CL=$(trimQuotes ${PLEXPORT_CL});;
		(--saveconfig) SAVECONFIG=yes;;

		(--) ;;
		(-*) error "Unrecognized option $1"; usage; exit 1;;
		(*)  break;;
	esac
	shift
done

# Sanity, make sure wget is in our path...
if ! hash wget 2>/dev/null; then
	error "This script requires wget in the path. It could also signify that you don't have the tool installed."
	exit 1
fi

# Allow manual control of configfile
if [ ! -z "${CONFIGFILE}" ]; then
	if [ -f "${CONFIGFILE}" ]; then
		info "Using configuration: ${CONFIGFILE}" #>/dev/null
		source "${CONFIGFILE}"
	else
		error "Cannot load configuration ${CONFIGFILE}"
		exit 1
	fi
else
	# Load settings from config file if it exists
	if [ -f /etc/plexupdate.conf ]; then
		info "Reading configuration in: /etc/plexupdate.conf"
		CONFIGFILE=/etc/plexupdate.conf
		source /etc/plexupdate.conf
	fi

	# Check for a SUDO_USER config
	if [ ! -z "${SUDO_USER}" ]; then
		# Make sure nothing bad comes from this (since we use eval)
		ERROR=0
		if   [[ $SUDO_USER == *";"* ]]; then ERROR=1 ; # Allows more commands
		elif [[ $SUDO_USER == *" "* ]]; then ERROR=1 ; # Space is not a good thing
		elif [[ $SUDO_USER == *"&"* ]]; then ERROR=1 ; # Spinning off the command is bad
		elif [[ $SUDO_USER == *"<"* ]]; then ERROR=1 ; # No redirection
		elif [[ $SUDO_USER == *">"* ]]; then ERROR=1 ; # No redirection
		elif [[ $SUDO_USER == *"|"* ]]; then ERROR=1 ; # No pipes
		elif [[ $SUDO_USER == *"~"* ]]; then ERROR=1 ; # No tilde
		fi
		if [ ${ERROR} -gt 0 ]; then
			error "SUDO_USER variable is COMPROMISED: \"${SUDO_USER}\""
			exit 255
		fi

		# Try using original user's config
		CONFIGDIR="$( eval cd ~${SUDO_USER} 2>/dev/null && pwd )"
		if [ -z "${CONFIGDIR}" ]; then
			warn "SUDO_USER \"${SUDO_USER}\" does not have a valid home directory, ignoring."
		fi

		if [ ! -z "${CONFIGDIR}" -a -f "${CONFIGDIR}/.plexupdate" ]; then
			info "Reading \"${SUDO_USER}\" configuration in: ${CONFIGDIR}/.plexupdate"
			CONFIGFILE="${CONFIGDIR}/.plexupdate"
			source "${CONFIGDIR}/.plexupdate"
		elif [ -f ~/.plexupdate ]; then
			# Fallback for compatibility
			info "Reading \"${SUDO_USER}\" configuration in: ${HOME}/.plexupdate"
			CONFIGFILE="${HOME}/.plexupdate"		# tilde expansion won't happen later.
			source ~/.plexupdate
		fi
	elif [ -f ~/.plexupdate ]; then
		# Fallback for compatibility
		info "Reading configuration in: ${HOME}/.plexupdate"
		CONFIGFILE="${HOME}/.plexupdate"
		source ~/.plexupdate
	fi
fi

# DO NOT ALLOW VERBOSE FROM CONFIGURATION FILE!
if [ "${VERBOSE_CL}" = "yes" ]; then
	VERBOSE=yes
else
	VERBOSE=no
fi

# The way I wrote this, it assumes that whatever we put on the command line is what we want and should override
#   any values in the configuration file. As a result, we need to check if they've been set on the command line
#   and overwrite the values that may have been loaded with the config file

for VAR in AUTOINSTALL AUTODELETE DOWNLOADDIR EMAIL PASS FORCE FORCEALL PUBLIC AUTOSTART AUTOUPDATE PLEXSERVER PLEXPORT
do
	VAR2="$VAR""_CL"
	if [ ! -z ${!VAR2} ]; then
		eval $VAR='${!VAR2}'
	fi
done

# This will destroy and recreate the config file. Any settings that are set in the config file but are no longer
# valid will NOT be saved.
if [ "${SAVECONFIG}" = "yes" ]; then
	if [ ! -d "$(eval cd ${DOWNLOADDIR// /\\ } 2>/dev/null && pwd)" ]; then
		errorLog "Download directory does not exist or is not a directory (tried \"${DOWNLOADDIR}\")"
		exit 1
	fi
	echo "# Config file for plexupdate" >${CONFIGFILE:="${HOME}/.plexupdate"}

	for VAR in AUTOINSTALL AUTODELETE DOWNLOADDIR EMAIL PASS FORCE FORCEALL PUBLIC AUTOSTART AUTOUPDATE PLEXSERVER PLEXPORT CHECKUPDATE
	do
		if [ ! -z ${!VAR} ]; then

			# The following keys have defaults set in this file. We don't want to include these values if they are the default.
			if [ ${VAR} = "FORCE" \
			-o ${VAR} = "FORCEALL" \
			-o ${VAR} = "PUBLIC" \
			-o ${VAR} = "AUTOINSTALL" \
			-o ${VAR} = "AUTODELETE" \
			-o ${VAR} = "AUTOUPDATE" \
			-o ${VAR} = "AUTOSTART" ]; then

				if [ ${!VAR} = "yes" ]; then
					echo "${VAR}='${!VAR}'" >> ${CONFIGFILE}
				fi
			elif [ ${VAR} = "PLEXPORT" ]; then
				if [ ! "${!VAR}" = "32400" ]; then
					echo "${VAR}='${!VAR}'" >> ${CONFIGFILE}
				fi
			else
				echo "${VAR}='${!VAR}'" >> ${CONFIGFILE}
			fi
		fi
	done
fi

if [ "${SHOWPROGRESS}" = "yes" ]; then
	WGETOPTIONS="--show-progress"
fi

if [ "${IGNOREAUTOUPDATE}" = "yes" ]; then
	AUTOUPDATE=no
fi

if [ "${CRON}" = "yes" ]; then
	error "CRON has been deprecated, please use cronwrapper (see README.md)"
	exit 255
fi

if [ "${KEEP}" = "yes" ]; then
	error "KEEP is deprecated and should be removed from .plexupdate"
	exit 255
fi

if [ ! -z "${RELEASE}" ]; then
	error "RELEASE keyword is deprecated and should be removed from .plexupdate"
	error "Use DISTRO and BUILD instead to manually select what to install (check README.md)"
	exit 255
fi

if [ "${AUTOUPDATE}" = "yes" ]; then
	if ! hash git 2>/dev/null; then
		error "You need to have git installed for this to work"
		exit 1
	fi
	pushd "$(dirname "$0")" >/dev/null
	if [ ! -d .git ]; then
		error "This is not a git repository, auto update only works if you've done a git clone"
		exit 1
	fi
	git status | grep "git commit -a" >/dev/null 2>/dev/null
	if [ $? -eq 0 ]; then
		error "You have made changes to the script, cannot auto update"
		exit 1
	fi
	info "Auto updating"
	git pull >/dev/null
	if [ $? -ne 0 ]; then
		error 'Unable to update git, try running "git pull" manually to see what is wrong'
		exit 1
	fi
	info "Update complete"
	popd >/dev/null

	if ! type "$0" 2>/dev/null >/dev/null ; then
		if [ -f "$0" ]; then
			/bin/bash "$0" -U ${ALLARGS[@]}
		else
			error "Unable to relaunch, couldn't find $0"
			exit 1
		fi
	else
		"$0" -U ${ALLARGS[@]}
	fi
	exit $?
fi

# Sanity check
if [ -z "${EMAIL}" -o -z "${PASS}" ] && [ "${PUBLIC}" = "no" ]; then
	error "Need username & password to download PlexPass version. Otherwise run with -p to download public version."
	exit 1
elif [ ! -z "${EMAIL}" ] && [[ "$EMAIL" == *"@"* ]] && [[ "$EMAIL" != *"@"*"."* ]]; then
	error "EMAIL field must contain a valid email address"
	exit 1
fi


if [ "${AUTOINSTALL}" = "yes" -o "${AUTOSTART}" = "yes" ]; then
	id | grep -i 'uid=0(' 2>&1 >/dev/null
	if [ $? -ne 0 ]; then
		error "You need to be root to use AUTOINSTALL/AUTOSTART option."
		exit 1
	fi
fi


# Remove any ~ or other oddness in the path we're given
DOWNLOADDIR_PRE=${DOWNLOADDIR}
DOWNLOADDIR="$(eval cd ${DOWNLOADDIR// /\\ } 2>/dev/null && pwd)"
if [ ! -d "${DOWNLOADDIR}" ]; then
	error "Download directory does not exist or is not a directory (tried \"${DOWNLOADDIR_PRE}\")"
	exit 1
fi

if [ -z "${DISTRO_INSTALL}" ]; then
	if [ -z "${DISTRO}" -a -z "${BUILD}" ]; then
		# Detect if we're running on redhat instead of ubuntu
		if [ -f /etc/redhat-release ]; then
			REDHAT=yes
			BUILD="linux-ubuntu-${ARCH}"
			DISTRO="redhat"
			DISTRO_INSTALL="${REDHAT_INSTALL}"
		else
			REDHAT=no
			BUILD="linux-ubuntu-${ARCH}"
			DISTRO="ubuntu"
			DISTRO_INSTALL="${DEBIAN_INSTALL}"
		fi
	elif [ -z "${DISTRO}" -o -z "${BUILD}" ]; then
		error "You must define both DISTRO and BUILD"
		exit 255
	fi
else
	if [ -z "${DISTRO}" -o -z "${BUILD}" ]; then
		error "Using custom DISTRO_INSTALL requires custom DISTRO and BUILD too"
		exit 255
	fi
fi

if [ "${CHECKUPDATE}" = "yes" ]; then
	(wget -q https://raw.githubusercontent.com/mrworf/plexupdate/master/plexupdate.sh -O - 2>/dev/null || echo ERROR) | shasum >"${FILE_REMOTE}" 2>/dev/null
	ERR1=$?
	(cat "$0" 2>/dev/null || echo ERROR) | shasum >"${FILE_LOCAL}" 2>/dev/null
	ERR2=$?
	if [ $ERR1 -ne 0 -o $ERR2 -ne 0 ]; then
		error "When checking for version, was unable to confirm version of script"
	else
		# "709c7506b17090bce0d1e2464f39f4a434cf25f1" is the hash for "ERROR" :)
		if grep -sq "709c7506b17090bce0d1e2464f39f4a434cf25f1" "${FILE_LOCAL}" ; then
			error "When checking for version, was unable to validate local copy"
		elif grep -sq "709c7506b17090bce0d1e2464f39f4a434cf25f1" "${FILE_REMOTE}" ; then
			error "When checking for version, was was unable to validate remote copy"
		elif ! diff "${FILE_LOCAL}" "${FILE_REMOTE}" >/dev/null 2>/dev/null ; then
			info "Newer version of this script is available at https://github.com/mrworf/plexupdate"
		fi
	fi
	rm "${FILE_LOCAL}" 2>/dev/null >/dev/null
	rm "${FILE_REMOTE}" 2>/dev/null >/dev/null
fi



# Fields we need to submit for login to work
#
# Field			Value
# utf8			&#x2713;
# authenticity_token	<Need to be obtained from web page>
# user[login]		$EMAIL
# user[password]	$PASSWORD
# user[remember_me]	0
# commit		Sign in

if [ "${PUBLIC}" = "no" ]; then
	info "Authenticating with plex.tv"

	# Clean old session
	rm "${FILE_KAKA}" 2>/dev/null

	# Build post data
	echo -ne >"${FILE_POSTDATA}" "$(keypair "user[login]" "${EMAIL}" )"
	echo -ne >>"${FILE_POSTDATA}" "&$(keypair "user[password]" "${PASS}" )"
	echo -ne >>"${FILE_POSTDATA}" "&$(keypair "user[remember_me]" "0" )"

	# Authenticate (using Plex Single Sign On)
	wget --header "X-Plex-Client-Identifier: 4a745ae7-1839-e44e-1e42-aebfa578c865" --header "X-Plex-Product: Plex SSO" --load-cookies "${FILE_KAKA}" --save-cookies "${FILE_KAKA}" --keep-session-cookies "${URL_LOGIN}" --post-file="${FILE_POSTDATA}" -q -S -O "${FILE_FAILCAUSE}" 2>"${FILE_RAW}"
	# Delete authentication data ... Bad idea to let that stick around
	rm "${FILE_POSTDATA}"

	# Provide some details to the end user
	RESULTCODE=$(head -n1 "${FILE_RAW}" | grep -oe '[1-5][0-9][0-9]')
	if [ $RESULTCODE -eq 401 ]; then
		error "Username and/or password incorrect"
		if [ "$VERBOSE" = "yes" ]; then
			info "Tried using \"${EMAIL}\" and \"${PASS}\" "
		fi
		exit 1
	elif [ $RESULTCODE -ne 201 ]; then
		error "Failed to login, debug information:"
		cat "${FILE_RAW}" >&2
		exit 1
	fi

	# If the system got here, it means the login was successfull, so we set the TOKEN variable to the authToken from the response
	# I use cut -c 14- to cut off the "authToken":" string from the grepped result, can probably be done in a different way
	TOKEN=$(<"${FILE_FAILCAUSE}"  grep -ioe '"authToken":"[^"]*' | cut -c 14-)

	# Remove this, since it contains more information than we should leave hanging around
	rm "${FILE_FAILCAUSE}"

elif [ "$PUBLIC" != "no" ]; then
	# It's a public version, so change URL and make doubly sure that cookies are empty
	rm 2>/dev/null >/dev/null "${FILE_KAKA}"
	touch "${FILE_KAKA}"
	URL_DOWNLOAD=${URL_DOWNLOAD_PUBLIC}
fi

if [ "${LISTOPTS}" = "yes" ]; then
	opts="$(wget --load-cookies "${FILE_KAKA}" --save-cookies "${FILE_KAKA}" --keep-session-cookies "${URL_DOWNLOAD}" -O - 2>/dev/null | grep -oe '"label"[^}]*' | grep -v Download | sed 's/"label":"\([^"]*\)","build":"\([^"]*\)","distro":"\([^"]*\)".*/"\3" "\2" "\1"/' | uniq | sort)"
	eval opts=( "DISTRO" "BUILD" "DESCRIPTION" "======" "=====" "==============================================" $opts )

	BUILD=
	DISTRO=

	for X in "${opts[@]}" ; do
		if [ -z "$DISTRO" ]; then
			DISTRO="$X"
		elif [ -z "$BUILD" ]; then
			BUILD="$X"
		else
			printf "%-12s %-30s %s\n" "$DISTRO" "$BUILD" "$X"
			BUILD=
			DISTRO=
		fi
	done
	exit 0
fi

# Extract the URL for our release
info "Retrieving list of available distributions"

# Set "X-Plex-Token" to the auth token, if no token is specified or it is invalid, the list will return public downloads by default
RELEASE=$(wget --header "X-Plex-Token:"${TOKEN}"" --load-cookies "${FILE_KAKA}" --save-cookies "${FILE_KAKA}" --keep-session-cookies "${URL_DOWNLOAD}" -O - 2>/dev/null | grep -ioe '"label"[^}]*' | grep -i "\"distro\":\"${DISTRO}\"" | grep -m1 -i "\"build\":\"${BUILD}\"")
DOWNLOAD=$(echo ${RELEASE} | grep -m1 -ioe 'https://[^\"]*')
CHECKSUM=$(echo ${RELEASE} | grep -ioe '\"checksum\"\:\"[^\"]*' | sed 's/\"checksum\"\:\"//')

if [ -z "${DOWNLOAD}" ]; then
	error "Unable to retrieve the URL needed for download (Query DISTRO: $DISTRO, BUILD: $BUILD)"
	exit 3
fi

FILENAME="$(basename 2>/dev/null ${DOWNLOAD})"
if [ $? -ne 0 ]; then
	error "Failed to parse HTML, download cancelled."
	exit 3
fi

echo "${CHECKSUM}  ${DOWNLOADDIR}/${FILENAME}" >"${FILE_SHA}"

if [ "${PRINT_URL}" = "yes" ]; then
	info "${DOWNLOAD}"
	exit 0
fi

# By default, try downloading
SKIP_DOWNLOAD="no"

# Installed version detection (only supported for deb based systems, feel free to submit rpm equivalent)
if [ "${REDHAT}" != "yes" ]; then
	INSTALLED_VERSION=$(dpkg-query -s plexmediaserver 2>/dev/null | grep -Po 'Version: \K.*')
else
	if [ "${AUTOSTART}" = "no" ]; then
		warn "Your distribution may require the use of the AUTOSTART [-s] option for the service to start after the upgrade completes."
	fi
	INSTALLED_VERSION=$(rpm -qv plexmediaserver 2>/dev/null)
fi

if [[ $FILENAME == *$INSTALLED_VERSION* ]] && [ "${FORCE}" != "yes" -a "${FORCEALL}" != "yes" ] && [ ! -z "${INSTALLED_VERSION}" ]; then
	info "Your OS reports the latest version of Plex ($INSTALLED_VERSION) is already installed. Use -f to force download."
	exit 5
fi

if [ -f "${DOWNLOADDIR}/${FILENAME}" ]; then
	if [ "${FORCE}" != "yes" -a "${FORCEALL}" != "yes" ]; then
		sha1sum --status -c "${FILE_SHA}"
		if [ $? -eq 0 ]; then
			info "File already exists (${FILENAME}), won't download."
			if [ "${AUTOINSTALL}" != "yes" ]; then
				exit 2
			fi
			SKIP_DOWNLOAD="yes"
		else
			info "File exists but fails checksum. Redownloading."
			SKIP_DOWNLOAD="no"
		fi
	elif [ "${FORCEALL}" == "yes" ]; then
		info "Note! File exists, but asked to overwrite with new copy"
	else
		sha1sum --status -c "${FILE_SHA}"
		if [ $? -ne 0 ]; then
			info "File exists but fails checksum. Redownloading."
		else
			info "File exists and checksum passes, won't redownload."
			if [ "${AUTOINSTALL}" != "yes" ]; then
				exit 2
			fi
			SKIP_DOWNLOAD="yes"
		fi
	fi
fi

if [ "${SKIP_DOWNLOAD}" = "no" ]; then
	info "Downloading release \"${FILENAME}\""
	wget ${WGETOPTIONS} -o "${FILE_WGETLOG}" --load-cookies "${FILE_KAKA}" --save-cookies "${FILE_KAKA}" --keep-session-cookies "${DOWNLOAD}" -O "${DOWNLOADDIR}/${FILENAME}" 2>&1
	CODE=$?
	if [ ${CODE} -eq 2 ]; then
		error "Your wget is too old to support --show-progress"
		info "Trying to download release \"${FILENAME}\" again"
		wget -o "${FILE_WGETLOG}" --load-cookies "${FILE_KAKA}" --save-cookies "${FILE_KAKA}" --keep-session-cookies "${DOWNLOAD}" -O "${DOWNLOADDIR}/${FILENAME}" 2>&1
		CODE=$?
	fi

	if [ ${CODE} -ne 0 ]; then
		error "Download failed with code ${CODE}:"
		cat "${FILE_WGETLOG}" >&2
		exit ${CODE}
	fi
	info "File downloaded"
fi

sha1sum --status -c "${FILE_SHA}"
if [ $? -ne 0 ]; then
	error "Downloaded file corrupt. Try again."
	exit 4
fi

if [ ! -z "${PLEXSERVER}" -a "${AUTOINSTALL}" = "yes" ]; then
	# Check if server is in-use before continuing (thanks @AltonV, @hakong and @sufr3ak)...
	if running ${PLEXSERVER} ${TOKEN} ${PLEXPORT}; then
		error "Server ${PLEXSERVER} is currently being used by one or more users, skipping installation. Please run again later"
		exit 6
	fi
fi

if [ "${AUTOINSTALL}" = "yes" ]; then
	if ! hash ldconfig 2>/dev/null && [ "${DISTRO}" = "ubuntu" ]; then
		export PATH=$PATH:/sbin
	fi
	# no elif since DISTRO_INSTALL will produce error output for us

	${DISTRO_INSTALL} "${DOWNLOADDIR}/${FILENAME}"
fi

if [ "${AUTODELETE}" = "yes" ]; then
	if [ "${AUTOINSTALL}" = "yes" ]; then
		rm -rf "${DOWNLOADDIR}/${FILENAME}"
		info "Deleted \"${FILENAME}\""
	else
		info "Will not auto delete without [-a] auto install"
	fi
fi

if [ "${AUTOSTART}" = "yes" ]; then
	if [ "${REDHAT}" = "no" ]; then
		warn "The AUTOSTART [-s] option may not be needed on your distribution."
	fi
	# Check for systemd
	if hash systemctl 2>/dev/null; then
		systemctl start plexmediaserver.service
	elif hash service 2>/dev/null; then
		service plexmediaserver start
	elif [ -x /etc/init.d/plexmediaserver ]; then
		/etc/init.d/plexmediaserver start
	else
		error "AUTOSTART was specified but no startup scripts were found for 'plexmediaserver'."
		exit 1
	fi
fi

exit 0
