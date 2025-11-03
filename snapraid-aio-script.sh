#!/usr/bin/env bash
########################################################################
#                                                                      #
#   Project page: https://github.com/auanasgheps/snapraid-aio-script   #
#                                                                      #
########################################################################

######################
# One‑time, centralized elevation 
######################

# Identify the *original* caller BEFORE elevation 
: "${AIO_CALLER_USER:=$(id -un 2>/dev/null || whoami)}"

# One-time elevation
SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]:-$0}")"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    # Preserve only what we need. If your sudoers has env_reset (default on Debian),
    # --preserve-env=... ensures these are still visible after elevation.
    exec sudo -n \
      --preserve-env=PATH,LANG,AIO_CALLER_USER \
      -- "$SCRIPT_PATH" "$@"
  else
    echo "Error: root privileges required and 'sudo' not available."
    exit 1
  fi
fi


######################
#  SCRIPT VARIABLES  #
######################
SNAPSCRIPTVERSION="3.4" #DEV18

# Read SnapRAID version
SNAPRAIDVERSION="$(snapraid -V | sed -e 's/snapraid v\(.*\)by.*/\1/')"

# find the current path
CURRENT_DIR=$(dirname "${0}")

# Default argument values
CONFIG_FILE="$CURRENT_DIR/script-config.conf"
FORCE_SYNC=false

SYNC_MARKER="SYNC -"
SCRUB_MARKER="SCRUB -"

####################
#   MAIN SCRIPT    #
####################

function main(){

  # parse commands from arguments
  parse_cmd_arguments "$@"

  # Check if script configuration file has been found, if not send a message
  # to syslog and exit
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Script configuration file not found! The script cannot be run! Please check and try again!"
    mklog_noconfig "WARN: Script configuration file not found! The script cannot be run! Please check and try again!"
    exit 1
  fi
  
  # Source config file
  source "$CONFIG_FILE"

  # check if the config file has the correct version
  if [ "$CONFIG_VERSION" != "$SNAPSCRIPTVERSION" ]; then
    echo "Please update your config file to the latest version. The current file is not compatible with this script!"
    mklog "WARN: Please update your config file to the latest version. The current file is not compatible with this script!"
    SUBJECT="[WARNING] - Configuration Error $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT"
    notify_warning "fatal"
    exit 1;
  fi
  
  # check if sync has been forced by a command argument
  if [ "$FORCE_SYNC" = true ]; then
    SYNC_WARN_THRESHOLD=0
  fi

  # create tmp file for output
  true > "$TMP_OUTPUT"

  # Redirect all output to file and screen. Starts a tee process
  output_to_file_screen

  # Check if the script is running as root
  check_root
  
  # Begin user output
  
  echo "SnapRAID Script Job started [$(date)]"
  echo "Running SnapRAID version $SNAPRAIDVERSION"
  echo "SnapRAID AIO Script version $SNAPSCRIPTVERSION"
  echo "Using configuration file: $CONFIG_FILE"
  echo "----------------------------------------"
  mklog "INFO: ----------------------------------------"
  mklog "INFO: SnapRAID Script Job started"
  mklog "INFO: Running SnapRAID version $SNAPRAIDVERSION"
  mklog "INFO: SnapRAID Script version $SNAPSCRIPTVERSION"
  mklog "INFO: Using configuration file: $CONFIG_FILE"
  echo "## Preprocessing"

  # Check for basic dependencies
  check_and_install python3-markdown
  check_and_install bc


  # Initialize notification
  if [ "$HEALTHCHECKS" -eq 1 ] || [ "$TELEGRAM" -eq 1 ] || [ "$DISCORD" -eq 1 ] || [ "$CHECK_UPDATES" -eq 1 ]; then
  # Check for notification dependencies
  check_and_install curl
  check_and_install jq

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
    if [ "$APPRISE" -eq 1 ] || [ "$APPRISE_EMAIL" -eq 1 ] ; then
      echo "Apprise service notification is enabled."
      check_and_install_apprise
      if [ "$APPRISE" -eq 1 ] ; then
      for APPRISE_URL_U in "${APPRISE_URL[@]}"; do
      "$APPRISE_BIN" -b "SnapRAID Script Job started" "$APPRISE_URL_U"
      done
      fi
    fi  
  fi

  ### Check if SnapRAID is found
  if [ -z "$SNAPRAID_BIN" ]; then
  echo "**ERROR**: SnapRAID binary not found in PATH. Please check if SnapRAID is installed correctly and found in the PATH environment values of your system."
    mklog "WARN: SnapRAID binary not found in PATH. Please check if SnapRAID is installed correctly and found in the PATH environment values of your system."
    SUBJECT="[WARNING] - SnapRAID binary not found in PATH $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT"
    notify_warning "fatal"
    exit 1
fi

  ### Check if SnapRAID is already running
  if pgrep -x snapraid >/dev/null; then
    echo "The script has detected SnapRAID is already running. Please check the status of the previous SnapRAID job before running this script again."
      mklog "WARN: The script has detected SnapRAID is already running. Please check the status of the previous SnapRAID job before running this script again."
      SUBJECT="[WARNING] - SnapRAID already running $EMAIL_SUBJECT_PREFIX"
      NOTIFY_OUTPUT="$SUBJECT"
      notify_warning "fatal"
      exit 1;
  else
      echo "SnapRAID is not running, proceeding."
    mklog "INFO: SnapRAID is not running, proceeding."
  fi

  if [ "$RETENTION_DAYS" -gt 0 ]; then
    echo "SnapRAID output retention is enabled. Detailed logs will be kept in $SNAPRAID_LOG_DIR for $RETENTION_DAYS days."
  fi

  # check for script updates
  if [ "$CHECK_UPDATES" -eq 1 ]; then
   remote_version=$(curl -fsS -m 5 --retry 3 https://raw.githubusercontent.com/auanasgheps/snapraid-aio-script/master/version)
    if [[ "$(printf '%s\n' "$remote_version" "$SNAPSCRIPTVERSION" | sort -V | tail -n 1)" == "$remote_version" ]] && [[ "$remote_version" != "$SNAPSCRIPTVERSION" ]]; then
     update_message="A newer version ($remote_version) is available! You can find more information by visiting https://github.com/auanasgheps/snapraid-aio-script/releases"
     echo "$update_message"
     mklog "WARN: $update_message"
     INFO_MESSAGE="$update_message"
     INFO_MESSAGE_DISCORD="$update_message"
     notify_snapraid_info
    fi
  fi

  # Check if Snapraid configuration file has been found, if not, notify and exit
  if [ ! -f "$SNAPRAID_CONF" ]; then
  # if running on OMV7, try to find the SnapRAID conf file automatically
  check_omv_version
  if [ "$OMV_VERSION" -ge 7 ]; then
  pick_snapraid_conf_file
  else
  echo "SnapRAID configuration file not found. The script cannot be run! Please check your settings, because the specified file "$SNAPRAID_CONF" does not exist."
    mklog "WARN: SnapRAID configuration file not found. The script cannot be run! Please check your settings, because the specified file "$SNAPRAID_CONF" does not exist."
  SUBJECT="[WARNING] - SnapRAID configuration file not found!"
    FORMATTED_CONF="\`$SNAPRAID_CONF\`"
  NOTIFY_OUTPUT="$SUBJECT The script cannot be run! Please check your settings, because the specified file $FORMATTED_CONF does not exist."
    notify_warning "fatal"
    exit 1;
  fi
  fi

  # Extract SnapRAID info (content and parity files) from the config file
  extract_snapraid_info

  # sanity check first to make sure we can access the content and parity files
  mklog "INFO: Checking SnapRAID disks"
  sanity_check
  
# Check if previous sync was completed before running a new sync 
# If the status is ok (exit code 0) the script will proceed, otherwise will stop 

  mklog "INFO: Checking SnapRAID Status"
  check_snapraid_status
  if [ $SNAPRAID_STATUS -eq 1 ]; then
    # Stop the script due to warning
    echo "Stopping the script because the previous SnapRAID sync did not complete correctly."
    SUBJECT="[WARNING] - Previous SnapRAID sync did not complete correctly."
    NOTIFY_OUTPUT="$SUBJECT"
    notify_warning "fatal"
    exit 1;
    
  elif [ $SNAPRAID_STATUS -eq 2 ]; then
    # Handle unknown status
    echo "Stopping the script due to unknown SnapRAID status. Please run 'snapraid status' on your host for more information."
      SUBJECT="[WARNING] - SnapRAID unknown status"
      NOTIFY_OUTPUT="$SUBJECT"
      notify_warning "fatal"
    exit 1;
  fi  

  # pause configured containers
  if [ "$MANAGE_SERVICES" -eq 1 ]; then
    service_array_setup
    if [ "$DOCKERALLOK" = YES ]; then
      echo
      pause_services
      echo
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
  $SNAPRAID_BIN -c $SNAPRAID_CONF diff
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
    SUBJECT="[WARNING] - Unable to continue with SYNC/SCRUB job(s). Check DIFF job output. $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT"
    notify_warning "fatal"
    exit 1;
  fi
  if [ $IGNORE_PATTERN ]; then
    echo "**SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT] - Ignored [$IGNORE_COUNT]**"
    mklog "INFO: SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT] - Ignored [$IGNORE_COUNT]"
  else
    echo "**SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]**"
    mklog "INFO: SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]"
  fi

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
      $SNAPRAID_BIN -c $SNAPRAID_CONF -h --force-zero -q sync
    elif [ "$PREHASH" -eq 1 ]; then
      $SNAPRAID_BIN -c $SNAPRAID_CONF -h -q sync
    elif [ "$FORCE_ZERO" -eq 1 ]; then
      $SNAPRAID_BIN -c $SNAPRAID_CONF --force-zero -q sync
    else
      $SNAPRAID_BIN -c $SNAPRAID_CONF -q sync
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
        # The function will check if scrub delayed run is enabled and run scrub
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


# Show SnapRAID SMART info and send notification
if [ "$SMART_LOG" -eq 1 ]; then
  show_snapraid_info "$SNAPRAID_BIN -c $SNAPRAID_CONF smart" "### SnapRAID Smart"
   if [ "$SMART_LOG_NOTIFY" -eq 1 ]; then
    notify_snapraid_info
   fi
fi

# Show SnapRAID Status information and send notification
if [ "$SNAP_STATUS" -eq 1 ]; then
  show_snapraid_info "$SNAPRAID_BIN -c $SNAPRAID_CONF status" "### SnapRAID Status"
   if [ "$SNAP_STATUS_NOTIFY" -eq 1 ]; then
    notify_snapraid_info
   fi
fi

# Custom Hook - After (if executed before drive spin down)
if [ "$CUSTOM_HOOK" -eq 1 ] && [ "$EXECUTE_BEFORE_SPINDOWN" -eq 1 ]; then
    echo "### Custom Hook - [$AFTER_HOOK_NAME]";
    bash -c "$AFTER_HOOK_CMD"
fi

# Spin down disks (Method hd-idle - spins down all rotational devices)
# NOTE: Uses hd-idle rewrite

  if [ "$SPINDOWN" -eq 1 ]; then
   for DRIVE in $(lsblk -d -o name | tail -n +2)
     do
       if [[ $(smartctl -a /dev/"$DRIVE" | grep 'Rotation Rate' | grep rpm) ]]; then
          echo "spinning down /dev/$DRIVE"
          hd-idle -t /dev/"$DRIVE"
       fi
     done
   fi

  # Resume Docker containers
  if [ "$SERVICES_STOPPED" -eq 1 ]; then
    echo
    resume_services
    echo
  fi

  # Custom Hook - After
  if [ "$CUSTOM_HOOK" -eq 1 ] && [ "$EXECUTE_BEFORE_SPINDOWN" -ne 1 ]; then
    echo "### Custom Hook - [$AFTER_HOOK_NAME]";
    bash -c "$AFTER_HOOK_CMD"
  fi

  echo "All jobs ended. [$(date)]"
  mklog "INFO: Snapraid: all jobs ended."

  # all jobs done
  # check snapraid output and build the message output
  # if notification services are enabled, messages will be sent now
  prepare_output
  ELAPSED="$((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
  echo "----------------------------------------"
  echo "## Total time elapsed for SnapRAID: $ELAPSED"
  mklog "INFO: Total time elapsed for SnapRAID: $ELAPSED"
  # if email or hook service are enabled, will be sent now
  if [ "$EMAIL_ADDRESS" ] || [ -x "$HOOK_NOTIFICATION" ] || [ "$APPRISE_EMAIL" -eq 1 ] || [ "$HEALTHCHECKS" -eq 1 ] || [ "$TELEGRAM" -eq 1 ] || [ "$DISCORD" -eq 1 ]; then
    # Add a topline to email body and send a long mail
  sed_me "1s:^:##$SUBJECT \n:" "${TMP_OUTPUT}"
    # send long mail if verbosity is set to 1
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
    cp $TMP_OUTPUT "$SNAPRAID_LOG_DIR"/SnapRAID-"$(date +"%Y_%m_%d-%H%M")".txt
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
    notify_warning "fatal"
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
      notify_warning "fatal"
    exit 1;
    fi
  done
  echo "All content files found."
  mklog "INFO: All content files found."
}

function get_counts() {
  EQ_COUNT=$(grep -wE '^ *[0-9]+ equal' "$TMP_OUTPUT" | sed 's/^ *//g' | cut -d ' ' -f1)
  if [ $IGNORE_PATTERN ]; then
    ADD_COUNT=$(grep -c -P "^add (?!.*(?:$IGNORE_PATTERN).*$).*$" "$TMP_OUTPUT")
    UPDATE_COUNT=$(grep -c -P "^update (?!.*(?:$IGNORE_PATTERN).*$).*$" "$TMP_OUTPUT")
    DEL_COUNT=$(grep -c -P "^remove (?!.*(?:$IGNORE_PATTERN).*$).*$" "$TMP_OUTPUT")
    MOVE_COUNT=$(grep -c -P "^move (?!.*(?:$IGNORE_PATTERN).*$).*$" "$TMP_OUTPUT")
    IGNORE_COUNT=$(grep -c -P ".*(?:$IGNORE_PATTERN).*" "$TMP_OUTPUT")
  else
    ADD_COUNT=$(grep -c -P '^add .+$' "$TMP_OUTPUT")
    UPDATE_COUNT=$(grep -c -P '^update .+$' "$TMP_OUTPUT")
    DEL_COUNT=$(grep -c -P '^remove .+$' "$TMP_OUTPUT")
    MOVE_COUNT=$(grep -c -P '^move .+$' "$TMP_OUTPUT")
  fi
  COPY_COUNT=$(grep -wE '^ *[0-9]+ copied' "$TMP_OUTPUT" | sed 's/^ *//g' | cut -d ' ' -f1)
  # REST_COUNT=$(grep -wE '^ *[0-9]+ restored' $TMP_OUTPUT | sed 's/^ *//g' | cut -d ' ' -f1)
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
  # check if ADD_DEL_THRESHOLD is greater than zero before attempting to use it
  elif [ "$(echo "$ADD_DEL_THRESHOLD > 0" | bc -l)" -eq 1 ]; then
    ADD_DEL_RATIO=$(echo "scale=2; $ADD_COUNT / $DEL_COUNT" | bc)
    if [ "$(echo "$ADD_DEL_RATIO >= $ADD_DEL_THRESHOLD" | bc -l)" -eq 1 ]; then
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
      echo "For more information, please check the DIFF output saved in $SNAPRAID_LOG_DIR."
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
  if [ "$UPDATE_COUNT" -eq 0 ]; then
    echo "There are no updated files, that's fine."
    DO_SYNC=1
  elif [ "$UPDATE_COUNT" -lt "$UP_THRESHOLD" ]; then
      echo "There are updated files. The number of updated files ($UPDATE_COUNT) is below the threshold of ($UP_THRESHOLD)."
      DO_SYNC=1
  else
    if [ "$RETENTION_DAYS" -gt 0 ]; then
      echo "**WARNING!** Updated files ($UPDATE_COUNT) reached/exceeded threshold ($UP_THRESHOLD)."
      echo "For more information, please check the DIFF output saved in $SNAPRAID_LOG_DIR."
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
  TIMESTATUS=$($SNAPRAID_BIN -c $SNAPRAID_CONF status | grep -E 'You have [1-9][0-9]* files with( a)? zero sub-second timestamp\.' | sed 's/^You have/Found/g')
  if [ -n "$TIMESTATUS" ]; then
    echo "$TIMESTATUS"
    echo "Running TOUCH job to timestamp. [$(date)]"
    echo "\`\`\`"
    $SNAPRAID_BIN -c $SNAPRAID_CONF touch
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
    $SNAPRAID_BIN -c $SNAPRAID_CONF -p new -q scrub
    close_output_and_wait
    output_to_file_screen
    echo "\`\`\`"
  fi
  echo "SCRUB Previous Blocks [$(date)]"
  echo "\`\`\`"
  $SNAPRAID_BIN -c $SNAPRAID_CONF -p "$SCRUB_PERCENT" -o "$SCRUB_AGE" -q scrub
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
    DOCKER_CMD1_LOG="Pausing"
    DOCKER_CMD2=unpause
    DOCKER_CMD2_LOG="Unpausing"
    DOCKERCMD_VALIDATED=YES
  elif [ "$DOCKER_MODE" = 2 ]; then
    DOCKER_CMD1=stop
    DOCKER_CMD1_LOG="Stopping"
    DOCKER_CMD2=start
    DOCKER_CMD2_LOG="Starting"
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
  echo "### $DOCKER_CMD1_LOG Containers [$(date)]";
  if [ "$DOCKER_LOCAL" -eq 1 ]; then
    echo "$DOCKER_CMD1_LOG Local Container(s)";
    docker $DOCKER_CMD1 $SERVICES
  fi
  if [ "$DOCKER_REMOTE" -eq 1 ]; then
    IFS=':, '
    for (( i=0; i < "${#DOCKER_HOST_SERVICES[@]}"; i++ )); do
      # delete previous array/list (this is crucial!)
      unset tmpArray
      read -r -a tmpArray <<< "${DOCKER_HOST_SERVICES[i]}"
      REMOTE_HOST="${tmpArray[0]}"
      REMOTE_SERVICES=""
      for (( j=1; j < "${#tmpArray[@]}"; j++ )); do
        REMOTE_SERVICES="$REMOTE_SERVICES${tmpArray[j]} "
      done
      echo "$DOCKER_CMD1_LOG Container(s) on $REMOTE_HOST";
      ssh "$DOCKER_USER"@"$REMOTE_HOST" docker "$DOCKER_CMD1" "$REMOTE_SERVICES"
      sleep "$DOCKER_DELAY"
    done
    unset IFS
  fi
  SERVICES_STOPPED=1
}

function resume_services(){
  if [ "$SERVICES_STOPPED" -eq 1 ]; then
    echo "### $DOCKER_CMD2_LOG Containers [$(date)]";
    if [ "$DOCKER_LOCAL" -eq 1 ]; then
      echo "$DOCKER_CMD2_LOG Local Container(s)";
      docker $DOCKER_CMD2 $SERVICES
    fi
    if [ "$DOCKER_REMOTE" -eq 1 ]; then
      IFS=':, '
      for (( i=0; i < "${#DOCKER_HOST_SERVICES[@]}"; i++ )); do
        # delete previous array/list (this is crucial!)
        unset tmpArray
        read -r -a tmpArray <<< "${DOCKER_HOST_SERVICES[i]}"
        REMOTE_HOST="${tmpArray[0]}"
        REMOTE_SERVICES=""
        for (( j=1; j < "${#tmpArray[@]}"; j++ )); do
          REMOTE_SERVICES="$REMOTE_SERVICES${tmpArray[j]} "
        done
        echo "$DOCKER_CMD2_LOG Container(s) on $REMOTE_HOST";
        ssh "$DOCKER_USER"@"$REMOTE_HOST" docker "$DOCKER_CMD2" "$REMOTE_SERVICES"
        sleep "$DOCKER_DELAY"
      done
      unset IFS
    fi
    SERVICES_STOPPED=0
  fi
}

function clean_desc(){
  [[ $- == *i* ]] && exec &>/dev/tty
 }

function final_cleanup() {
  if [ "${MANAGE_SERVICES:-0}" -eq 1 ]; then
    resume_services
  fi
  clean_desc
  exit
}


function prepare_output() {
# severe warning first
  if [ -z "${JOBS_DONE##*"SYNC"*}" ] && ! grep -qw "$SYNC_MARKER" "$TMP_OUTPUT"; then
    # Sync ran but did not complete successfully so lets warn the user
    SUBJECT="[SEVERE WARNING] SYNC job ran but did not complete successfully $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT
This is a severe warning, check your logs immediately."
    notify_warning
  elif [ -z "${JOBS_DONE##*"SCRUB"*}" ] && ! grep -qw "$SCRUB_MARKER" "$TMP_OUTPUT"; then
    # Scrub ran but did not complete successfully so lets warn the user
    SUBJECT="[SEVERE WARNING] SCRUB job ran but did not complete successfully $EMAIL_SUBJECT_PREFIX"
    if [ $IGNORE_PATTERN ]; then
      NOTIFY_OUTPUT="$SUBJECT

This is a severe warning, check your logs immediately.
SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT] - Ignored [$IGNORE_COUNT]"
    else
      NOTIFY_OUTPUT="$SUBJECT

This is a severe warning, check your logs immediately.
SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]"
    fi
    notify_warning

# minor warnings, less critical
  elif [ "$CHK_FAIL" -eq 1 ]; then
    if [ "$DEL_COUNT" -ge "$DEL_THRESHOLD" ] && [ "$DO_SYNC" -eq 0 ]; then
    if [ "$(echo "$ADD_DEL_THRESHOLD" == 0 | bc -l)" -eq 1 ]; then
    MSG="Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) violation"
       elif [ "$(echo "$ADD_DEL_RATIO < $ADD_DEL_THRESHOLD" | bc -l)" -eq 1 ]; then
        MSG="Multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) and add/delete ratio ($ADD_DEL_RATIO) / ($ADD_DEL_THRESHOLD)"
      fi
    fi

    if [ "$DEL_COUNT" -ge "$DEL_THRESHOLD" ] && [ "$DO_SYNC" -eq 1 ]; then
      if [ "$(echo "$ADD_DEL_THRESHOLD" == 0 | bc -l)" -eq 1 ]; then
      MSG="Forced sync with deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) violation"
      elif [ "$(echo "$ADD_DEL_RATIO < $ADD_DEL_THRESHOLD" | bc -l)" -eq 1 ]; then
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
    if [ "$(echo "$ADD_DEL_THRESHOLD" == 0 | bc -l)" -eq 1 ]; then
      MSG="Multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
      elif [ "$(echo "$ADD_DEL_RATIO < $ADD_DEL_THRESHOLD" | bc -l)" -eq 1 ]; then
        MSG="Multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD), add/delete ratio ($ADD_DEL_RATIO) / ($ADD_DEL_THRESHOLD), and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
    fi
  fi

    if [ "$DEL_COUNT" -ge  "$DEL_THRESHOLD" ] && [ "$UPDATE_COUNT" -ge "$UP_THRESHOLD" ] && [ "$DO_SYNC" -eq 1 ]; then
    if [ "$(echo "$ADD_DEL_THRESHOLD" == 0 | bc -l)" -eq 1 ]; then
    MSG="Sync forced with multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD) and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
      elif [ "$(echo "$ADD_DEL_RATIO < $ADD_DEL_THRESHOLD" | bc -l)" -eq 1 ]; then
      MSG="Sync forced with multiple violations - Deleted files ($DEL_COUNT) / ($DEL_THRESHOLD), add/delete ratio ($ADD_DEL_RATIO) / ($ADD_DEL_THRESHOLD), and changed files ($UPDATE_COUNT) / ($UP_THRESHOLD)"
    fi
    fi
    SUBJECT="[WARNING] $MSG $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT"
    notify_warning
# else a good run, no warnings
  else
    SUBJECT="[COMPLETED] $JOBS_DONE Jobs $EMAIL_SUBJECT_PREFIX"
    if [ $IGNORE_PATTERN ]; then
      NOTIFY_OUTPUT="$SUBJECT
SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT] - Ignored [$IGNORE_COUNT]"
    else
      NOTIFY_OUTPUT="$SUBJECT
SUMMARY: Equal [$EQ_COUNT] - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]"
    fi
    notify_success
  fi
}

### Notify functions

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
  DISCORD_SUBJECT=$(echo "$NOTIFY_OUTPUT" | jq -Rs | cut -c 2- | rev | cut -c 2- | rev)
    curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
    -H 'Content-Type: application/json' \
    -d '{"content": "'"$DISCORD_SUBJECT"'"}' \
    "$DISCORD_WEBHOOK_URL"
  fi
  
  if [ "$APPRISE" -eq 1 ]; then
    echo "Sending notification using Apprise service(s)."
      for APPRISE_URL_U in "${APPRISE_URL[@]}"; do
      "$APPRISE_BIN" -t "SnapRAID on $(hostname)" -b "$NOTIFY_OUTPUT" "$APPRISE_URL_U"
      done
  fi

  if [ "$APPRISE_EMAIL" -eq 1 ]; then
    APPRISE_EMAIL_ATTACH_DO=0
  fi
  
  mklog "INFO: "$SUBJECT""
  }

function notify_warning(){
  local MODE="${1:-nonfatal}"  # default to nonfatal if not specified

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
    DISCORD_SUBJECT=$(echo "$NOTIFY_OUTPUT" | jq -Rs | cut -c 2- | rev | cut -c 2- | rev)
    curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
    -H 'Content-Type: application/json' \
    -d '{"content": "'"$DISCORD_SUBJECT"'"}' \
    "$DISCORD_WEBHOOK_URL"
  fi

  if [ "$APPRISE" -eq 1 ]; then
    echo "Sending notification using Apprise service(s)."
    for APPRISE_URL_U in "${APPRISE_URL[@]}"; do
      if [ "$APPRISE_ATTACH" -eq 1 ]; then
        "$APPRISE_BIN" -t "SnapRAID on $(hostname)" -b "$NOTIFY_OUTPUT" -a "$TMP_OUTPUT" "$APPRISE_URL_U"
      else
        "$APPRISE_BIN" -t "SnapRAID on $(hostname)" -b "$NOTIFY_OUTPUT" "$APPRISE_URL_U"
      fi
    done
  fi

  if [ "$EMAIL_ADDRESS" ] && [ "$MODE" == "fatal" ]; then
    trim_log < "$TMP_OUTPUT" | send_mail
  fi
  
  if [ "$APPRISE_EMAIL" -eq 1 ]; then
    APPRISE_EMAIL_ATTACH_DO=1
  fi    

  mklog "WARN: $SUBJECT"
}


function show_snapraid_info() {
  local command_output=$($1)
  echo "$2"
  echo "\`\`\`"
  echo "$command_output"
  close_output_and_wait
  output_to_file_screen
  echo "\`\`\`"
  INFO_MESSAGE="$2 - \`\`\`$command_output\`\`\`"
  INFO_MESSAGE_DISCORD="$2 - $command_output"
  }

 function notify_snapraid_info() {
  if [ "$TELEGRAM" -eq 1 ]; then
   curl -fsS -m 5 --retry 3 -o /dev/null -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
   -d chat_id="$TELEGRAM_CHAT_ID" \
   -d text="$INFO_MESSAGE" \
   -d parse_mode="markdown"
  fi
  
if [ "$DISCORD" -eq 1 ]; then
  if [ "${#INFO_MESSAGE_DISCORD}" -gt 2000 ]; then
    curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
      -H 'Content-Type: application/json' \
      -d "{\"content\": \"⚠️ SnapRAID output exceeds Discord's 2000 character limit and was not posted. \"}" \
      "$DISCORD_WEBHOOK_URL"
  else
    INFO_MESSAGE_ESCAPED=$(echo "$INFO_MESSAGE_DISCORD" | jq -Rs | cut -c 2- | rev | cut -c 2- | rev)
    curl -fsS -m 5 --retry 3 -o /dev/null -X POST \
      -H 'Content-Type: application/json' \
      -d "{\"content\": \"\`\`\`\n${INFO_MESSAGE_ESCAPED}\n\`\`\`\"}" \
      "$DISCORD_WEBHOOK_URL"
  fi
fi
  
if [ "$APPRISE" -eq 1 ]; then
  # Create temp file to attach if needed
  if [ "${#INFO_MESSAGE}" -gt 2000 ]; then
    echo "$INFO_MESSAGE" > /tmp/snapraid_info_msg.txt
    APPRISE_ATTACHMENT="-a /tmp/snapraid_info_msg.txt"
    APPRISE_BODY="⚠️ SnapRAID output exceeds 2000 characters. The output is attached."
  else
    APPRISE_ATTACHMENT=""
    APPRISE_BODY="$INFO_MESSAGE"
  fi
  
    for APPRISE_URL_U in "${APPRISE_URL[@]}"; do
        if [[ "$APPRISE_URL_U" == *"discord://"* ]]; then
            # For Discord, use the URL without format (markdown) parameter
            "$APPRISE_BIN" -v -b "$APPRISE_BODY" $APPRISE_ATTACHMENT "$APPRISE_URL_U"
        else
            # For all other services, use markdown formatting
            APPRISE_URL_FORMAT="${APPRISE_URL_U}?format=markdown"
            "$APPRISE_BIN" -v -b "$APPRISE_BODY" $APPRISE_ATTACHMENT "$APPRISE_URL_FORMAT"
        fi
    done

  # Clean up temp file if it was used
  [ -f /tmp/snapraid_info_msg.txt ] && rm /tmp/snapraid_info_msg.txt
  
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
    };
    /^Unexpected /d;
    /^WARNING! You cannot modify files during a sync\./d;
    /^Rerun the sync command when finished\./d'
  }

# Process and mail the email body read from stdin.
function send_mail(){
  local body; body=$(cat)
  # Send the raw $body and append the HTML.
  # Try to workaround py markdown 2.6.8 issues:
  # 1. Will not format code blocks with empty lines, so just remove
  #    them.
  # 2. A dash line inside of code block breaks it, so remove it.
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
elif [ "$APPRISE_EMAIL" -eq 1 ]; then
  echo "Sending email report using Apprise service."
  if [ "$APPRISE_EMAIL_ATTACH" -eq 1 ] && [ "$APPRISE_EMAIL_ATTACH_DO" -eq 1 ]; then
    "$APPRISE_BIN" -vv -i "html" -t "$SUBJECT" -b "$body" -a "$TMP_OUTPUT" \ "$APPRISE_EMAIL_URL"
    else
    "$APPRISE_BIN" -vv -i "html" -t "$SUBJECT" -b "$body" \ "$APPRISE_EMAIL_URL"
  fi
elif [ "$EMAIL_ADDRESS" ]; then
  echo -e "Email address is set. Sending email report to **$EMAIL_ADDRESS** [$(date)]"
  if [ -z "$MAIL_BIN" ]; then
    echo -e "No mail program set in MAIL_BIN, you must set it to send email."
  else
    # Check if mailx is executable
    if ! command -v "$MAIL_BIN" &> /dev/null; then
      echo -e "$MAIL_BIN not found, you must install it to send email."
    else
      # Try to determine if the mailx version is the incompatible one
      MAILX_VERSION=$($MAIL_BIN -V 2>/dev/null || echo "unknown")
      if [[ "$MAILX_VERSION" == *"12.5 7/5/10"* ]]; then
        echo "Incompatible version of mailx found, using sendmail instead."
        (
          echo To: "$EMAIL_ADDRESS"
          echo From: "$FROM_EMAIL_ADDRESS"
          echo "Content-Type: text/html;"
          echo Subject: "$SUBJECT"
          echo
          echo "$body"
        ) | sendmail -t
      else
        $MAIL_BIN -a 'Content-Type: text/html; charset=UTF-8' -s "$SUBJECT" -r "$FROM_EMAIL_ADDRESS" "$EMAIL_ADDRESS" \
          < <(echo "$body")
      fi
     fi
   fi
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

# Function to check and install packages if not found
check_and_install() {

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}
  PACKAGE_NAME="$1"

  # If dpkg is missing, skip the check but warn the user
  if ! command -v dpkg >/dev/null 2>&1; then
    echo "WARNING: dpkg not found. Cannot check or install $PACKAGE_NAME. Please ensure it's installed manually."
    mklog "WARN: dpkg not found. Skipping check/install for $PACKAGE_NAME."
    return
  fi

  # Check if package is already installed
  if ! dpkg-query -W -f='${Status}' "$PACKAGE_NAME" 2>/dev/null | grep -q "ok installed"; then
    echo "$PACKAGE_NAME not found. Attempting to install..."
    mklog "INFO: Attempting to install missing package: $PACKAGE_NAME"

    if ! apt-get -qq install -y "$PACKAGE_NAME" > /dev/null 2>&1; then
      echo "ERROR: Failed to install $PACKAGE_NAME"
      mklog "ERROR: apt-get failed to install $PACKAGE_NAME"
      return 1
    fi

    # Verify again after install
    if ! dpkg-query -W -f='${Status}' "$PACKAGE_NAME" 2>/dev/null | grep -q "ok installed"; then
      echo "ERROR: $PACKAGE_NAME still not installed after attempting installation."
      mklog "ERROR: $PACKAGE_NAME still missing after install attempt."
      return 1
    fi

    echo "$PACKAGE_NAME installed successfully."
    mklog "INFO: $PACKAGE_NAME installed successfully."
  fi
}

# Built-in command check (avoid external 'which')
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Get a user's HOME via passwd DB (no eval/tilde)
user_home() { getent passwd "$1" | awk -F: '{print $6}'; }

# Run a one-liner as a login shell for user (prefer runuser, fallback to su)
as_user_login() {
  local u="$1" ; shift
  if command_exists runuser; then
    runuser -l "$u" -c "$*" 2>/dev/null
  else
    su - "$u" -c "$*" 2>/dev/null
  fi
}

check_and_install_apprise() {
  # Decide owner: original caller if available, else root
  local USER_TO_RUN="${AIO_CALLER_USER:-root}"
  local HOME_TO_RUN
  HOME_TO_RUN="$(user_home "$USER_TO_RUN")"
  [ -z "$HOME_TO_RUN" ] && HOME_TO_RUN="/root"

  # Ensure pipx exists (system-wide)
  if ! command_exists pipx; then
    if ! command_exists apt-get; then
      echo "Error: apt-get not found and /usr/bin/apprise missing."
      return 1
    fi
    echo "Installing pipx..."
    apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get -qq install -y pipx \
      || { echo "Error: pipx installation failed."; return 1; }
  fi

  # Resolve user's current pipx bin dir and look for apprise there
  #    (fast path if user already has it)
  local PIPX_BIN_DIR_USER
  PIPX_BIN_DIR_USER="$(as_user_login "$USER_TO_RUN" 'pipx environment 2>/dev/null | sed -n "s/^PIPX_BIN_DIR=//p"')"
  if [ -n "$PIPX_BIN_DIR_USER" ] && [ -x "$PIPX_BIN_DIR_USER/apprise" ]; then
    APPRISE_BIN="$PIPX_BIN_DIR_USER/apprise"
    export APPRISE_BIN
    return 0
  fi

  # Also check common default shim path
  if [ -x "$HOME_TO_RUN/.local/bin/apprise" ]; then
    APPRISE_BIN="$HOME_TO_RUN/.local/bin/apprise"
    export APPRISE_BIN
    return 0
  fi

  # Install Apprise with pipx (for the owner), then resolve again
  echo "Apprise not found; installing with pipx for '$USER_TO_RUN'..."
  if [ "$USER_TO_RUN" != "root" ]; then
    as_user_login "$USER_TO_RUN" 'pipx install apprise' \
      || { echo "WARN: pipx install for $USER_TO_RUN failed."; }
  else
    pipx install apprise || { echo "WARN: pipx install for root failed."; }
  fi
  # Recompute user’s pipx bin dir and shim
  PIPX_BIN_DIR_USER="$(as_user_login "$USER_TO_RUN" 'pipx environment 2>/dev/null | sed -n "s/^PIPX_BIN_DIR=//p"')"
  if [ -n "$PIPX_BIN_DIR_USER" ] && [ -x "$PIPX_BIN_DIR_USER/apprise" ]; then
    APPRISE_BIN="$PIPX_BIN_DIR_USER/apprise"
  elif [ -x "$HOME_TO_RUN/.local/bin/apprise" ]; then
    APPRISE_BIN="$HOME_TO_RUN/.local/bin/apprise"
  fi

  # Final check & export
  if [ -z "${APPRISE_BIN:-}" ] || [ ! -x "$APPRISE_BIN" ]; then
    echo "Error: could not resolve apprise binary."
    echo "Debug:"
    echo "  USER_TO_RUN=$USER_TO_RUN"
    echo "  HOME_TO_RUN=$HOME_TO_RUN"
    echo "  PIPX_BIN_DIR_USER=$PIPX_BIN_DIR_USER"
    return 1
  fi

  export APPRISE_BIN
  return 0
}

# Check OMV Version
check_omv_version() {
    if dpkg-query -W -f='${Status}' openmediavault 2>/dev/null | grep -q "install ok installed"; then
        version=$(dpkg-query -W -f='${Version}' openmediavault)
        if [[ -n "$version" ]]; then
            major_version=$(echo "$version" | cut -d. -f1)
            if [[ "$major_version" -ge 7 ]]; then
                OMV_VERSION=7
            else
                OMV_VERSION=6
            fi
        else
            OMV_VERSION=0
        fi
    else
        OMV_VERSION=0
    fi
}

# Pick Snapraid config file for OMV7
function pick_snapraid_conf_file() {
search_conf_files "/etc/snapraid"
result=$?
if [ $result -eq 0 ]; then
    # Only one SnapRAID config file found, proceeding
    echo "Proceeding with the omv-snapraid-.conf file: $SNAPRAID_CONF"
elif [ $result -eq 2 ]; then
    # Multiple SnapRAID config files found, stopping the script
    echo "Stopping the script due to multiple SnapRAID configuration files. Please choose one config file and update your settings in the script-config file at ""$CONFIG_FILE"". Available SnapRAID config files:"
        for file in "${conf_files[@]}"; do
            echo "$file"
        done
    mklog "WARN: Stopping the script due to multiple SnapRAID configuration files. Please choose up one config file and update your settings."
  SUBJECT="[WARNING] - Multiple SnapRAID configuration files!"
    FORMATTED_CONF="\`$SNAPRAID_CONF\`"
  NOTIFY_OUTPUT="$SUBJECT Stopping the script due to multiple SnapRAID configuration files. Please choose one config file and update your settings in the script-config file at ""$CONFIG_FILE""."
    notify_warning "fatal"
  exit 1;

else
  # No SnapRAID conf file found, stopping the script
    echo "SnapRAID configuration file not found. The script cannot be run! Please check your settings, because the specified file ""$SNAPRAID_CONF"" does not exist."
    mklog "WARN: SnapRAID configuration file not found. The script cannot be run! Please check your settings, because the specified file ""$SNAPRAID_CONF"" does not exist."
  SUBJECT="[WARNING] - SnapRAID configuration file not found!"
    FORMATTED_CONF="\`$SNAPRAID_CONF\`"
  NOTIFY_OUTPUT="$SUBJECT The script cannot be run! Please check your settings, because the specified file $FORMATTED_CONF does not exist."
    notify_warning "fatal"
  exit 1;
fi
}
# Search SnapRAID config file for OMV7
search_conf_files() {
    folder="$1"

    # Check if the directory exists
    if [ ! -d "$folder" ]; then
        echo "Directory $folder does not exist."
        return 1
    fi

    conf_files=("$folder"/omv-snapraid-*.conf)

    #echo "Searching in folder: $folder"
    #echo "Found files matching pattern: ${conf_files[@]}"

  # if no files are found
    if [ ${#conf_files[@]} -eq 0 ]; then
        return 1
  # if one file is found
    elif [ ${#conf_files[@]} -eq 1 ]; then
    SNAPRAID_CONF="${conf_files[0]}"
        return 0
    # if multiple files are found
  else
        return 2
    fi
}

# Extract SnapRAID info (content and parity files) from the config file
extract_snapraid_info() {
  # Extract info from SnapRAID config
  SNAPRAID_CONF_LINES=$(grep -E '^[^#;]' "$SNAPRAID_CONF")

  IFS=$'\n'
  # Build an array of content files
  CONTENT_FILES=(
    $(echo "$SNAPRAID_CONF_LINES" \
      | grep -E '^content ' \
      | cut -d ' ' -f2 \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  )

  # Build an array of parity files
  PARITY_FILES=(
    $(echo "$SNAPRAID_CONF_LINES" \
      | grep -E '^([1-6z]-)*parity' \
      | cut -d ' ' -f2- \
      | tr ',' '\n' \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  )
  unset IFS
}

# Run SnapRAID status to check for the previous sync
check_snapraid_status() {
  # Run snapraid status command and capture the output
  local snapraid_status_output=$($SNAPRAID_BIN status -c "$SNAPRAID_CONF")

  # Check for the "No sync is in progress" message
  if echo "$snapraid_status_output" | grep -q "No sync is in progress"; then
    echo "Previous sync completed successfully, proceeding."
    mklog "WARN: Previous sync completed successfully, proceeding."
    SNAPRAID_STATUS=0
        
    # Check for the "NOT fully synced" warning message
  elif echo "$snapraid_status_output" | grep -q "WARNING! The array is NOT fully synced."; then
    mklog "WARN: The array is NOT fully synced. Stopping the script."
    SNAPRAID_STATUS=1
  else 
    # If neither message is found, handle the unknown state
    mklog "WARN: The array status is unknown. Stopping the script."
    SNAPRAID_STATUS=2
  fi
}

# Function to check if the script is running as root
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    mklog "ERROR: Script not run as root. Exiting."
    SUBJECT="[WARNING] - Script not run as root. Exiting. $EMAIL_SUBJECT_PREFIX"
    NOTIFY_OUTPUT="$SUBJECT"
    notify_warning "fatal"
    exit 1
  fi
}

# Function to parse command arguments 
parse_cmd_arguments() {
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      if [[ -n "$2" && "$2" != --* ]]; then
        CONFIG_FILE="$2"
        shift 2
      else
        echo "Error: --config requires a path argument."
        exit 1
      fi
      ;;
    --force-sync)
      FORCE_SYNC=true
      SYNC_WARN_THRESHOLD=0
      shift
      ;;
    --help)
      echo "Usage: $0 [--config <path>] [--force-sync]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help to see usage."
      exit 1
      ;;
  esac
done
}

# Set TRAP
trap final_cleanup INT EXIT

main "$@"
