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
  echo "ERROR: You must execute this script with BASH"
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

#################################################################
# Don't change anything below this point
#

# Defaults
# (aka "Advanced" settings, can be overriden with config file)
KEEP=no
FORCE=no
PUBLIC=no
AUTOINSTALL=no
AUTODELETE=no
AUTOUPDATE=no
AUTOSTART=no
CRON=no
QUIET=no
SILENT=no
ARCH=$(uname -m)

# Default options for package managers, override if needed
REDHAT_INSTALL="yum -y install"
DEBIAN_INSTALL="dpkg -i"
DISTRO_INSTALL=""

# Sanity, make sure wget is in our path...
wget >/dev/null 2>/dev/null
if [ $? -eq 127 ]; then
	echo "Error: This script requires wget in the path. It could also signify that you don't have the tool installed." >&2
	exit 1
fi

# Load settings from config file if it exists
if [ -f ~/.plexupdate ]; then
	source ~/.plexupdate
fi

if [ ! "${RELEASE}" = "" ]; then
	echo "ERROR: RELEASE keyword is deprecated, use DISTRO and BUILD"
	exit 255
fi

# Current pages we need - Do not change unless Plex.tv changes again
URL_LOGIN=https://plex.tv/users/sign_in.json
URL_DOWNLOAD=https://plex.tv/api/downloads/1.json?channel=plexpass
URL_DOWNLOAD_PUBLIC=https://plex.tv/api/downloads/1.json

usage() {
        echo "Usage: $(basename $0) [-aCfhkopqsSuU]"
        echo "    -a Auto install if download was successful (requires root)"
        echo "    -C Cron mode. Only output to stdout on an actionable operation"
        echo "    -d Auto delete after auto install"
        echo "    -f Force download even if it's the same version or file"
        echo "       already exists (WILL NOT OVERWRITE)"
        echo "    -h This help"
        echo "    -k Reuse last authentication"
        echo "    -l List available builds and distros"
        echo "    -p Public Plex Media Server version"
        echo "    -q Quiet mode. No stdout, only stderr and exit codes"
        echo "    -r Print download URL and exit"
        echo "    -s Auto start (needed for some distros)"
        echo "    -S Silent mode. No text output, only exit codes"
        echo "    -u Auto update plexupdate.sh before running it (experimental)"
        echo "    -U Do not autoupdate plexupdate.sh (experimental, default)"
        echo
        exit 0
}

# Parse commandline
ALLARGS="$@"
set -- $(getopt aCdfhkopqruU: -- "$@")
while true;
do
	case "$1" in
                (-h) usage;;
                (-a) AUTOINSTALL=yes;;
                (-C) CRON=yes;;
                (-d) AUTODELETE=yes;;
                (-f) FORCE=yes;;
                (-k) KEEP=yes;;
                (-l) LISTOPTS=yes;;
                (-p) PUBLIC=yes;;
                (-q) QUIET=yes;;
                (-r) PRINT_URL=yes;;
                (-s) AUTOSTART=yes;;
                (-S) SILENT=yes;;
                (-u) AUTOUPDATE=yes;;
                (-U) AUTOUPDATE=no;;
                (--) ;;
                (-*) echo "Error: unrecognized option $1" 1>&2; usage; exit 1;;
                (*)  break;;
	esac
	shift
done

# send all stdout to /dev/null
if [ "${QUIET}" = "yes" ] || [ "${SILENT}" = "yes" ]; then
        exec 1> /dev/null
fi

# send all stdout and stderr to /dev/null
if [ "${SILENT}" = "yes" ]; then
        exec 2> /dev/null
fi

if [ "${AUTOUPDATE}" == "yes" ]; then
	git >/dev/null 2>/dev/null
	if [ $? -eq 127 ]; then
		echo "Error: You need to have git installed for this to work" >&2
		exit 1
	fi
	pushd "$(dirname "$0")" >/dev/null
	if [ ! -d .git ]; then
		echo "Error: This is not a git repository, auto update only works if you've done a git clone" >&2
		exit 1
	fi
	git status | grep "git commit -a" >/dev/null 2>/dev/null
	if [ $? -eq 0 ]; then
		echo "Error: You have made changes to the script, cannot auto update" >&2
		exit 1
	fi
	echo -n "Auto updating..."
	git pull >/dev/null
	if [ $? -ne 0 ]; then
		echo 'Error: Unable to update git, try running "git pull" manually to see what is wrong' >&2
		exit 1
	fi
	echo "OK"
	popd >/dev/null
	if ! type "$0" 2>/dev/null >/dev/null ; then
		if [ -f "$0" ]; then
			/bin/bash "$0" ${ALLARGS} -U
		else
			echo "Error: Unable to relaunch, couldn't find $0" >&2
			exit 1
		fi
	else
		"$0" ${ALLARGS} -U
	fi
	exit $?
fi

# Sanity check
if [ "${EMAIL}" == "" -o "${PASS}" == "" ] && [ "${PUBLIC}" == "no" ] && [ ! -f /tmp/kaka ]; then
	echo "Error: Need username & password to download PlexPass version. Otherwise run with -p to download public version." >&2
	exit 1
fi

if [ "${AUTOINSTALL}" == "yes" -o "${AUTOSTART}" == "yes" ]; then
	id | grep -i 'uid=0(' 2>&1 >/dev/null
	if [ $? -ne 0 ]; then
		echo "Error: You need to be root to use autoinstall/autostart option." >&2
		exit 1
	fi
fi


# Remove any ~ or other oddness in the path we're given
DOWNLOADDIR="$(eval cd ${DOWNLOADDIR// /\\ } ; if [ $? -eq 0 ]; then pwd; fi)"
if [ -z "${DOWNLOADDIR}" ]; then
	echo "Error: Download directory does not exist or is not a directory" >&2
	exit 1
fi

if [ "${DISTRO_INSTALL}" == "" ]; then
	if [ "${DISTRO}" == "" -a "${BUILD}" == "" ]; then
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
	elif [ "${DISTRO}" == "" -o "${BUILD}" == "" ]; then
		echo "ERROR: You must define both DISTRO and BUILD"
		exit 255
	fi
else
	if [ "${DISTRO}" == "" -o "${BUILD}" == "" ]; then
		echo "Using custom DISTRO_INSTALL requires custom DISTRO and BUILD too"
		exit 255
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

# Setup an exit handler so we cleanup
function cleanup {
	rm /tmp/postdata 2>/dev/null >/dev/null
	rm /tmp/raw 2>/dev/null >/dev/null
	rm /tmp/failcause 2>/dev/null >/dev/null
	if [ "${KEEP}" != "yes" ]; then
		rm /tmp/kaka 2>/dev/null >/dev/null
	fi
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

# If user wants, we skip authentication, but only if previous auth exists
if [ "${KEEP}" != "yes" -o ! -f /tmp/kaka ] && [ "${PUBLIC}" == "no" ]; then
	if [ "${CRON}" = "no" ]; then
	        echo -n "Authenticating..."
	fi
	# Clean old session
	rm /tmp/kaka 2>/dev/null

	# Build post data
	echo -ne >/tmp/postdata "$(keypair "user[login]" "${EMAIL}" )"
	echo -ne >>/tmp/postdata "&$(keypair "user[password]" "${PASS}" )"
	echo -ne >>/tmp/postdata "&$(keypair "user[remember_me]" "0" )"

	# Authenticate (using Plex Single Sign On)
	wget --header "X-Plex-Client-Identifier: 4a745ae7-1839-e44e-1e42-aebfa578c865" --header "X-Plex-Product: Plex SSO" --load-cookies /tmp/kaka --save-cookies /tmp/kaka --keep-session-cookies "${URL_LOGIN}" --post-file=/tmp/postdata -q -S -O /tmp/failcause 2>/tmp/raw
	# Delete authentication data ... Bad idea to let that stick around
	rm /tmp/postdata

	# Provide some details to the end user
	RESULTCODE=$(head -n1 /tmp/raw | grep -oe '[1-5][0-9][0-9]')
	if [ $RESULTCODE -eq 401 ]; then
		echo "ERROR: Username and/or password incorrect" >&2
		exit 1
	elif [ $RESULTCODE -ne 201 ]; then
		echo "ERROR: Failed to login, debug information:" >&2
		cat /tmp/failcause >&2
		exit 1
	fi
	# Remove this, since it contains more information than we should leave hanging around
	rm /tmp/failcause

	if [ "${CRON}" = "no" ]; then
	        echo "OK"
	fi
elif [ "$PUBLIC" != "no" ]; then
	# It's a public version, so change URL and make doubly sure that cookies are empty
	rm 2>/dev/null >/dev/null /tmp/kaka
	touch /tmp/kaka
	URL_DOWNLOAD=${URL_DOWNLOAD_PUBLIC}
fi

if [ "${LISTOPTS}" == "yes" ]; then
	opts="$(wget --load-cookies /tmp/kaka --save-cookies /tmp/kaka --keep-session-cookies "${URL_DOWNLOAD}" -O - 2>/dev/null | grep -oe '"label"[^}]*' | grep -v Download | sed 's/"label":"\([^"]*\)","build":"\([^"]*\)","distro":"\([^"]*\)".*/"\3" "\2" "\1"/' | uniq | sort)"
	eval opts=( "DISTRO" "BUILD" "DESCRIPTION" "======" "=====" "==============================================" $opts )

	BUILD=
	DISTRO=

	for X in "${opts[@]}" ; do
		if [ "$DISTRO" == "" ]; then
			DISTRO="$X"
		elif [ "$BUILD" == "" ]; then
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
if [ "${CRON}" = "no" ]; then
        echo -n "Finding download URL to download..."
fi

DOWNLOAD=$(wget --load-cookies /tmp/kaka --save-cookies /tmp/kaka --keep-session-cookies "${URL_DOWNLOAD}" -O - 2>/dev/null | grep -ioe '"label"[^}]*' | grep -i "\"distro\":\"${DISTRO}\"" | grep -i "\"build\":\"${BUILD}\"" | grep -m1 -ioe 'https://[^\"]*' )
if [ "${CRON}" = "no" ]; then
        echo -e "OK"
fi

if [ "${DOWNLOAD}" == "" ]; then
	echo "ERROR: Unable to retrieve the URL needed for download (Query DISTRO: $DISTRO, BUILD: $BUILD)"
	exit 3
fi

FILENAME="$(basename 2>/dev/null ${DOWNLOAD})"
if [ $? -ne 0 ]; then
	echo "Failed to parse HTML, download cancelled."
	exit 3
fi

if [ "${PRINT_URL}" == "yes" ]; then
  echo "${DOWNLOAD}"
  exit 0
fi

# By default, try downloading
SKIP_DOWNLOAD="no"

# Installed version detection (only supported for deb based systems, feel free to submit rpm equivalent)
if [ "${REDHAT}" != "yes" ]; then
	INSTALLED_VERSION=$(dpkg-query -s plexmediaserver 2>/dev/null | grep -Po 'Version: \K.*')
else
	if [ "${AUTOSTART}" == "no" ]; then
		echo "Your distribution may require the use of the AUTOSTART [-s] option for the service to start after the upgrade completes."
	fi
	INSTALLED_VERSION=$(rpm -qv plexmediaserver 2>/dev/null)
fi
if [[ $FILENAME == *$INSTALLED_VERSION* ]] && [ "${FORCE}" != "yes" ] && [ ! -z "${INSTALLED_VERSION}" ]; then
        if [ "${CRON}" = "no" ]; then
	        echo "Your OS reports the latest version of Plex ($INSTALLED_VERSION) is already installed. Use -f to force download."
	        exit 5
        fi
	exit 0
fi

if [ -f "${DOWNLOADDIR}/${FILENAME}" -a "${FORCE}" != "yes" ]; then
	if [ "${CRON}" = "no" ]; then
	        echo "File already exists, won't download."
        fi
	if [ "${AUTOINSTALL}" != "yes" ]; then
		exit 2
	fi
	SKIP_DOWNLOAD="yes"
fi

if [ "${SKIP_DOWNLOAD}" == "no" ]; then
	if [ -f "${DOWNLOADDIR}/${FILENAME}" ]; then
		if [ "${CRON}" = "no" ]; then
		        echo "Note! File exists, but asked to overwrite with new copy"
		fi
	fi

	echo -ne "Downloading release \"${FILENAME}\"..."
	ERROR=$(wget --load-cookies /tmp/kaka --save-cookies /tmp/kaka --keep-session-cookies "${DOWNLOAD}" -O "${DOWNLOADDIR}/${FILENAME}" 2>&1)
	CODE=$?
	if [ ${CODE} -ne 0 ]; then
		echo -e "\n  !! Download failed with code ${CODE}, \"${ERROR}\""
		exit ${CODE}
	fi
	echo "OK"
fi

if [ "${AUTOINSTALL}" == "yes" ]; then
	sudo ${DISTRO_INSTALL} "${DOWNLOADDIR}/${FILENAME}"
fi

if [ "${AUTODELETE}" == "yes" ]; then
	if [ "${AUTOINSTALL}" == "yes" ]; then
		rm -rf "${DOWNLOADDIR}/${FILENAME}"
		echo "Deleted \"${FILENAME}\""
	else
		echo "Will not auto delete without [-a] auto install"
	fi
fi

if [ "${AUTOSTART}" == "yes" ]; then
	if [ "${REDHAT}" == "no" ]; then
		echo "The AUTOSTART [-s] option may not be needed on your distribution."
	fi
	# Check for systemd
	if [ -f "/bin/systemctl" ]; then
		systemctl start plexmediaserver.service
	else
		/sbin/service plexmediaserver start
	fi
fi

exit 0
