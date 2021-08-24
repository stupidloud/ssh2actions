#!/usr/bin/env bash
#
# Copyright (c) 2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/ssh2actions
# File name：ngrok2actions.sh
# Description: Connect to Github Actions VM via SSH by using ngrok
# Version: 2.0
#

Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m"
Font_color_suffix="\033[0m"
INFO="[${Green_font_prefix}INFO${Font_color_suffix}]"
ERROR="[${Red_font_prefix}ERROR${Font_color_suffix}]"
LOG_FILE='/tmp/ngrok.log'
TELEGRAM_LOG="/tmp/telegram.log"
CONTINUE_FILE="/tmp/continue"

if [[ -z "${NGROK_TOKEN}" ]]; then
    echo -e "${ERROR} Please set 'NGROK_TOKEN' environment variable."
    exit 2
fi

if [[ -z "${SSH_PASSWORD}" && -z "${SSH_PUBKEY}" && -z "${GH_SSH_PUBKEY}" ]]; then
    echo -e "${ERROR} Please set 'SSH_PASSWORD' environment variable."
    exit 3
fi

if [[ -n "${SSH_PASSWORD}" ]]; then
    echo -e "${INFO} Set user(${USER}) password ..."
    echo -e "${SSH_PASSWORD}\n${SSH_PASSWORD}" | sudo passwd "${USER}"
fi

if [[ -n "${SSH_PUBKEY}" ]]; then
    echo -e "${INFO} Set user(${USER}) authorized key ..."
    mkdir -p /home/${USER}/.ssh
    echo ${SSH_PUBKEY} > /home/${USER}/.ssh/authorized_keys
    chmod 600 /home/${USER}/.ssh/authorized_keys
fi

sudo chmod 755 /home/${USER}
echo '. ~/.bashrc' >> /home/${USER}/.bash_profile
export > /home/${USER}/.env
echo '. ~/.env' >> /home/${USER}/.bash_profile

echo -e "${INFO} Start SSH tunnel for SSH port..."
eval `ssh-agent`
echo "${NGROK_TOKEN}" | base64 --decode | ssh-add -
random_port=`shuf -i 20000-65000 -n 1`
ssh -NTR $random_port:127.0.0.1:22 -oStrictHostKeyChecking=no -C tunnel@us2.diao.im -v 2>&1 | tee $LOG_FILE
screen -dmS ngrok \
    "ssh -NTR $random_port:127.0.0.1:22 -oStrictHostKeyChecking=no -C tunnel@us2.diao.im -v 2>&1 | tee $LOG_FILE"

while ((${SECONDS_LEFT:=10} > 0)); do
    echo -e "${INFO} Please wait ${SECONDS_LEFT}s ..."
    sleep 1
    SECONDS_LEFT=$((${SECONDS_LEFT} - 1))
done

ERRORS_LOG=$(grep "forwarding requests processed" ${LOG_FILE})

if [[ -e "${LOG_FILE}" && -n "${ERRORS_LOG}" ]]; then
    SSH_CMD="ssh us2.diao.im -p $random_port"
    MSG="
*GitHub Actions - SSH tunnel info:*

⚡ *CLI:*
\`${SSH_CMD}\`

🔔 *TIPS:*
Run '\`touch ${CONTINUE_FILE}\`' to continue to the next step.
"
    if [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]]; then
        echo -e "${INFO} Sending message to Telegram..."
        curl -sSX POST "${TELEGRAM_API_URL:-https://api.telegram.org}/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "disable_web_page_preview=true" \
            -d "parse_mode=Markdown" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${MSG}" >${TELEGRAM_LOG}
        TELEGRAM_STATUS=$(cat ${TELEGRAM_LOG} | jq -r .ok)
        if [[ ${TELEGRAM_STATUS} != true ]]; then
            echo -e "${ERROR} Telegram message sending failed: $(cat ${TELEGRAM_LOG})"
        else
            echo -e "${INFO} Telegram message sent successfully!"
        fi
    fi
    while ((${PRT_COUNT:=1} <= ${PRT_TOTAL:=10})); do
        SECONDS_LEFT=${PRT_INTERVAL_SEC:=10}
        while ((${PRT_COUNT} > 1)) && ((${SECONDS_LEFT} > 0)); do
            echo -e "${INFO} (${PRT_COUNT}/${PRT_TOTAL}) Please wait ${SECONDS_LEFT}s ..."
            sleep 1
            SECONDS_LEFT=$((${SECONDS_LEFT} - 1))
        done
        echo "------------------------------------------------------------------------"
        echo "To connect to this session copy and paste the following into a terminal:"
        echo -e "${Green_font_prefix}$SSH_CMD${Font_color_suffix}"
        echo -e "TIPS: Run 'touch ${CONTINUE_FILE}' to continue to the next step."
        echo "------------------------------------------------------------------------"
        PRT_COUNT=$((${PRT_COUNT} + 1))
    done
else
    cat $LOG_FILE
    exit 4
fi

while [[ -n $(ps aux | grep NTR) ]]; do
    sleep 1
    if [[ -e ${CONTINUE_FILE} ]]; then
        echo -e "${INFO} Continue to the next step."
        exit 0
    fi
done

# ref: https://gist.github.com/retyui/7115bb6acf151351a143ec8f96a7c561
