#!/usr/bin/bash
# /etc/profile.d/sourceless-audit.sh
# Logs every interactive Bash command to systemd-journald in real time

# Capture the latest command from Bash history and emit a journald record if not already logged
log_command_to_journal() {
    local LAST_CMD
    LAST_CMD=$(history 1 | sed -e 's/^[ ]*[0-9]*[ ]*//')
    if [ "$LAST_CMD" != "$SOURCELESS_LAST_LOGGED" ]; then
        logger -t "sourceless-audit" -p user.notice "USER=$(whoami) PWD=$(pwd) CMD=$LAST_CMD"
        export SOURCELESS_LAST_LOGGED="$LAST_CMD"
    fi
}
export -f log_command_to_journal

# Safely prepend the logger hook to PROMPT_COMMAND without duplicating or splitting entries
if [[ ! "$PROMPT_COMMAND" =~ "log_command_to_journal" ]]; then
    export PROMPT_COMMAND="type log_command_to_journal &>/dev/null && log_command_to_journal${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
