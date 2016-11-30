#!/bin/bash

ORIGIN_REPO="https://github.com/demonbane/plexupdate" #FIXME
OPT_PATH="/opt"
FULL_PATH="$OPT_PATH/plexupdate"
CONFIGFILE="/etc/plexupdate.conf"
CONFIGCRON="/etc/plexupdate.cron.conf"
CRONWRAPPER="/etc/cron.daily/plexupdate"

# default options
AUTOINSTALL=yes
AUTOUPDATE=yes
PUBLIC=

install() {
	echo "'$req' is required but not installed, attempting to install..."
	sleep 1

	[ -z "$DISTRO_INSTALL" ] && check_distro

	if [ $EUID -ne 0 ]; then
		sudo $DISTRO_INSTALL $1
	else
		$DISTRO_INSTALL $1
	fi
}

check_distro() {
	if [ -f /etc/redhat-release ] && hash dnf 2>/dev/null; then
		DISTRO="redhat"
		DISTRO_INSTALL="dnf -y install"
	elif [ -f /etc/redhat-release ] && hash yum 2>/dev/null; then
		DISTRO="redhat" #or CentOS but functionally the same
		DISTRO_INSTALL="yum -y install"
	elif hash apt 2>/dev/null; then
		DISTRO="debian" #or Ubuntu
		DISTRO_INSTALL="apt install"
	elif hash apt-get 2>/dev/null; then
		DISTRO="debian"
		DISTRO_INSTALL="apt-get install"
	else
		DISTRO="unknown"
	fi
}

yesno() {
	case "$1" in
		"")
			default="Y"
			;;
		yes)
			default="Y"
			;;
		true)
			default="Y"
			;;
		no)
			default="N"
			;;
		false)
			default="N"
			;;
		*)
			default="$1"
			;;
	esac

	default="$(tr "[:lower:]" "[:upper:]" <<< "$default")"
	if [ "$default" == "Y" ]; then
		prompt="[Y/n] "
	else
		prompt="[N/y] "
	fi

	while true; do
		read -n 1 -p "$prompt" answer
		answer=${answer:-$default}
		answer="$(tr "[:lower:]" "[:upper:]" <<< "$answer")"

		if [ "$answer" == "Y" ]; then
			echo
			return 0
		elif [ "$answer" == "N" ]; then
			echo
			return 1
		fi
	done
}

noyes() {
	yesno N
}

abort() {
	echo "$@"
	exit 1
}

install_plexupdate() {
	echo
	read -e -p "Directory to install into: " -i "/opt/plexupdate" FULL_PATH

	while [[ "$FULL_PATH" == *"~"* ]]; do
		echo "Using '~' in your path can cause problems, please type out the full path instead"
		echo
		read -e -p "Directory to install into: " -i "/opt/plexupdate" FULL_PATH
	done

	if [ ! -d "$FULL_PATH" ]; then
		echo -n "'$FULL_PATH' doesn't exist, attempting to create... "
		if ! mkdir -p "$FULL_PATH" 2>/dev/null; then
			sudo mkdir -p "$FULL_PATH" || abort "failed, cannot continue"
			sudo chown $(id -un):$(id -gn) "$FULL_PATH" || abort "failed, cannot continue"
		fi
		echo "done"
	elif [ ! -w "$FULL_PATH" ]; then
		echo -n "'$FULL_PATH' exists, but you don't have permission to write to it. Changing owner... "
		sudo chown $(id -un):$(id -gn) "$FULL_PATH" || abort "failed, cannot continue"
		echo "done"
	fi

	if [ -d "${FULL_PATH}/.git" ]; then
		cd "$FULL_PATH"
		if git remote -v 2>/dev/null | grep -q "plexupdate"; then
			echo -n "Found existing plexupdate repository in '$FULL_PATH', updating... "
			git pull &>/dev/null || abort "Unknown error while updating, please check '$FULL_PATH' and then try again."
			echo
		else
			abort "'$FULL_PATH' appears to contain a different git repository, cannot continue"
		fi
		echo "done"
		cd - &> /dev/null
	else
		echo -n "Installing plexupdate into '$FULL_PATH'... "
		git clone "$ORIGIN_REPO" "$FULL_PATH" &> /dev/null || abort "install failed, cannot continue"
		echo "done"
		# FIXME These 3 lines are just to allow us to test easily while we're still using this branch. Remember to take this out before merging to master.
		cd "$FULL_PATH"
		git checkout reworklog > /dev/null
		cd - &> /dev/null
	fi
}

configure_plexupdate() {

	[ -f "$CONFIGFILE" ] && source "$CONFIGFILE"

	echo
	echo -n "Do you want to install the latest PlexPass releases? "
	# The answer to this question and the value of PUBLIC are basically inverted
	if [ "$PUBLIC" == "yes" ]; then
		default=N
	fi
	if yesno $default; then
		PUBLIC=
		while true; do
			read -e -p "PlexPass Email Address: " -i "$EMAIL" EMAIL
			if [ -z "${EMAIL}" ] || [[ "$EMAIL" == *"@"* ]] && [[ "$EMAIL" != *"@"*"."* ]]; then
				echo "Please provide a valid email address"
			else
				break
			fi
		done
		while true; do
			read -e -p "PlexPass Password: " -i "$PASS" PASS
			if [ -z "$PASS" ]; then
				echo "Please provide a password"
			else
				break
			fi
		done
	else
		# don't forget to erase old settings if they changed their answer
		EMAIL=
		PASS=
		PUBLIC=yes
	fi

	echo
	echo -n "Would you like to automatically install the latest release when it is downloaded? "

	if yesno "$AUTOINSTALL"; then
		AUTOINSTALL=yes

		[ -z "$DISTRO" ] && check_distro
		if [ "$DISTRO" == "redhat" ]; then
			AUTOSTART=yes
		else
			AUTOSTART=
		fi

		echo
		echo -n "When using the auto-install option, would you like to check if the server is in use before upgrading? "
		#We can't tell if they previously selected no or if this is their first run, so we have to assume Yes
		if yesno; then
			if [ -z "$PLEXSERVER" ]; then
				PLEXSERVER="127.0.0.1"
			fi
			while true; do
				read -e -p "Plex Server IP/DNS name: " -i "$PLEXSERVER" PLEXSERVER
				if ! ping -c 1 -w 1 "$PLEXSERVER" &>/dev/null ; then
					echo -n "Server $PLEXSERVER isn't responding, are you sure you entered it correctly? "
					if yesno N; then
						break
					fi
				else
					break
				fi
			done
			if [ -z "$PLEXPORT" ]; then
				PLEXPORT=32400
			fi
			while true; do
				read -e -p "Plex Server Port: " -i "$PLEXPORT" PLEXPORT
				if ! [[ "$PLEXPORT" =~ ^[1-9][0-9]*$ ]]; then
					echo "Port $PLEXPORT isn't valid, please try again"
					PLEXPORT=32400
				else
					break
				fi
			done
		else
			PLEXSERVER=
			PLEXPORT=
		fi
	else
		AUTOINSTALL=no
		PLEXSERVER=
		PLEXPORT=
	fi

	save_config "AUTOINSTALL AUTODELETE DOWNLOADDIR EMAIL PASS FORCE FORCEALL PUBLIC AUTOSTART AUTOUPDATE PLEXSERVER PLEXPORT CHECKUPDATE" "$CONFIGFILE"
}

configure_cron() {
	if [ ! -d "$(dirname "$CRONWRAPPER")" ]; then
		echo "Seems like you don't have a supported cron job setup, please see README.md for more details."
		return 1
	fi

	[ -f "$CONFIGCRON" ] && source "$CONFIGCRON"

	echo
	echo -n "Would you like to set up automatic daily updates for Plex? "
	if yesno $CRON; then
		CONF="$CONFIGFILE"
		SCRIPT="${FULL_PATH}/plexupdate.sh"
		LOGGING=${LOGGING:-false}

		echo
		echo -n "Do you want to log the daily update runs to syslog so you can examine the output later? "
		if yesno $LOGGING; then
			LOGGING=true
		fi

		save_config "CONF SCRIPT LOGGING" "/etc/plexupdate.cron.conf"

		echo
		echo -n "Installing daily cron job... "
		if [ $EUID -ne 0 ]; then
			sudo chown root:root "${FULL_PATH}/extras/cronwrapper"
			sudo ln -sf "${FULL_PATH}/extras/cronwrapper" "$CRONWRAPPER"
		else
			chown root:root "${FULL_PATH}/extras/cronwrapper"
			ln -sf "${FULL_PATH}/extras/cronwrapper" "$CRONWRAPPER"
		fi
		echo "done"
	elif [ -f "$CRONWRAPPER" -o -f "$CONFIGCRON" ]; then
		echo
		echo -n "Cleaning up old cron configuration... "
		if [ -f "$CRONWRAPPER" ]; then
			sudo rm "$CRONWRAPPER" || echo "Failed to remove old cron script, please check '$CRONWRAPPER'"
		fi
		if [ -f "$CONFIGCRON" ]; then
			sudo rm "$CONFIGCRON" || echo "Failed to remove old cron configuration, please check '$CONFIGCRON'"
		fi
		echo done
	fi
}

save_config() {
	CONFIGTEMP=$(mktemp /tmp/plexupdate.XXX)
	for VAR in $1; do
		if [ ! -z "${!VAR}" ]; then
			echo "${VAR}='${!VAR}'" >> $CONFIGTEMP
		fi
	done

	echo
	echo -n "Writing configuration file '$2'... "
	if [ $EUID -ne 0 ]; then
		# make sure that new file is owned by root instead of owner of CONFIGTEMP
		sudo tee "$2" > /dev/null < "$CONFIGTEMP"
		rm "$CONFIGTEMP"
	else
		mv "$CONFIGTEMP" "$2"
	fi
	echo "done"
}

if [ $EUID -ne 0 ]; then
	echo
	echo "This script needs to install files in system locations and will ask for sudo/root permissions now"
	sudo -v || abort "Root permissions are required for setup, cannot continue"
elif [ ! -z "$SUDO_USER" ]; then
	echo
	abort "This script will ask for sudo as necessary, but you should not run it as sudo. Please try again."
fi

for req in wget git; do
	if ! hash $req 2>/dev/null; then
		install $req
	fi
done

if [ -f ~/.plexupdate ]; then
	echo
	echo -n "Existing configuration found in ~/.plexupdate, would you like to import these settings? "
	if yesno; then
		echo "Backing up old configuration as ~/.plexupdate.old. All new settings should be modified through this script, or by editing ${CONFIGFILE} directly. Please see README.md for more details."
		source ~/.plexupdate
		mv ~/.plexupdate ~/.plexupdate.old
	fi
fi

if [ -f "$(dirname "$0")/../plexupdate.sh" -a -d "$(dirname "$0")/../.git" ]; then
	FULL_PATH="$(readlink -f "$(dirname "$0")/../")"
	echo
	echo "Found plexupdate.sh in '$FULL_PATH', using that as your install path"
else
	install_plexupdate
fi



configure_plexupdate
configure_cron

echo
echo -n "Configuration complete. Would you like to run plexupdate with these settings now? "
if yesno; then
	if [ "$AUTOINSTALL" == "yes" -a $EUID -ne 0 ]; then
		sudo "$FULL_PATH/plexupdate.sh" -P --config "$CONFIGFILE"
	else
		"$FULL_PATH/plexupdate.sh" -P --config "$CONFIGFILE"
	fi
fi
