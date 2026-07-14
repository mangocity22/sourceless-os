# /etc/profile.d/sourceless-audit.sh
# Trimite instantaneu fiecare comanda interactiva in systemd-journald

log_command_to_journal() {
    local LAST_CMD
    LAST_CMD=$(history 1 | sed -e 's/^[ ]*[0-9]*[ ]*//')
    if [ "$LAST_CMD" != "$SOURCELESS_LAST_LOGGED" ]; then
        # Logam securizat in journald sub identificatorul 'sourceless-audit'
        logger -t "sourceless-audit" -p user.notice "USER=$(whoami) PWD=$(pwd) CMD=$LAST_CMD"
        export SOURCELESS_LAST_LOGGED="$LAST_CMD"
    fi
}

# Injectam functia in lantul de executie al promptului Bash
export PROMPT_COMMAND="log_command_to_journal; $PROMPT_COMMAND"