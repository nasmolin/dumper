declare -A levels=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)
script_logging_level="DEBUG"
host_name=$(cat /etc/hosts | grep 127.0.1.1 |awk '{print $2}')
discord_webhook_url=''
script_start_timestamp=$(date +"%d.%m.%Y-%H:%M:%S")
workdir=/etc/postgresql/14/main/dumper
logfile=$workdir/dumper.log
dumpsdir=$workdir/dumps
dumpfile=$workdir/dumps/$script_start_timestamp.dump

logThis() {
        local log_message=$1
        local log_priority=$2
        [[ ${levels[$log_priority]} ]] || return 1
        (( ${levels[$log_priority]} < ${levels[$script_logging_level]} )) && return 2
        echo "${log_priority} $(date +"%d.%m.%Y-%H:%M:%S") ${host_name} ${log_message}" 1>> $logfile
}

function notify_if_error {
        message_header="Новый инцидент: ошибка при создании бекапа баз данных на сервере ${host_name}"
        message_body=$(tail -n 5 $logfile | tr -d '\"' | tr -s '\r\n' ' ' )
        discord_error_header=\"$message_header\"
        discord_error_body=\"\`$message_body\`\"
        curl \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"content\": $discord_error_header,\"embeds\": [{\"title\": \"Output\",\"description\": $discord_error_body}]}" \
        $discord_webhook_url
        if [ $? -eq 0 ]; then
                logThis "Notification was send, exiting." "DEBUG"
                cat $logfile
                exit 1
        else
                logThis "Unable to notify Discord." "ERROR"
                cat $logfile
                exit 1
        fi
}

function check_exec {
        if [ $? -eq 0 ]; then
                logThis "Success." "INFO"
        else
                logThis "Command exit with errors." "ERROR"
                logThis "Trying to send notification." "DEBUG"
                notify_if_error
        fi
}

rm $logfile
if ! [[ -f ${logfile} ]]; then
        echo -e "[INFO] No log file located, creating new log file (${logfile})."
        echo -e "All logs will be redirecte to this file."
        logThis "Log file created." "INFO"
fi
logThis "Script initiated" "DEBUG"
logThis "Trying to create empty .dump file." "DEBUG"
touch $dumpfile >> $logfile 2>> $logfile
check_exec

logThis "Trying to change permissions." "DEBUG"
chown -R postgres:postgres $workdir >> $logfile 2>> $logfile
check_exec

logThis "Trying to create dump." "DEBUG"
logThis "Dump will be saved in ${dumpfile}." "DEBUG"
sudo -u postgres pg_dumspall -f $dumpfile >> $logfile 2>>$logfile
check_exec

logThis "Script exit with code 0." "INFO"
exit 0
