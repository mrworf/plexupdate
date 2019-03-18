#!/bin/bash
#
# Plex Linux Server download tool
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# This tool will download the latest version of Plex Media
# Server for Linux. It supports both the public versions
# as well as the PlexPass versions.
#
# See https://github.com/mrworf/plexupdate for more details.
#
# Returns 0 on success
#         1 on error
#         3 if page layout has changed.
#         4 if download fails
#         6 if update was deferred due to usage
#         7 if update is available (requires --check-update)
#        10 if new file was downloaded/installed (requires --notify-success)
#       255 configuration is invalid
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
PUBLIC=no
AUTOINSTALL=no
AUTODELETE=no
AUTOUPDATE=no
AUTOSTART=no
ARCH=$(uname -m)
BUILD="linux-$ARCH"
SHOWPROGRESS=no
WGETOPTIONS=""	# extra options for wget. Used for progress bar.
CHECKUPDATE=yes
NOTIFY=no
CHECKONLY=no
SYSTEMDUNIT=plexmediaserver.service

FILE_SHA=$(mktemp /tmp/plexupdate.sha.XXXX)
FILE_WGETLOG=$(mktemp /tmp/plexupdate.wget.XXXX)
SCRIPT_PATH="$(dirname "$0")"

######################################################################

usage() {
	echo "Usage: $(basename $0) [-acdfFhlpPqsuU] [<long options>]"
	echo ""
	echo ""
	echo "    -a Auto install if download was successful (requires root)"
	echo "    -d Auto delete after auto install"
	echo "    -f Force download/update even if the newest release is already installed"
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
	echo "    --check-update Check for new version of plex only"
	echo "    --config <path/to/config/file> Configuration file to use"
	echo "    --dldir <path/to/download/dir> Download directory to use"
	echo "    --help This help"
	echo "    --notify-success Set exit code 10 if update is available/installed"
	echo "    --port <Plex server port> Port for Plex Server. Used with --server"
	echo "    --server <Plex server address> Address of Plex Server"
	echo "    --token Manually specify the token to use to download Plex Pass releases"
	echo ""
	exit 0
}

if ! source "${SCRIPT_PATH}/plexupdate-core"; then
	echo "ERROR: plexupdate-core can't be found. Please redownload plexupdate and try again." >2
	exit 1
fi

# Setup an exit handler so we cleanup
cleanup() {
	rm "${FILE_SHA}" "${FILE_WGETLOG}" &> /dev/null
}
trap cleanup EXIT

# Parse commandline
ALLARGS=( "$@" )
optstring="-o acCdfFhlpPqrSsuUv -l config:,dldir:,email:,pass:,server:,port:,token:,notify-success,check-update,help"
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
	warn ".plexupdate has been deprecated. Please run ${SCRIPT_PATH}/extras/installer.sh to update your configuration."
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
		(-F) error "FORCEALL/-F option is deprecated, please use FORCE/-f instead"; exit 255;;
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
		(--email) shift; warn "EMAIL is deprecated. Use TOKEN instead."; EMAIL=$(trimQuotes ${1});;
		(--pass) shift; warn "PASS is deprecated. Use TOKEN instead."; PASS=$(trimQuotes ${1});;
		(--server) shift; PLEXSERVER=$(trimQuotes ${1});;
		(--port) shift; PLEXPORT=$(trimQuotes ${1});;
		(--token) shift; TOKEN=$(trimQuotes ${1});;
		(--help) usage;;

		(--notify-success) NOTIFY=yes;;
		(--check-update) CHECKONLY=yes;;

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
	error "KEEP is deprecated and must be removed from config file"
	exit 255
fi

if [ "${FORCEALL}" = "yes" ]; then
	error "FORCEALL is deprecated, please use FORCE instead"
	exit 255
fi

if [ ! -z "${RELEASE}" ]; then
	error "RELEASE keyword is deprecated and must be removed from config file"
	error "Use DISTRO and BUILD instead to manually select what to install (check README.md)"
	exit 255
fi

if [ "${AUTOUPDATE}" = "yes" ]; then
	if ! hash git 2>/dev/null; then
		error "You need to have git installed for this to work"
		exit 1
	fi

	pushd "${SCRIPT_PATH}" >/dev/null

	if [ ! -d .git ]; then
		warn "This is not a git repository. Auto-update only works if you've done a git clone"
	elif ! git diff --quiet; then
		warn "You have made changes to the plexupdate files, cannot auto update"
	else
		if [ -z "${BRANCHNAME}" ]; then
			BRANCHNAME="$(git symbolic-ref -q --short HEAD)"
		elif [ "${BRANCHNAME}" != "$(git symbolic-ref -q --short HEAD)" ]; then
			git checkout "${BRANCHNAME}"
		fi
		# Force FETCH_HEAD to point to the correct branch (for older versions of git which don't default to current branch)
		if git fetch origin ${BRANCHNAME} --quiet && ! git diff --quiet FETCH_HEAD; then
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
	fi

	#we may have already returned, so ignore any errors as well
	popd &>/dev/null
fi

if [ "${AUTOINSTALL}" = "yes" -o "${AUTOSTART}" = "yes" ] && [ ${EUID} -ne 0 ]; then
	error "You need to be root to use AUTOINSTALL/AUTOSTART option."
	exit 1
fi


# Remove any ~ or other oddness in the path we're given
DOWNLOADDIR_PRE=${DOWNLOADDIR}
DOWNLOADDIR="$(eval cd ${DOWNLOADDIR// /\\ } 2>/dev/null && pwd)"
if [ ! -d "${DOWNLOADDIR}" ]; then
	error "Download directory does not exist or is not a directory (tried \"${DOWNLOADDIR_PRE}\")"
	exit 1
fi

if [ -z "${DISTRO_INSTALL}" ]; then
	if [ -z "${DISTRO}" ]; then
		# Detect if we're running on redhat instead of ubuntu
		if [ -f /etc/redhat-release ]; then
			REDHAT=yes
			DISTRO="redhat"
			if ! hash dnf 2>/dev/null; then
				DISTRO_INSTALL="${REDHAT_INSTALL/dnf/yum}"
			else
				DISTRO_INSTALL="${REDHAT_INSTALL}"
			fi
		else
			REDHAT=no
			DISTRO="debian"
			DISTRO_INSTALL="${DEBIAN_INSTALL}"
		fi
	fi
else
	if [ -z "${DISTRO}" -o -z "${BUILD}" ]; then
		error "Using custom DISTRO_INSTALL requires custom DISTRO and BUILD too"
		exit 255
	fi
fi

if [ "${CHECKUPDATE}" = "yes" -a "${AUTOUPDATE}" = "no" ]; then
	pushd "${SCRIPT_PATH}" > /dev/null
	for filename in $PLEXUPDATE_FILES; do
		[ -f "$filename" ] || error "Update check failed. '$filename' could not be found"

		REMOTE_SHA=$(getRemoteSHA "$UPSTREAM_GIT_URL/$filename") || error "Update check failed. Unable to fetch '$UPSTREAM_GIT_URL/$filename'."
		LOCAL_SHA=$(getLocalSHA "$filename")
		if [ "$REMOTE_SHA" != "$LOCAL_SHA" ]; then
			info "Newer version of this script is available at https://github.com/${GIT_OWNER:-mrworf}/plexupdate"
			break
		fi
	done
	popd > /dev/null
fi

if [ "${PUBLIC}" = "no" ] && ! getPlexToken; then
	error "Unable to get Plex token, falling back to public release"
	PUBLIC="yes"
fi

if [ "$PUBLIC" != "no" ]; then
	# It's a public version, so change URL
	URL_DOWNLOAD=${URL_DOWNLOAD_PUBLIC}
fi

if [ "${LISTOPTS}" = "yes" ]; then
	wgetresults="$(wget "${URL_DOWNLOAD}" -o "${FILE_WGETLOG}" -O -)"
	if [ $? -ne 0 ]; then
		error "Unable to retrieve available builds due to a wget error, run with -v for details"
		[ "$VERBOSE" = "yes" ] && cat "${FILE_WGETLOG}"
		exit 1
	fi
	opts="$(grep -oe '"label"[^}]*' <<<"${wgetresults}" | grep -v Download | sed 's/"label":"\([^"]*\)","build":"\([^"]*\)","distro":"\([^"]*\)".*/"\3" "\2" "\1"/' | uniq | sort)"
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
wgetresults="$(wget --header "X-Plex-Token:"${TOKEN}"" "${URL_DOWNLOAD}" -o "${FILE_WGETLOG}" -O -)"
if [ $? -ne 0 ]; then
	error "Unable to retrieve the URL needed for download due to a wget error, run with -v for details"
	[ "$VERBOSE" = "yes" ] && cat "${FILE_WGETLOG}"
	exit 1
fi
RELEASE=$(grep -ioe '"label"[^}]*' <<<"${wgetresults}" | grep -i "\"distro\":\"${DISTRO}\"" | grep -m1 -i "\"build\":\"${BUILD}\"")
DOWNLOAD=$(echo ${RELEASE} | grep -m1 -ioe 'https://[^\"]*')
CHECKSUM=$(echo ${RELEASE} | grep -ioe '\"checksum\"\:\"[^\"]*' | sed 's/\"checksum\"\:\"//')

verboseOutput RELEASE DOWNLOAD CHECKSUM

if [ -z "${DOWNLOAD}" ]; then
	if [ "$DISTRO" = "ubuntu" -a "$BUILD" = "linux-ubuntu-armv7l" ]; then
		error "Plex Media Server on Raspbian is not officially supported and script cannot download a working package."
	else
		error "Unable to retrieve the URL needed for download (Query DISTRO: $DISTRO, BUILD: $BUILD)"
	fi
	if [ ! -z "${RELEASE}" ]; then
		error "It seems release info is missing a link"
		error "Please try https://plex.tv and confirm it works there before reporting this issue"
	fi
	exit 3
elif [ -z "${CHECKSUM}" ]; then
	error "Unable to retrieve a checksum for the download. Please try https://plex.tv/downloads before reporting this issue."
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

INSTALLED_VERSION="$(getPlexVersion)" || warn "Unable to detect installed version, first time?"
FILE_VERSION="$(parseVersion "${FILENAME}")"
verboseOutput INSTALLED_VERSION FILE_VERSION

if [ "${REDHAT}" = "yes" -a "${AUTOINSTALL}" = "yes" -a "${AUTOSTART}" = "no" ]; then
	warn "Your distribution may require the use of the AUTOSTART [-s] option for the service to start after the upgrade completes."
fi

if [ "${CHECKONLY}" = "yes" ]; then
	if [ -n "${INSTALLED_VERSION}" ] && isNewerVersion "$FILE_VERSION" "$INSTALLED_VERSION"; then
		info "Your OS reports Plex $INSTALLED_VERSION installed, newer version is available (${FILE_VERSION})"
		exit 7
	elif [ -n "${INSTALLED_VERSION}" ]; then
		info "You are running the latest version of Plex (${INSTALLED_VERSION})"
	fi
	exit 0
fi

if ! isNewerVersion "$FILE_VERSION" "$INSTALLED_VERSION" && [ "${FORCE}" != "yes" ]; then
	info "Your OS reports the latest version of Plex ($INSTALLED_VERSION) is already installed. Use -f to force download."
	exit 0
fi

if [ -f "${DOWNLOADDIR}/${FILENAME}" ]; then
	if sha1sum --status -c "${FILE_SHA}"; then
		info "File already exists (${FILENAME}), won't download."
		if [ "${AUTOINSTALL}" != "yes" ]; then
			exit 0
		fi
		SKIP_DOWNLOAD="yes"
	else
		info "File exists but fails checksum. Redownloading."
		SKIP_DOWNLOAD="no"
	fi
fi

if [ "${SKIP_DOWNLOAD}" = "no" ]; then
	info "Downloading release \"${FILENAME}\""
	wget ${WGETOPTIONS} -o "${FILE_WGETLOG}" "${DOWNLOAD}" -O "${DOWNLOADDIR}/${FILENAME}" 2>&1
	CODE=$?

	if [ ${CODE} -ne 0 ]; then
		error "Download failed with code ${CODE}:"
		cat "${FILE_WGETLOG}" >&2
		exit ${CODE}
	fi
	info "File downloaded"
fi

if ! sha1sum --status -c "${FILE_SHA}"; then
	error "Downloaded file corrupt. Try again."
	exit 4
fi

if [ -n "${PLEXSERVER}" -a "${AUTOINSTALL}" = "yes" ]; then
	# Check if server is in-use before continuing (thanks @AltonV, @hakong and @sufr3ak)...
	if running "${PLEXSERVER}" "${PLEXPORT}"; then
		error "Server ${PLEXSERVER} is currently being used by one or more users, skipping installation. Please run again later"
		exit 6
	fi
fi

if [ "${AUTOINSTALL}" = "yes" ]; then
	if ! hash ldconfig 2>/dev/null && [ "${REDHAT}" = "no" ]; then
		export PATH=$PATH:/sbin
	fi

	${DISTRO_INSTALL} "${DOWNLOADDIR}/${FILENAME}"
	RET=$?
	if [ ${RET} -ne 0 ]; then
		# Clarify why this failed, so user won't be left in the dark
		error "Failed to install update. Command '${DISTRO_INSTALL} "${DOWNLOADDIR}/${FILENAME}"' returned error code ${RET}"
		exit ${RET}
	fi
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
		systemctl start "$SYSTEMDUNIT"
	elif hash service 2>/dev/null; then
		service plexmediaserver start
	elif [ -x /etc/init.d/plexmediaserver ]; then
		/etc/init.d/plexmediaserver start
	else
		error "AUTOSTART was specified but no startup scripts were found for 'plexmediaserver'."
		exit 1
	fi
fi

if [ "${NOTIFY}" = "yes" ]; then
	# Notify success if we downloaded and possibly installed the update
	exit 10
fi
exit 0
