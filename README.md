# Snapraid AIO Script
The definitive all-in-one [SnapRAID](https://github.com/amadvance/snapraid) script. I hope you'll agree :).

There are many SnapRAID scripts out there, but none has the features I want. So I made my own, inspired by existing solutions.

It is meant to be run periodically (daily), do the heavy lifting and send an email you will actually read.

Supports single and dual parity configurations. It is highly customizable and has been tested with Debian 10 and [OpenMediaVault 5](https://github.com/openmediavault/openmediavault).

Contributions are welcome!

# Table of Contents

- [Highlights](#highlights)
  * [How it works](#how-it-works)
    + [Additional Information](#additional-information)
  * [Customization](#customization)
    + [Customizable features](#customizable-features)
  * [A nice email report](#a-nice-email-report)
- [Requirements](#requirements)
- [Installation](#installation)
  * [First Run](#first-run)
  * [OMV5 and SnapRAID plugin](#omv5-and-snapraid-plugin)
- [Upgrade](#upgrade)
- [Known Issues](#known-issues)
- [Credits](#credits)

# Highlights

## How it works
- After some preliminary checks, the script will execute `snapraid diff` to figure out if parity info is out of date, which means checking for changes since the last execution. During this step, the script will ensure drives are fine by reading parity and content files. 
- One of the following will happen:     
    - If parity info is out of sync **and** the number of deleted or changed files exceed the threshold you have configured it **stops**. You may want to take a look to the output log.
    - If parity info is out of sync **and** the number of deleted or changed files exceed the threshold, you can still **force a sync** after a number of warnings. It's useful If  you often get a false alarm but you're confident enough. This is called "Sync with threshold warnings"
    - If parity info is out of sync **but** the number of deleted or changed files did not exceed the threshold, it **executes a sync** to update the parity info.
- When the parity info is in sync, either because nothing has changed or after a successfully sync, it runs the `snapraid scrub` command to validate the integrity of the data, both the files and the parity info. If sync was cancelled or other issues were found, scrub will not be run. 
    - Note that each run of the scrub command will validate only a configurable portion of parity info to avoid having a long running job and affecting the performance of the server. 
    - Scrub frequency can also be customized in case you don't want to do it every time the script runs. 
    - It is still recommended to run scrub frequently. 
- Extra information can be added, like SnapRAID's disk health report o SnapRAID array status.  
- When the script is done sends an email with the results, both in case of error or success.

### Additional Information
- Docker container management, if enabled, will manage containers before SnapRAID operations and restore them when finished. It avoids nasty errors aboud data being written during SnapRAID sync.
	- The script supports  local or remote Docker instances.
	- You can either choose to pause or stop your containers.
- Healthchecks.io and Telegram can be used to track script execution time and promptly alert about errors.
- Important messages are also sent to the system log.
- Emails are still the best place to get detailed but readable information.

## Customization
Many options can be changed to your taste, their behavior is documented in the config file.
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
- Snapraid Status - shows the status of the array, disabled by default.
- SMART Log - enabled by default. A SnapRAID report for disks health status.
- Verbosity option - disabled by default. When enabled, includes the TOUCH and DIFF commands output. Please note email will be huge and mostly unreadable.
- Healthchecks.io and Telegram integration
	- If you don't read your emails every day, this is a great one for you, since you can be quickly informed if things go wrong. 
  	- The script will report to Healthchecks.io and Telegram when is started and when is completed. If there's a failure it's included as well.
  	- **Healthchecks.io only:** If the script ends with a **_WARNING_** message, it will be reported **_DOWN_** to Healthchecks.io, instead if the message is **_COMPLETED_** it will be **_UP_**. 
  	- **Healthchecks.io only:** This service will also show how much time the script took to complete.
- Container management - disabled by default. 
	- A list of containers you want to be interrupted before running actions and restored when completed.
   	- Docker mode - choose to pause/unpause or to stop/restart your containers
   	- Docker remote - if docker is running on a remote machine
   	   - Docker remote action delay - Set by default to 5 seconds, reduces errors when using remote docker
- Spindown - spindown drives after the script, disabled because is currently not working. 

 
You can also change more advanced options such as mail binary (by default uses `mailx`), SnapRAID binary location, log file location.

## A nice email report
This script produces emails that don't contain a list of changed files to improve clarity.

You can re-enable full output in the email by switching the option `VERBOSITY`. The full report will always be available in `/tmp/snapRAID.out` but will be replaced after each run, or deleted when the system is shut down. You can change the location of the file if you need to keep it.

Here's a sneak peek of the email report. 


```markdown
## [COMPLETED] DIFF + SYNC + SCRUB Jobs (SnapRAID on omv-test.local)
SnapRAID Script Job started [Tue 20 Apr 11:43:37 CEST 2021]
Running SnapRAID version 11.5
SnapRAID AIO Script version X.YZ

----------

## Preprocessing
Healthchecks.io integration is enabled.
Configuration file found.
Checking if all parity and content files are present.
All parity files found.
All content files found.
Docker containers management is enabled.

### Stopping Containers [Tue 20 Apr 11:43:37 CEST 2021]
Stopping Container - Code-server
code-server
Stopping Container - Portainer
portainer

----------

## Processing
### SnapRAID TOUCH [Tue 20 Apr 11:43:37 CEST 2021]
Checking for zero sub-second files.
No zero sub-second timestamp files found.
TOUCH finished [Tue 20 Apr 11:43:38 CEST 2021]

### SnapRAID DIFF [Tue 20 Apr 11:43:38 CEST 2021]
DIFF finished [Tue 20 Apr 11:43:38 CEST 2021]
**SUMMARY of changes - Added [0] - Deleted [0] - Moved [0] - Copied [0] - Updated [1]**
There are no deleted files, that's fine.
There are updated files. The number of updated files (1) is below the threshold of (500).
SYNC is authorized. [Tue 20 Apr 11:43:38 CEST 2021]

### SnapRAID SYNC [Tue 20 Apr 11:43:38 CEST 2021]
Self test...  
Loading state from /srv/dev-disk-by-label-DISK1/snapraid.content...  
Scanning disk DATA1...  
Scanning disk DATA2...  
Using 0 MiB of memory for the file-system.  
Initializing...  
Hashing...  
SYNC - Everything OK  
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
    DATA1 12% | *******  
    DATA2 82% | ************************************************  
   parity  0% |   
 2-parity  0% |   
     raid  1% | *  
     hash  1% |   
    sched 11% | ******  
     misc  0% |   
              |____________________________________________________________  
                            wait time (total, less is better)  
SYNC - Everything OK  
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

SYNC finished [Tue 20 Apr 11:43:40 CEST 2021]

### SnapRAID SCRUB [Tue 20 Apr 11:43:40 CEST 2021]
Self test...  
Loading state from /srv/dev-disk-by-label-DISK1/snapraid.content...  
Using 0 MiB of memory for the file-system.  
Initializing...  
Scrubbing...  
Using 48 MiB of memory for 32 cached blocks.  
    DATA1  2% | *  
    DATA2 18% | **********  
   parity  0% |   
 2-parity  0% |   
     raid 21% | ************  
     hash  7% | ****  
    sched 51% | ******************************  
     misc  0% |   
              |____________________________________________________________  
                            wait time (total, less is better)  
SCRUB - Everything OK  
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

SCRUB finished [Tue 20 Apr 11:43:41 CEST 2021]

----------

## Postprocessing
SnapRAID Smart
SnapRAID SMART report:  
   Temp  Power   Error   FP Size  
      C OnDays   Count        TB  Serial                Device    Disk  
      -      -       -  SSD  0.0  00000000000000000001  /dev/sdb  DATA1  
      -      -       -  SSD  0.0  01000000000000000001  /dev/sdc  DATA2  
      -      -       -    -  0.0  02000000000000000001  /dev/sdd  parity  
      -      -       -  SSD  0.0  03000000000000000001  /dev/sde  2-parity  
      -      -       -  n/a    -  -                     /dev/sr0  -  
      0      -       -    -  0.0  -                     /dev/sda  -  
The FP column is the estimated probability (in percentage) that the disk  
is going to fail in the next year.  
Probability that at least one disk is going to fail in the next year is 0%.

## Restarting Containers [Tue 20 Apr 11:43:41 CEST 2021]

Restarting Container - Code-server
code-server
Restarting Container - Portainer
portainer
All jobs ended. [Tue 20 Apr 11:43:41 CEST 2021]
Email address is set. Sending email report to yourmail@example.com [Tue 20 Apr 11:43:41 CEST 2021]
```

# Requirements
- [`markdown`](https://packages.debian.org/buster/python-markdown) to format emails - will be installed if not found
- `curl` to use Healhchecks - will be installed if not found
- ~~`hd-idle` to spin down disks - [Link](https://github.com/adelolmo/hd-idle) - currently not really required since spin down does not work properly.~~

# Installation

_Optional: install markdown `apt install python-markdown` and curl `apt install curl` . You can skip this step since the script will check and install missing packages for you._

1. Download the latest version from [Releases](https://github.com/auanasgheps/snapraid-aio-script/releaseshttps://github.com/auanasgheps/snapraid-aio-script/releases) 
2. Extract the archive wherever you prefer 
   - e.g. `/usr/sbin/snapraid`
3. Give executable rights to the main script 
   - `chmod +x snapraid-aio-script.sh`
4. Open the config file and add your email address
5. Make other changes to the config file as required. 
   - Every config is documented, but defaults are pretty resonable, so don't change what you don't know.
   - When you see  `""` or `''` in some options, do not remove these characters but just fill in your data.
6. Schedule the script execution. 
   - I recommend running the script daily. 

It is tested on OMV5, but will work on other distros. In such case you may have to change the mail binary or SnapRAID location.

## First Run
If you start with empty disks, you cannot use (yet) this script, since it expects SnapRAID files which would not exist.

First run `snapraid sync`. Once completed, the array will be ready to be used with this script.

## OMV5 and SnapRAID plugin

Ignore what you see at OMV GUI > Services > SnapRAID > Diff Script Settings, since it only applies to the plugin's built-in script. Also don't forget to remove the built-in script from the scheduled jobs.  

# Upgrade 
If you are using a previous version of the script, do not use current config file. Please move your preferences to the new `script-config.sh` found in the archive. 

# Known Issues
- Hard disk spin down does not work: they are immediately woken up. The script probably does not handle this correctly while running.

# Credits
All rights belong to the respective creators. 
This script would not exist without:
- [Zack Reed](https://zackreed.me/snapraid-split-parity-sync-script/) for most of the original script
- [mtompkins](https://gist.github.com/mtompkins/91cf0b8be36064c237da3f39ff5cc49d) for most of the original script
- [sburke](https://zackreed.me/snapraid-split-parity-sync-script/#comment-300) for the Debian 10 fix
- metagliatore (a friend not on Github) for helping out on several BASH issues
- [ozboss](https://forum.openmediavault.org/wsc/index.php?user/27331-ozboss/)
- [tehniemer](https://github.com/tehniemer)
- [cmcginty](https://github.com/cmcginty)
