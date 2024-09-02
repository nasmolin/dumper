discord_webhook_url=''
now=$(date +"%d.%m.%Y-%H:%M:%S")
node_env=dev
workdir=/etc/postgresql/14/main/dumper
logfile=$workdir/dumper.log
dumpsdir=$workdir/dumps
dumpfile=$workdir/dumps/$now.dump

function notify_if_error {

        message_header="Новый инцидент: ошибка при создании бекапа баз данных $node_env окружения"
        message_body=$(tail -n 1 $logfile | tr -d '\"')
        discord_error_header=\"$message_header\"
        discord_error_body=\"\`$message_body\`\"

        curl \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"content\": $discord_error_header,\"embeds\": [{\"title\": $discord_error_body}]}" \
        $discord_webhook_url
        }

function check_exec {
        if [ $? -eq 0 ]; then
                echo "[SUCCESS]"
        else
                echo "[ERROR] Trying to send notification."
                notify_if_error
                exit 1
        fi
}

echo "[DEBUG] Trying to create some dir..."
touch $dumpfile >> $logfile 2>> $logfile
check_exec

echo "[DEBUG] Trying to change permissions..."
chown -R postgres:postgres $workdir >> $logfile 2>> $logfile
check_exec

echo "[DEBUG] Trying to create dump..."
echo "[DEBUG] Dump will be saved in $dumpfile"
sudo -u postgres pg_dumpall -f $dumpfile >> $logfile 2>>$logfile
check_exec

exit 0
