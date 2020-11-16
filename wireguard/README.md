# WireGuard

This configuration sets up a [WireGuard](https://www.wireguard.com/) server on a
[Digital Ocean](https://www.digitalocean.com/) droplet, in the *nyc1* zone.

A script, [run.sh](./run.sh) is included, which will generate a public and
private keys, as well as configurations for both server and client for those
keys.

The template requires and `API_TOKEN` environment variable to be set, which
should be a [Digital Ocean API access
token](https://cloud.digitalocean.com/account/api/tokens).
