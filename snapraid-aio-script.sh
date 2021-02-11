#!/bin/bash
########################################################################
#
#   Project page: https://github.com/auanasgheps/snapraid-aio-script
#
########################################################################

########################
#   CONFIG VARIABLES   #
########################
SNAPSCRIPTVERSION="2.9"

# find the current path
CURRENT_DIR="$(dirname "${0}")"

# import the config file for this script which contain user configuration 
CONFIG_FILE=$CURRENT_DIR/script-config.sh
source $CONFIG_FILE

########################################################################

###################
#   MAIN SCRIPT   #
###################

function main(){
  # create tmp file for output
  > $TMP_OUTPUT

  # Redirect all output to file and screen. Starts a tee process
  output_to_file_screen
 
  # timestamp the job
  echo "SnapRAID Script Job started [`date`]"
  echo "Running SnapRAID version $SNAPRAIDVERSION"
  echo "SnapRAID AIO Script version $SNAPSCRIPTVERSION"
  echo
  echo "----------------------------------------"
  mklog "INFO: ----------------------------------------"
  mklog "INFO: SnapRAID Script Job started"
  mklog "INFO: Running SnapRAID version $SNAPRAIDVERSION"
  mklog "INFO: SnapRAID Script version $SNAPSCRIPTVERSION"

  echo "##Preprocessing"
  
  # Check if script configuration file has been found
  if [ ! -f $CONFIG_FILE ]; 
  then
    echo "Script configuration file not found! The script cannot be run! Please check and try again!"
	mklog "WARN: Script configuration file not found! The script cannot be run! Please check and try again!"
	exit 1;
  else
	echo "Configuration file found! Proceeding."
	mklog "INFO: Script configuration file found! Proceeding."
  fi
  
  # install markdown if not present
  if [ $(dpkg-query -W -f='${Status}' python-markdown 2>/dev/null | grep -c "ok installed") -eq 0 ];
  then
	echo "**Markdown has not been found and will be installed.**"
	mklog "WARN: Markdown has not been found and will be installed."
	# super silent and secret install command 
	export DEBIAN_FRONTEND=noninteractive
	apt-get install -qq -o=Dpkg::Use-Pty=0 python-markdown;
	echo 
  fi
  
  # sanity check first to make sure we can access the content and parity files
  mklog "INFO: Checking SnapRAID disks"
  sanity_check

  # Pause any services that may inhibit optimum execution
  if [ $MANAGE_SERVICES -eq 1 ]; then
    service_array_setup
    echo
    echo "###Pause Services [`date`]"
    pause_services
  fi

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
    echo "SYNC is authorized. [`date`]"
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
    sed_me "s/^Everything OK/**SYNC JOB - Everything OK**/g;s/^Nothing to do/**SYNC JOB - Nothing to do**/g" "$TMP_OUTPUT"
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
	  echo
      echo "Scrub job is cancelled as parity info is out of sync (deleted or changed files threshold has been breached). [`date`]"
    mklog "INFO: Scrub job is cancelled as parity info is out of sync (deleted or changed files threshold has been breached)."
    else
      # NO, delete threshold has not been breached OR we forced a sync, but we have one last test -
      # let's make sure if sync ran, it completed successfully (by checking for our marker text "SYNC JOB -" in the output).
      if [ $DO_SYNC -eq 1 -a -z "$(grep -w "SYNC JOB -" $TMP_OUTPUT)" ]; then
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
        sed_me "s/^Everything OK/**SCRUB JOB - Everything OK**/g;s/^Nothing to do/**SCRUB JOB - Nothing to do**/g" "$TMP_OUTPUT"
      fi
    fi
  else
    echo "Scrub job is not enabled. Not running SCRUB job. [`date`]"
  mklog "INFO: Scrub job is not enabled. Not running SCRUB job."
  fi

  echo
  echo "----------------------------------------"
  echo "##Postprocessing"

  # Show SnapRAID SMART info if enabled
  if [ $SMART_LOG -eq 1 ]; then
    echo
    $SNAPRAID_BIN smart
    close_output_and_wait
    output_to_file_screen
	echo
  fi
  
  # Show SnapRAID Status information if enabled
  if [ $SNAP_STATUS -eq 1 ]; then
    echo
    echo "###SnapRAID Status"
    $SNAPRAID_BIN status
    close_output_and_wait
    output_to_file_screen
	echo
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
  #       hd-idle -t /dev/$DRIVE
  #     fi
  #   done
  # fi

  # Resume paused services
  if [ $MANAGE_SERVICES -eq 1 ]; then
    echo
    echo "###Resume Services [`date`]"
    resume_services
  fi
  
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
	if [ $DEL_COUNT -eq 0 ]; then
	echo "There are no deleted files, that's fine."
	DO_SYNC=1
	else 
    echo "There are deleted files. The number of deleted files ($DEL_COUNT) is below the threshold of ($DEL_THRESHOLD)."
    DO_SYNC=1
	fi
  else
    echo "**WARNING** Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD)."
  mklog "WARN: Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD)."
    CHK_FAIL=1
  fi
}

function chk_updated(){
  if [ $UPDATE_COUNT -lt $UP_THRESHOLD ]; then
	if [ $UPDATE_COUNT -eq 0 ]; then
	echo "There are no updated files, that's fine."
	DO_SYNC=1
	else 
    echo "There are updated files. The number of updated files ($UPDATE_COUNT) is below the threshold of ($UP_THRESHOLD)."
    DO_SYNC=1
	fi
  else
    echo "**WARNING** Updated files ($UPDATE_COUNT) reached/exceeded threshold ($UP_THRESHOLD)."
  mklog "WARN: Updated files ($UPDATE_COUNT) reached/exceeded threshold ($UP_THRESHOLD)."
    CHK_FAIL=1
  fi
}

function chk_sync_warn(){
  if [ $SYNC_WARN_THRESHOLD -gt -1 ]; then
	if [ $SYNC_WARN_THRESHOLD -eq 0 ]; then
	echo "Forced sync is enabled."
  mklog "INFO: Forced sync is enabled."
	else 
	echo "Sync after threshold warning(s) is enabled."
  mklog "INFO: Sync after threshold warning(s) is enabled."
  	fi
    SYNC_WARN_COUNT=$(sed 'q;/^[0-9][0-9]*$/!d' $SYNC_WARN_FILE 2>/dev/null)
    SYNC_WARN_COUNT=${SYNC_WARN_COUNT:-0} #value is zero if file does not exist or does not contain what we are expecting
	if [ $SYNC_WARN_COUNT -ge $SYNC_WARN_THRESHOLD ]; then
	  # force a sync 
	  # if the warn count is zero it means the sync was already forced, do not output a dumb message and continue with the sync job.
      if [ $SYNC_WARN_COUNT -eq 0 ]; then
	  echo
	  DO_SYNC=1
	  else
      # if there is at least one warn count, output a message and force a sync job. Do not need to remove warning marker here as it is automatically removed when the sync job is run by this script
      echo "Number of threshold warning(s) ($SYNC_WARN_COUNT) has reached/exceeded threshold ($SYNC_WARN_THRESHOLD). Forcing a SYNC job to run."
    mklog "INFO: Number of threshold warning(s) ($SYNC_WARN_COUNT) has reached/exceeded threshold ($SYNC_WARN_THRESHOLD). Forcing a SYNC job to run." 
      DO_SYNC=1
	  fi
    else
      # NO, so let's increment the warning count and skip the sync job
      ((SYNC_WARN_COUNT += 1))
      echo $SYNC_WARN_COUNT > $SYNC_WARN_FILE
	  if [ $SYNC_WARN_COUNT == $SYNC_WARN_THRESHOLD ]; then
		echo  "This is the **last** warning left. **NOT** proceeding with SYNC job. [`date`]"
		mklog "This is the **last** warning left. **NOT** proceeding with SYNC job. [`date`]"
		DO_SYNC=0
	  else 
		echo "$((SYNC_WARN_THRESHOLD - SYNC_WARN_COUNT)) threshold warning(s) until the next forced sync. **NOT** proceeding with SYNC job. [`date`]"
		mklog "INFO: $((SYNC_WARN_THRESHOLD - SYNC_WARN_COUNT)) threshold warning(s) until the next forced sync. **NOT** proceeding with SYNC job."
		DO_SYNC=0
    fi
	fi
  else
    # NO, so let's skip SYNC
    echo "Forced sync is not enabled. Check $TMP_OUTPUT for details. **NOT** proceeding with SYNC job. [`date`]"
  mklog "INFO: Forced sync is not enabled. Check $TMP_OUTPUT for details. **NOT** proceeding with SYNC job."
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

function pause_services(){
  for i in ${service_array[@]}; do
    echo "Pausing Service - ""${i^}";
    if [ $DOCKER_REMOTE -eq 1 ]; then
      ssh $DOCKER_USER@$DOCKER_IP docker pause $i
    else
      docker pause $i
    fi
  done
}

function resume_services(){
  for i in ${service_array[@]}; do
    echo "Resuming Service - ""${i^}";
    if [ $DOCKER_REMOTE -eq 1 ]; then
      ssh $DOCKER_USER@$DOCKER_IP docker unpause $i
    else
      docker unpause $i
    fi
  done
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
  elif [ -z "${JOBS_DONE##*"SYNC"*}" -a -z "$(grep -w "SYNC JOB -" $TMP_OUTPUT)" ]; then
    # Sync ran but did not complete successfully so lets warn the user
    SUBJECT="[WARNING] SYNC job ran but did not complete successfully $EMAIL_SUBJECT_PREFIX"
  elif [ -z "${JOBS_DONE##*"SCRUB"*}" -a -z "$(grep -w "SCRUB JOB -" $TMP_OUTPUT)" ]; then
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
