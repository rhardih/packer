#!/usr/bin/env bash

set -euxo pipefail

usage() {
  echo "Usage: $0 [-c <number>]" 1>&2
  echo
  echo " -c Specifiy number of WireGuard clients to generate. Default 10"
}

##############################
#  Sanity check environment  #
##############################

for cmd in wg packer jq
do
  if ! command -v $cmd &> /dev/null
  then
    echo "$cmd could not be found"
    exit 1
  fi
done

# Required for Packer to connect to Digital Ocean
echo "$API_TOKEN" > /dev/null

#########################################################
#  Build a Ubuntu snapshot with WireGuard using Packer  #
#########################################################

CLIENT_COUNT=10
while getopts "hc:" opt; do
  case $opt in
    c ) CLIENT_COUNT=$OPTARG;;
    h ) usage
      exit 0;;
    *) usage
      exit 1;;
  esac
done

echo "<$CLIENT_COUNT>"

# Create server keys
mkdir -p server
pushd server

SERVER_PRIVATEKEY=$(wg genkey)
SERVER_PUBLICKEY=$(wg pubkey <<< "$SERVER_PRIVATEKEY")

# Create server config
cat > "wg0.conf" <<- EOF
	[Interface]
	PrivateKey = $SERVER_PRIVATEKEY
	Address = 10.0.0.1/24
	PostUp = iptables -A FORWARD -i wg -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
	PostDown = iptables -D FORWARD -i wg -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
	ListenPort = 51820

EOF

popd

# Create client keys
mkdir -p client-configs
pushd client-configs

# Start at 2 here, because 10.0.0.1 is the gateway, i.e. the server.
for n in $(seq 2 "$CLIENT_COUNT")
do
  CLIENT_PRIVATEKEY=$(wg genkey)
  CLIENT_PUBLICKEY=$(wg pubkey <<< "$CLIENT_PRIVATEKEY")

  # Create client config
  cat > "wg$n.conf" <<- EOF
		[Interface]
		Address = 10.0.0.$n/32
		PrivateKey = $CLIENT_PRIVATEKEY
		DNS = 1.1.1.1

		[Peer]
		PublicKey = $SERVER_PUBLICKEY
		Endpoint = {SERVER-IP}:51820
		AllowedIPs = 0.0.0.0/0, ::/0
	EOF

  # Add client as peer to server config
  pushd ../server

  cat >> "wg0.conf" <<- EOF
		[Peer]
		PublicKey = $CLIENT_PUBLICKEY
		AllowedIPs = 10.0.0.$n/32

	EOF

  popd
done

popd

# Run packer
packer build -machine-readable wireguard.json | tee build.output

##################################################
#  Create Droplet from snapshot built by packer  #
##################################################

# Get log line with the info we need
log_line=$(grep 'digitalocean,artifact.*snapshot' build.output)
log_line_value=$(echo "$log_line" | awk -F "," '{print $6}')

# Fetch name, image id and region the snapshot was created with
SNAPSHOT_NAME=$(echo "$log_line_value" | awk -F "'" '{print $2}')
IMAGE_ID=$(echo "$log_line_value" | awk -F "[()]" '{print $2}' | awk '{ print $2}')
REGION=$(echo "$log_line_value" | awk -F "'" '{print $4}')

# Create a droplet from the newly created snapshot
curl -X POST -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer '"$API_TOKEN"'' \
  -d '{"name":"'"$SNAPSHOT_NAME"'-s-4vcpu-8gb-intel-nyc1-01",
  "size":"s-4vcpu-8gb-intel",
  "region":"'"$REGION"'",
  "image":"'"$IMAGE_ID"'",
  "vpc_uuid":"87a13848-0424-41da-9ba5-9acc55241ce1"}' \
    "https://api.digitalocean.com/v2/droplets" | tee curl-0.output

# Get the id of the newly created droplet
DROPLET_ID=$(jq '.droplet.id' < curl-0.output)

# Query the API to get the ip address of the newly created droplet, repeat if
# the droplet has not yet booted and thus don't have an IP yet.
RETRY_COUNT=0
RETRY_LIMIT=10
DROPLET_IP=""
while [[ $RETRY_COUNT -lt $RETRY_LIMIT ]]; do
  curl -X GET -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $API_TOKEN" \
    "https://api.digitalocean.com/v2/droplets/$DROPLET_ID" | tee curl-1.output

  DROPLET_IP=$(jq  '.droplet.networks.v4[0].ip_address' < curl-1.output | tr -d '"')

  if [[ "$DROPLET_IP" == "null" ]]; then
    echo "Droplet $DROPLET_ID has no IP yet. Sleeping 5s..."
    sleep 10 # Delay to avoid spamming the server with requests

    RETRY_COUNT=$((RETRY_COUNT+1))
  else
    break
  fi
done

if [[ -z $DROPLET_IP ]]; then
  echo "Failed to get IP of droplet $DROPLET_ID after $RETRY_LIMIT retries"
else
  # Replace the server IP placeholder in the client configs with the IP address of
  # the newly created droplet
  gsed -i "s/{SERVER-IP}/$DROPLET_IP/g" client-configs/*
fi
