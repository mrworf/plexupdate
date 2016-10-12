#!/bin/bash
#
# Plex Linux Server download tool
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# This tool will download the latest version of Plex Media
# Server for Linux. It supports both the public versions
# as well as the PlexPass versions.
#
# PlexPass users:
#   Either modify this file to add email and password OR create
#   a separate .plexupdate file in your home directory with these
#   values.
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
####################################################################
# Set these three settings to what you need, or create a .plexupdate file
# in your home directory with this section (avoids changing this).
# DOWNLOADDIR is the full directory path you would like the download to go.
#
EMAIL=
PASS=
DOWNLOADDIR="."
PLEXSERVER=

#################################################################
# Don't change anything below this point
#

# Defaults
# (aka "Advanced" settings, can be overriden with config file)
FORCE=no
FORCEALL=no
PUBLIC=no
AUTOINSTALL=no
AUTODELETE=no
AUTOUPDATE=no
AUTOSTART=no
CRON=no
QUIET=no
ARCH=$(uname -m)
IGNOREAUTOUPDATE=no

# Default options for package managers, override if needed
REDHAT_INSTALL="yum -y install"
DEBIAN_INSTALL="dpkg -i"
DISTRO_INSTALL=""

FILE_STDOUTLOG=$(mktemp /tmp/plexupdate.log.XXXX)
FILE_POSTDATA=$(mktemp /tmp/plexupdate.postdata.XXXX)
FILE_RAW=$(mktemp /tmp/plexupdate.raw.XXXX)
FILE_FAILCAUSE=$(mktemp /tmp/plexupdate.failcause.XXXX)
FILE_KAKA=$(mktemp /tmp/plexupdate.kaka.XXXX)
FILE_SHA=$(mktemp /tmp/plexupdate.sha.XXXX)

# Current pages we need - Do not change unless Plex.tv changes again
URL_LOGIN=https://plex.tv/users/sign_in.json
URL_DOWNLOAD=https://plex.tv/api/downloads/1.json?channel=plexpass
URL_DOWNLOAD_PUBLIC=https://plex.tv/api/downloads/1.json

# Functions for rest of script

cronexit() {
	# Don't give anything but true error codes if in CRON mode
	RAWEXIT=$1
	if [ "${CRON}" = "yes" -a $1 -gt 1 -a $1 -lt 255 ]; then
		exit 0
	fi
	exit $1
}

usage() {
	echo "Usage: $(basename $0) [-acdfFhlpqsuU] [<long options>]"
	echo ""
	echo ""
	echo "    -a Auto install if download was successful (requires root)"
	echo "    -c Cron mode, only fatal errors return non-zero cronexit code"
	echo "    -d Auto delete after auto install"
	echo "    -f Force download even if it's the same version or file"
	echo "       already exists unless checksum passes"
	echo "    -F Force download always"
	echo "    -h This help"
	echo "    -l List available builds and distros"
	echo "    -p Public Plex Media Server version"
	echo "    -q Quiet mode. No stdout, only stderr and cronexit codes"
	echo "    -r Print download URL and exit"
	echo "    -s Auto start (needed for some distros)"
	echo "    -u Auto update plexupdate.sh before running it (experimental)"
	echo "    -U Do not autoupdate plexupdate.sh (experimental, default)"
	echo ""
	echo "    Long Argument Options:"
	echo "    --config <path/to/config/file> Configuration file to use"
	echo "    --dldir <path/to/download/dir> Download directory to use"
	echo "    --email <plex.tv email> Plex.TV email address"
	echo "    --pass <plex.tv password> Plex.TV password"
	echo "    --server <Plex server address> Address of Plex Server"
	echo "    --saveconfig Save the configuration to config file"
	echo
	cronexit 0
}

running() {
	local DATA="$(wget --no-check-certificate -q -O - https://$1:32400/status/sessions?X-Plex-Token=$2)"
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
		echo "WARN: Unknown response (${RET}) from server >>>" >&2
		echo "${DATA}" >&2
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

HASCFG="${@: -1}"
if [ ! -z "${HASCFG}" -a ! "${HASCFG:0:1}" = "-" -a ! "${@:(-2):1}" = "--config" ]; then
	if [ -f "${HASCFG}" ]; then
		echo "WARNING: Specifying config file as last argument is deprecated. Use --config <path> instead."
		CONFIGFILE=${HASCFG}
	fi
fi

# Parse commandline
ALLARGS=( "$@" )
optstring="acCdfFhlpqrSsuU -l config:,dldir:,email:,pass:,server:,saveconfig"
getopt -T >/dev/null
if [ $? -eq 4 ]; then
	optstring="-o $optstring"
fi
GETOPTRES=$(getopt $optstring -- "$@")
if [ $? -eq 1 ]; then
	cronexit 1
fi

set -- ${GETOPTRES}
while true;
do
	case "$1" in
		(-h) usage;;
		(-a) AUTOINSTALL_CL=yes;;
		(-c) CRON_CL=yes;;
		(-C) echo "ERROR: CRON option has changed, please review README.md" >&2; cronexit 255;;
		(-d) AUTODELETE_CL=yes;;
		(-f) FORCE_CL=yes;;
		(-F) FORCEALL_CL=yes;;
		(-l) LISTOPTS=yes;;
		(-p) PUBLIC_CL=yes;;
		(-q) QUIET_CL=yes;;
		(-r) PRINT_URL=yes;;
		(-s) AUTOSTART_CL=yes;;
		(-S) echo "ERROR: SILENT option has been removed, please use QUIET (-q) instead" >&2; cronexit 255;;
		(-u) AUTOUPDATE_CL=yes;;
		(-U) IGNOREAUTOUPDATE=yes;;

    (--config) shift; CONFIGFILE="$1"; CONFIGFILE=$(trimQuotes ${CONFIGFILE});;
    (--dldir) shift; DOWNLOADDIR_CL="$1"; DOWNLOADDIR_CL=$(trimQuotes ${DOWNLOADDIR_CL});; 
    (--email) shift; EMAIL_CL="$1"; EMAIL_CL=$(trimQuotes ${EMAIL_CL});;
    (--pass) shift; PASS_CL="$1"; PASS_CL=$(trimQuotes ${PASS_CL});;
    (--server) shift; PLEXSERVER_CL="$1"; PLEXSERVER_CL=$(trimQuotes ${PLEXSERVER_CL});;
		(--saveconfig) SAVECONFIG=yes;;

		(--) ;;
		(-*) echo "ERROR: unrecognized option $1" >&2; usage; cronexit 1;;
		(*)  break;;
	esac
	shift
done

# Sanity, make sure wget is in our path...
if ! hash wget 2>/dev/null; then
	echo "ERROR: This script requires wget in the path. It could also signify that you don't have the tool installed." >&2
	exit 1
fi

# Allow manual control of configfile
if [ ! -z "${CONFIGFILE}" ]; then
	if [ -f "${CONFIGFILE}" ]; then
		source "${CONFIGFILE}"
	else
		echo "ERROR: Cannot load configuration ${CONFIGFILE}" >&2
		exit 1
	fi
else
	# Load settings from config file if it exists
	# Also, respect SUDO_USER and try that first
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
			echo "ERROR: SUDO_USER variable is COMPROMISED: \"${SUDO_USER}\"" >&2
			exit 255
		fi

		# Try using original user's config
		CONFIGDIR="$( eval cd ~${SUDO_USER} 2>/dev/null && pwd )"
		if [ -z "${CONFIGDIR}" ]; then
			echo "WARNING: SUDO_USER \"${SUDO_USER}\" does not have a valid home directory, ignoring." >&2
		fi

		if [ ! -z "${CONFIGDIR}" -a -f "${CONFIGDIR}/.plexupdate" ]; then
			#echo "INFO: Using \"${SUDO_USER}\" configuration: ${CONFIGDIR}/.plexupdate"
			CONFIGFILE="${CONFIGDIR}/.plexupdate"
			source "${CONFIGDIR}/.plexupdate"
		elif [ -f ~/.plexupdate ]; then
			# Fallback for compatibility
			CONFIGFILE="${HOME}/.plexupdate"		# tilde expansion won't happen later.
			source ~/.plexupdate
		fi
	elif [ -f ~/.plexupdate ]; then
		# Fallback for compatibility
		CONFIGFILE="${HOME}/.plexupdate"
		source ~/.plexupdate
	fi
fi

# The way I wrote this, it assumes that whatever we put on the command line is what we want and should override
#   any values in the configuration file. As a result, we need to check if they've been set on the command line
#   and overwrite the values that may have been loaded with the config file

for VAR in AUTOINSTALL CRON AUTODELETE DOWNLOADDIR EMAIL PASS FORCE FORCEALL PUBLIC QUIET AUTOSTART AUTOUPDATE PLEXSERVER
do
	VAR2="$VAR""_CL"
	if [ ! -z ${!VAR2} ]; then
		eval $VAR=${!VAR2}
	fi
done

# This will destroy and recreate the config file. Any settings that are set in the config file but are no longer
# valid will NOT be saved.
if [ "${SAVECONFIG}" = "yes" ]; then
	echo "# Config file for plexupdate" >${CONFIGFILE:="${HOME}/.plexupdate"}

	for VAR in AUTOINSTALL CRON AUTODELETE DOWNLOADDIR EMAIL PASS FORCE FORCEALL PUBLIC QUIET AUTOSTART AUTOUPDATE PLEXSERVER
	do
		if [ ! -z ${!VAR} ]; then

			# The following keys have defaults set in this file. We don't want to include these values if they are the default.
			if [ ${VAR} = "FORCE" \
			-o ${VAR} = "FORCEALL" \
			-o ${VAR} = "PUBLIC" \
			-o ${VAR} = "AUTOINSTALL" \
			-o ${VAR} = "AUTODELETE" \
			-o ${VAR} = "AUTOUPDATE" \
			-o ${VAR} = "AUTOSTART" \
			-o ${VAR} = "CRON" \
			-o ${VAR} = "QUIET" ]; then

				if [ ${!VAR} = "yes" ]; then
					echo "${VAR}=${!VAR}" >> ${CONFIGFILE}
				fi
			else
				echo "${VAR}=${!VAR}" >> ${CONFIGFILE}
			fi
		fi
	done
fi

if [ "${IGNOREAUTOUPDATE}" = "yes" ]; then
	AUTOUPDATE=no
fi

if [ "${KEEP}" = "yes" ]; then
	echo "ERROR: KEEP is deprecated and should be removed from .plexupdate" >&2
	cronexit 255
fi

if [ "${SILENT}" = "yes" ]; then
	echo "ERROR: SILENT option has been removed and should be removed from .plexupdate" >&2
	echo "       Use QUIET or -q instead" >&2
	cronexit 255
fi

if [ ! -z "${RELEASE}" ]; then
	echo "ERROR: RELEASE keyword is deprecated and should be removed from .plexupdate" >&2
	echo "       Use DISTRO and BUILD instead to manually select what to install (check README.md)" >&2
	cronexit 255
fi

if [ "${CRON}" = "yes" -a "${QUIET}" = "no" ]; then
	# If running in cron mode, redirect STDOUT to temporary file
	exec 3>&1 >"${FILE_STDOUTLOG}"
elif [ "${QUIET}" = "yes" ]; then
	# Redirect STDOUT to dev null. Use >&3 if you really, really, REALLY need to print to STDOUT
	exec 3>&1 > /dev/null
fi

if [ "${AUTOUPDATE}" = "yes" ]; then
	if ! hash git 2>/dev/null; then
		echo "ERROR: You need to have git installed for this to work" >&2
		cronexit 1
	fi
	pushd "$(dirname "$0")" >/dev/null
	if [ ! -d .git ]; then
		echo "ERROR: This is not a git repository, auto update only works if you've done a git clone" >&2
		cronexit 1
	fi
	git status | grep "git commit -a" >/dev/null 2>/dev/null
	if [ $? -eq 0 ]; then
		echo "ERROR: You have made changes to the script, cannot auto update" >&2
		cronexit 1
	fi
	echo -n "Auto updating..."
	git pull >/dev/null
	if [ $? -ne 0 ]; then
		echo 'ERROR: Unable to update git, try running "git pull" manually to see what is wrong' >&2
		cronexit 1
	fi
	echo "OK"
	popd >/dev/null

	if ! type "$0" 2>/dev/null >/dev/null ; then
		if [ -f "$0" ]; then
			/bin/bash "$0" -U ${ALLARGS[@]}
		else
			echo "ERROR: Unable to relaunch, couldn't find $0" >&2
			cronexit 1
		fi
	else
		"$0" -U ${ALLARGS[@]}
	fi
	cronexit $?
fi

# Sanity check
if [ -z "${EMAIL}" -o -z "${PASS}" ] && [ "${PUBLIC}" = "no" ] && [ ! -f "${FILE_KAKA}" ]; then
	echo "ERROR: Need username & password to download PlexPass version. Otherwise run with -p to download public version." >&2
	cronexit 1
fi

if [ "${AUTOINSTALL}" = "yes" -o "${AUTOSTART}" = "yes" ]; then
	id | grep -i 'uid=0(' 2>&1 >/dev/null
	if [ $? -ne 0 ]; then
		echo "ERROR: You need to be root to use autoinstall/autostart option." >&2
		cronexit 1
	fi
fi


# Remove any ~ or other oddness in the path we're given
DOWNLOADDIR="$(eval cd ${DOWNLOADDIR// /\\ } && pwd)"
if [ ! -d "${DOWNLOADDIR}" ]; then
	echo "ERROR: Download directory does not exist or is not a directory" >&2
	cronexit 1
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
		echo "ERROR: You must define both DISTRO and BUILD" >&2
		cronexit 255
	fi
else
	if [ -z "${DISTRO}" -o -z "${BUILD}" ]; then
		echo "Using custom DISTRO_INSTALL requires custom DISTRO and BUILD too" >&2
		cronexit 255
	fi
fi

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

# Setup an cronexit handler so we cleanup
function cleanup {
	if [ "${CRON}" = yes -a "${RAWEXIT}" -ne 5 -a -f "${FILE_STDOUTLOG}" ]; then
		exec 1>&3
		cat "${FILE_STDOUTLOG}"
	fi
	rm "${FILE_POSTDATA}" 2>/dev/null >/dev/null
	rm "${FILE_RAW}" 2>/dev/null >/dev/null
	rm "${FILE_FAILCAUSE}" 2>/dev/null >/dev/null
	rm "${FILE_KAKA}" 2>/dev/null >/dev/null
	rm "${FILE_SHA}" 2>/dev/null >/dev/null
}
trap cleanup EXIT

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
	echo -n "Authenticating..."

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
		echo "ERROR: Username and/or password incorrect" >&2
		cronexit 1
	elif [ $RESULTCODE -ne 201 ]; then
		echo "ERROR: Failed to login, debug information:" >&2
		cat "${FILE_FAILCAUSE}" >&2
		cronexit 1
	fi

	# If the system got here, it means the login was successfull, so we set the TOKEN variable to the authToken from the response
	# I use cut -c 14- to cut off the "authToken":" string from the grepped result, can probably be done in a different way
	TOKEN=$(<"${FILE_FAILCAUSE}"  grep -ioe '"authToken":"[^"]*' | cut -c 14-)

	# Remove this, since it contains more information than we should leave hanging around
	rm "${FILE_FAILCAUSE}"

	echo "OK"

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
			if [ "${QUIET}" = "yes" ]; then
				printf "%-12s %-30s %s\n" "$DISTRO" "$BUILD" "$X" >&3
			else
				printf "%-12s %-30s %s\n" "$DISTRO" "$BUILD" "$X"
			fi
			BUILD=
			DISTRO=
		fi
	done
	cronexit 0
fi

# Extract the URL for our release
echo -n "Finding download URL to download..."

# Set "X-Plex-Token" to the auth token, if no token is specified or it is invalid, the list will return public downloads by default
RELEASE=$(wget --header "X-Plex-Token:"${TOKEN}"" --load-cookies "${FILE_KAKA}" --save-cookies "${FILE_KAKA}" --keep-session-cookies "${URL_DOWNLOAD}" -O - 2>/dev/null | grep -ioe '"label"[^}]*' | grep -i "\"distro\":\"${DISTRO}\"" | grep -m1 -i "\"build\":\"${BUILD}\"")
DOWNLOAD=$(echo ${RELEASE} | grep -m1 -ioe 'https://[^\"]*')
CHECKSUM=$(echo ${RELEASE} | grep -ioe '\"checksum\"\:\"[^\"]*' | sed 's/\"checksum\"\:\"//')
echo "OK"

if [ -z "${DOWNLOAD}" ]; then
	echo "ERROR: Unable to retrieve the URL needed for download (Query DISTRO: $DISTRO, BUILD: $BUILD)" >&2
	cronexit 3
fi

FILENAME="$(basename 2>/dev/null ${DOWNLOAD})"
if [ $? -ne 0 ]; then
	echo "ERROR: Failed to parse HTML, download cancelled." >&2
	cronexit 3
fi

echo "${CHECKSUM}  ${DOWNLOADDIR}/${FILENAME}" >"${FILE_SHA}"

if [ "${PRINT_URL}" = "yes" ]; then
	if [ "${QUIET}" = "yes" ]; then
		echo "${DOWNLOAD}" >&3
	else
		echo "${DOWNLOAD}"
	fi
	cronexit 0
fi

# By default, try downloading
SKIP_DOWNLOAD="no"

# Installed version detection (only supported for deb based systems, feel free to submit rpm equivalent)
if [ "${REDHAT}" != "yes" ]; then
	INSTALLED_VERSION=$(dpkg-query -s plexmediaserver 2>/dev/null | grep -Po 'Version: \K.*')
else
	if [ "${AUTOSTART}" = "no" ]; then
		echo "WARNING: Your distribution may require the use of the AUTOSTART [-s] option for the service to start after the upgrade completes."
	fi
	INSTALLED_VERSION=$(rpm -qv plexmediaserver 2>/dev/null)
fi

if [[ $FILENAME == *$INSTALLED_VERSION* ]] && [ "${FORCE}" != "yes" -a "${FORCEALL}" != "yes" ] && [ ! -z "${INSTALLED_VERSION}" ]; then
	echo "Your OS reports the latest version of Plex ($INSTALLED_VERSION) is already installed. Use -f to force download."
	cronexit 5
fi

if [ -f "${DOWNLOADDIR}/${FILENAME}" ]; then
	if [ "${FORCE}" != "yes" -a "${FORCEALL}" != "yes" ]; then
		sha1sum --status -c "${FILE_SHA}"
		if [ $? -eq 0 ]; then
			echo "File already exists (${FILENAME}), won't download."
			if [ "${AUTOINSTALL}" != "yes" ]; then
				cronexit 2
			fi
			SKIP_DOWNLOAD="yes"
		else
			echo "File exists but fails checksum. Redownloading."
			SKIP_DOWNLOAD="no"
		fi
	elif [ "${FORCEALL}" == "yes" ]; then
		echo "Note! File exists, but asked to overwrite with new copy"
	else
		sha1sum --status -c "${FILE_SHA}"
		if [ $? -ne 0 ]; then
			echo "Note! File exists but fails checksum. Redownloading."
		else
			echo "File exists and checksum passes, won't redownload."
			if [ "${AUTOINSTALL}" != "yes" ]; then
				cronexit 2
			fi
			SKIP_DOWNLOAD="yes"
		fi
	fi
fi

if [ "${SKIP_DOWNLOAD}" = "no" ]; then
	echo -ne "Downloading release \"${FILENAME}\"..."
	ERROR=$(wget --load-cookies "${FILE_KAKA}" --save-cookies "${FILE_KAKA}" --keep-session-cookies "${DOWNLOAD}" -O "${DOWNLOADDIR}/${FILENAME}" 2>&1)
	CODE=$?
	if [ ${CODE} -ne 0 ]; then
		echo -e "\n  !! Download failed with code ${CODE}, \"${ERROR}\""
		cronexit ${CODE}
	fi
	echo "OK"
fi

sha1sum --status -c "${FILE_SHA}"
if [ $? -ne 0 ]; then
	echo "Downloaded file corrupt. Try again."
	cronexit 4
fi

if [ ! -z "${PLEXSERVER}" -a "${AUTOINSTALL}" = "yes" ]; then
	# Check if server is in-use before continuing (thanks @AltonV, @hakong and @sufr3ak)...
	if running ${PLEXSERVER} ${TOKEN} ; then
		echo "Server ${PLEXSERVER} is currently being used by one or more users, skipping installation. Please run again later"
		cronexit 6
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
		echo "Deleted \"${FILENAME}\""
	else
		echo "Will not auto delete without [-a] auto install"
	fi
fi

if [ "${AUTOSTART}" = "yes" ]; then
	if [ "${REDHAT}" = "no" ]; then
		echo "The AUTOSTART [-s] option may not be needed on your distribution." >&2
	fi
	# Check for systemd
	if hash systemctl 2>/dev/null; then
		systemctl start plexmediaserver.service
	elif hash service 2>/dev/null; then
		service plexmediaserver start
	elif [ -x /etc/init.d/plexmediaserver ]; then
		/etc/init.d/plexmediaserver start
	else
		echo "ERROR: AUTOSTART was specified but no startup scripts were found for 'plexmediaserver'." >&2
		cronexit 1
	fi
fi

cronexit 0
