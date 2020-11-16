#!/usr/bin/env bash

set -euxo pipefail

# Create client and server keys
for dir in client server
do
  mkdir -p $dir
  pushd $dir

  wg genkey | tee privatekey | wg pubkey > publickey

  popd
done

# Create server config
sed -e "s/{PRIVATEKEY}/$(sed 's/\//\\\//g' server/privatekey)/" \
  -e "s/{PUBLICKEY}/$(sed 's/\//\\\//g' client/publickey)/" \
  server/wg0.conf.tmpl > server/wg0.conf

# Create client config
sed -e "s/{PRIVATEKEY}/$(sed 's/\//\\\//g' client/privatekey)/" \
  -e "s/{PUBLICKEY}/$(sed 's/\//\\\//g' server/publickey)/" \
  client/wg0.conf.tmpl > client/wg0.conf

# Run packer
packer build wireguard.json
