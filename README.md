# snapraid-aio-script
The definitive all-in-one [SnapRAID](https://github.com/amadvance/snapraid) script.

There are many SnapRAID scripts out there, but none could fit my needs. So I took the best of them to start a new one.

It is meant to be run periodically (e.g. daily) and do the heavy lifting, then send an email you will actually read.
It is highly customizable.
It has been tested with Debian 10 and OpenMediaVault 5.

Contributions are welcome: there's always room for improvement!

_This readme has some rough edges which will be smoothened over time._

# Highlights

## How it works
- After some preliminary checks, the script will execute `snapraid diff` to figure out if parity info is out of date, which means checking for changes since the last execution.
- One of the following will happen:     
    - If parity info is out of sync **and** the number of deleted or changed files exceed the threshold you have configured it **stops**. You may want to take a look to the output log.
    - If parity info is out of sync **and** the number of deleted or changed files exceed the threshold, you can still **force a sync** after a number of warnings. It's useful If  you often get a false alarm but you're confident enough.
    - If parity info is out of sync **but** the number of deleted or changed files did not exceed the treshold, it **executes a sync** to update the parity info.
- When the parity info is in sync, either because nothing has changed or after a successfully sync, it runs the `snapraid scrub` command to validate the integrity of the data, both the files and the parity info. _Note that each run of the scrub command will validate only a configurable portion of parity info to avoid having a long running job and affecting the performance of the server._
- When the script is done sends an email with the results, both in case of error or success.

## Safety thresholds
If file update/delete thresholds are reached the sync will not be run and the script will stop.

Pre-hashing is enabled by default to avoid silent read errors. It mitigates the lack of ECC memory.
## A nice email report
This report produces emails that don't contain a list of changed files to improve clarity.

You can re-enable full output in the email by switching the option `VERBOSITY` but either way, the full report will always be available in `/tmp/snapRAID.out` and will be replaced after each run or deleted when the system is shut down if kept there.

SMART drive report from SnapRAID is also included by default.

[Screen1](Snapraid AIO Script 1.jpg)


## Customization
All the above options can be either turned on or off. 

If you don't know what to do, I recommend using the default values and see how it performs.  

You can also change more advanced options such as mail binary (by default uses `mailx`), SnapRAID binary location, log file location.


# Requirements
- Markdown to have nice emails
- ~~Hd-idle to spin down disks - [Link TBD] - currently not required since spin down does not work properly.~~

# Installation
[WIP]
1. Install markdown `apt install python-markdown`. You can skip this step since the script will check and install it for you.
2. Download config file and script, then place wherever you prefer e.g. `/usr/sbin/snapraid`
3. Give executable rights to the main script - `chmod +x snapraid-aio-script.sh`
4. Edit the config file and add your email address at line 43
5. Tweak the config file if needed
6. Schedule the script execution time

# Known Issues
Hard disk spin down does not work: they are immediately woken up. The script probably does not handle this correctly while running.

# Credits
All rights belong to the respective creators. 
Thanks to:
- [Zack Reed](https://zackreed.me/snapraid-split-parity-sync-script/) for most of the original script
- [mtompkins](https://gist.github.com/mtompkins/91cf0b8be36064c237da3f39ff5cc49d) for most of the original script
- [sburke](https://zackreed.me/snapraid-split-parity-sync-script/#comment-300) for the Debian 10 fix
- metagliatore (a friend, not on Github) for removing the DIFF output from the email
- [ozboss](https://forum.openmediavault.org/wsc/index.php?user/27331-ozboss/)
