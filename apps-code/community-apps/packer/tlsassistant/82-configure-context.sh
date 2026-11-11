#!/usr/bin/env bash

# Configure and enable service context.

exec 1>&2
set -eux -o pipefail

mv /etc/one-appliance/net-90-service-appliance /etc/one-context.d/
mv /etc/one-appliance/net-99-report-ready      /etc/one-context.d/

chown root:root /etc/one-context.d/*
chmod u=rwx,go=rx /etc/one-context.d/*

# Remove netplan configs created by NetworkManager during the Packer build.
# They use renderer NetworkManager while one-context uses networkd, and the
# two then compete for eth0 at boot and the VM can start with no route.
rm -f /etc/netplan/90-NM-*.yaml
rm -f /etc/netplan/50-one-context.yaml

sync
