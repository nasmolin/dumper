#!/bin/bash

# vars:
discord_webhook_url='URL'
declare -A levels=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)
script_logging_level="DEBUG"
host_name=$(cat /etc/hosts | grep 127.0.1.1 |awk '{print $2}')
script_start_timestamp=$(date +"%d.%m.%Y-%H:%M:%S")
workdir=$(pwd)
logsdir=$workdir/logs
logfile=$workdir/logs/pg_dumper.log
dumpsdir=$workdir/dumps
dumpfile=$workdir/dumps/$script_start_timestamp.dump
logrotateonfig=/etc/logrotate.d/pg_dumper.conf

# func:
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
        -f \
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
                logThis "Done." "INFO"
        else
                logThis "Command exit with errors." "ERROR"
                logThis "Trying to send notification." "DEBUG"
                notify_if_error
        fi
}

# Script:
echo -e "Script initiated"

if ! [[ $(whoami) == root ]]; then 
         echo -e "[ERROR] Permission Denied, are you root?"
         exit 1
fi

if ! [[ -f ${logfile} ]]; then
        echo -e "[INFO] Creating log file: (${logfile})."
        echo -e "stdout and stderr will be redirected to this file."
        echo -e "Trying to create logs dir." 
        mkdir -p $logsdir
        echo -e "Log file was created." && logThis "Log file was created." "DEBUG"
fi

echo -e "Trying to create dir for .dump files." && logThis "Trying to create dir for .dump files." "INFO"
mkdir -p $dumpsdir >> $logfile 2>> $logfile && check_exec

rm $logrotateonfig
logThis "Creating logrotate config." "DEBUG"
cat >${logrotateonfig} <<-EOF
        ${logfile} {
        missingok
        daily
        rotate 3
        size 50k
        }
EOF

echo -e "Apply logrotate config." && logThis "Apply logrotate config." "DEBUG"
logrotate ${logrotateonfig} >> $logfile 2>> $logfile && check_exec

echo -e "Trying to create empty .dump file." && logThis "Trying to create empty .dump file." "INFO"
touch $dumpfile >> $logfile 2>> $logfile && check_exec

echo -e "Trying to change permissions." && logThis "Trying to change permissions." "INFO"
chown postgres:postgres $dumpfile >> $logfile 2>> $logfile && check_exec

echo -e "Trying to create dump." && logThis "Trying to create dump." "DEBUG"
echo -e "Dump will be saved in ${dumpfile}." && logThis "Dump will be saved in ${dumpfile}." "DEBUG"
sudo -u postgres pg_dumpall -f $dumpfile >> $logfile 2>>$logfile && check_exec

echo -e "[SUCCESS] script exit with code 0." && logThis "Script exit with code 0." "INFO."
exit 0
