#!/bin/bash

CURRENT_DIR=$(dirname "${0}")
CONFIG_FILE=$CURRENT_DIR/script-config.sh
source "$CONFIG_FILE"

# this 3 checks (if) are not necessary but should be convenient
if [ "$1" == "-h" ]; then
  echo "Usage: `basename $0` \"text message\""
  exit 0
fi

if [ -z "$1" ]
  then
    echo "Add message text as second arguments"
    exit 0
fi

if [ "$#" -ne 1 ]; then
    echo "You can pass only one argument. For string with spaces put it on quotes"
    exit 0
fi

curl -fsS -m 5 --retry 3 -o -s --data "text=$1" --data "chat_id=$TELEGRAM_CHAT_ID" 'https://api.telegram.org/bot'$TELEGRAM_TOKEN'/sendMessage' > /dev/null