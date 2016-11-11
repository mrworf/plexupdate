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
Note that unzip is required (`sudo apt-get install unzip`).

####Using git to clone (Recommended)
Using git is way easier and recommended, if you ask me. 
```
git clone https://github.com/mrworf/plexupdate.git
```
Note that git is required (`sudo apt-get install git`)

The main benefit with git clone is that you can update to latest version very easily. If you want to use the auto update feature, you must be using a git clone.

## 2. Setting it up

To quickly setup plexupdate.sh, you should run it the first time like below:

```
./plexupdate.sh --email='my.email@plex-server.com' --pass='my-secret-plex-password' --dldir='/a/folder/to/save/the/files/in' --saveconfig
```

Obviously you need to change these so they match your account information. And if you don't put anything as for the ```--dldir``` option, the tool will use the folder you're executing the script from. So take care.

## 3. Advanced options

You can point out a different file than ```.plexupdate``` by providing it as the argument to the ```--config``` option. Any options set by the config file can be overridden with command-line options.

There are also a few additional options for the more enterprising user. Setting any of these to `yes` will enable the function.

- CHECKUPDATE
  If set (and it is by default), it will compare your local copy with the one stored on github. If there is any difference, it will let you know. This is handy if you're not using ```git clone``` but want to be alerted to new versions.
- PLEXSERVER
  If set, and combined with AUTOINSTALL, the script will automatically check if the server is in-use and defer the update. Great for crontab users. PLEXSERVER should be set to the IP/DNS of your Plex Media Server, which typically is 127.0.0.1
- PLEXPORT
  Sets the port to use along with PLEXSERVER
- AUTOUPDATE
  Makes plexupdate.sh automatically update itself using git. Note! This will fail if git isn't available on the command line.
- AUTOINSTALL
  Automatically installs the newly downloaded version. Currently works for Debian based systems as well as rpm based distros. Will fail miserably if you're not root.
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

If you don't even want to know when something has been done, you can combine this with the -q option and you will only receive output in the event of an error. Everything else will just silently finish without producing any output.

### Command Line Options

Several new command line options are available. They can be specified in any order.

- ```--config <path/to/config/file>```
  Defines the location the script should look for the config file. 
- ```--email <Plex.tv email>```
  Email to sign in to Plex.tv
- ```--pass <Plex.tv password>```
  Password to sign in to Plex.tv
- ```--dldir <path/to/where/you/want/files/downloaded/to>```
  This is the folder that the files will be downloaded to.
- ```--server <Plex server address>```
  This is the address that Plex Media Server is on. Setting this will enable a check to see if users are on the server prior to the software being updated.
- ```--port <Plex server port>```
  This is the port that Plex Media Server uses.
- ```--saveconfig```
  Saves the configuration as it is currently. This will take whatever is in the config file, plus whatever is specified on the command line and will save the config file with that information. Any information in the config file that plexupdate.sh does not understand or use WILL BE LOST. 
	
### Logs

The script now outputs everything to a file (by default `/tmp/plexupdate.log`). This log ***MAY*** contain passwords, so if you post it online, ***USE CAUTION***.

To change the default log file, you can specify a new location:

```FILE_STDOUTLOG="<new/path/to/log>" ./plexupdate.sh <options>```

# Running it

It's very simple, just execute the tool once configured. It will complain if you've forgotten to set it up. If you want to use the autoinstall (-a option or `AUTOINSTALL=YES` is set), you must run as root or use sudo when executing or plexupdate.sh will stop and give you an error.

Overall it tries to give you hints regarding why it isn't doing what you expected it to.

# Trivia

- "kaka" is Swedish for "cookie"

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
