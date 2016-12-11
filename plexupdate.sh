#!/bin/bash
#
# Plex Linux Server download tool
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# This tool will download the latest version of Plex Media
# Server for Linux. It supports both the public versions
# as well as the PlexPass versions.
#
# PlexPass users:
#   Create a plexupdate.conf file in your home directory with these
#   values:
#
#   EMAIL='<whatever your plexpass email was>'
#   PASS='<whatever password you used>'
#   DOWNLOADDIR='<where you would like to save the downloaded package>'
#
# And run the tool using: ./plexupdate.sh --config plexupdate.conf
# or place the config in /etc/plexupdate.conf
#
# See https://github.com/mrworf/plexupdate for more details.
#
# Returns 0 on success
#         1 on error
#         2 if file already downloaded
#         3 if page layout has changed.
#         4 if download fails
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
##############################################################################
# Quick-check before we allow bad things to happen
if [ -z "${BASH_VERSINFO}" ]; then
	echo "ERROR: You must execute this script with BASH" >&2
	exit 255
fi

##############################################################################
# Don't change anything below this point, use a plexupdate.conf file
# to override this section.
# DOWNLOADDIR is the full directory path you would like the download to go.
#
EMAIL=
PASS=
DOWNLOADDIR="/tmp"
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
SHOWPROGRESS=no
WGETOPTIONS=""	# extra options for wget. Used for progress bar.
CHECKUPDATE=yes

# Default options for package managers, override if needed
REDHAT_INSTALL="dnf -y install"
DEBIAN_INSTALL="dpkg -i"
DISTRO_INSTALL=""

# Current pages we need - Do not change unless Plex.tv changes again
URL_LOGIN='https://plex.tv/users/sign_in.json'
URL_DOWNLOAD='https://plex.tv/api/downloads/1.json?channel=plexpass'
URL_DOWNLOAD_PUBLIC='https://plex.tv/api/downloads/1.json'

#URL for new version check
UPSTREAM_GIT_URL='https://raw.githubusercontent.com/mrworf/plexupdate/master/plexupdate.sh'

#Branch to fetch updates from
BRANCHNAME="master"

#Files "owned" by plexupdate, for autoupdate
PLEXUPDATE_FILES="plexupdate.sh extras/installer.sh extras/cronwrapper"

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
	echo "    -u Auto update plexupdate.sh before running it (default with installer)"
	echo "    -U Do not autoupdate plexupdate.sh"
	echo "    -v Show additional debug information"
	echo ""
	echo "    Long Argument Options:"
	echo "    --config <path/to/config/file> Configuration file to use"
	echo "    --dldir <path/to/download/dir> Download directory to use"
	echo "    --email <plex.tv email> Plex.TV email address"
	echo "    --pass <plex.tv password> Plex.TV password"
	echo "    --server <Plex server address> Address of Plex Server"
	echo "    --port <Plex server port> Port for Plex Server. Used with --server"
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

# Parse commandline
ALLARGS=( "$@" )
optstring="-o acCdfFhlpPqrSsuUv -l config:,dldir:,email:,pass:,server:,port:"
GETOPTRES=$(getopt $optstring -- "$@")
if [ $? -eq 1 ]; then
	exit 1
fi

set -- ${GETOPTRES}

for i in `seq 1 $#`; do
	if [ "${!i}" == "--config" ]; then
		config_index=$((++i))
		CONFIGFILE=$(trimQuotes ${!config_index})
		break
	fi
done

#DEPRECATED SUPPORT: Temporary error checking to notify people of change from .plexupdate to plexupdate.conf
# We have to double-check that both files exist before trying to stat them. This is going away soon.
if [ -z "${CONFIGFILE}" -a -f ~/.plexupdate -a ! -f /etc/plexupdate.conf ] || \
	([ -f "${CONFIGFILE}" -a -f ~/.plexupdate ] && [ `stat -Lc %i "${CONFIGFILE}"` == `stat -Lc %i ~/.plexupdate` ]); then
warn ".plexupdate has been deprecated. Please run $(dirname "$0")/extras/installer.sh to update your configuration."
	if [ -t 1 ]; then
		for i in `seq 1 5`; do echo -n .\ ; sleep 1; done
		echo .
	fi
	CONFIGFILE=~/.plexupdate
fi
#DEPRECATED END

# If a config file was specified, or if /etc/plexupdate.conf exists, we'll use it. Otherwise, just skip it.
source "${CONFIGFILE:-"/etc/plexupdate.conf"}" 2>/dev/null

while true;
do
	case "$1" in
		(-h) usage;;
		(-a) AUTOINSTALL=yes;;
		(-c) error "CRON option is deprecated, please use cronwrapper (see README.md)"; exit 255;;
		(-C) error "CRON option is deprecated, please use cronwrapper (see README.md)"; exit 255;;
		(-d) AUTODELETE=yes;;
		(-f) FORCE=yes;;
		(-F) FORCEALL=yes;;
		(-l) LISTOPTS=yes;;
		(-p) PUBLIC=yes;;
		(-P) SHOWPROGRESS=yes;;
		(-q) error "QUIET option is deprecated, please redirect to /dev/null instead"; exit 255;;
		(-r) PRINT_URL=yes;;
		(-s) AUTOSTART=yes;;
		(-u) AUTOUPDATE=yes;;
		(-U) AUTOUPDATE=no;;
		(-v) VERBOSE=yes;;

		(--config) shift;; #gobble up the paramater and silently continue parsing
		(--dldir) shift; DOWNLOADDIR=$(trimQuotes ${1});;
		(--email) shift; EMAIL=$(trimQuotes ${1});;
		(--pass) shift; PASS=$(trimQuotes ${1});;
		(--server) shift; PLEXSERVER=$(trimQuotes ${1});;
		(--port) shift; PLEXPORT=$(trimQuotes ${1});;

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

if [ "${SHOWPROGRESS}" = "yes" ]; then
	if ! wget --show-progress -V &>/dev/null; then
		warn "Your wget is too old to support --show-progress, ignoring"
	else
		WGETOPTIONS="--show-progress"
	fi
fi

if [ "${CRON}" = "yes" ]; then
	error "CRON has been deprecated, please use cronwrapper (see README.md)"
	exit 255
fi

if [ "${KEEP}" = "yes" ]; then
	error "KEEP is deprecated and should be removed from config file"
	exit 255
fi

if [ ! -z "${RELEASE}" ]; then
	error "RELEASE keyword is deprecated and should be removed from config file"
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
		error "This is not a git repository. Auto-update only works if you've done a git clone"
		exit 1
	fi

	if ! git diff --quiet; then
		error "You have made changes to the plexupdate files, cannot auto update"
		exit 1
	fi

	# Force FETCH_HEAD to point to the correct branch (for older versions of git which don't default to current branch)
	if git fetch origin $BRANCHNAME --quiet && ! git diff --quiet FETCH_HEAD; then
		info "Auto-updating..."

		# Use an associative array to store permissions. If you're running bash < 4, the declare will fail and we'll
		# just run in "dumb" mode without trying to restore permissions
		declare -A FILE_OWNER FILE_PERMS && \
		for filename in $PLEXUPDATE_FILES; do
			FILE_OWNER[$filename]=$(stat -c "%u:%g" "$filename")
			FILE_PERMS[$filename]=$(stat -c "%a" "$filename")
		done

		if ! git merge --quiet FETCH_HEAD; then
			error 'Unable to update git, try running "git pull" manually to see what is wrong'
			exit 1
		fi

		if [ ${#FILE_OWNER[@]} -gt 0 ]; then
			for filename in $PLEXUPDATE_FILES; do
				chown ${FILE_OWNER[$filename]} $filename &> /dev/null || error "Failed to restore ownership for '$filename' after auto-update"
				chmod ${FILE_PERMS[$filename]} $filename &> /dev/null || error "Failed to restore permissions for '$filename' after auto-update"
			done
		fi

		# .git permissions don't seem to be affected by running as root even though files inside do, so just reset
		# the permissions to match the folder
		chown -R --reference=.git .git

		info "Update complete"

		#make sure we're back in the right relative location before testing $0
		popd >/dev/null

		if [ ! -f "$0" ]; then
			error "Unable to relaunch, couldn't find $0"
			exit 1
		else
			[ -x "$0" ] || chmod 755 "$0"
			"$0" ${ALLARGS[@]}
			exit $?
		fi
	fi

	#we may have already returned, so ignore any errors as well
	popd &>/dev/null
fi

# Sanity check
if [ -z "${EMAIL}" -o -z "${PASS}" ] && [ "${PUBLIC}" = "no" ]; then
	error "Need username & password to download PlexPass version. Otherwise run with -p to download public version."
	exit 1
elif [ ! -z "${EMAIL}" ] && [[ "$EMAIL" == *"@"* ]] && [[ "$EMAIL" != *"@"*"."* ]]; then
	error "EMAIL field must contain a valid email address"
	exit 1
fi


if [ "${AUTOINSTALL}" = "yes" -o "${AUTOSTART}" = "yes" ] && [ ${EUID} -ne 0 ]; then
	error "You need to be root to use AUTOINSTALL/AUTOSTART option."
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
			if ! hash dnf 2>/dev/null; then
				DISTRO_INSTALL="${REDHAT_INSTALL/dnf/yum}"
			else
				DISTRO_INSTALL="${REDHAT_INSTALL}"
			fi
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

if [ "${CHECKUPDATE}" = "yes" -a "${AUTOUPDATE}" = "no" ]; then
	(wget -q "$UPSTREAM_GIT_URL" -O - 2>/dev/null || echo ERROR) | sha1sum >"${FILE_REMOTE}" 2>/dev/null
	ERR1=$?
	(cat "$0" 2>/dev/null || echo ERROR) | sha1sum >"${FILE_LOCAL}" 2>/dev/null
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

# Installed version detection
if [ "${REDHAT}" != "yes" ]; then
	INSTALLED_VERSION=$(dpkg-query -s plexmediaserver 2>/dev/null | grep -Po 'Version: \K.*')
else
	if [ "${AUTOINSTALL}" = "yes" -a "${AUTOSTART}" = "no" ]; then
		warn "Your distribution may require the use of the AUTOSTART [-s] option for the service to start after the upgrade completes."
	fi
	INSTALLED_VERSION=$(rpm -qv plexmediaserver 2>/dev/null)
fi

if [[ $FILENAME == *$INSTALLED_VERSION* ]] && [ "${FORCE}" != "yes" -a "${FORCEALL}" != "yes" ] && [ ! -z "${INSTALLED_VERSION}" ]; then
	info "Your OS reports the latest version of Plex ($INSTALLED_VERSION) is already installed. Use -f to force download."
	exit 0
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
