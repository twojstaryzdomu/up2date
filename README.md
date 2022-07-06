# up2date
Maintain an up-to-date set of configuration files in tar archives.

Keep an accurate copy of your configuraion files in a safe tarball and 
update the archives easily as needed.

## How to run
0. Copy the script to a directory under a PATH for convenience.

1. Create a tar archive with a set of files with an absolute path, e.g.:
```
# tar -C / -czvf archive.tar.gz /yourfile
```

2. Modify a file in the file system, e.g.:
```
# touch /yourfile
```

## Report mode
Report the status of archived files without modifying the archive, e.g.:
```
# up2date.ksh archive.tar.gz
archive.tar.gz: /yourfile (1) more recent than archived file (0)
```

## Update mode
Update the archive with the modified file from the file systemd, e.g.:
```
# MODE=update update.ksh archive.tar.gz
archive.tar.gz: more recent files in file system, compressing
```

The old file in the archive isn't being preserved by appending the new file
to the archive. The archive is re-created with the new file(s), discarding
the old contents of the modifed file(s).

## Multiple archives
It is possible to run up2date against a directory where archives are
stored, e.g.:
```
# up2date.ksh .
```
When run this way, all the archives in that directory that contain obsolete
files will be either reported or updated, depending on the mode selected.

## OS branch tagging
Tag is the archive filename component after the final underscore and before
the format extension. Tags make it possible to update only the archives that
match a given system, especially when running in the directory mode.

Archives tagged with an OS release number or release name are updated only
if the current system matches. It works for Debian or openSUSE, but may be
easily extended for other distros.

When the current system release number of release name does not match that
of the archive processed, a message similar to the below is printed.

```
archive_15.2.tar.gz: 15.2 branch tagged archive does not match os release 15.4, skipping archive
```

## Configuration file 
The script parses the configuration file `up2date.conf` from its own directory.
If the script is renamed, the configuration file will need to do likewise.

Several variables may be specified, such as tar ownership or OS release/name
overrides.

```
# cat up2date.conf
EXCLUDELIST=${DSELF}/${SELF%.*}.excludelist
TAR_ROOT=/
USER=${USER}
GROUP=users
TESTING_OS_CODENAME=bookworm
OPENSUSE_RELEASE="15.*
```

### Exclude list
Exclude lists allow to exclude files from being tarred up when directory
paths are included in a tar archive. Normally, tar includes all files under
a directory path for archiving. An exclude list allows to exclude unwanted
files, or directories, from being archived. See `man tar` for explanation.

A single exclude list for all tar archives processed by `up2date` is set
via the `EXCLUDELIST` variable in the configuration file, e.g.:
```
EXCLUDELIST=${DSELF}/${SELF%.*}.excludelist
```
`${DSELF}` stands for the directory the script is installed, `${SELF%.*}`
standing for the current name of the script (`up2date.ksh` unless renamed).

## Notes
Multiple modified files are supported.

For convenience, set up an alias similar to:
```
alias update='MODE=update up2date.ksh'
```
