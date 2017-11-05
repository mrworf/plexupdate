![plexupdate.sh](http://i.imgur.com/ThY5Rvl.png "plexupdate")
# plexupdate

Plex Update is a bash script which helps you keep Plex Media Server up to date on Linux.

You can schedule updates to run daily and install Plex Pass beta releases if you have a Plex Pass membership.

# Installation

In the old days, this used to be a bit of a chore. But no more!

```
bash -c "$(wget -qO - https://raw.githubusercontent.com/mrworf/plexupdate/master/extras/installer.sh)"
```

will automatically install the tool as well as any dependencies. This has been tested on Ubuntu, Fedora and CentOS but should, for the most part, work on any modern Linux distribution.

If you'd ever like to change your configuration, just re-run the installer from the extras folder inside your plexupdate directory. (`/opt/plexupdate/extras/installer.sh` by default)

If you have any trouble with the installer, or would just prefer to set plexupdate up manually, [read the guide](https://github.com/mrworf/plexupdate/wiki/Manually-installing-plexupdate).

# Advanced options

There are a few additional options for the more enterprising user. Setting any of these to `yes` will enable the function.

- `CHECKUPDATE`
  If you didn't install using `git clone` or by running the installer, you can use this option to notify you when there are updates to plexupdate. If you used git or the installer, see `AUTOUPDATE` instead.
- `PLEXSERVER`
  If set, and combined with `AUTOINSTALL`, the script will automatically check if the server is in use and defer the update. Great for crontab users. `PLEXSERVER` should be set to the IP/DNS of your Plex Media Server, which typically is 127.0.0.1
- `PLEXPORT`
  Sets the port to use along with `PLEXSERVER`
- `AUTOUPDATE`
  Makes plexupdate.sh automatically update itself using git. This only works if you installed using `git clone` or by using the installer.
- `AUTOINSTALL`
  Automatically installs the newly downloaded version. Currently works for Debian based systems as well as rpm based distros. Requires root permissions.
- `AUTODELETE`
  Delete the downloaded package after installation is complete to conserve disk space.
- `PUBLIC`
  The default behavior of plexupdate.sh is to download the PlexPass edition of Plex Media Server. Setting this option to `yes` will make it download the public version instead.
- `FORCE`
  Normally plexupdate.sh will avoid downloading a file it already has or if it's the same as the installed version. Using this option will force it to download again UNLESS the file already downloaded has the correct checksum. If you have AUTOINSTALL set, plexupdate.sh will then reinstall it.
- `PRINT_URL`
  Authenticate, fetch the download URL, print it, and then exit.
- `DISTRO_INSTALL`
  The command used to install packages, only change if you need special options. Natively supports Debian and Redhat, so you don't need to set this for these systems.
  NOTE! If you define this, you MUST define `DISTRO` and `BUILD`
- `DISTRO` and `BUILD`
  Override which version to download, use -l option to see what you can select.
- `TOKEN`
  If you want to install Plex Pass releases, plexupdate will try to get your account token directly from your Plex Media Server. If you want to use a different token to authenticate, you can enter it here instead. Please read [Authenticating with Plex Pass](https://github.com/mrworf/plexupdate/wiki/Authenticating-with-Plex-Pass) on the wiki for more details.
- `SYSTEMDUNIT`
  If set, plexupdate.sh will use a custom systemd unit during `AUTOSTART`, which may be necessary when you are using a custom NAS package. The default is `plexmediaserver.service`.

Most of these options can be specified on the command-line as well, this is just a more convenient way of doing it if you're scripting it. Which brings us to...

## Command Line Options

Plexupdate comes with many command line options. For the most up-to-date list, run plexupdate.sh with -h

Here are some of the more useful ones:

- `--config <path/to/config/file>`
  Defines the location the script should look for the config file.
- `--dldir <path/to/where/you/want/files/downloaded/to>`
  This is the folder that the files will be downloaded to.
- `--server <Plex server address>`
  This is the address that Plex Media Server is on. Setting this will enable a check to see if users are on the server prior to the software being updated.
- `--port <Plex server port>`
  This is the port that Plex Media Server uses.

# FAQ

## Do I have to use the `extras/installer.sh`?

Of course not, anything you find under `extras/` is optional and only provided as an easier way to get `plexupdate.sh` up and running quickly. Read the guide for [installing plexupdate manually](https://github.com/mrworf/plexupdate/wiki/Manually-installing-plexupdate).

## Why am I getting a warning about email and password being deprecated?

Since just storing your password in plexupdate.conf isn't secure, plexupdate will now use a "token" instead. To make this warning go away just re-run the installer (`extras/installer.sh`) or manually remove `EMAIL` and `PASS` from your plexupdate.conf. For more details, see [this wiki article](https://github.com/mrworf/plexupdate/wiki/Authenticating-with-Plex-Pass).

# Need more information?

See https://github.com/mrworf/plexupdate/wiki for more information
