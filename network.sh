#!/bin/bash

if ! [ $# -eq 2 ]; then
  echo "Usage: $0 <host-number> <remote-host-ip>"
  echo
  echo "Example:"
  echo
  echo "  On first host with IP 192.168.10.75 you run:"
  echo "    $0 1 192.168.10.80"
  echo
  echo "  And on second host with IP 192.168.10.80 you run:"
  echo "    $0 2 192.168.10.75"
  exit 1
fi

# The 'other' host
REMOTE_IP=$2
# Name of the bridge
BRIDGE_NAME=docker0
# Bridge address
BRIDGE_IP=172.16.42.$1
BRIDGE_ADDRESS=$BRIDGE_IP/24

# Deactivate the docker0 bridge
ip link set $BRIDGE_NAME down
# Remove the docker0 bridge
brctl delbr $BRIDGE_NAME
# Delete the Open vSwitch bridge
ovs-vsctl del-br br0
# Add the docker0 bridge
brctl addbr $BRIDGE_NAME
# Set up the IP for the docker0 bridge
ip a add $BRIDGE_ADDRESS dev $BRIDGE_NAME
# Activate the bridge
ip link set $BRIDGE_NAME up
# Add the br0 Open vSwitch bridge
ovs-vsctl add-br br0
# Create the tunnel to the other host and attach it to the
# br0 bridge
ovs-vsctl add-port br0 gre0 -- set interface gre0 type=gre options:remote_ip=$REMOTE_IP
# Add the br0 bridge to docker0 bridge
brctl addif $BRIDGE_NAME br0

# Set the required iptables rules

# Enable NAT
iptables -t nat -A POSTROUTING -s 172.16.42.0/24 ! -d 172.16.42.0/24 -j MASQUERADE
# Accept incoming packets for existing connections
iptables -A FORWARD -o $BRIDGE_NAME -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# Accept all non-intercontainer outgoing packets
iptables -A FORWARD -i $BRIDGE_NAME ! -o $BRIDGE_NAME -j ACCEPT
# By default allow all outgoing traffic
iptables -A FORWARD -i $BRIDGE_NAME -o $BRIDGE_NAME -j ACCEPT

# Drop DHCPD request/replies on br0 OpenSwitch bridge
# This will let us run multiple DHCP serwers on the network
# but still communicate between containers
ovs-ofctl add-flow br0 udp,tp_src=68,tp_dst=67,action=drop
ovs-ofctl add-flow br0 udp,tp_src=67,tp_dst=68,action=drop

# Prepare dhcpd.conf file
cat > /etc/dhcp/dhcpd.conf << EOF
option domain-name-servers 8.8.8.8;
option subnet-mask 255.255.255.0;
option routers $BRIDGE_IP;

subnet 172.16.42.0 netmask 255.255.255.0 {
  default-lease-time 300;
  range 172.16.42.${1}0 172.16.42.${1}9;
}
EOF

# Run the DHCP server
systemctl restart dhcpd

# Some useful commands to confirm the settings:
# ip a s
# ip r s
# ovs-vsctl show
# brctl show
# ovs-ofctl dump-flows br0

