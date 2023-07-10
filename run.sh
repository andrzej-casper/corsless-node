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
  echo " $ sudo usermod -aG docker \$USER && newgrp docker"
  exit 1
fi

# Parse parameters.
if [ "$#" -lt 1 ]; then
  echo "Illegal number of parameters."
  echo "Usage:"
  echo "  $0 <upstream_node_ip> [<upstream_node_port>]"
  echo "You can also get node IP automatically"
  echo "  $0 mainnet|testnet"
  exit 1
fi
case $1 in
  mainnet|testnet)
    echo "> Looking for ${1} node"
    PEERS=`curl \
      --silent \
      "https://event-store-api-clarity-${1}.make.services/rpc/info_get_status"`
    UPSTREAM_NODE_IP=`echo ${PEERS} | jq -r ".result.peers[].address" | sort -R | head -n 1 | cut -d ":" -f 1`
    UPSTREAM_NODE_PORT="7777"
    echo "Randomly picked ${UPSTREAM_NODE_IP} (port 7777 assumed)"
    ;;
  *)
    UPSTREAM_NODE_IP="${1}"
    UPSTREAM_NODE_PORT="${2:-7777}"
esac

echo "> Making sure upstream node is online - uptime, chain"
NODE_STATUS=`curl \
  --silent \
  --compressed \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"info_get_status","id":1}' \
  ${UPSTREAM_NODE_IP}:${UPSTREAM_NODE_PORT}/rpc`
echo ${NODE_STATUS} | jq .result.uptime
echo ${NODE_STATUS} | jq .result.chainspec_name

echo "> Making sure no old container is running"
if [ "$(docker ps -qa -f name=${CONTAINER_NAME})" ]; then
  if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    docker stop ${CONTAINER_NAME};
  fi
  docker rm ${CONTAINER_NAME};
fi

echo "> Looking for optional certificates at ./mitmproxy/cert.pem"
CERTS_ENABLED=""
if [ -s "${SCRIPT_PATH}/mitmproxy/cert.pem" ]; then
  if [ -z "$(cat ${SCRIPT_PATH}/mitmproxy/cert.pem | grep 'BEGIN PRIVATE KEY')" ]; then
    echo "[ERROR] Certificate must contain private key."
    exit 1
  fi
  if [ -z "$(cat ${SCRIPT_PATH}/mitmproxy/cert.pem | grep 'BEGIN CERTIFICATE')" ]; then
    echo "[ERROR] Certificate must contain public key."
    exit 1
  fi
  CERTS_ENABLED="yup"
  echo "HTTPS support enabled."
else
  echo "No certificates found."
fi

echo "> Launching new MITM proxy container"
docker run \
  --detach \
  --name ${CONTAINER_NAME} \
  --restart=unless-stopped \
  -v ${SCRIPT_PATH}/mitmproxy:/mitmproxy \
  -p ${BIND_PORT}:${BIND_PORT} \
  ${MITMPROXY_IMAGE} \
  mitmdump -s /mitmproxy/cors.py --mode reverse:http://${UPSTREAM_NODE_IP}:${UPSTREAM_NODE_PORT} --listen-host ${BIND_HOST} -p ${BIND_PORT} --set block_global=false --no-http2 \
  ${CERTS_ENABLED:+--certs} ${CERTS_ENABLED:+*=/mitmproxy/cert.pem}

echo "Done! Reverse proxy is running in background, listening at ${BIND_HOST}:${BIND_PORT}."
echo "You might close this console ;)"
