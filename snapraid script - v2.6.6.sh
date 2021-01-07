#!/bin/bash
########################################################################
# This is a helper script that keeps snapraid parity info in sync with
# your data and optionally verifies the parity info. Here's how it works:
#   1) Calls diff to figure out if the parity info is out of sync.
#   2) If parity info is out of sync, AND the number of deleted or changed files exceed
#      X (each configurable), it triggers an alert email and stops. (In case of
#      accidental deletions, you have the opportunity to recover them from
#      the existing parity info. This also mitigates to a degree encryption malware.)
#   3) If parity info is out of sync, AND the number of deleted or changed files exceed X
#      AND it has reached/exceeded Y (configurable) number of warnings, force
#      a sync. (Useful when you get a false alarm above and you can't be bothered
#      to login and do a manual sync. Note the risk is if its not a false alarm
#      and you can't access the server to fix the issue before the job is run Y number of
#      times... Well I hope you have other backups...)
#   4) If parity info is out of sync BUT the number of deleted files did NOT
#      exceed X, it calls sync to update the parity info.
#   5) If the parity info is in sync (either because nothing changed or after it
#      has successfully completed the sync job, it runs the scrub command to
#      validate the integrity of the data (both the files and the parity info).
#      Note that each run of the scrub command will validate only a (configurable)
#      portion of parity info to avoid having a long running job and affecting
#      the performance of the server.
#   6) Once all jobs are completed, it sends an email with the output to user
#      (if configured).
#
#   Original by Zack Reed https://zackreed.me/snapraid-split-parity-sync-script/
#   + mtompkins https://gist.github.com/mtompkins/91cf0b8be36064c237da3f39ff5cc49d
#   Maintained by auanasgheps
#   CHANGELOG
# - version 2.0 changelog by auanasgheps
#   - Removed DIFF output from email (still present in logs) - credits to metagliatore
#   - Fixed script for Debian 10/OMV5 - credits to sburke
#   - Added alternative way of spinning down disks with hdparm
# - version 2.1 changelog by auanasgheps
#   - disabled disk spindown (code is commented) since it's not working properly
# - version 2.2 changelog by auanasgheps
#   - Redone changelog section
#   - Added 'Prehash Data' feature - credits to Zack Reed
#   - Added HTML formatting - NOTE: requires python-markdown
# - version 2.3 changelog by auanasgheps
#   - Removed TOUCH output from email (still present in logs)
#   - Fixed small typos
# - version 2.4 changelog by auanasgheps
#    Send an email alert if parity or content files are not found, then exit gracefully
# - version 2.5 changelog by auanasgheps
#   - Added configurable options for disk spindown and email verbosity
#   - Added syslog features
# - version 2.6 changelog by auanasgheps
#   - Fixed sed error caused by a slash when updated/deleted threshold is breached
#   - Fixed violation message not shown when threshold is reached but not exceeded
#   - Fixed concurrent (deleted AND updated) violation message and mail subject
#   - Added message and mail subject when sync is forced with breached thresholds (deleted, changed or both)
# - version 2.6.1 changelog by auanasgheps
#    Disabled clean_desc function in main script, caused {out} file in /root
# - version 2.6.2 changelog by auanasgheps
#   - Added SnapRAID version to output
#   - Added variable for script version
#   - Removed timestamps from logs text since it's already added by the system
# - version 2.6.3 changelog by auanasgheps
#    Small change to email subject when forcing syncs with violations
# - version 2.6.4 changelog by auanasgheps
#    Removed unnecessary capitalized letters in email subject
# - version 2.6.5 changelog by ozboss
#   - Replaced tabs with spaces
#   - Change default of 'SYNC_WARN_THRESHOLD' to '-1', will not force a sync
#   - Added requirements
#   - Added alternative spindown method (hd-idle)
#   - Added automatic detection of rotational devices for spindown (hdparm and hd-idle)
# - version 2.6.6 changelog by auanasgheps
#	- removed code for Docker Container management, was unreliable
# KNOWN ISSUES:
# - Spindown does not work correctly: drives are immediately spun up after spindown.
SNAPSCRIPTVERSION="2.6.6"
########################################################################

######################
#   REQUIREMENTS     #
######################

# This script requires the python markdown module.
# Install procedure (Debian):
# `apt install python-markdown`

########################################################################

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

# location of the snapraid binary
SNAPRAID_BIN="/usr/bin/snapraid"
# location of the mail program binary
MAIL_BIN="/usr/bin/mailx"

function main(){

  ######################
  #   INIT VARIABLES   #
  ######################
  CHK_FAIL=0
  DO_SYNC=0
  EMAIL_SUBJECT_PREFIX="(SnapRAID on `hostname`)"
  GRACEFUL=0
  SYNC_WARN_FILE="/tmp/snapRAID.warnCount"
  SYNC_WARN_COUNT=""
  TMP_OUTPUT="/tmp/snapRAID.out"
  SNAPRAID_LOG="/var/log/snapraid.log"
  # Capture time
  SECONDS=0

  # Build Services Array...
  service_array_setup

  # Expand PATH for smartctl
  PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

  # Determine names of first content file...
  CONTENT_FILE=`grep -v '^$\|^\s*\#' /etc/snapraid.conf | grep snapraid.content | head -n 1 | cut -d " " -f2`

  # Build an array of parity all files...
  PARITY_FILES[0]=`grep -v '^$\|^\s*\#' /etc/snapraid.conf | grep snapraid.parity | head -n 1 | cut -d " " -f2`
  IFS=$'\n' PARITY_FILES=(`cat /etc/snapraid.conf | grep "^[^#;]" | grep "^\([2-6z]-\)*parity" | cut -d " " -f 2 | tr ',' '\n'`)

##### USER CONFIGURATION STOP ##### MAKE NO CHANGES BELOW THIS LINE ####

  # create tmp file for output
  > $TMP_OUTPUT

  # Redirect all output to file and screen. Starts a tee process
  output_to_file_screen

  # timestamp the job
  echo "SnapRAID Script Job started [`date`]"
  echo "Running SnapRAID version $SNAPRAIDVERSION"
  echo "SnapRAID Script version $SNAPSCRIPTVERSION"
  echo
  echo "----------------------------------------"
  mklog "INFO: ----------------------------------------"
  mklog "INFO: SnapRAID Script Job started"
  mklog "INFO: Running SnapRAID version $SNAPRAIDVERSION"
  mklog "INFO: SnapRAID Script version $SNAPSCRIPTVERSION"


  # Remove any plex created anomalies
  echo "##Preprocessing"

  # sanity check first to make sure we can access the content and parity files
  mklog "INFO: Checking SnapRAID disks"
  sanity_check

  echo
  echo "----------------------------------------"
  echo "##Processing"

  # Fix timestamps
  chk_zero

  # run the snapraid DIFF command
  echo "###SnapRAID DIFF [`date`]"
  mklog "INFO: SnapRAID DIFF started"
  $SNAPRAID_BIN diff
  # wait for the above cmd to finish, save output and open new redirect
  close_output_and_wait
  output_to_file_screen
  echo
  echo "DIFF finished [`date`]"
  mklog "INFO: SnapRAID DIFF finished"
  JOBS_DONE="DIFF"

  # Get number of deleted, updated, and modified files...
  get_counts

  # sanity check to make sure that we were able to get our counts from the output of the DIFF job
  if [ -z "$DEL_COUNT" -o -z "$ADD_COUNT" -o -z "$MOVE_COUNT" -o -z "$COPY_COUNT" -o -z "$UPDATE_COUNT" ]; then
    # failed to get one or more of the count values, lets report to user and exit with error code
    echo "**ERROR** - failed to get one or more count values. Unable to proceed."
    echo "Exiting script. [`date`]"
    if [ $EMAIL_ADDRESS ]; then
      SUBJECT="$EMAIL_SUBJECT_PREFIX WARNING - Unable to proceed with SYNC/SCRUB job(s). Check DIFF job output."
      send_mail
    fi
    exit 1;
  fi
  echo
  echo "**SUMMARY of changes - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]**"
  mklog "INFO: SUMMARY of changes - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]"
  echo

  # check if the conditions to run SYNC are met
  # CHK 1 - if files have changed
  if [ $DEL_COUNT -gt 0 -o $ADD_COUNT -gt 0 -o $MOVE_COUNT -gt 0 -o $COPY_COUNT -gt 0 -o $UPDATE_COUNT -gt 0 ]; then
    chk_del

    if [ $CHK_FAIL -eq 0 ]; then
      chk_updated
    fi

    if [ $CHK_FAIL -eq 1 ]; then
      chk_sync_warn
    fi
  else
    # NO, so let's skip SYNC
    echo "No change detected. Not running SYNC job. [`date`]"
  mklog "INFO: No change detected. Not running SYNC job."
    DO_SYNC=0
  fi

  # Now run sync if conditions are met
  if [ $DO_SYNC -eq 1 ]; then
    echo "###SnapRAID SYNC [`date`]"
  mklog "INFO: SnapRAID SYNC Job started"
  if [ $PREHASH -eq 1 ]; then
    $SNAPRAID_BIN sync -h -q
    else
      $SNAPRAID_BIN sync -q
    fi
    #wait for the job to finish
    close_output_and_wait
    output_to_file_screen
    echo "SYNC finished [`date`]"
  mklog "INFO: SnapRAID SYNC Job finished"
    JOBS_DONE="$JOBS_DONE + SYNC"
    # insert SYNC marker to 'Everything OK' or 'Nothing to do' string to differentiate it from SCRUB job later
    sed_me "s/^Everything OK/SYNC_JOB--Everything OK/g;s/^Nothing to do/SYNC_JOB--Nothing to do/g" "$TMP_OUTPUT"
    # Remove any warning flags if set previously. This is done in this step to take care of scenarios when user
    # has manually synced or restored deleted files and we will have missed it in the checks above.
    if [ -e $SYNC_WARN_FILE ]; then
      rm $SYNC_WARN_FILE
    fi
    echo
  fi

  # Moving onto scrub now. Check if user has enabled scrub
  if [ $SCRUB_PERCENT -gt 0 ]; then
    # YES, first let's check if delete threshold has been breached and we have not forced a sync.
    if [ $CHK_FAIL -eq 1 -a $DO_SYNC -eq 0 ]; then
      # YES, parity is out of sync so let's not run scrub job
      echo "Scrub job cancelled as parity info is out of sync (deleted or changed files threshold has been breached). [`date`]"
    mklog "INFO: Scrub job cancelled as parity info is out of sync (deleted or changed files threshold has been breached)."
    else
      # NO, delete threshold has not been breached OR we forced a sync, but we have one last test -
      # let's make sure if sync ran, it completed successfully (by checking for our marker text "SYNC_JOB--" in the output).
      if [ $DO_SYNC -eq 1 -a -z "$(grep -w "SYNC_JOB-" $TMP_OUTPUT)" ]; then
        # Sync ran but did not complete successfully so lets not run scrub to be safe
        echo "**WARNING** - check output of SYNC job. Could not detect marker. Not proceeding with SCRUB job. [`date`]"
    mklog "WARN: Check output of SYNC job. Could not detect marker. Not proceeding with SCRUB job."
      else
        # Everything ok - let's run the scrub job!
        echo "###SnapRAID SCRUB [`date`]"
    mklog "INFO: SnapRAID SCRUB Job started"
        $SNAPRAID_BIN scrub -p $SCRUB_PERCENT -o $SCRUB_AGE -q
        #wait for the job to finish
        close_output_and_wait
        output_to_file_screen
        echo "SCRUB finished [`date`]"
    mklog "INFO: SnapRAID SCRUB Job finished"
        echo
        JOBS_DONE="$JOBS_DONE + SCRUB"
        # insert SCRUB marker to 'Everything OK' or 'Nothing to do' string to differentiate it from SYNC job above
        sed_me "s/^Everything OK/SCRUB_JOB--Everything OK/g;s/^Nothing to do/SCRUB_JOB--Nothing to do/g" "$TMP_OUTPUT"
      fi
    fi
  else
    echo "Scrub job is not enabled. Not running SCRUB job. [`date`]"
  mklog "INFO: Scrub job is not enabled. Not running SCRUB job."
  fi

  echo
  echo "----------------------------------------"
  echo "##Postprocessing"

  # Moving onto logging SMART info if enabled
  if [ $SMART_LOG -eq 1 ]; then
    echo
    $SNAPRAID_BIN smart
    close_output_and_wait
    output_to_file_screen
  fi

  # Spinning down disks (Method 1: snapraid - preferred)
  if [ $SPINDOWN -eq 1 ]; then
  $SNAPRAID_BIN down
  fi
  
  # Spinning down disks (Method 2: hdparm - spins down all rotational devices)
  # if [ $SPINDOWN -eq 1 ]; then
  # for DRIVE in `lsblk -d -o name | tail -n +2`
  #   do
  #     if [[ `smartctl -a /dev/$DRIVE | grep 'Rotation Rate' | grep rpm` ]]; then
  #       hdparm -Y /dev/$DRIVE
  #     fi
  #   done
  # fi

  # Spinning down disks (Method 3: hd-idle - spins down all rotational devices)
  # if [ $SPINDOWN -eq 1 ]; then
  # for DRIVE in `lsblk -d -o name | tail -n +2`
  #   do
  #     if [[ `smartctl -a /dev/$DRIVE | grep 'Rotation Rate' | grep rpm` ]]; then
  #       echo "spinning down /dev/$DRIVE"
  #       hd-idle -t $DRIVE
  #     fi
  #   done
  # fi

  echo "All jobs ended. [`date`]"
  mklog "INFO: Snapraid: all jobs ended."

  # all jobs done, let's send output to user if configured
  if [ $EMAIL_ADDRESS ]; then
    echo -e "Email address is set. Sending email report to **$EMAIL_ADDRESS** [`date`]"
    # check if deleted count exceeded threshold
    prepare_mail

    ELAPSED="$(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
    echo
    echo "----------------------------------------"
    echo "##Total time elapsed for SnapRAID: $ELAPSED"
  mklog "INFO: Total time elapsed for SnapRAID: $ELAPSED"

    # Add a topline to email body
    sed_me "1s:^:##$SUBJECT \n:" "${TMP_OUTPUT}"
  if [ $VERBOSITY -eq 1 ]; then
   send_mail_verbose
  else
     send_mail
  fi
  fi

  #clean_desc

  exit 0;
}

#######################
# FUNCTIONS & METHODS #
#######################

function sanity_check() {
  if [ ! -e $CONTENT_FILE ]; then
    echo "**ERROR** Content file ($CONTENT_FILE) not found!"
  echo "**ERROR**: Please check the status of your disks! The script exits here due to missing file or disk..."
  mklog "WARN: Content file ($CONTENT_FILE) not found!"
  mklog "WARN: Please check the status of your disks! The script exits here due to missing file or disk..."
    prepare_mail
    # Add a topline to email body
    sed_me "1s:^:##$SUBJECT \n:" "${TMP_OUTPUT}"
    send_mail
    exit;
  fi

  echo "Testing that all parity files are present."
  mklog "INFO: Testing that all parity files are present."
  for i in "${PARITY_FILES[@]}"
    do
      if [ ! -e $i ]; then
        echo "[`date`] ERROR - Parity file ($i) not found!"
        echo "ERROR - Parity file ($i) not found!" >> $TMP_OUTPUT
    echo "**ERROR**: Please check the status of your disks! The script exits here due to missing file or disk..."
    mklog "WARN: Parity file ($i) not found!"
    mklog "WARN: Please check the status of your disks! The script exits here due to missing file or disk..."
      prepare_mail
      # Add a topline to email body
      sed_me "1s:^:##$SUBJECT \n:" "${TMP_OUTPUT}"
      send_mail
        exit;
      fi
  done
  echo "All parity files found. Continuing..."
}

function get_counts() {
  DEL_COUNT=$(grep -w '^ \{1,\}[0-9]* removed' $TMP_OUTPUT | sed 's/^ *//g' | cut -d ' ' -f1)
  ADD_COUNT=$(grep -w '^ \{1,\}[0-9]* added' $TMP_OUTPUT | sed 's/^ *//g' | cut -d ' ' -f1)
  MOVE_COUNT=$(grep -w '^ \{1,\}[0-9]* moved' $TMP_OUTPUT | sed 's/^ *//g' | cut -d ' ' -f1)
  COPY_COUNT=$(grep -w '^ \{1,\}[0-9]* copied' $TMP_OUTPUT | sed 's/^ *//g' | cut -d ' ' -f1)
  UPDATE_COUNT=$(grep -w '^ \{1,\}[0-9]* updated' $TMP_OUTPUT | sed 's/^ *//g' | cut -d ' ' -f1)
}

function sed_me(){
  # Close the open output stream first, then perform sed and open a new tee process and redirect output.
  # We close stream because of the calls to new wait function in between sed_me calls.
  # If we do not do this we try to close Processes which are not parents of the shell.
  exec >&$out 2>&$err
  $(sed -i "$1" "$2")

  output_to_file_screen
}

function chk_del(){
  if [ $DEL_COUNT -lt $DEL_THRESHOLD ]; then
    # NO, delete threshold not reached, lets run the sync job
    echo "There are deleted files. The number of deleted files, ($DEL_COUNT), is below the threshold of ($DEL_THRESHOLD). SYNC Authorized."
    DO_SYNC=1
  else
    echo "**WARNING** Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD)."
  mklog "WARN: Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD)."
    CHK_FAIL=1
  fi
}  

function chk_updated(){
  if [ $UPDATE_COUNT -lt $UP_THRESHOLD ]; then
    echo "There are updated files. The number of updated files, ($UPDATE_COUNT), is below the threshold of ($UP_THRESHOLD). SYNC Authorized."
    DO_SYNC=1
  else
    echo "**WARNING** Updated files ($UPDATE_COUNT) reached/exceeded threshold ($UP_THRESHOLD)."
  mklog "WARN: Updated files ($UPDATE_COUNT) reached/exceeded threshold ($UP_THRESHOLD)."
    CHK_FAIL=1
  fi
}

function chk_sync_warn(){
  if [ $SYNC_WARN_THRESHOLD -gt -1 ]; then
    echo "Forced sync is enabled. [`date`]"
  mklog "INFO: Forced sync is enabled."

    SYNC_WARN_COUNT=$(sed 'q;/^[0-9][0-9]*$/!d' $SYNC_WARN_FILE 2>/dev/null)
    SYNC_WARN_COUNT=${SYNC_WARN_COUNT:-0} #value is zero if file does not exist or does not contain what we are expecting

    if [ $SYNC_WARN_COUNT -ge $SYNC_WARN_THRESHOLD ]; then
      # YES, lets force a sync job. Do not need to remove warning marker here as it is automatically removed when the sync job is run by this script
      echo "Number of warning(s) ($SYNC_WARN_COUNT) has reached/exceeded threshold ($SYNC_WARN_THRESHOLD). Forcing a SYNC job to run. [`date`]"
    mklog "INFO: Number of warning(s) ($SYNC_WARN_COUNT) has reached/exceeded threshold ($SYNC_WARN_THRESHOLD). Forcing a SYNC job to run." 
      DO_SYNC=1
    else
      # NO, so let's increment the warning count and skip the sync job
      ((SYNC_WARN_COUNT += 1))
      echo $SYNC_WARN_COUNT > $SYNC_WARN_FILE
      echo "$((SYNC_WARN_THRESHOLD - SYNC_WARN_COUNT)) warning(s) till forced sync. NOT proceeding with SYNC job. [`date`]"
    mklog "INFO: $((SYNC_WARN_THRESHOLD - SYNC_WARN_COUNT)) warning(s) till forced sync. NOT proceeding with SYNC job."
      DO_SYNC=0
    fi
  else
    # NO, so let's skip SYNC
    echo "Forced sync is not enabled. Check $TMP_OUTPUT for details. NOT proceeding with SYNC job. [`date`]"
  mklog "INFO: Forced sync is not enabled. Check $TMP_OUTPUT for details. NOT proceeding with SYNC job."
    DO_SYNC=0
  fi
}

function chk_zero(){
  echo "###SnapRAID TOUCH [`date`]"
  echo "Checking for zero sub-second files."
  TIMESTATUS=$($SNAPRAID_BIN status | grep 'You have [1-9][0-9]* files with zero sub-second timestamp\.' | sed 's/^You have/Found/g')
  if [ -n "$TIMESTATUS" ]; then
    echo "$TIMESTATUS"
    echo "Running TOUCH job to timestamp. [`date`]"
    $SNAPRAID_BIN touch
    close_output_and_wait
    output_to_file_screen
    echo "TOUCH finished [`date`]"
  else
    echo "No zero sub-second timestamp files found."
  echo "TOUCH finished [`date`]"
  fi
}

function service_array_setup() {
  if [ -z "$SERVICES" ]; then
    echo "Please configure services"
  else
    echo "Setting up service array"
    read -a service_array <<<$SERVICES
  fi
}

function clean_desc(){
  # Cleanup file descriptors
  exec >&{out} 2>&{err}
 
  # If interactive shell restore output
  [[ $- == *i* ]] && exec &>/dev/tty
}

function prepare_mail() {
  if [ $CHK_FAIL -eq 1 ]; then
    if [ $DEL_COUNT -ge $DEL_THRESHOLD -a $DO_SYNC -eq 0 ]; then
      MSG="Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) violation"
    fi
  
    if [ $DEL_COUNT -ge $DEL_THRESHOLD -a $DO_SYNC -eq 1 ]; then
      MSG="Forced sync with deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) violation"
    fi
  
  if [ $UPDATE_COUNT -ge $UP_THRESHOLD -a $DO_SYNC -eq 0 ]; then
      MSG="Changed files ($UPDATE_COUNT) / ($UP_THRESHOLD) violation"
    fi
  
  if [ $UPDATE_COUNT -ge $UP_THRESHOLD -a $DO_SYNC -eq 1 ]; then
      MSG="Forced sync with changed files ($UPDATE_COUNT) / ($UP_THRESHOLD) violation"
    fi 
  
  if [ $DEL_COUNT -ge  $DEL_THRESHOLD -a $UPDATE_COUNT -ge $UP_THRESHOLD -a $DO_SYNC -eq 0 ]; then
     MSG="Multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
    fi
  
  if [ $DEL_COUNT -ge  $DEL_THRESHOLD -a $UPDATE_COUNT -ge $UP_THRESHOLD -a $DO_SYNC -eq 1 ]; then
     MSG="Sync forced with multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
    fi  
    SUBJECT="[WARNING] $MSG $EMAIL_SUBJECT_PREFIX"
  elif [ -z "${JOBS_DONE##*"SYNC"*}" -a -z "$(grep -w "SYNC_JOB-" $TMP_OUTPUT)" ]; then
    # Sync ran but did not complete successfully so lets warn the user
    SUBJECT="[WARNING] SYNC job ran but did not complete successfully $EMAIL_SUBJECT_PREFIX"
  elif [ -z "${JOBS_DONE##*"SCRUB"*}" -a -z "$(grep -w "SCRUB_JOB-" $TMP_OUTPUT)" ]; then
    # Scrub ran but did not complete successfully so lets warn the user
    SUBJECT="[WARNING] SCRUB job ran but did not complete successfully $EMAIL_SUBJECT_PREFIX"
  else
    SUBJECT="[COMPLETED] $JOBS_DONE Jobs $EMAIL_SUBJECT_PREFIX"
  fi
}

function send_mail(){
  # Format for markdown
  sed_me "s:$:  :" "$TMP_OUTPUT"
  sed  "/^Running TOUCH job to timestamp/,/^\TOUCH finished/{/^Running TOUCH job to timestamp/!{/^TOUCH finished/!d}}; /^###SnapRAID DIFF/,/^\DIFF finished/{/^###SnapRAID DIFF/!{/^DIFF finished/!d}}" $TMP_OUTPUT | $MAIL_BIN -a 'Content-Type: text/html' -s "$SUBJECT" "$EMAIL_ADDRESS" < <(python -m markdown)  
}

function send_mail_verbose(){
  # Format for markdown
  sed_me "s:$:  :" "$TMP_OUTPUT"
  $MAIL_BIN -a 'Content-Type: text/html' -s "$SUBJECT" "$EMAIL_ADDRESS" < $TMP_OUTPUT < <(python -m markdown)  
}

#Due to how process substitution and newer bash versions work, this function stops the output stream which allows wait stops wait from hanging on the tee process.
#If we do not do this and use normal 'wait' the processes will wait forever as newer bash version will wait for the process substitution to finish.
#Probably not the best way of 'fixing' this issue. Someone with more knowledge can provide better insight.
function close_output_and_wait(){
  exec >&$out 2>&$err
  wait $(pgrep -P "$$")
}

# Redirects output to file and screen. Open a new tee process.
function output_to_file_screen(){
  # redirect all output to screen and file
  exec {out}>&1 {err}>&2
  # NOTE: Not preferred format but valid: exec &> >(tee -ia "${TMP_OUTPUT}" )
  exec > >(tee -a "${TMP_OUTPUT}") 2>&1
}

# Sends important messages to syslog
function mklog() {
     [[ "$*" =~ ^([A-Za-z]*):\ (.*) ]] &&
     {
      PRIORITY=${BASH_REMATCH[1]} # INFO, DEBUG, WARN
      LOGMESSAGE=${BASH_REMATCH[2]} # the Log-Message
     }
  echo "$(date '+[%Y-%m-%d %H:%M:%S]') $(basename "$0"): $PRIORITY: '$LOGMESSAGE'" >> $SNAPRAID_LOG
}

# Read SnapRAID version 
SNAPRAIDVERSION="$(snapraid -V | sed -e 's/snapraid v\(.*\)by.*/\1/')"

main "$@"
