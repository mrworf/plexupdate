# plexupdate

Plex Update is a BASH script which simplifies the life of headless Linux Plex Media Server users (how's that for a strange description).

This tool will automatically download the latest version for linux (be it plexpass or public version) and if you ask it to, install it for you.

# installation

It's fairly easy, but let's take it step by step (if it seems too much, skip to the end for a short version)

## 1. getting the code

You can either just download it as a [zip file](https://github.com/mrworf/plexupdate/archive/master.zip) and unzip it on your server, or you can use git to clone it ( git clone https://github.com/mrworf/plexupdate.git ). The main benefit with git clone is that you can update to latest version very easily. 

## 2. setting it up

plexupdate.sh looks for a file named `.plexupdate` located in your home directory. Please note that I'm referring to the home directory of the user who is running the plexupdate.sh ... If that user is someone else (root for instance) you'll need to make sure that user has the config file set up properly as well.

The contents of this file usually is

```
EMAIL="my.email@plex-server.com"
PASS="my-secret-plex-password"
DOWNLOADDIR="/a/folder/to/save/the/files/in"
```

Obviously you need to change these three so they match your account information. And if you don't put anything as a `DOWNLOADDIR`, the tool will use the folder you're executing the script from. So take care.

## 3. advanced options

You can point out a different file than ```.plexupdate``` by providing it as the last argument to the script. It HAS to be the LAST argument, or it will be ignored. Any options set by the config file can be overriden with commandline options.

There are also a few additional options for the more enterprising user. Setting any of these to `yes` will enable the function.

- PLEXSERVER
  If set, and combined with AUTOINSTALL, the script will automatically check if server is in-use and deferr the update. Great for crontab users. PLEXSERVER should be set to the IP/DNS of your Plex Media Server, which typically is 127.0.0.1
- AUTOUPDATE
  Makes plexupdate.sh automatically update itself using git. Note! This will fail if git isn't available on the command line.
- AUTOINSTALL
  Automatically installs the newly downloaded version. Currently works for debian based systems as well as rpm based distros. Will fail miserably if you're not root.
- AUTODELETE 
  Once successfully downloaded and installed, it will delete the package (want not, waste not? ;-))
- PUBLIC 
  The default behavior of plexupdate.sh is to download the PlexPass edition of Plex Media Center. Setting this option to `yes` will make it download the public version instead. If this is yes, then `EMAIL` and `PASS` is no longer needed.
- FORCE 
  Normally plexupdate.sh will avoid downloading a file it already has or if it's the same as the installed version, but this allows you to override.
- PRINT_URL
  Authenticate, fetch the download URL, print it, and then exit.
- DISTRO_INSTALL
  The commandline used to install packages, only change if you need special options. Natively supports Debian and Redhat, so need to set this for these systems.
  NOTE! If you define this, you MUST define DISTRO and BUILD
- DISTRO and BUILD
  Override which version to download, use -l option to see what you can select.
- TELEGRAM_NOTIFY
  Enable Telegram notification support. Requires TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
- TELEGRAM_BOT_TOKEN
  After talking to BotFather and creating a new bot, you can acquire the Bot Token required for the Telegram API.
- TELEGRAM_CHAT_ID
  Ask myidbot for your chat ID, or your group's chat ID, required for the Telegram API.
- TELEGRAM_DEBUG
  Output API messages for debugging. 

Most of these options can be specified on the command-line as well, this is just a more convenient way of doing it if you're scripting it. Which brings us to...

### Using it from CRON

It seems quite popular to run this via crontab, which is fine. But the behavior of the script has been somewhat, shall we say, annoying.

Starting today, the ```-C``` option is deprecated and will give an error to check the docs. The new version is ```-c``` and will make sure that only fatal errors are reported back via the exit code. No more 2, 3, 4 or 5 exitcodes. They are converted into 0. Combining this option with ```-q``` will hide any and all non-essential output from the script as well. Only error messages are emitted, so if it fails, you'll know why.

## 4. command-line

I'm going to be lazy, just run the tool with `-h` and you'll find out what you can do. It will basically be a mirror of what section 3 just stated :-)

# running it

It's very simple, just execute the tool once configured. It will complain if you've forgotten to set it up. If you want to use the autoinstall (-a option or `AUTOINSTALL=YES` is set), you must run as root or use sudo when executing or plexupdate.sh will stop and give you an error.

Overall it tries to give you hints regarding why it isn't doing what you expected it to.

# trivia

- "kaka" is swedish for "cookie"

# TL;DR

Open a terminal or SSH on the server running Plex Media Center
```
wget https://raw.githubusercontent.com/mrworf/plexupdate/master/plexupdate.sh
chmod +x plexupdate.sh
echo -e > ~/.plexupdate 'EMAIL="<plex email account>"\nPASS="<plex password>"'
nano -w ~/.plexupdate
sudo ./plexupdate.sh -a
```

# FAQ

## What username and password are you talking about

The username and password for http://plex.tv 

## My password is rejected even though correct

If you use certain characters, such as dollar sign, in your password, bash will interpret that as a reference to a variable. To resolve this, enclose your password with single quotes instead of the normal quotes.

Ie, `PASS="MyP4$$w0rD"` will not work, but changing to it to `PASS='MyP4$$w0rD'` will
