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
EMAIL=my.email@plex-server.com
PASS="my-secret-plex-password"
DOWNLOADDIR=/a/folder/to/save/the/files/in
```

Obviously you need to change these three so they match your account information. And if you don't put anything as a `DOWNLOADDIR`, the tool will use the folder you're executing the script from. So take care.

## 3. advanced options

There are a few other options for the more enterprising user. Setting any of these to `yes` will enable the function.

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

Most of these options can be specified on the command-line as well, this is just a more convenient way of doing it if you're scripting it. Which brings us to...

## 4. command-line

I'm going to be lazy, just run the tool with `-h` and you'll find out what you can do. It will basically be a mirror of what section 3 just stated :-)

# running it

It's very simple, just execute the tool once configured. It will complain if you've forgotten to set it up. If you want to use the autoinstall (-a option or `AUTOINSTALL=YES` is set), you must run as root or use sudo when executing or plexupdate.sh will stop and give you an error.

Overall it tries to give you hints regarding why it isn't doing what you expected it to.

# known issues

- Command-line option handling needs cleanup
- Should extract the help text into a function instead

# trivia

- "kaka" is swedish for "cookie"

# TL;DR

Open a terminal or SSH on the server running Plex Media Center
```
wget https://raw.githubusercontent.com/mrworf/plexupdate/master/plexupdate.sh
chmod +x plexupdate.sh
echo -e > ~/.plexupdate 'EMAIL=<plex email account>\nPASS="<plex password>"'
nano -w ~/.plexupdate
sudo ./plexupdate.sh -a
```

# FAQ

## My password is rejected even though correct

If you use certain characters, such as dollar sign, in your password, bash will interpret that as a reference to a variable. To resolve this, enclose your password with single quotes instead of the normal quotes.

Ie, `PASS="MyP4$$w0rD"` will not work, but changing to it to `PASS='MyP4$$w0rD'` will
