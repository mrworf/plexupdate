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
PLEXSERVER=

#################################################################
# Don't change anything below this point
#

# Defaults
# (aka "Advanced" settings, can be overriden with config file)
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

# Telegram notification options
TELEGRAM_NOTIFY="no"
TELEGRAM_CHAT_ID="no"
TELEGRAM_BOT_TOKEN="no"
TELEGRAM_MESSAGE=""
TELEGRAM_DEBUG=no

# Sanity, make sure wget is in our path...
wget >/dev/null 2>/dev/null
if [ $? -eq 127 ]; then
	echo "Error: This script requires wget in the path. It could also signify that you don't have the tool installed." >&2
	exit 1
fi

# Allow manual control of configfile
HASCFG="${@: -1}"
if [ ! "${HASCFG}" = "" -a ! "${HASCFG:0:1}" = "-" ]; then
	if [ -f "${HASCFG}" ]; then
		source "${HASCFG}"
	else
		echo "ERROR: Cannot load configuration ${HASCFG}" >&2
		exit 1
	fi
else
	# Load settings from config file if it exists
	# Also, respect SUDO_USER and try that first
	if [ "${SUDO_USER}" != "" ]; then
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
		if [ "${CONFIGDIR}" == "" ]; then
			echo "WARNING: SUDO_USER \"${SUDO_USER}\" does not have a valid home directory, ignoring." >&2
		fi

		if [ "${CONFIGDIR}" != "" -a -f "${CONFIGDIR}/.plexupdate" ]; then
			#echo "INFO: Using \"${SUDO_USER}\" configuration: ${CONFIGDIR}/.plexupdate"
			source "${CONFIGDIR}/.plexupdate"
		elif [ -f ~/.plexupdate ]; then
			# Fallback for compatibility
			source ~/.plexupdate
		fi
	elif [ -f ~/.plexupdate ]; then
		# Fallback for compatibility
		source ~/.plexupdate
	fi
fi

if [ ! "${RELEASE}" = "" ]; then
	echo "ERROR: RELEASE keyword is deprecated and should be removed from .plexupdate" >&2
	echo "       Use DISTRO and BUILD instead to manually select what to install (check README.md)" >&2
	exit 255
fi

# Current pages we need - Do not change unless Plex.tv changes again
URL_LOGIN=https://plex.tv/users/sign_in.json
URL_DOWNLOAD=https://plex.tv/api/downloads/1.json?channel=plexpass
URL_DOWNLOAD_PUBLIC=https://plex.tv/api/downloads/1.json

cronexit() {
	# Don't give anything but true error codes if in CRON mode
	if [ "${CRON}" = "yes" -a $1 -gt 1 -a $1 -lt 255 ]; then
		cronexit 0
	fi
	exit $1
}

usage() {
        echo "Usage: $(basename $0) [-acfhopqsStuU] [config file]"
	echo ""
	echo "    config file overrides the default ~/.plexupdate"
	echo "    If used, it must be the LAST option or it will be ignored"
	echo ""
        echo "    -a Auto install if download was successful (requires root)"
	echo "    -c Cron mode, only fatal errors return non-zero cronexit code"
        echo "    -d Auto delete after auto install"
        echo "    -f Force download even if it's the same version or file"
        echo "       already exists (WILL NOT OVERWRITE)"
        echo "    -h This help"
        echo "    -l List available builds and distros"
        echo "    -p Public Plex Media Server version"
        echo "    -q Quiet mode. No stdout, only stderr and cronexit codes"
        echo "    -r Print download URL and exit"
        echo "    -s Auto start (needed for some distros)"
        echo "    -S Silent mode. No text output, only exit codes"
        echo "    -t Send a Telegram notification"
        echo "    -u Auto update plexupdate.sh before running it (experimental)"
        echo "    -U Do not autoupdate plexupdate.sh (experimental, default)"
        echo
        cronexit 0
}

# Parse commandline
ALLARGS=( "$@" )
set -- $(getopt acCdfhkopqruU: -- "$@")
while true;
do
	case "$1" in
                (-h) usage;;
                (-a) AUTOINSTALL=yes;;
                (-c) CRON=yes;;
		(-C) echo "ERROR: CRON option has changed, please review README.md" 1>&2; cronexit 255;;
                (-d) AUTODELETE=yes;;
                (-f) FORCE=yes;;
                (-l) LISTOPTS=yes;;
                (-p) PUBLIC=yes;;
                (-q) QUIET=yes;;
                (-r) PRINT_URL=yes;;
                (-s) AUTOSTART=yes;;
                (-S) SILENT=yes;;
                (-t) TELEGRAM_NOTIFY=yes;;
                (-u) AUTOUPDATE=yes;;
                (-U) AUTOUPDATE=no;;
                (--) ;;
                (-*) echo "Error: unrecognized option $1" 1>&2; usage; cronexit 1;;
                (*)  break;;
	esac
	shift
done

if [ "${KEEP}" = "yes" ]; then
	echo "ERROR: KEEP is deprecated" >&2
	cronexit 1
fi

# send all stdout to /dev/null
if [ "${QUIET}" = "yes" ] || [ "${SILENT}" = "yes" ]; then
	exec 5>&1 >/dev/null
fi

# send all stdout and stderr to /dev/null
if [ "${SILENT}" = "yes" ]; then
        exec 2> /dev/null
fi

if [ "${AUTOUPDATE}" == "yes" ]; then
	git >/dev/null 2>/dev/null
	if [ $? -eq 127 ]; then
		echo "Error: You need to have git installed for this to work" >&2
		cronexit 1
	fi
	pushd "$(dirname "$0")" >/dev/null
	if [ ! -d .git ]; then
		echo "Error: This is not a git repository, auto update only works if you've done a git clone" >&2
		cronexit 1
	fi
	git status | grep "git commit -a" >/dev/null 2>/dev/null
	if [ $? -eq 0 ]; then
		echo "Error: You have made changes to the script, cannot auto update" >&2
		cronexit 1
	fi
	echo -n "Auto updating..."
	git pull >/dev/null
	if [ $? -ne 0 ]; then
		echo 'Error: Unable to update git, try running "git pull" manually to see what is wrong' >&2
		cronexit 1
	fi
	echo "OK"
	popd >/dev/null

	ALLARGS2=()
	for A in ${ALLARGS[@]} ; do
		if [ ! "${A}" = "-u" ]; then
			ALLARGS2+=(${A})
		fi
	done
	ALLARGS=("${ALLARGS2[@]}")

	if ! type "$0" 2>/dev/null >/dev/null ; then
		if [ -f "$0" ]; then
			/bin/bash "$0" -U ${ALLARGS[@]}
		else
			echo "Error: Unable to relaunch, couldn't find $0" >&2
			cronexit 1
		fi
	else
		"$0" -U ${ALLARGS[@]}
	fi
	cronexit $?
fi

# Sanity check
if [ "${EMAIL}" == "" -o "${PASS}" == "" ] && [ "${PUBLIC}" == "no" ] && [ ! -f /tmp/kaka ]; then
	echo "Error: Need username & password to download PlexPass version. Otherwise run with -p to download public version." >&2
	cronexit 1
fi

if [ "${AUTOINSTALL}" == "yes" -o "${AUTOSTART}" == "yes" ]; then
	id | grep -i 'uid=0(' 2>&1 >/dev/null
	if [ $? -ne 0 ]; then
		echo "Error: You need to be root to use autoinstall/autostart option." >&2
		cronexit 1
	fi
fi


# Remove any ~ or other oddness in the path we're given
DOWNLOADDIR="$(eval cd ${DOWNLOADDIR// /\\ } ; if [ $? -eq 0 ]; then pwd; fi)"
if [ -z "${DOWNLOADDIR}" ]; then
	echo "Error: Download directory does not exist or is not a directory" >&2
	cronexit 1
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
		echo "ERROR: You must define both DISTRO and BUILD" >&2
		cronexit 255
	fi
else
	if [ "${DISTRO}" == "" -o "${BUILD}" == "" ]; then
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
	rm /tmp/postdata 2>/dev/null >/dev/null
	rm /tmp/raw 2>/dev/null >/dev/null
	rm /tmp/failcause 2>/dev/null >/dev/null
	rm /tmp/kaka 2>/dev/null >/dev/null
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

# Load previous token if stored
if [ -f /tmp/kaka_token ]; then
	TOKEN=$(cat /tmp/kaka_token)
fi

# If user wants, we skip authentication, but only if previous auth exists
if [ "${PUBLIC}" == "no" ]; then
        echo -n "Authenticating..."

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
		cronexit 1
	elif [ $RESULTCODE -ne 201 ]; then
		echo "ERROR: Failed to login, debug information:" >&2
		cat /tmp/failcause >&2
		cronexit 1
	fi

	# If the system got here, it means the login was successfull, so we set the TOKEN variable to the authToken from the response
	# I use cut -c 14- to cut off the "authToken":" string from the grepped result, can probably be done in a different way
	TOKEN=$(</tmp/failcause  grep -ioe '"authToken":"[^"]*' | cut -c 14-)

	# Remove this, since it contains more information than we should leave hanging around
	rm /tmp/failcause

        echo "OK"
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
	cronexit 0
fi

# Extract the URL for our release
        echo -n "Finding download URL to download..."

# Set "X-Plex-Token" to the auth token, if no token is specified or it is invalid, the list will return public downloads by default
DOWNLOAD=$(wget --header "X-Plex-Token:"${TOKEN}"" --load-cookies /tmp/kaka --save-cookies /tmp/kaka --keep-session-cookies "${URL_DOWNLOAD}" -O - 2>/dev/null | grep -ioe '"label"[^}]*' | grep -i "\"distro\":\"${DISTRO}\"" | grep -i "\"build\":\"${BUILD}\"" | grep -m1 -ioe 'https://[^\"]*' )

echo -e "OK"

if [ "${DOWNLOAD}" == "" ]; then
	echo "ERROR: Unable to retrieve the URL needed for download (Query DISTRO: $DISTRO, BUILD: $BUILD)" >&2
	cronexit 3
fi

FILENAME="$(basename 2>/dev/null ${DOWNLOAD})"
if [ $? -ne 0 ]; then
	echo "ERROR: Failed to parse HTML, download cancelled." >&2
	cronexit 3
fi

if [ "${PRINT_URL}" == "yes" ]; then
  echo "${DOWNLOAD}" >&5
  cronexit 0
fi

# By default, try downloading
SKIP_DOWNLOAD="no"

# Installed version detection (only supported for deb based systems, feel free to submit rpm equivalent)
if [ "${REDHAT}" != "yes" ]; then
	INSTALLED_VERSION=$(dpkg-query -s plexmediaserver 2>/dev/null | grep -Po 'Version: \K.*')
else
	if [ "${AUTOSTART}" == "no" ]; then
		echo "WARNING: Your distribution may require the use of the AUTOSTART [-s] option for the service to start after the upgrade completes."
	fi
	INSTALLED_VERSION=$(rpm -qv plexmediaserver 2>/dev/null)
fi
if [[ $FILENAME == *$INSTALLED_VERSION* ]] && [ "${FORCE}" != "yes" ] && [ ! -z "${INSTALLED_VERSION}" ]; then
        echo "Your OS reports the latest version of Plex ($INSTALLED_VERSION) is already installed. Use -f to force download."
        cronexit 5
fi

if [ -f "${DOWNLOADDIR}/${FILENAME}" -a "${FORCE}" != "yes" ]; then
        echo "File already exists (${FILENAME}), won't download."
	if [ "${AUTOINSTALL}" != "yes" ]; then
		cronexit 2
	fi
	SKIP_DOWNLOAD="yes"
fi

if [ "${SKIP_DOWNLOAD}" == "no" ]; then
	if [ -f "${DOWNLOADDIR}/${FILENAME}" ]; then
	        echo "Note! File exists, but asked to overwrite with new copy"
	fi

	echo -ne "Downloading release \"${FILENAME}\"..."
	ERROR=$(wget --load-cookies /tmp/kaka --save-cookies /tmp/kaka --keep-session-cookies "${DOWNLOAD}" -O "${DOWNLOADDIR}/${FILENAME}" 2>&1)
	CODE=$?
	if [ ${CODE} -ne 0 ]; then
		echo -e "\n  !! Download failed with code ${CODE}, \"${ERROR}\""
		cronexit ${CODE}
	fi
	echo "OK"
fi

if [ ! "${PLEXSERVER}" = "" -a "${AUTOINSTALL}" == "yes" ]; then
	# Check if server is in-use before continuing (thanks @AltonV, @hakong and @sufr3ak)...
	if ! wget --no-check-certificate -q -O - https://${PLEXSERVER}:32400/status/sessions | grep -q '<MediaContainer size="0">' ; then
		echo "Server ${PLEXSERVER} is currently being used by one or more users, skipping installation. Please run again later"
		cronexit 6
	fi
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

if [ "${TELEGRAM_NOTIFY}" == "yes" ]; then
        # check to see if there is a BOT_TOKEN provided; if not, error out sending notification.
        if [ "${TELEGRAM_BOT_TOKEN}" == "no" ]; then
                echo "TELEGRAM_BOT_TOKEN is empty. Get your BOT_TOKEN from @BotFather."
                cronexit 1
        fi
        # check to see if there is a CHAT_ID in which to send the notification; if not, error out sending notification.
        if [ "${TELEGRAM_CHAT_ID}" = "no" ]; then
                echo "TELEGRAM_CHAT_ID is empty. Get the Chat ID from @myidbot."
                cronexit 1
        fi
        # check to see if AUTOINSTALL is on; if so, set a successful update notice.
        if [ "${AUTOINSTALL}" == "yes" ]; then
                TELEGRAM_MESSAGE="Plex was successfully updated using ${FILENAME}"
        else
                TELEGRAM_MESSAGE="Plex downloaded ${FILENAME} to ${DOWNLOADDIR}"
        fi
        # send the notification to Telegram's BOT API, output to TELEGRAM_RESPONSE for potential debugging.
        TELEGRAM_RESPONSE=$(curl -s https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage?chat_id="${TELEGRAM_CHAT_ID}"\&text="${TELEGRAM_MESSAGE}")

        if [ "${TELEGRAM_DEBUG}" == "yes" ]; then
                echo "######################"
                echo "### TELEGRAM DEBUG ###"
                echo $TELEGRAM_RESPONSE
                echo "######################"
        else
                echo "Telegram notification sent."
        fi

fi


cronexit 0
