![plexupdate.sh](http://i.imgur.com/ThY5Rvl.png "plexupdate")
# plexupdate

Plex Update is a BASH script which simplifies the life of headless Linux Plex Media Server users (how's that for a strange description).

This tool will automatically download the latest version for linux (Using plexpass or public version) and if you **kindly ask**, also install it for you.

# Installation

It's fairly easy, but let's take it step by step (if it seems too much, skip to the end for a short version)

## 1. Getting the code

####Using wget and unzip

Download it as a [zip file](https://github.com/mrworf/plexupdate/archive/master.zip) and unzip it on your server.
```
wget https://github.com/mrworf/plexupdate/archive/master.zip && unzip master.zip && mv plexupdate-master plexupdate && rm master.zip
```
Note that unzip is requered (`sudo apt-get install unzip`).

####Using git to clone (Recommended)
Using git is way easier and recommended, if you ask me. 
```
git clone https://github.com/mrworf/plexupdate.git
```
Note that git is requered (`sudo apt-get install git-all`)

The main benefit with git clone is that you can update to latest version very easily. If you want to use the auto update feature, you must be using a git clone.

## 2. Setting it up

plexupdate.sh looks for a file named `.plexupdate` located in your home directory. Please note that I'm referring to the home directory of the user who is running the plexupdate.sh ... If that user is someone else (root for instance) you'll need to make sure that user has the config file set up properly as well.

The contents of this file are usually:

```
EMAIL="my.email@plex-server.com"
PASS="my-secret-plex-password"
DOWNLOADDIR="/a/folder/to/save/the/files/in"
```

Obviously you need to change these so they match your account information. And if you don't put anything as a `DOWNLOADDIR`, the tool will use the folder you're executing the script from. So take care.

## 3. Advanced options

You can point out a different file than ```.plexupdate``` by providing it as the last argument to the script. It HAS to be the LAST argument, or it will be ignored. Any options set by the config file can be overriden with command-line options.

There are also a few additional options for the more enterprising user. Setting any of these to `yes` will enable the function.

- PLEXSERVER
  If set, and combined with AUTOINSTALL, the script will automatically check if the server is in-use and deferr the update. Great for crontab users. PLEXSERVER should be set to the IP/DNS of your Plex Media Server, which typically is 127.0.0.1
- AUTOUPDATE
  Makes plexupdate.sh automatically update itself using git. Note! This will fail if git isn't available on the command line.
- AUTOINSTALL
  Automatically installs the newly downloaded version. Currently works for debian based systems as well as rpm based distros. Will fail miserably if you're not root.
- AUTODELETE 
  Once successfully downloaded and installed, it will delete the package (want not, waste not? ;-))
- PUBLIC 
  The default behavior of plexupdate.sh is to download the PlexPass edition of Plex Media Center. Setting this option to `yes` will make it download the public version instead. If this is yes, then `EMAIL` and `PASS` is no longer needed.
- FORCE 
  Normally plexupdate.sh will avoid downloading a file it already has or if it's the same as the installed version. Using this option will force it to download again UNLESS the file already downloaded has the correct checksum. If you have AUTOINSTALL set, plexupdate.sh will then reinstall it.
- FORCEALL
  Using this option will force plexupdate.sh to override the checksum check and will download the file again, and if you have AUTOINSTALL set, will reinstall it.
- PRINT_URL
  Authenticate, fetch the download URL, print it, and then exit.
- DISTRO_INSTALL
  The command used to install packages, only change if you need special options. Natively supports Debian and Redhat, so you don't need to set this for these systems.
  NOTE! If you define this, you MUST define DISTRO and BUILD
- DISTRO and BUILD
  Override which version to download, use -l option to see what you can select.

Most of these options can be specified on the command-line as well, this is just a more convenient way of doing it if you're scripting it. Which brings us to...

### Using it from CRON

If you want to use plexupdate as either a cron job or as a [systemd job](https://github.com/mrworf/plexupdate/wiki/Running-plexupdate-daily-as-a-systemd-timer), the -c option should do what you want. All non-error exit codes will be set to 0 and no output will be printed to stdout unless something has actually been done. (a new version was downloaded, installed, etc)

If you don't even want to know when something has been done, you can combine this with the -q option and you will only receive output in the event of an error. Everything else will just silenty finish without producing any output.

# Running it

It's very simple, just execute the tool once configured. It will complain if you've forgotten to set it up. If you want to use the autoinstall (-a option or `AUTOINSTALL=YES` is set), you must run as root or use sudo when executing or plexupdate.sh will stop and give you an error.

Overall it tries to give you hints regarding why it isn't doing what you expected it to.

# Trivia

- "kaka" is swedish for "cookie"

# TL;DR
Open a terminal or SSH on the server running Plex Media Center
## First install
```
git clone https://github.com/mrworf/plexupdate.git
sudo plexupdate/plexupdate.sh -p -a
```
## Updating Plex and the script
```
sudo plexupdate/plexupdate.sh -p -u -a
```

# FAQ

## What username and password are you talking about

The username and password for http://plex.tv 

## My password is rejected even though correct

If you use certain characters (such as `$`) in your password, bash will interpret that as a reference to a variable. To resolve this, enclose your password within single quotes (`'`) instead of the normal quotes (`"`).

i.e. `PASS="MyP4$$w0rD"` will not work, but changing to it to `PASS='MyP4$$w0rD'` will
