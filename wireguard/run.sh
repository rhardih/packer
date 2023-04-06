#!/usr/bin/env bash

set -euxo pipefail

usage() {
  echo "Usage: $0 [-c <number>]" 1>&2
  echo
  echo " -c Specifiy number of WireGuard clients to generate. Default 10"
}

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

# Sanity check env

for cmd in wg packer
do
  if ! command -v $cmd &> /dev/null
  then
    echo "$cmd could not be found"
    exit
  fi
done

# Required for Packer to connect to Digital Ocean
echo $API_TOKEN > /dev/null

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

for n in $(seq 2 $(($CLIENT_COUNT + 1)))
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
packer build wireguard.json
