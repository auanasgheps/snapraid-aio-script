#!/bin/bash
######################
#   USER VARIABLES   #
######################

####################### USER CONFIGURATION START #######################

# address where the output of the jobs will be emailed to.
EMAIL_ADDRESS="youremailgoeshere"

# Set the threshold of deleted files to stop the sync job from running.
# NOTE that depending on how active your filesystem is being used, a low
# number here may result in your parity info being out of sync often and/or
# you having to do lots of manual syncing.
DEL_THRESHOLD=500
UP_THRESHOLD=500

# Set number of warnings before we force a sync job.
# This option comes in handy when you cannot be bothered to manually
# start a sync job when DEL_THRESHOLD is breached due to false alarm.
# Set to 0 to ALWAYS force a sync (i.e. ignore the delete threshold above)
# Set to -1 to NEVER force a sync (i.e. need to manual sync if delete threshold is breached)
SYNC_WARN_THRESHOLD=-1

# Set percentage of array to scrub if it is in sync.
# i.e. 0 to disable and 100 to scrub the full array in one go
# WARNING - depending on size of your array, setting to 100 will take a very long time!
SCRUB_PERCENT=5
SCRUB_AGE=10

# Prehash Data To avoid the risk of a latent hardware issue, you can enable the "pre-hash" mode and have all the
# data read two times to ensure its integrity. This option also verifies the files moved inside the array, to ensure
# that the move operation went successfully, and in case to block the sync and to allow to run a fix operation.
# 1 to enable, any other values to disable
PREHASH=1

# Set the option to log SMART info. 1 to enable, any other value to disable
SMART_LOG=1

# Set verbosity of the email output. TOUCH and DIFF outputs will be kept in the email, producing a potentially huge email. Keep this disabled for optimal reading
# You can always check TOUCH and DIFF outputs using the TMP file.
# 1 to enable, any other values to disable
VERBOSITY=0

# Set if disk spindown should be performed. Depending on your system, this may not work. 1 to enable, any other values to disable
SPINDOWN=0

# Run snapraid status command to show array general information.
# Be aware the HTML output is pretty broken.
SNAP_STATUS=0

# location of the snapraid binary
SNAPRAID_BIN="/usr/bin/snapraid"
# location of the mail program binary
MAIL_BIN="/usr/bin/mailx"

# Set to 1 to manage docker containers.
MANAGE_SERVICES=0
  
# Containers to manage (separated with spaces).
SERVICES='container1 container2 container3'  

# Set to 1 if docker is running on remote machine, and enter Docker host machine IP.
# Passwordless ssh access between snapRAID host and Docker host must be set up before running the script.
DOCKER_REMOTE=0
DOCKER_USER="sshusernamegoeshere"
DOCKER_IP="127.0.0.1"

####################### USER CONFIGURATION END #######################

####################### SYSTEM CONFIGURATION #######################
# Make changes only if you know what you're doing 
######################

# Init variables
CHK_FAIL=0
DO_SYNC=0
EMAIL_SUBJECT_PREFIX="(SnapRAID on `hostname`)"
GRACEFUL=0
SYNC_WARN_FILE="$CURRENT_DIR/snapRAID.warnCount"
SYNC_WARN_COUNT=""
TMP_OUTPUT="/tmp/snapRAID.out"
SNAPRAID_LOG="/var/log/snapraid.log"
SECONDS=0 #Capture time

# Expand PATH for smartctl
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Determine names of first content file...
CONTENT_FILE=`grep -v '^$\|^\s*\#' /etc/snapraid.conf | grep snapraid.content | head -n 1 | cut -d " " -f2`

# Build an array of parity all files...
PARITY_FILES[0]=`grep -v '^$\|^\s*\#' /etc/snapraid.conf | grep snapraid.parity | head -n 1 | cut -d " " -f2`
IFS=$'\n' PARITY_FILES=(`cat /etc/snapraid.conf | grep "^[^#;]" | grep "^\([2-6z]-\)*parity" | cut -d " " -f 2 | tr ',' '\n'`)
