#!/bin/bash

ORIGIN_REPO="https://github.com/mrworf/plexupdate"
OPT_PATH="/opt"
FULL_PATH="$OPT_PATH/plexupdate"
CONFIGFILE="/etc/plexupdate.conf"
CONFIGCRON="/etc/plexpass.cron.conf"

install() {
	echo "'$req' is required but not installed, attempting to install..."
	sleep 1

	if $UBUNTU; then
		DISTRO_INSTALL="apt install $1"
	elif $REDHAT; then
		if hash dnf 2>/dev/null; then
			DISTRO_INSTALL="dnf install $1"
		else
			DISTRO_INSTALL="yum install $1"
		fi
	fi

	if [ $EUID != 0 ]; then
		echo "You don't have permissions to continue, trying sudo instead..."
		sleep 1
		sudo $DISTRO_INSTALL
	else
		$DISTRO_INSTALL
	fi
}

yesno() {
	read -n 1 -p "[Y/n] " answer

	if [ "$answer" == "n" -o "$answer" == "N" ]; then
		echo
		return 1
	elif [ ! -z "$answer" ]; then
		echo
	fi

	return 0
}

noyes() {
	read -n 1 -p "[N/y] " answer

	if [ "$answer" == "y" -o "$answer" == "Y" ]; then
		echo
		return 1
	elif [ ! -z "$answer" ]; then
		echo
	fi

	return 0
}

abort() {
	echo "$@"
	exit 1
}

configure_plexupdate() {

	CONFIGTEMP=$(mktemp /tmp/plexupdate.tempconf.XXX)
	AUTOUPDATE=yes

	[ -f "$CONFIGFILE" ] && source "$CONFIGFILE"

	echo
	echo -n "Do you want to install the latest PlexPass releases? "
	if yesno; then
		PUBLIC=
		read -e -p "PlexPass Email Address: " -i "$EMAIL" EMAIL
		read -e -p "PlexPass Password: " -i "$PASS" PASS
	else
		EMAIL=
		PASS=
		PUBLIC=yes
	fi

	echo
	echo -n "Would you like to automatically install the latest release when it is downloaded? "
	if yesno; then
		AUTOINSTALL=yes
	else
		AUTOINSTALL=no
	fi

	if [ "$AUTOINSTALL" == "yes" ]; then
		echo
		echo -n "When using the auto-install option, would you like to check if the server is in use before upgrading? "
		if yesno; then
			if [ -z "$PLEXSERVER" ]; then
				PLEXSERVER="127.0.0.1"
			fi
			read -e -p "Plex Server IP/DNS name: " -i "$PLEXSERVER" PLEXSERVER
			if [ -z "$PLEXPORT" ]; then
				PLEXPORT=32400
			fi

			read -e -p "Plex Server Port: " -i "$PLEXPORT" PLEXPORT
		else
			PLEXSERVER=
			PLEXPORT=
		fi
	else
		PLEXSERVER=
		PLEXPORT=
	fi

	save_config "AUTOUPDATE EMAIL PASS PUBLIC AUTOINSTALL PLEXSERVER PLEXPORT" "$CONFIGFILE"
}

configure_cron() {
	echo
	echo -n "Would you like to set up automatic daily updates for Plex? "
	if yesno; then
		CONF="$CONFIGFILE"
		SCRIPT="${FULL_PATH}/plexupdate.sh"
		LOGGING=false

		echo
		echo -n "Do you want to log the daily update runs to syslog so you can examine the output later? "
		if yesno; then
			LOGGING=true
		fi

		save_config "CONF SCRIPT LOGGING" "/etc/plexupdate.cron.conf"

		echo
		echo -n "Installing daily cron job... "
		if [ $EUID -ne 0 ]; then
			sudo ln -sf ${FULL_PATH}/extras/cronwrapper /etc/cron.daily/plexupdate
		else
			ln -sf ${FULL_PATH}/extras/cronwrapper /etc/cron.daily/plexupdate
		fi
		echo "done"
	fi
}


save_config() {
	CONFIGTEMP=$(mktemp /tmp/plexupdate.XXX)
	for VAR in $1; do
		if [ ! -z ${!VAR} ]; then
			echo "${VAR}='${!VAR}'" >> $CONFIGTEMP
		fi
	done

	echo
	echo "Writing configuration file '$2'..."
	if [ $EUID -ne 0 ]; then
		# make sure that new file is owned by root instead of owner of CONFIGTEMP
		sudo tee "$2" > /dev/null < "$CONFIGTEMP"
		rm "$CONFIGTEMP"
	else
		mv "$CONFIGTEMP" "$2"
	fi
}

if [ -f /etc/redhat-release ]; then
	REDHAT=true
else
	UBUNTU=true
fi

for req in wget git; do
	if ! hash $req 2>/dev/null; then
		install $req
	fi
done

echo -e "\n"

read -e -p "Directory to install into: " -i "/opt/plexupdate" FULL_PATH
if [ ! -d "$FULL_PATH" ]; then
	echo -n "'$FULL_PATH' doesn't exist, attempting to create... "
	if ! mkdir -p "$FULL_PATH" 2>/dev/null; then
		echo "trying with sudo... "
		sudo mkdir -p "$FULL_PATH" || abort "failed, cannot continue"
		sudo chown $(whoami) "$FULL_PATH" || abort "failed, cannot continue"
	fi
	echo "done"
elif [ ! -w "$FULL_PATH" ]; then
	echo -n "'$FULL_PATH' exists, but you don't have permission to write to it. Changing owner with sudo... "
	sudo chown $(whoami) "$FULL_PATH" || abort "failed, cannot continue"
	echo "done"
fi

if [ -d "${FULL_PATH}/.git" ]; then
	cd "$FULL_PATH"
	if git remote -v | grep -q "mrworf/plexupdate"; then
		echo -n "Found existing plexupdate repository in '$FULL_PATH', updating... "
		git pull >/dev/null || abort "Unknown error while updating, please check '$FULL_PATH' and then try again."
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

configure_plexupdate
configure_cron
