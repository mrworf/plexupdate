![plexupdate.sh](http://i.imgur.com/ThY5Rvl.png "plexupdate")
# plexupdate

Plex Update is a bash script which helps you keep Plex Media Server up to date on Linux.

plexupdate will automatically download the latest version of Plex Media Server for Linux and, optionally, also install it for you.

### What happened to `.plexupdate` ?

It has gone away to keep things simpler and more secure. You can either provide the config you want using the `--config` parameter or place it in `/etc/plexupdate.conf`.

# Installation

In the old days, this used to be a bit of a chore. But no more!

```
bash -c "$(wget -O - https://raw.githubusercontent.com/mrworf/plexupdate/master/extras/installer.sh)"
```

will automatically install the tool as well as any dependencies. This has been tested on Ubuntu, Fedora and CentOS but should, for the most part, work on any modern Linux distribution.

If you'd ever like to change your configuration, you can just re-run this from the extras folder inside your plexupdate directory. (`/opt/plexupdate/extras/installer.sh` by default)

If you have any trouble with the installer, or would just prefer to set plexupdate up manually, read on.

## 1. Getting the code

####Using git to clone (recommended)
```
git clone https://github.com/mrworf/plexupdate.git
```
Note that git is required (`sudo apt-get install git`)

This is the recommended way to install plexupdate. Using git allows you to know when a new version is available as well allowing plexupdate to keep itself up to date (with the AUTOUPDATE option).

####Using wget and unzip

Download it as a [zip file](https://github.com/mrworf/plexupdate/archive/master.zip) and unzip it on your server.
```
wget https://github.com/mrworf/plexupdate/archive/master.zip && unzip master.zip && mv plexupdate-master plexupdate && rm master.zip
```
Note that unzip is required (`sudo apt-get install unzip`).

## 2. Setting it up

In order to use `plexupdate.sh`, it's recommended you create a configuration file.

```
sudo nano -w /etc/plexupdate.conf
```

In the newly opened editor, insert the following (and make *sure* to change email and password)

```
EMAIL='john.doe@void.com'
PASS='verySecretPassword'
DOWNLOADDIR='/tmp/'
```

This will make `plexupdate.sh` login and download the latest version and save it to /tmp/ folder.

If you don't have PlexPass, you can still use `plexupdate.sh`, just set `PUBLIC=yes` instead. The section above becomes

```
PUBLIC=yes
DOWNLOADDIR='/tmp/'
```

## 3. Cronjob

You might be more interested in running this on a regular basis. To accomplish this, we need to do the following. Locate the `extras` folder which was included with plexupdate. In this folder you'll find `cronwrapper`. You need to "symlink" this into `/etc/cron.daily/`. Symlink means we tell the system that there should be reference/link to the file included in plexupdate. By not copying, we will automatically get updates to the `cronwrapper` when we update plexupdate.

When doing the symlink, it's important to provide the complete path to the file in question, so you will need to edit the path to it in the following snippet. Also, we need to run as root, since only root is allowed to edit files under `/etc`.

```
sudo ln -s /home/john/plexupdate/extras/cronwrapper /etc/cron.daily/plexupdate
```

We also need to tell cronwrapper where to find plexupdate, again, this needs to be done as root for the same reasons as above.

```
sudo nano -w /etc/plexupdate.cron.conf
```

In the new file, we simply point out the location of `plexupdate.sh` and `plexupdate.conf`

```
SCRIPT=/home/john/plexupdate/plexupdate.sh
CONF=/home/john/plexupdate.conf
```

If you've installed it somewhere else and/or the path to the config is somewhere else, please *make sure* to write the correct paths.

Almost done. Final step is to make `plexupdate.sh` a bit smarter and have it install the newly downloaded version, so open the `plexupdate.conf` file you created previously and add the following:

```
AUTOINSTALL=yes
AUTODELETE=yes
```

This tells `plexupdate.sh` to install the file once downloaded and delete it when done, keeping your server nice and clean.

## 4. Advanced options

There are also a few additional options for the more enterprising user. Setting any of these to `yes` will enable the function.

- CHECKUPDATE
  If set (and it is by default), it will compare your local copy with the one stored on github. If there is any difference, it will let you know. This is handy if you're not using `git clone` but want to be alerted to new versions.
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
  The default behavior of plexupdate.sh is to download the PlexPass edition of Plex Media Server. Setting this option to `yes` will make it download the public version instead. If this is yes, then `EMAIL` and `PASS` is no longer needed.
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

### Command Line Options

Plexupdate comes with many command line options. For the most up-to-date list, I'd recommend you run plexupdate.sh with -h

But here are some of the more useful ones:

- `--config <path/to/config/file>`
  Defines the location the script should look for the config file.
- `--email <Plex.tv email>`
  Email to sign in to Plex.tv
- `--pass <Plex.tv password>`
  Password to sign in to Plex.tv
- `--dldir <path/to/where/you/want/files/downloaded/to>`
  This is the folder that the files will be downloaded to.
- `--server <Plex server address>`
  This is the address that Plex Media Server is on. Setting this will enable a check to see if users are on the server prior to the software being updated.
- `--port <Plex server port>`
  This is the port that Plex Media Server uses.

# Trivia

- "kaka" is Swedish for "cookie"

# FAQ

## Where is `.plexupdate`

See explanation in the top of this document.

## What email and password are you talking about

The email and password for http://plex.tv

## My password is rejected even though correct

If you use certain characters (such as `$`) in your password, bash will interpret that as a reference to a variable. To resolve this, enclose your password within single quotes (`'`) instead of the normal quotes (`"`).

i.e. `PASS="MyP4$$w0rD"` will not work, but changing to it to `PASS='MyP4$$w0rD'` will

If it's still not working, run `plexupdate.sh` with `-v` which prints out the email and password used to login which might help you understand what the problem is.
