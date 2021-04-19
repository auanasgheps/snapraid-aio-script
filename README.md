# snapraid-aio-script
The definitive all-in-one [SnapRAID](https://github.com/amadvance/snapraid) script.

There are many SnapRAID scripts out there, but none could fit my needs. So I took the best of them to start a new one.

It is meant to be run periodically (e.g. daily), do the heavy lifting and send an email you will actually read.

Supports single and dual parity configurations. It is customizable and has been tested with Debian 10 and [OpenMediaVault 5](https://github.com/openmediavault/openmediavault).

Contributions are welcome!

# Highlights

## How it works
- After some preliminary checks, the script will execute `snapraid diff` to figure out if parity info is out of date, which means checking for changes since the last execution. During this step, the script will ensure drives are fine by reading parity and content files. 
- One of the following will happen:     
    - If parity info is out of sync **and** the number of deleted or changed files exceed the threshold you have configured it **stops**. You may want to take a look to the output log.
    - If parity info is out of sync **and** the number of deleted or changed files exceed the threshold, you can still **force a sync** after a number of warnings. It's useful If  you often get a false alarm but you're confident enough. This is called "Sync with threshold warnings"
    - If parity info is out of sync **but** the number of deleted or changed files did not exceed the threshold, it **executes a sync** to update the parity info.
- When the parity info is in sync, either because nothing has changed or after a successfully sync, it runs the `snapraid scrub` command to validate the integrity of the data, both the files and the parity info. If sync was cancelled or other issues were found, scrub will not be run. _Note that each run of the scrub command will validate only a configurable portion of parity info to avoid having a long running job and affecting the performance of the server._ Scrub frequency can also be customized in case you don't want to do it every time the script runs. It is still recommended to run scrub frequently. 
- Extra information is be added, like SnapRAID's disk health report.  
- When the script is done sends an email with the results, both in case of error or success.

### Additional Information
- Docker container management, if enabled, will manage containers before SnapRAID activity and restore them when finished. This avoids nasty errors aboud data being written during SnapRAID sync.
	- You can either choose to pause or stop your containers.
- Important messages are sent to the system log, at least on OMV.

## Customization
Many options can be changed to your taste, their behavior is documented in the script config file.
If you don't know what to do, I recommend using the default values and see how it performs.

### Customizable features
- Sync options
	- Sync always (forced sync).
	- Sync after a number of breached threshold warnings. 
	- Sync only if thresholds warnings are not breached (enabled by default).
	- User definable thresholds for deleted and updated files.
- Scrub options 
	- Enable or disable scrub job.
	- Delayed option, disabled by default. Run scrub only after a number of script executions, e.g. every 7 times. If you don't want to scrub your array every time, this one is for you.
	- Data to be scrubbed - by default 5% older than 10 days.
- Pre-hashing - enabled by default. Mitigate the lack of ECC memory, reading data twice to avoid silent read errors. 
- SMART Log - enabled by default. A SnapRAID report for disks health status.
- Container management - disabled by default. 
	- A list of containers you want to be interrupted before running actions and restored when completed.
   	- Docker mode - choose to pause/unpause or to stop/restart your containers
   	- Docker remote - if docker is running on a remote machine
- Verbosity - disabled by default. When enabled, includes the TOUCH and DIFF commands output, email will be huge and unreadable.
- Spindown - spindown drives after the script, disabled because is currently not working. 
- Snapraid Status - shows the status of the array, disabled by default.
 
You can also change more advanced options such as mail binary (by default uses `mailx`), SnapRAID binary location, log file location.

## A nice email report
This report produces emails that don't contain a list of changed files to improve clarity.

You can re-enable full output in the email by switching the option `VERBOSITY` but the full report will always be available in `/tmp/snapRAID.out` but will be replaced after each run, or deleted when the system is shut down. You can change the location of the file if you need to keep it.

Here's a sneak peek of the email report. 

```markdown
## [COMPLETED] DIFF + SYNC + SCRUB Jobs (SnapRAID on omv-test.local)

SnapRAID Script Job started [Sat Jan 9 02:07:46 CET 2021]  
Running SnapRAID version 11.5  
SnapRAID Script version 2.7.0

----------

## Preprocessing

Configuration file found! Proceeding.  
Testing that all parity files are present.  
All parity files found. Continuing...

----------

## Processing

### SnapRAID TOUCH [Sat Jan 9 02:07:46 CET 2021]

Checking for zero sub-second files.  
No zero sub-second timestamp files found.  
TOUCH finished [Sat Jan 9 02:07:46 CET 2021]

### SnapRAID DIFF [Sat Jan 9 02:07:46 CET 2021]

DIFF finished [Sat Jan 9 02:07:46 CET 2021]

**SUMMARY of changes - Added [2] - Deleted [0] - Moved [0] - Copied [0] - Updated [0]**

There are no deleted files, that's fine.
There are no updated files, that's fine.
SYNC is authorized.

### SnapRAID SYNC [Sat Jan 9 02:07:46 CET 2021]

Self test...  
Loading state from /srv/dev-disk-by-label-DISK1/snapraid.content...  
Scanning disk DATA1...  
Scanning disk DATA2...  
Using 0 MiB of memory for the file-system.  
Initializing...  
Hashing...  
SYNC_JOB--Everything OK  
Resizing...  
Saving state to /srv/dev-disk-by-label-DISK1/snapraid.content...  
Saving state to /srv/dev-disk-by-label-DISK2/snapraid.content...  
Saving state to /srv/dev-disk-by-label-DISK3/snapraid.content...  
Saving state to /srv/dev-disk-by-label-DISK4/snapraid.content...  
Verifying /srv/dev-disk-by-label-DISK1/snapraid.content...  
Verifying /srv/dev-disk-by-label-DISK2/snapraid.content...  
Verifying /srv/dev-disk-by-label-DISK3/snapraid.content...  
Verifying /srv/dev-disk-by-label-DISK4/snapraid.content...  
Verified /srv/dev-disk-by-label-DISK4/snapraid.content in 0 seconds  
Verified /srv/dev-disk-by-label-DISK3/snapraid.content in 0 seconds  
Verified /srv/dev-disk-by-label-DISK2/snapraid.content in 0 seconds  
Verified /srv/dev-disk-by-label-DISK1/snapraid.content in 0 seconds  
Syncing...  
Using 32 MiB of memory for 32 cached blocks.

DATA1 59% | ***********************************  
DATA2 55% | ********************************
parity 0% |  
2-parity 0% |  
raid 6% |
hash 5% |  
sched 7% |   
misc 17% | 
|______________
wait time (total, less is better)

SYNC_JOB--Everything OK  
Saving state to /srv/dev-disk-by-label-DISK1/snapraid.content...  
Saving state to /srv/dev-disk-by-label-DISK2/snapraid.content...  
Saving state to /srv/dev-disk-by-label-DISK3/snapraid.content...  
Saving state to /srv/dev-disk-by-label-DISK4/snapraid.content...  
Verifying /srv/dev-disk-by-label-DISK1/snapraid.content...  
Verifying /srv/dev-disk-by-label-DISK2/snapraid.content...  
Verifying /srv/dev-disk-by-label-DISK3/snapraid.content...  
Verifying /srv/dev-disk-by-label-DISK4/snapraid.content...  
Verified /srv/dev-disk-by-label-DISK4/snapraid.content in 0 seconds  
Verified /srv/dev-disk-by-label-DISK3/snapraid.content in 0 seconds  
Verified /srv/dev-disk-by-label-DISK2/snapraid.content in 0 seconds  
Verified /srv/dev-disk-by-label-DISK1/snapraid.content in 0 seconds  
SYNC finished [Sat Jan 9 02:07:49 CET 2021]

### SnapRAID SCRUB [Sat Jan 9 02:07:49 CET 2021]

Self test...  
Loading state from /srv/dev-disk-by-label-DISK1/snapraid.content...  
Using 0 MiB of memory for the file-system.  
Initializing...  
Scrubbing...  
Using 48 MiB of memory for 32 cached blocks.  
SCRUB_JOB--Nothing to do  
SCRUB finished [Sat Jan 9 02:07:49 CET 2021]

----------

## Postprocessing

SnapRAID SMART report:

Temp Power Error FP Size  
C OnDays Count TB Serial Device Disk

----------

  -      -       -  SSD  0.0  00000000000000000001  /dev/sdb  DATA1  
  -      -       -    -  0.0  01000000000000000001  /dev/sdc  DATA2  
  -      -       -  SSD  0.0  02000000000000000001  /dev/sdd  parity  
  -      -       -  SSD  0.0  03000000000000000001  /dev/sde  2-parity  
  0      -       -    -  0.0  -                     /dev/sda  -

The FP column is the estimated probability (in percentage) that the disk  
is going to fail in the next year.

Probability that at least one disk is going to fail in the next year is 0%.  
All jobs ended. [Sat Jan 9 02:07:49 CET 2021]  
Email address is set. Sending email report to example@example.com [Sat Jan 9 02:07:49 CET 2021]
```

# Requirements
- Markdown to have nice emails - will be installed if not found
- ~~Hd-idle to spin down disks - [Link TBD] - currently not required since spin down does not work properly.~~

# Installation
If you want to use this script on OMV, don't worry about the section _Diff Script Settings_ in the main page of the SnapRAID plugin. These settings only apply to the plugin built-in script. Also don't forget to remove from scheduling the built-in script.  

1. Install markdown `apt install python-markdown`. You can skip this step since the script will check and install it for you.
2. Download config file and script, to be placed wherever you prefer e.g. `/usr/sbin/snapraid`
3. Give executable rights to the main script - `chmod +x snapraid-aio-script.sh`
4. Edit the config file and add your email address at line 9
5. Make other changes to the config file as required
6. Schedule the script execution time 

It is tested on OMV5, but will work on other distros. In such case you may have to change the mail binary or SnapRAID location.

If you want to use this script on OMV, don't worry about the section _Diff Script Settings_ in the main page of the SnapRAID plugin, since it only applies to the built-in plugin script. Also don't forget to remove from scheduling the built-in script.

# Known Issues
- Hard disk spin down does not work: they are immediately woken up. The script probably does not handle this correctly while running.

# Credits
All rights belong to the respective creators. 
Thanks to:
- [Zack Reed](https://zackreed.me/snapraid-split-parity-sync-script/) for most of the original script
- [mtompkins](https://gist.github.com/mtompkins/91cf0b8be36064c237da3f39ff5cc49d) for most of the original script
- [sburke](https://zackreed.me/snapraid-split-parity-sync-script/#comment-300) for the Debian 10 fix
- metagliatore (a friend, not on Github) for removing the DIFF output from the email
- [ozboss](https://forum.openmediavault.org/wsc/index.php?user/27331-ozboss/)
- [tehniemer](https://github.com/tehniemer)
- [cmcginty](https://github.com/cmcginty)
