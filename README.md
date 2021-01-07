# snapraid-aio-script
The definitive all-in-one [SnapRAID](https://github.com/amadvance/snapraid) script.

This script is a collection of many scripts with added improvements.
It is meant to be run periodically (e.g. daily) and do the heavy lifting, then send an email you will actually read.
It is highly customizable to user needs.

It has been tested with Debian 10 and OpenMediaVault 5.

# Features
[WIP]

# Requirements
- Markdown to have a nicely formatted email - `apt install python-markdown`
- Hd-Idle to spin down disks - [Link TBD]

# Installation
[WIP]

# Known Issues
Hard disk spin down does not work. The script probably does not handle this correctly while running.

# Credits
All rights belong to the respective creators. 
Thanks to:
- [Zack Reed](https://zackreed.me/snapraid-split-parity-sync-script/) for most of the original script
- [mtompkins](https://gist.github.com/mtompkins/91cf0b8be36064c237da3f39ff5cc49d) for most of the original script
- [sburke](https://zackreed.me/snapraid-split-parity-sync-script/#comment-300) for the Debian 10 fix
- metagliatore (I don't think he's on Github) for removing the DIFF output from the email
- [ozboss](https://forum.openmediavault.org/wsc/index.php?user/27331-ozboss/)
