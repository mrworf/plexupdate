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
RELEASE="64"
FORCE=no
PUBLIC=no
AUTOINSTALL=no
AUTODELETE=no
AUTOUPDATE=no
AUTOSTART=no

# Sanity, make sure curl and jq are in our path...
BINS="jq curl"
for BIN in ${BINS}; do
	${BIN} >/dev/null 2>/dev/null
	if [ $? -eq 127 ]; then
		echo "Error: This script requires ${BIN} in the path. It could also signify that you don't have the tool installed."
		exit 1
	fi
done

# Load settings from config file if it exists
if [ -f ~/.plexupdate ]; then
	source ~/.plexupdate
fi

if [ "${RELEASE}" = "64-bit" ]; then
	echo "WARNING: RELEASE=64-bit is deprecated, use RELEASE=64 instead"
	RELEASE="64"
elif [ "${RELEASE}" = "32-bit" ]; then
	echo "WARNING: RELEASE=32-bit is deprecated, use RELEASE=32 instead"
	RELEASE="32"
elif [ "${RELEASE}" != "64" -a "${RELEASE}" != "32" ]; then
	echo "ERROR: Use of RELEASE=${RELEASE} will no longer work"
	exit 255
fi

# Current pages we need - Do not change unless Plex.tv changes again
URL_LOGIN=https://plex.tv/users/sign_in.json
URL_DOWNLOAD=https://plex.tv/downloads?channel=plexpass
URL_DOWNLOAD_PUBLIC=https://plex.tv/downloads

# Parse commandline
ALLARGS="$@"
set -- $(getopt aufhkro: -- "$@")
while true;
do
	case "$1" in
	(-h) echo -e "Usage: $(basename $0) [-afhkopsuU]\n\na = Auto install if download was successful (requires root)\nd = Auto delete after auto install\nf = Force download even if it's the same version or file already exists (WILL NOT OVERWRITE)\nh = This help\no = 32-bit version (default 64 bit)\np = Public Plex Media Server version\nu = Auto update plexupdate.sh before running it (experimental)\nU = Do not autoupdate plexupdate.sh (experimental, default)\ns = Auto start (needed for some distros)\n"; exit 0;;
	(-a) AUTOINSTALL=yes;;
	(-d) AUTODELETE=yes;;
	(-f) FORCE=yes;;
	(-o) RELEASE="32";;
	(-p) PUBLIC=yes;;
	(-u) AUTOUPDATE=yes;;
	(-U) AUTOUPDATE=no;;
	(-s) AUTOSTART=yes;;
	(-r) PRINT_URL=yes;;
	(--) ;;
	(-*) echo "Error: unrecognized option $1" 1>&2; exit 1;;
	(*)  break;;
	esac
	shift
done

if [ "${AUTOUPDATE}" == "yes" ]; then
	git >/dev/null 2>/dev/null
	if [ $? -eq 127 ]; then
		echo "Error: You need to have git installed for this to work"
		exit 1
	fi
	pushd "$(dirname "$0")" >/dev/null
	if [ ! -d .git ]; then
		echo "Error: This is not a git repository, auto update only works if you've done a git clone"
		exit 1
	fi
	git status | grep "git commit -a" >/dev/null 2>/dev/null
	if [ $? -eq 0 ]; then
		echo "Error: You have made changes to the script, cannot auto update"
		exit 1
	fi
	echo -n "Auto updating..."
	git pull >/dev/null
	if [ $? -ne 0 ]; then
		echo 'Error: Unable to update git, try running "git pull" manually to see what is wrong'
		exit 1
	fi
	echo "OK"
	popd >/dev/null
	if ! type "$0" 2>/dev/null >/dev/null ; then
		if [ -f "$0" ]; then
			/bin/bash "$0" ${ALLARGS} -U
		else
			echo "Error: Unable to relaunch, couldn't find $0"
			exit 1
		fi
	else
		"$0" ${ALLARGS} -U
	fi
	exit $?
fi

# Sanity check
if [ "${EMAIL}" == "" -o "${PASS}" == "" ] && [ "${PUBLIC}" == "no" ]; then
	echo "Error: Need username & password to download PlexPass version. Otherwise run with -p to download public version."
	exit 1
fi

if [ "${AUTOINSTALL}" == "yes" -o "${AUTOSTART}" == "yes" ]; then
	id | grep -i 'uid=0(' 2>&1 >/dev/null
	if [ $? -ne 0 ]; then
		echo "Error: You need to be root to use autoinstall/autostart option."
		exit 1
	fi
fi


# Remove any ~ or other oddness in the path we're given
DOWNLOADDIR="$(eval cd ${DOWNLOADDIR// /\\ } ; if [ $? -eq 0 ]; then pwd; fi)"
if [ -z "${DOWNLOADDIR}" ]; then
	echo "Error: Download directory does not exist or is not a directory"
	exit 1
fi

# Detect if we're running on redhat instead of ubuntu
if [ -f /etc/redhat-release ]; then
	REDHAT=yes;
	PKGEXT='.rpm'
	RELEASE="Fedora${RELEASE}"
else
	REDHAT=no;
	PKGEXT='.deb'
	RELEASE="Ubuntu${RELEASE}"
fi

# Fields we need to submit for login to work
#
# Field			Value
# user[login]		$EMAIL
# user[password]	$PASS
# authentication_token	<retreived from sign_in.json>

# Plex Pass account
if [ "${PUBLIC}" == "no" ]; then
	echo -n "Authenticating..."

	AUTH="user%5Blogin%5D=${EMAIL}&user%5Bpassword%5D=${PASS}"
	CURL_OPTS="-s -H X-Plex-Client-Identifier:plexupdate -H X-Plex-Product:plexupdate -H X-Plex-Version:0.0.1"
	# Authenticate and get X-Plex-Token
	TOKEN=$(curl ${CURL_OPTS} --data "${AUTH}" "${URL_LOGIN}" | jq -r .user.authentication_token)
	if [ $? -ne 0 -o "${TOKEN}" == "" -o "${TOKEN}" == "null" ]; then
		echo "Error: Unable to obtain authentication token, page changed?"
		exit 1
	fi

	# append TOKEN to CURL_OPTS
	CURL_OPTS="${CURL_OPTS} -H X-Plex-Token:${TOKEN}"
else
	# It's a public version, so change URL and make doubly sure that cookies are empty
	CURL_OPTS="-s"
	URL_DOWNLOAD=${URL_DOWNLOAD_PUBLIC}
fi

# Extract the URL for our release
echo -n "Finding download URL for ${RELEASE}..."


DOWNLOAD=$(curl ${CURL_OPTS} "${URL_DOWNLOAD}" | grep "${PKGEXT}" | grep -m 1 ${RELEASE} | sed "s/.*href=\"\([^\"]*\\${PKGEXT}\)\"[^>]*>.*/\1/" )

if [ "${DOWNLOAD}" == "" ]; then
	echo "Sorry, page layout must have changed, I'm unable to retrieve the URL needed for download"
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
	echo "Your OS reports the latest version of Plex ($INSTALLED_VERSION) is already installed. Use -f to force download."
	exit 5
fi

if [ -f "${DOWNLOADDIR}/${FILENAME}" -a "${FORCE}" != "yes" ]; then
	echo "File already exists, won't download."
	if [ "${AUTOINSTALL}" != "yes" ]; then
		exit 2
	fi
	SKIP_DOWNLOAD="yes"
fi

if [ "${SKIP_DOWNLOAD}" == "no" ]; then
	if [ -f "${DOWNLOADDIR}/${FILENAME}" ]; then
		echo "Note! File exists, but asked to overwrite with new copy"
	fi

	echo -ne "Downloading release \"${FILENAME}\"..."
	ERROR=$(curl "${DOWNLOAD}" -o "${DOWNLOADDIR}/${FILENAME}" 2>&1)
	CODE=$?
	if [ ${CODE} -ne 0 ]; then
		echo -e "\n  !! Download failed with code ${CODE}, \"${ERROR}\""
		exit ${CODE}
	fi
	echo "OK"
fi

if [ "${AUTOINSTALL}" == "yes" ]; then
	if [ "${REDHAT}" == "yes" ]; then
		sudo yum -y install "${DOWNLOADDIR}/${FILENAME}"
	else
		sudo dpkg -i "${DOWNLOADDIR}/${FILENAME}"
	fi
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
