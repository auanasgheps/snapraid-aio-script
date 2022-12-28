#!/bin/bash
########################################################################
#                                      #
#   Project page: https://github.com/auanasgheps/snapraid-aio-script   #
#                                      #
########################################################################

######################
#   CONFIG VARIABLES #
######################
SNAPSCRIPTVERSION="3.2"

# Read SnapRAID version
SNAPRAIDVERSION="$(snapraid -V | sed -e 's/snapraid v\(.*\)by.*/\1/')"

# find the current path
CURRENT_DIR=$(dirname "${0}")
# import the config file for this script which contain user configuration
CONFIG_FILE=$CURRENT_DIR/script-config.sh
#shellcheck source=script-config.sh
source "$CONFIG_FILE"

########################################################################

SYNC_MARKER="SYNC -"
SCRUB_MARKER="SCRUB -"

######################
#   MAIN SCRIPT      #
######################

function main(){
  # create tmp file for output
  true > "$TMP_OUTPUT"

  # Redirect all output to file and screen. Starts a tee process
  output_to_file_screen

  # timestamp the job
  echo "SnapRAID Script Job started [$(date)]"
  echo "Running SnapRAID version $SNAPRAIDVERSION"
  echo "SnapRAID AIO Script version $SNAPSCRIPTVERSION"
  echo "----------------------------------------"
  mklog "INFO: ----------------------------------------"
  mklog "INFO: SnapRAID Script Job started"
  mklog "INFO: Running SnapRAID version $SNAPRAIDVERSION"
  mklog "INFO: SnapRAID Script version $SNAPSCRIPTVERSION"


  echo "## Preprocessing"

  # Initialize notification
  if [ "$HEALTHCHECKS" -eq 1 ] || [ "$TELEGRAM" -eq 1 ] || [ "$DISCORD" -eq 1 ]; then
   # install curl if not found
   if [ "$(dpkg-query -W -f='${Status}' curl 2>/dev/null | grep -c "ok installed")" -eq 0 ]; then
    echo "**Curl has not been found and will be installed.**"
    mklog "WARN: Curl has not been found and will be installed."
    # super silent and secret install command
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -qq -o=Dpkg::Use-Pty=0 curl;
   fi
   # invoke notification services if configured
    if [ "$HEALTHCHECKS" -eq 1 ]; then
   echo "Healthchecks.io notification is enabled. Notifications sent to $HEALTHCHECKS_URL."
   curl -fsS -m 5 --retry 3 -o /dev/null "$HEALTHCHECKS_URL$HEALTHCHECKS_ID"/start
   fi
    if [ "$TELEGRAM" -eq 1 ]; then
   echo "Telegram notification is enabled."
   curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
     -H 'Content-Type: application/json' \
     -d '{"chat_id": "'$TELEGRAM_CHAT_ID'", "text": "SnapRAID Script Job started"}' \
     https://api.telegram.org/bot"$TELEGRAM_TOKEN"/sendMessage
     fi
   if [ "$DISCORD" -eq 1 ]; then
     echo "Discord notification is enabled."
     curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
     -H 'Content-Type: application/json' \
     -d '{"content": "SnapRAID Script Job started"}' \
     "$DISCORD_WEBHOOK_URL"
    fi
  fi

  if [ "$RETENTION_DAYS" -gt 0 ]; then
  echo "SnapRAID output retention is enabled. Detailed logs will be kept in $SNAPRAID_LOG_DIR for $RETENTION_DAYS days."
  fi

  # Check if script configuration file has been found, if not send a message
  # to syslog and exit
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Script configuration file not found! The script cannot be run! Please check and try again!"
    mklog_noconfig "WARN: Script configuration file not found! The script cannot be run! Please check and try again!"
    exit 1;
  # check if the config file has the correct version
  elif [ "$CONFIG_VERSION" != "$SNAPSCRIPTVERSION" ]; then
    echo "Please update your config file to the latest version. The current file is not compatible with this script!"
    mklog "WARN: Please update your config file to the latest version. The current file is not compatible with this script!"
    if [ "$EMAIL_ADDRESS" ]; then
      SUBJECT="[WARNING] - Configuration Error $EMAIL_SUBJECT_PREFIX"
      NOTIFY_OUTPUT="$SUBJECT"
      trim_log < "$TMP_OUTPUT" | send_mail
      notify_warning
    fi
    exit 1;
  else
    echo "Configuration file found."
    mklog "INFO: Script configuration file found."
  fi

  # install markdown if not found
  if [ "$(dpkg-query -W -f='${Status}' python3-markdown 2>/dev/null | grep -c "ok installed")" -eq 0 ]; then
    echo "**Markdown has not been found and will be installed.**"
    mklog "WARN: Markdown has not been found and will be installed."
    # super silent and secret install command
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -qq -o=Dpkg::Use-Pty=0 python3-markdown;
  fi

  # sanity check first to make sure we can access the content and parity files
  mklog "INFO: Checking SnapRAID disks"
  sanity_check

  # pause configured containers
  if [ "$MANAGE_SERVICES" -eq 1 ]; then
   service_array_setup
    if [ "$DOCKERALLOK" = YES ]; then
     echo
      if [ "$DOCKER_MODE" = 1 ]; then
       echo "### Pausing Containers [$(date)]";
       else
       echo "### Stopping Containers [$(date)]";
      fi
     pause_services
    fi
  fi

  # Custom Hook - Before
  if [ "$CUSTOM_HOOK" -eq 1 ]; then
    echo "### Custom Hook [$BEFORE_HOOK_NAME]";
    bash -c "$BEFORE_HOOK_CMD"
  fi

  echo "----------------------------------------"
  echo "## Processing"

  # Fix timestamps
  chk_zero

  # run the snapraid DIFF command
  echo "### SnapRAID DIFF [$(date)]"
  mklog "INFO: SnapRAID DIFF started"
  echo "\`\`\`"
  $SNAPRAID_BIN diff
  close_output_and_wait
  output_to_file_screen
  echo "\`\`\`"
  echo "DIFF finished [$(date)]"
  mklog "INFO: SnapRAID DIFF finished"
  JOBS_DONE="DIFF"

  # Get number of deleted, updated, and modified files...
  get_counts

  # sanity check to make sure that we were able to get our counts from the
  # output of the DIFF job
  if [ -z "$DEL_COUNT" ] || [ -z "$ADD_COUNT" ] || [ -z "$MOVE_COUNT" ] || [ -z "$COPY_COUNT" ] || [ -z "$UPDATE_COUNT" ]; then
    # failed to get one or more of the count values, lets report to user and
    # exit with error code
    echo "**ERROR** - Failed to get one or more count values. Unable to continue."
    mklog "WARN: Failed to get one or more count values. Unable to continue."
    echo "Exiting script. [$(date)]"
    if [ "$EMAIL_ADDRESS" ]; then
      SUBJECT="[WARNING] - Unable to continue with SYNC/SCRUB job(s). Check DIFF job output. $EMAIL_SUBJECT_PREFIX"
        NOTIFY_OUTPUT="$SUBJECT"
      trim_log < "$TMP_OUTPUT" | send_mail
      notify_warning
    fi
    exit 1;
  fi
  echo "**SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]**"
  mklog "INFO: SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]"

  # check if the conditions to run SYNC are met
  # CHK 1 - if files have changed
  if [ "$DEL_COUNT" -gt 0 ] || [ "$ADD_COUNT" -gt 0 ] || [ "$MOVE_COUNT" -gt 0 ] || [ "$COPY_COUNT" -gt 0 ] || [ "$UPDATE_COUNT" -gt 0 ]; then
    chk_del

    if [ "$CHK_FAIL" -eq 0 ]; then
      chk_updated
    fi

    if [ "$CHK_FAIL" -eq 1 ]; then
      chk_sync_warn
    fi
  else
    # NO, so let's skip SYNC
    echo "No change detected. Not running SYNC job. [$(date)]"
    mklog "INFO: No change detected. Not running SYNC job."
    DO_SYNC=0
  fi

  # Now run sync if conditions are met
  if [ "$DO_SYNC" -eq 1 ]; then
    echo "SYNC is authorized. [$(date)]"
    echo "### SnapRAID SYNC [$(date)]"
    mklog "INFO: SnapRAID SYNC Job started"
    echo "\`\`\`"
    if [ "$PREHASH" -eq 1 ] && [ "$FORCE_ZERO" -eq 1 ]; then
      $SNAPRAID_BIN sync -h --force-zero -q
    elif [ "$PREHASH" -eq 1 ]; then
      $SNAPRAID_BIN sync -h -q
    elif [ "$FORCE_ZERO" -eq 1 ]; then
      $SNAPRAID_BIN sync --force-zero -q
    else
      $SNAPRAID_BIN sync -q
    fi
    close_output_and_wait
    output_to_file_screen
    echo "\`\`\`"
    echo "SYNC finished [$(date)]"
    mklog "INFO: SnapRAID SYNC Job finished"
    JOBS_DONE="$JOBS_DONE + SYNC"
    # insert SYNC marker to 'Everything OK' or 'Nothing to do' string to
    # differentiate it from SCRUB job later
    sed_me "
      s/^Everything OK/${SYNC_MARKER} Everything OK/g;
      s/^Nothing to do/${SYNC_MARKER} Nothing to do/g" "$TMP_OUTPUT"
    # Remove any warning flags if set previously. This is done in this step to
    # take care of scenarios when user has manually synced or restored deleted
    # files and we will have missed it in the checks above.
    if [ -e "$SYNC_WARN_FILE" ]; then
      rm "$SYNC_WARN_FILE"
    fi
  fi

  # Moving onto scrub now. Check if user has enabled scrub
  echo "### SnapRAID SCRUB [$(date)]"
    mklog "INFO: SnapRAID SCRUB Job started"
  if [ "$SCRUB_PERCENT" -gt 0 ]; then
    # YES, first let's check if delete threshold has been breached and we have
    # not forced a sync.
    if [ "$CHK_FAIL" -eq 1 ] && [ "$DO_SYNC" -eq 0 ]; then
      # YES, parity is out of sync so let's not run scrub job
      echo "Parity info is out of sync (deleted or changed files threshold has been breached)."
      echo "Not running SCRUB job. [$(date)]"
      mklog "INFO: Parity info is out of sync (deleted or changed files threshold has been breached). Not running SCRUB job."
    else
      # NO, delete threshold has not been breached OR we forced a sync, but we
      # have one last test - let's make sure if sync ran, it completed
      # successfully (by checking for the marker text in the output).
      if [ "$DO_SYNC" -eq 1 ] && ! grep -qw "$SYNC_MARKER" "$TMP_OUTPUT"; then
        # Sync ran but did not complete successfully so lets not run scrub to
        # be safe
        echo "**WARNING!** - Check output of SYNC job. Could not detect marker."
        echo "Not running SCRUB job. [$(date)]"
        mklog "WARN: Check output of SYNC job. Could not detect marker. Not running SCRUB job."
      else
        # Everything ok - ready to run the scrub job!
        # The fuction will check if scrub delayed run is enabled and run scrub
        # based on configured conditions
        chk_scrub_settings
      fi
    fi
  else
    echo "Scrub job is not enabled. "
    echo "Not running SCRUB job. [$(date)]"
    mklog "INFO: Scrub job is not enabled. Not running SCRUB job."
  fi

  echo "----------------------------------------"
  echo "## Postprocessing"

  # Show SnapRAID SMART info if enabled
  if [ "$SMART_LOG" -eq 1 ]; then
    echo "### SnapRAID Smart"
    echo "\`\`\`"
    $SNAPRAID_BIN smart
    close_output_and_wait
    output_to_file_screen
    echo "\`\`\`"
  fi

  # Show SnapRAID Status information if enabled
  if [ "$SNAP_STATUS" -eq 1 ]; then
    echo "### SnapRAID Status"
    echo "\`\`\`"
    $SNAPRAID_BIN status
    close_output_and_wait
    output_to_file_screen
    echo "\`\`\`"
  fi

  # Spinning down disks (Method 1: snapraid - preferred)
  # if [ "$SPINDOWN" -eq 1 ]; then
  #  echo "### SnapRAID Spindown"
  #  echo "\`\`\`"
  #  $SNAPRAID_BIN down
  #  close_output_and_wait
  #  output_to_file_screen
  #  echo "\`\`\`"
  #fi

  # Spinning down disks (Method 2: hdparm - spins down all rotational devices)
  # if [ $SPINDOWN -eq 1 ]; then
  # for DRIVE in `lsblk -d -o name | tail -n +2`
  #   do
  #     if [[ `smartctl -a /dev/$DRIVE | grep 'Rotation Rate' | grep rpm` ]]; then
  #       hdparm -Y /dev/$DRIVE
  #     fi
  #   done
  # fi

# Spin down disks (Method 3: hd-idle - spins down all rotational devices)
  if [ "$SPINDOWN" -eq 1 ]; then
   for DRIVE in $(lsblk -d -o name | tail -n +2)
     do
       if [[ $(smartctl -a /dev/"$DRIVE" | grep 'Rotation Rate' | grep rpm) ]]; then
         echo "spinning down /dev/$DRIVE"
         hd-idle -t /dev/"$DRIVE"
       fi
     done
   fi

  # Resume paused containers
  if [ "$SERVICES_STOPPED" -eq 1 ]; then
    echo
      if [ "$DOCKER_MODE" = 1 ]; then
        echo "### Resuming Containers [$(date)]";
    else
    echo "### Restarting Containers [$(date)]";
      fi
    resume_services
  fi

  # Custom Hook - After
  if [ "$CUSTOM_HOOK" -eq 1 ]; then
    echo "### Custom Hook - [$AFTER_HOOK_NAME]";
    bash -c "$AFTER_HOOK_CMD"
  fi

  echo "All jobs ended. [$(date)]"
  mklog "INFO: Snapraid: all jobs ended."

  # all jobs done, let's send output to user if configured
  if [ "$EMAIL_ADDRESS" ] || [ -x "$HOOK_NOTIFICATION" ]; then
    # check snapraid output and build the message subject, then send notifications if enabled
    prepare_mail

    ELAPSED="$((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
    echo "----------------------------------------"
    echo "## Total time elapsed for SnapRAID: $ELAPSED"
    mklog "INFO: Total time elapsed for SnapRAID: $ELAPSED"

    # Add a topline to email body and send a long mail
    sed_me "1s:^:##$SUBJECT \n:" "${TMP_OUTPUT}"
    if [ "$VERBOSITY" -eq 1 ]; then
      send_mail < "$TMP_OUTPUT"
    else
    # or send a short mail
     trim_log < "$TMP_OUTPUT" | send_mail
    fi
  fi

  # Save and rotate logs if enabled
  if [ "$RETENTION_DAYS" -gt 0 ]; then
    find "$SNAPRAID_LOG_DIR"/SnapRAID-* -mtime +"$RETENTION_DAYS" -delete  # delete old logs
    cp $TMP_OUTPUT "$SNAPRAID_LOG_DIR"/SnapRAID-"$(date +"%Y_%m_%d-%H%M")".out
  fi

  # exit with success, letting the trap handle cleanup of file descriptors
  exit 0;
}

#######################
# FUNCTIONS & METHODS #
#######################

function sanity_check() {
  echo "Checking if all parity and content files are present."
  mklog "INFO: Checking if all parity and content files are present."
  for i in "${PARITY_FILES[@]}"; do
    if [ ! -e "$i" ]; then
    echo "[$(date)] ERROR - Parity file ($i) not found!"
    echo "ERROR - Parity file ($i) not found!" >> "$TMP_OUTPUT"
    echo "**ERROR**: Please check the status of your disks! The script exits here due to missing file or disk."
    mklog "WARN: Parity file ($i) not found!"
    mklog "WARN: Please check the status of your disks! The script exits here due to missing file or disk."

    # Add a topline to email body
    SUBJECT="[WARNING] - Parity file ($i) not found! $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT"
    trim_log < "$TMP_OUTPUT" | send_mail
    notify_warning
    exit 1;
  fi
  done
  echo "All parity files found."
  mklog "INFO: All parity files found."

  for i in "${CONTENT_FILES[@]}"; do
    if [ ! -e "$i" ]; then
      echo "[$(date)] ERROR - Content file ($i) not found!"
      echo "ERROR - Content file ($i) not found!" >> "$TMP_OUTPUT"
      echo "**ERROR**: Please check the status of your disks! The script exits here due to missing file or disk."
      mklog "WARN: Content file ($i) not found!"
      mklog "WARN: Please check the status of your disks! The script exits here due to missing file or disk."

      # Add a topline to email body
      SUBJECT="[WARNING] - Content file ($i) not found! $EMAIL_SUBJECT_PREFIX"
      NOTIFY_OUTPUT="$SUBJECT"
      trim_log < "$TMP_OUTPUT" | send_mail
      notify_warning
    exit 1;
   fi
  done
  echo "All content files found."
  mklog "INFO: All content files found."
}

function get_counts() {
  EQ_COUNT=$(grep -w '^ \{1,\}[0-9]* equal' "$TMP_OUTPUT" | sed 's/^ *//g' | cut -d ' ' -f1)
  ADD_COUNT=$(grep -w '^ \{1,\}[0-9]* added' "$TMP_OUTPUT" | sed 's/^ *//g' | cut -d ' ' -f1)
  DEL_COUNT=$(grep -w '^ \{1,\}[0-9]* removed' "$TMP_OUTPUT" | sed 's/^ *//g' | cut -d ' ' -f1)
  UPDATE_COUNT=$(grep -w '^ \{1,\}[0-9]* updated' "$TMP_OUTPUT" | sed 's/^ *//g' | cut -d ' ' -f1)
  MOVE_COUNT=$(grep -w '^ \{1,\}[0-9]* moved' "$TMP_OUTPUT" | sed 's/^ *//g' | cut -d ' ' -f1)
  COPY_COUNT=$(grep -w '^ \{1,\}[0-9]* copied' "$TMP_OUTPUT" | sed 's/^ *//g' | cut -d ' ' -f1)
  # REST_COUNT=$(grep -w '^ \{1,\}[0-9]* restored' $TMP_OUTPUT | sed 's/^ *//g' | cut -d ' ' -f1)
}

function sed_me(){
  # Close the open output stream first, then perform sed and open a new tee
  # process and redirect output. We close stream because of the calls to new
  # wait function in between sed_me calls. If we do not do this we try to close
  # Processes which are not parents of the shell.
  exec >& "$OUT" 2>& "$ERROR"
  sed -i "$1" "$2"

  output_to_file_screen
}

function chk_del(){
  if [ "$DEL_COUNT" -eq 0 ]; then
    echo "There are no deleted files, that's fine."
    DO_SYNC=1
  elif [ "$DEL_COUNT" -lt "$DEL_THRESHOLD" ]; then
    echo "There are deleted files. The number of deleted files ($DEL_COUNT) is below the threshold of ($DEL_THRESHOLD)."
    DO_SYNC=1
  elif awk "BEGIN {exit !($ADD_DEL_THRESHOLD > 0)}"; then
    ADD_DEL_RATIO="$(awk -v a=$ADD_COUNT -v b=$DEL_COUNT 'BEGIN {print ( a / b )}')"
    if awk "BEGIN {exit !($ADD_DEL_RATIO >= $ADD_DEL_THRESHOLD)}"; then
      echo "There are deleted files. The number of deleted files ($DEL_COUNT) is above the threshold of ($DEL_THRESHOLD)"
      echo "but the add/delete ratio of ($ADD_DEL_RATIO) is above the threshold of ($ADD_DEL_THRESHOLD), sync will proceed."
      DO_SYNC=1
    else
      echo "**WARNING!** Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD) and add/delete threshold ($ADD_DEL_THRESHOLD) was not met."
      mklog "WARN: Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD) and add/delete threshold ($ADD_DEL_THRESHOLD) was not met."
      CHK_FAIL=1
    fi
  else
    if [ "$RETENTION_DAYS" -gt 0 ]; then
     echo "**WARNING!** Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD)."
     echo "For more information, please check the DIFF ouput saved in $SNAPRAID_LOG_DIR."
     mklog "WARN: Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD)."
     CHK_FAIL=1
    else
     echo "**WARNING!** Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD)."
     mklog "WARN: Deleted files ($DEL_COUNT) reached/exceeded threshold ($DEL_THRESHOLD)."
     CHK_FAIL=1
    fi
  fi
}

function chk_updated(){
  if [ "$UPDATE_COUNT" -lt "$UP_THRESHOLD" ]; then
    if [ "$UPDATE_COUNT" -eq 0 ]; then
      echo "There are no updated files, that's fine."
      DO_SYNC=1
    else
      echo "There are updated files. The number of updated files ($UPDATE_COUNT) is below the threshold of ($UP_THRESHOLD)."
      DO_SYNC=1
    fi
  else
    if [ "$RETENTION_DAYS" -gt 0 ]; then
     echo "**WARNING!** Updated files ($UPDATE_COUNT) reached/exceeded threshold ($UP_THRESHOLD)."
     echo "For more information, please check the DIFF ouput saved in $SNAPRAID_LOG_DIR."
     mklog "WARN: Updated files ($UPDATE_COUNT) reached/exceeded threshold ($UP_THRESHOLD)."
     CHK_FAIL=1
    else
     echo "**WARNING!** Updated files ($UPDATE_COUNT) reached/exceeded threshold ($UP_THRESHOLD)."
     mklog "WARN: Updated files ($UPDATE_COUNT) reached/exceeded threshold ($UP_THRESHOLD)."
     CHK_FAIL=1
    fi
  fi
}

function chk_sync_warn(){
  if [ "$SYNC_WARN_THRESHOLD" -gt -1 ]; then
    if [ "$SYNC_WARN_THRESHOLD" -eq 0 ]; then
      echo "Forced sync is enabled."
      mklog "INFO: Forced sync is enabled."
    else
      echo "Sync after threshold warning(s) is enabled."
      mklog "INFO: Sync after threshold warning(s) is enabled."
    fi

    local sync_warn_count
    sync_warn_count=$(sed '/^[0-9]*$/!d' "$SYNC_WARN_FILE" 2>/dev/null)
    # zero if file does not exist or did not contain a number
    : "${sync_warn_count:=0}"

    if [ "$sync_warn_count" -ge "$SYNC_WARN_THRESHOLD" ]; then
      # Force a sync. If the warn count is zero it means the sync was already
      # forced, do not output a dumb message and continue with the sync job.
      if [ "$sync_warn_count" -eq 0 ]; then
        DO_SYNC=1
      else
        # If there is at least one warn count, output a message and force a
        # sync job. Do not need to remove warning marker here as it is
        # automatically removed when the sync job is run by this script
        echo "Number of threshold warning(s) ($sync_warn_count) has reached/exceeded threshold ($SYNC_WARN_THRESHOLD). Forcing a SYNC job to run."
        mklog "INFO: Number of threshold warning(s) ($sync_warn_count) has reached/exceeded threshold ($SYNC_WARN_THRESHOLD). Forcing a SYNC job to run."
        DO_SYNC=1
      fi
    else
      # NO, so let's increment the warning count and skip the sync job
      ((sync_warn_count += 1))
      echo "$sync_warn_count" > "$SYNC_WARN_FILE"
      if [ "$sync_warn_count" == "$SYNC_WARN_THRESHOLD" ]; then
        echo  "This is the **last** warning left. **NOT** proceeding with SYNC job. [$(date)]"
        mklog "INFO: This is the **last** warning left. **NOT** proceeding with SYNC job. [$(date)]"
        DO_SYNC=0
      else
        echo "$((SYNC_WARN_THRESHOLD - sync_warn_count)) threshold warning(s) until the next forced sync. **NOT** proceeding with SYNC job. [$(date)]"
        mklog "INFO: $((SYNC_WARN_THRESHOLD - sync_warn_count)) threshold warning(s) until the next forced sync. **NOT** proceeding with SYNC job."
        DO_SYNC=0
      fi
    fi
  else
    # NO, so let's skip SYNC
    if [ "$RETENTION_DAYS" -gt 0 ]; then
    echo "Forced sync is not enabled. **NOT** proceeding with SYNC job. [$(date)]"
    mklog "INFO: Forced sync is not enabled. **NOT** proceeding with SYNC job."
    DO_SYNC=0
    else
    echo "Forced sync is not enabled. Check $TMP_OUTPUT for details. **NOT** proceeding with SYNC job. [$(date)]"
    mklog "INFO: Forced sync is not enabled. Check $TMP_OUTPUT for details. **NOT** proceeding with SYNC job."
    DO_SYNC=0
    fi
  fi
}

function chk_zero(){
  echo "### SnapRAID TOUCH [$(date)]"
  echo "Checking for zero sub-second files."
  TIMESTATUS=$($SNAPRAID_BIN status | grep 'You have [1-9][0-9]* files with zero sub-second timestamp\.' | sed 's/^You have/Found/g')
  if [ -n "$TIMESTATUS" ]; then
    echo "$TIMESTATUS"
    echo "Running TOUCH job to timestamp. [$(date)]"
    echo "\`\`\`"
    $SNAPRAID_BIN touch
    close_output_and_wait
    output_to_file_screen
    echo "\`\`\`"
  else
    echo "No zero sub-second timestamp files found."
  fi
  echo "TOUCH finished [$(date)]"
}

function chk_scrub_settings(){
    if [ "$SCRUB_DELAYED_RUN" -gt 0 ]; then
    echo "Delayed scrub is enabled."
    mklog "INFO: Delayed scrub is enabled.."
  fi

    local scrub_count
  scrub_count=$(sed '/^[0-9]*$/!d' "$SCRUB_COUNT_FILE" 2>/dev/null)
  # zero if file does not exist or did not contain a number
  : "${scrub_count:=0}"

    if [ "$scrub_count" -ge "$SCRUB_DELAYED_RUN" ]; then
    # Run a scrub job. if the warn count is zero it means the scrub was already
    # forced, do not output a dumb message and continue with the scrub job.
    if [ "$scrub_count" -eq 0 ]; then
      echo
      run_scrub
    else
      # if there is at least one warn count, output a message and force a scrub
      # job. Do not need to remove warning marker here as it is automatically
      # removed when the scrub job is run by this script
      echo "Number of delayed runs has reached/exceeded threshold ($SCRUB_DELAYED_RUN). A SCRUB job will run."
      mklog "INFO: Number of delayed runs has reached/exceeded threshold ($SCRUB_DELAYED_RUN). A SCRUB job will run."
      echo
      run_scrub
    fi
    else
    # NO, so let's increment the warning count and skip the scrub job
    ((scrub_count += 1))
    echo "$scrub_count" > "$SCRUB_COUNT_FILE"
    if [ "$scrub_count" == "$SCRUB_DELAYED_RUN" ]; then
      echo  "This is the **last** run left before running scrub job next time. [$(date)]"
      mklog "INFO: This is the **last** run left before running scrub job next time. [$(date)]"
    else
      echo "$((SCRUB_DELAYED_RUN - scrub_count)) runs until the next scrub. **NOT** proceeding with SCRUB job. [$(date)]"
      mklog "INFO: $((SCRUB_DELAYED_RUN - scrub_count)) runs until the next scrub. **NOT** proceeding with SCRUB job. [$(date)]"
    fi
    fi
}

function run_scrub(){
  if [ "$SCRUB_NEW" -eq 1 ]; then
  echo "SCRUB New Blocks [$(date)]"
    echo "\`\`\`"
    $SNAPRAID_BIN scrub -p new -q
    close_output_and_wait
    output_to_file_screen
    echo "\`\`\`"
  fi
  echo "SCRUB Previous Blocks [$(date)]"
  echo "\`\`\`"
  $SNAPRAID_BIN scrub -p "$SCRUB_PERCENT" -o "$SCRUB_AGE" -q
  close_output_and_wait
  output_to_file_screen
  echo "\`\`\`"
  echo "SCRUB finished [$(date)]"
  mklog "INFO: SnapRAID SCRUB Job(s) finished"
  JOBS_DONE="$JOBS_DONE + SCRUB"
  # insert SCRUB marker to 'Everything OK' or 'Nothing to do' string to
  # differentiate it from SYNC job above
  sed_me "
    s/^Everything OK/${SCRUB_MARKER} Everything OK/g;
    s/^Nothing to do/${SCRUB_MARKER} Nothing to do/g" "$TMP_OUTPUT"
  # Remove the warning flag if set previously. This is done now to
  # take care of scenarios when user has manually synced or restored
  # deleted files and we will have missed it in the checks above.
  if [ -e "$SCRUB_COUNT_FILE" ]; then
    rm "$SCRUB_COUNT_FILE"
  fi
}

function service_array_setup() {
  # check if container names are set correctly
  if [ -z "$SERVICES" ] && [ -z "$DOCKER_HOST_SERVICES" ]; then
   echo "Please configure Containers. Unable to manage containers."
   ARRAY_VALIDATED=NO
  else
   echo "Docker containers management is enabled."
   ARRAY_VALIDATED=YES
  fi

  # check what docker mode is set
  if [ "$DOCKER_MODE" = 1 ]; then
   DOCKER_CMD1=pause
   DOCKER_CMD2=unpause
   DOCKERCMD_VALIDATED=YES
  elif [ "$DOCKER_MODE" = 2 ]; then
   DOCKER_CMD1=stop
   DOCKER_CMD2=start
   DOCKERCMD_VALIDATED=YES
  else
   echo "Please check your command configuration. Unable to manage containers."
   DOCKERCMD_VALIDATED=NO
  fi

  # validate docker configuration
  if [ "$ARRAY_VALIDATED" = YES ] && [ "$DOCKERCMD_VALIDATED" = YES ]; then
   DOCKERALLOK=YES
  else
   DOCKERALLOK=NO
  fi
}

function pause_services(){
  if [ "$DOCKER_REMOTE" -eq 1 ]; then
   for i in "${DOCKER_HOST_SERVICES[@]}"; do
    # delete previous array/list (this is crucial!)
    unset remote_service_array
    # split sub-list if available
    if [[ $i == *":"* ]]
     then
      # split host name from services
      tmpArray=(${i//:/ })
      REMOTE_HOST=${tmpArray[0]}
      REMOTE_SERVICES=${tmpArray[1]}
    fi
    # make array from simple string
    IFS=',' read -r -a remote_service_array <<<"$REMOTE_SERVICES"
    # Loop over services
    for j in "${remote_service_array[@]}"; do
     if [ "$DOCKER_MODE" = 1 ]; then
      echo "Pausing Container - ""${j^}";
     else
      echo "Stopping Container - ""${j^}";
     fi
      ssh "$DOCKER_USER"@"$REMOTE_HOST" docker "$DOCKER_CMD1" "$j"
     sleep "$DOCKER_DELAY"
    done
   done
  else
   IFS=' ' read -r -a service_array <<<"$SERVICES"
   for i in "${service_array[@]}"; do
    if [ "$DOCKER_MODE" = 1 ]; then
     echo "Pausing Container - ""${i^}";
    else
     echo "Stopping Container - ""${i^}";
    fi
    docker "$DOCKER_CMD1" "$i"
   done
  fi
  SERVICES_STOPPED=1
  unset IFS
}

function resume_services(){
  if [ "$SERVICES_STOPPED" -eq 1 ]; then
   if [ "$DOCKER_REMOTE" -eq 1 ]; then
    for i in "${DOCKER_HOST_SERVICES[@]}"; do
     # delete previous array/list (this is crucial!)
     unset remote_service_array
     # split sub-list if available
     if [[ $i == *":"* ]]
      then
       # split host name from services
       tmpArray=(${i//:/ })
       REMOTE_HOST=${tmpArray[0]}
       REMOTE_SERVICES=${tmpArray[1]}
     fi
     # make array from simple string
     IFS=',' read -r -a remote_service_array <<<"$REMOTE_SERVICES"
     # Loop over services
     for j in "${remote_service_array[@]}"; do
      if [ "$DOCKER_MODE" = 1 ]; then
       echo "Resuming Container - ""${j^}";
      else
       echo "Restarting Container - ""${j^}";
      fi
      ssh "$DOCKER_USER"@"$REMOTE_HOST" docker "$DOCKER_CMD2" "$j"
      sleep "$DOCKER_DELAY"
     done
    done
   else
    IFS=' ' read -r -a service_array <<<"$SERVICES"
    for i in "${service_array[@]}"; do
     if [ "$DOCKER_MODE" = 1 ]; then
      echo "Resuming Container - ""${i^}";
     else
      echo "Restarting Container - ""${i^}";
     fi
      docker "$DOCKER_CMD2" "$i"
    done
   fi
   SERVICES_STOPPED=0
   unset IFS
  fi
}

function clean_desc(){
  [[ $- == *i* ]] && exec &>/dev/tty
 }

function final_cleanup(){
  resume_services
  clean_desc
  exit
}

function prepare_mail() {
  if [ $CHK_FAIL -eq 1 ]; then
    if [ "$DEL_COUNT" -ge "$DEL_THRESHOLD" ] && [ "$DO_SYNC" -eq 0 ]; then
      MSG="Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) violation"
      if awk "BEGIN {exit !($ADD_DEL_RATIO < $ADD_DEL_THRESHOLD)}"; then
        MSG="Multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) and add/delete ratio ($ADD_DEL_RATIO) / ($ADD_DEL_THRESHOLD)"
      fi
    fi

    if [ "$DEL_COUNT" -ge "$DEL_THRESHOLD" ] && [ "$DO_SYNC" -eq 1 ]; then
      MSG="Forced sync with deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) violation"
      if awk "BEGIN {exit !($ADD_DEL_RATIO < $ADD_DEL_THRESHOLD)}"; then
        MSG="Sync forced with multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) and add/delete ratio ($ADD_DEL_RATIO) / ($ADD_DEL_THRESHOLD)"
      fi
    fi

    if [ "$UPDATE_COUNT" -ge "$UP_THRESHOLD" ] && [ "$DO_SYNC" -eq 0 ]; then
      MSG="Changed files ($UPDATE_COUNT) / ($UP_THRESHOLD) violation"
    fi

    if [ "$UPDATE_COUNT" -ge "$UP_THRESHOLD" ] && [ "$DO_SYNC" -eq 1 ]; then
      MSG="Forced sync with changed files ($UPDATE_COUNT) / ($UP_THRESHOLD) violation"
    fi

    if [ "$DEL_COUNT" -ge  "$DEL_THRESHOLD" ] && [ "$UPDATE_COUNT" -ge "$UP_THRESHOLD" ] && [ "$DO_SYNC" -eq 0 ]; then
      MSG="Multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
      if awk "BEGIN {exit !($ADD_DEL_RATIO < $ADD_DEL_THRESHOLD)}"; then
        MSG="Multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD), add/delete ratio ($ADD_DEL_RATIO) / ($ADD_DEL_THRESHOLD), and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
      fi
    fi

    if [ "$DEL_COUNT" -ge  "$DEL_THRESHOLD" ] && [ "$UPDATE_COUNT" -ge "$UP_THRESHOLD" ] && [ "$DO_SYNC" -eq 1 ]; then
      MSG="Sync forced with multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
      if awk "BEGIN {exit !($ADD_DEL_RATIO < $ADD_DEL_THRESHOLD)}"; then
        MSG="Sync forced with multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD), add/delete ratio ($ADD_DEL_RATIO) / ($ADD_DEL_THRESHOLD), and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
      fi
    fi
    SUBJECT="[WARNING] $MSG $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT"
    notify_warning
  elif [ -z "${JOBS_DONE##*"SYNC"*}" ] && ! grep -qw "$SYNC_MARKER" "$TMP_OUTPUT"; then
    # Sync ran but did not complete successfully so lets warn the user
    SUBJECT="[WARNING] SYNC job ran but did not complete successfully $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT"
    notify_warning
  elif [ -z "${JOBS_DONE##*"SCRUB"*}" ] && ! grep -qw "$SCRUB_MARKER" "$TMP_OUTPUT"; then
    # Scrub ran but did not complete successfully so lets warn the user
    SUBJECT="[WARNING] SCRUB job ran but did not complete successfully $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT
SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]"
    notify_warning
  else
    SUBJECT="[COMPLETED] $JOBS_DONE Jobs $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT
SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]"
    notify_success
  fi
}

function notify_success(){
  if [ "$HEALTHCHECKS" -eq 1 ]; then
   curl -fsS -m 5 --retry 3 -o /dev/null "$HEALTHCHECKS_URL$HEALTHCHECKS_ID"/0 --data-raw "$NOTIFY_OUTPUT"
  fi
  if [ "$TELEGRAM" -eq 1 ]; then
   curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
   -H 'Content-Type: application/json' \
   -d '{"chat_id": "'"$TELEGRAM_CHAT_ID"'", "text": "'"$NOTIFY_OUTPUT"'"}' \
   https://api.telegram.org/bot"$TELEGRAM_TOKEN"/sendMessage
  fi
  if [ "$DISCORD" -eq 1 ]; then
   curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
   -H 'Content-Type: application/json' \
   -d '{"content": "'"$SUBJECT"'"}' \
   "$DISCORD_WEBHOOK_URL"
  fi
  }

function notify_warning(){
  if [ "$HEALTHCHECKS" -eq 1 ]; then
   curl -fsS -m 5 --retry 3 -o /dev/null "$HEALTHCHECKS_URL$HEALTHCHECKS_ID"/fail --data-raw "$NOTIFY_OUTPUT"
  fi
  if [ "$TELEGRAM" -eq 1 ]; then
   curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
   -H 'Content-Type: application/json' \
   -d '{"chat_id": "'"$TELEGRAM_CHAT_ID"'", "text": "'"$NOTIFY_OUTPUT"'"}' \
   https://api.telegram.org/bot"$TELEGRAM_TOKEN"/sendMessage
  fi
  if [ "$DISCORD" -eq 1 ]; then
   curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
   -H 'Content-Type: application/json' \
   -d '{"content": "'"$SUBJECT"'"}' \
   "$DISCORD_WEBHOOK_URL"
  fi
  }

# Trim the log file read from stdin.
function trim_log(){
  sed '
    /^Running TOUCH job to timestamp/,/^\TOUCH finished/{
      /^Running TOUCH job to timestamp/!{/^TOUCH finished/!d}
    };
    /^### SnapRAID DIFF/,/^\DIFF finished/{
      /^### SnapRAID DIFF/!{/^DIFF finished/!d}
    }'
  }

# Process and mail the email body read from stdin.
function send_mail(){
  local body; body=$(cat)
  # Send the raw $body and append the HTML.
  # Try to workaround py markdown 2.6.8 issues:
  # 1. Will not format code blocks with empty lines, so just remove
  #    them.
  # 2. A dash line inside of code block brekas it, so remove it.
  # 3. Add trailing double-spaces ensures the line endings are
  #    maintained.
  # 4. The HTML code blocks need to be modified to use <pre></pre> to display
  #    correctly.

  body=$(echo "$body" | sed '/^[[:space:]]*$/d; /^ -*$/d; s/$/  /' |
      python3 -m markdown |
      sed 's/<code>/<pre>/;s%</code>%</pre>%')

  if [ -x "$HOOK_NOTIFICATION" ]; then
    echo -e "Notification user script is set. Calling it now [$(date)]"
    $HOOK_NOTIFICATION "$SUBJECT" "$body"
  else
    echo -e "Email address is set. Sending email report to **$EMAIL_ADDRESS** [$(date)]"
    $MAIL_BIN -a 'Content-Type: text/html' -s "$SUBJECT" -r "$FROM_EMAIL_ADDRESS" "$EMAIL_ADDRESS" \
      < <(echo "$body")
  fi
}

# Due to how process substitution and newer bash versions work, this function
# stops the output stream which allows wait stops wait from hanging on the tee
# process. If we do not do this and use normal 'wait' the processes will wait
# forever as newer bash version will wait for the process substitution to
# finish. Probably not the best way of 'fixing' this issue. Someone with more
# knowledge can provide better insight.
function close_output_and_wait(){
  exec >& "$OUT" 2>& "$ERROR"
  CHILD_PID=$(pgrep -P $$)
  if [ -n "$CHILD_PID" ]; then
    wait "$CHILD_PID"
  fi
}

# Redirects output to file and screen. Open a new tee process.
function output_to_file_screen(){
  # redirect all output to screen and file
  exec {OUT}>&1 {ERROR}>&2
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
  echo "$(date '+[%Y-%m-%d %H:%M:%S]') $(basename "$0"): $PRIORITY: '$LOGMESSAGE'" >> "$SNAPRAID_LOG"
}

# Emergency syslog function when no config is found, using default log location
function mklog_noconfig() {
  [[ "$*" =~ ^([A-Za-z]*):\ (.*) ]] &&
  {
    PRIORITY=${BASH_REMATCH[1]} # INFO, DEBUG, WARN
    LOGMESSAGE=${BASH_REMATCH[2]} # the Log-Message
  }
  echo "$(date '+[%Y-%m-%d %H:%M:%S]') $(basename "$0"): $PRIORITY: '$LOGMESSAGE'" >> "/var/log/snapraid.log"
}

# Set TRAP
trap final_cleanup INT EXIT

main "$@"
