# WireGuard

This configuration sets up a [WireGuard](https://www.wireguard.com/) server on a
[Digital Ocean](https://www.digitalocean.com/) droplet image, in the *nyc1*
zone.

A script, [run.sh](./run.sh) is included, which will generate a server
configuration, with a number of client peers pre-specified, each of which will have a client configuration generate as well.

The packer template requires an `API_TOKEN` environment variable to be set,
which should be a [Digital Ocean API access
token](https://cloud.digitalocean.com/account/api/tokens).

After packer has run, create a new droplet off the newly created image and note
the public ip address. Each client config will need to have `{SERVER-IP}`
replaced with the droplets public ip.
