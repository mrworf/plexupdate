#!/bin/bash
#
# Plex Linux Server download tool v2.6.3
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
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
#
# All other return values not documented.
#
# Call program with -h for available options
#
# Enjoy!
#
# Version	Description
# ^^^^^^^	^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#  1.0		Initial version, was able to download from plexapp
#  2.0		Initial version supporting plex.tv
#  2.1		Updated to use options and error codes
#  2.2          Layout changed, so code also changed. Added better
#               resiliance to HTML changes and also better error handling
#  2.3          Now reads an optional config file to avoid having to
#               modify this script.
#  2.4          Added support for the public versions of PMS
#  2.5          Supports autoinstall if root and given the option
#  2.6		Support for redhat derived distributions
#  2.6.2	Merge download dir support and moved config sourcing
#		(per request)
#  2.6.3	Added detection for wget to avoid issues downloading
#
#################################################################
# Set these two to what you need, or create a .plexupdate file
# in your home directory with these two (avoids changing this)
# DOWNLOADDIR is the full directory path you would like the download to go, without trailing slash.
#
EMAIL=
PASS=
DOWNLOADDIR="."

#################################################################
# Don't change anything below this point
#

# Defaults
# (aka "Advanced" settings, can be overriden with config file)
RELEASE="64-bit"
KEEP=no
FORCE=no
PUBLIC=no
AUTOINSTALL=no

# Sanity, make sure wget is in our path...
wget >/dev/null 2>/dev/null
if [ $? -eq 127 ]; then
	echo "Error: This script requires wget in the path. It could also signify that you don't have the tool installed."
	exit 1
fi

# Load settings from config file if it exists
if [ -f ~/.plexupdate ]; then
	source ~/.plexupdate
fi

# Current pages we need - Do not change unless Plex.tv changea again
URL_LOGIN=https://plex.tv/users/sign_in
URL_DOWNLOAD=https://plex.tv/downloads?channel=plexpass
URL_DOWNLOAD_PUBLIC=https://plex.tv/downloads

# Parse commandline
set -- $(getopt fhko: -- "$@")
while true;
do
	case "$1" in
	(-h) echo -e "Usage: $(basename $0) [-afhkop]\n\na = Auto install if download was successful (requires root)\nf = Force download even if it exists (WILL NOT OVERWRITE)\nh = This help\nk = Reuse last authentication\no = 32-bit version (default 64 bit)\np = Public Plex Media Server version"; exit 0;;
	(-a) AUTOINSTALL=yes;;
	(-f) FORCE=yes;;
	(-k) KEEP=yes;;
	(-o) RELEASE="32-bit";;
	(-p) PUBLIC=yes;;
	(--) ;;
	(-*) echo "Error: unrecognized option $1" 1>&2; exit 1;;
	(*)  break;;
	esac
	shift
done

# Sanity check
if [ "${EMAIL}" == "" -o "${PASS}" == "" ] && [ "${PUBLIC}" == "no" ]; then
	echo "Error: Need username & password to download PlexPass version. Otherwise run with -p to download public version."
	exit 1
fi

if [ "${AUTOINSTALL}" == "yes" ]; then
	id | grep 'uid=0(' 2>&1 >/dev/null
	if [ $? -ne 0 ]; then
		echo "Error: You need to be root to use autoinstall option."
		exit 1
	fi
fi

# Detect if we're running on redhat instead of ubuntu
REDHAT=no;
PKGEXT='.deb'

if [ -f /etc/redhat-release ]; then
	REDHAT=yes;
	PKGEXT='.rpm'
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
	rm /tmp/kaka 2>/dev/null >/dev/null
	rm /tmp/postdata 2>/dev/null >/dev/null
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
	echo -n "Authenticating..."
	# Clean old session
	rm /tmp/kaka 2>/dev/null

	# Get initial seed we need to authenticate
	SEED=$(wget --save-cookies /tmp/kaka --keep-session-cookies ${URL_LOGIN} -O - 2>/dev/null | grep 'name="authenticity_token"' | sed 's/.*value=.\([^"]*\).*/\1/')
	if [ $? -ne 0 -o "${SEED}" == "" ]; then
		echo "Error: Unable to obtain authentication token, page changed?"
		exit 1
	fi

	# Build post data
	echo -ne  >/tmp/postdata  "$(keypair "utf8" "&#x2713;" )"
	echo -ne >>/tmp/postdata "&$(keypair "authenticity_token" "${SEED}" )"
	echo -ne >>/tmp/postdata "&$(keypair "user[login]" "${EMAIL}" )"
	echo -ne >>/tmp/postdata "&$(keypair "user[password]" "${PASS}" )"
	echo -ne >>/tmp/postdata "&$(keypair "user[remember_me]" "0" )"
	echo -ne >>/tmp/postdata "&$(keypair "commit" "Sign in" )"

	# Authenticate
	wget --load-cookies /tmp/kaka --save-cookies /tmp/kaka --keep-session-cookies "${URL_LOGIN}" --post-file=/tmp/postdata -O /dev/null 2>/dev/null
	RET=$?

	# Delete authentication data ... Bad idea to let that stick around
	rm /tmp/postdata

	# Provide some details to the end user
	if [ ${RET} -ne 0 ]; then
		echo "Error: Unable to authenticate"
		exit 1
	fi
	echo "OK"
else
	# It's a public version, so change URL and make doubly sure that cookies are empty
	rm 2>/dev/null >/dev/null /tmp/kaka
	touch /tmp/kaka
	URL_DOWNLOAD=${URL_DOWNLOAD_PUBLIC}
fi

# Extract the URL for our release
echo -n "Finding download URL for ${RELEASE}..."

DOWNLOAD=$(wget --load-cookies /tmp/kaka --save-cookies /tmp/kaka --keep-session-cookies "${URL_DOWNLOAD}" -O - 2>/dev/null | grep "${PKGEXT}" | grep -m 1 "${RELEASE}" | sed "s/.*href=\"\([^\"]*\\${PKGEXT}\)\"[^>]*>${RELEASE}.*/\1/" )
echo -e "OK"

if [ "${DOWNLOAD}" == "" ]; then
	echo "Sorry, page layout must have changed, I'm unable to retrieve the URL needed for download"
	exit 3
fi

FILENAME="$(basename 2>/dev/null ${DOWNLOAD})"
if [ $? -ne 0 ]; then
	echo "Failed to parse HTML, download cancelled."
	exit 3
fi

# Installed version detection (untested on Redhat)
if [ "${REDHAT}" != "yes" ]; then
	INSTALLED_VERSION=$(dpkg-query -s plexmediaserver 2>/dev/null | grep -Po 'Version: \K.*')
	if [ $FILENAME == *$INSTALLED_VERSION* ] && [ "${FORCE}" != "yes" ]; then
		echo "Your OS reports the latest version of Plex ($INSTALLED_VERSION) is already installed. Use -f to force download."
		exit 0
	fi
fi

if [ -f "${DOWNLOADDIR}/${FILENAME}" -a "${FORCE}" != "yes" ]; then
	echo "File already exists, won't download."
	exit 2
fi

echo -ne "Downloading release \"${FILENAME}\"..."
ERROR=$(wget --load-cookies /tmp/kaka --save-cookies /tmp/kaka --keep-session-cookies "${DOWNLOAD}" -O "${DOWNLOADDIR}/${FILENAME}" 2>&1)
CODE=$?
if [ ${CODE} -ne 0 ]; then
	echo -e "\n  !! Download failed with code ${CODE}, \"${ERROR}\""
	exit ${CODE}
fi
echo "OK"

if [ "${AUTOINSTALL}" == "yes" ]; then
	if [ "${REDHAT}" == "yes" ]; then
		rpm -i "${DOWNLOADDIR}/${FILENAME}"
	else
		dpkg -i "${DOWNLOADDIR}/${FILENAME}"
	fi
fi

exit 0
