# snapraid-aio-script
The definitive all-in-one [SnapRAID](https://github.com/amadvance/snapraid) script.

There are many SnapRAID scripts out there, but none could fit my needs. So I took the best of them to start a new one.

It is meant to be run periodically (e.g. daily) and do the heavy lifting, then send an email you will actually read.
It is highly customizable.
It has been tested with Debian 10 and OpenMediaVault 5.

Contributions are welcome: there's always room for improvement!

This readme has some rough edges which will be smoothened over time.

# Highlights
 
## Safety thresholds
If file update/delete thresholds are reached the sync will not be run and the script will stop.

Pre-hashing is enabled by default to avoid silent read errors. It mitigates the lack of ECC memory.
## A nice email report
This report produces emails that don't contain a list of changed files to improve clarity.

You can re-enable full output in the email changing the option `VERBOSITY`, but either way the full report will always be available in `/tmp/snapRAID.out` and will be replaced after each run or deleted when the system is shut down.

SMART drive report from SnapRAID is also included by default.

## Customization
All the above options can be either turned on or off. 

You can also change more advanced options such as mail binary (by default uses mailx), Snapraid binary location, log file location.


# Requirements
- Markdown to have nice emails
- ~~Hd-idle to spin down disks - [Link TBD] - currently not required since spin down does not work properly.~~

# Installation
[Better instructions on the way]
1. Install markdown `apt install python-markdown`. You can skip this step since the script will check and install it for you.
2. Download config file and script, then place wherever you prefer e.g. `/usr/sbin/snapraid`
3. Give executable rights to the script - `chmod +x snapraid-aio-script.sh`
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
- metagliatore (I don't think he's on Github) for removing the DIFF output from the email
- [ozboss](https://forum.openmediavault.org/wsc/index.php?user/27331-ozboss/)
