#!/usr/bin/env bash
set -e

# determine script path
pushd . > /dev/null
SCRIPT_PATH="${BASH_SOURCE[0]}"
if ([ -h "${SCRIPT_PATH}" ]); then
  while([ -h "${SCRIPT_PATH}" ]); do cd `dirname "$SCRIPT_PATH"`;
  SCRIPT_PATH=`readlink "${SCRIPT_PATH}"`; done
fi
cd `dirname ${SCRIPT_PATH}` > /dev/null
SCRIPT_PATH=`pwd`;
popd  > /dev/null

# if [ "$#" -lt 1 ]; then
#   echo "Illegal number of parameters."
#   echo "Usage: $0 <upstream_node_ip> [<upstream_node_port>]"
#   exit 1
# fi
UPSTREAM_NODE_IP="${1:-135.181.216.142}"
UPSTREAM_NODE_PORT="${2-7777}"

BIND_HOST="0.0.0.0"
BIND_PORT="7777"

MITMPROXY_IMAGE="mitmproxy/mitmproxy:9.0.1"
CONTAINER_NAME="corsless-casper-node"

echo "> Checking requirements"
if which curl >/dev/null 2>&1; then
  :
else
  echo "Error: curl not installed."
  echo "You can get it with:"
  echo " $ sudo pacman -S curl"
  exit 1
fi
if which jq >/dev/null 2>&1; then
  :
else
  echo "Error: jq not installed."
  echo "You can get it with:"
  echo " $ sudo pacman -S jq"
  exit 1
fi
if which docker >/dev/null 2>&1; then
  :
else
  echo "Error: docker not installed."
  echo "You can get it with:"
  echo " $ sudo pacman -S docker"
  echo " $ sudo systemctl enable --now docker.service"
  exit 1
fi

echo "> Making sure upstream node is online - check uptime"
curl \
  --silent \
  --compressed \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"info_get_status","id":1}' \
  135.181.216.142:7777/rpc \
  | jq .result.uptime

echo "> Making sure no old container is running"
if [ "$(docker ps -qa -f name=${CONTAINER_NAME})" ]; then
    if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
        docker stop ${CONTAINER_NAME};
    fi
    docker rm ${CONTAINER_NAME};
fi

echo "> Launching new MITM proxy container"
docker run \
  --detach \
  --name ${CONTAINER_NAME} \
  --restart=unless-stopped \
  -v ${SCRIPT_PATH}/mitmproxy:/home/mitmproxy/.mitmproxy \
  -p ${BIND_PORT}:${BIND_PORT} \
  ${MITMPROXY_IMAGE} \
  mitmdump -s /home/mitmproxy/.mitmproxy/cors.py --mode reverse:http://${UPSTREAM_NODE_IP}:${UPSTREAM_NODE_PORT} --listen-host ${BIND_HOST} -p ${BIND_PORT}

echo "Done! Reverse proxy is running in background, listening at ${BIND_HOST}:${BIND_PORT}."
echo "You might close this console ;)"
