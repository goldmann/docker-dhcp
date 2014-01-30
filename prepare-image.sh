#!/bin/bash

if ! [ $# -eq 1 ]; then
  echo "Usage: $0 <fedora-cloud-image.qcow2>"
  exit 1
fi

IMAGE=image.qcow2
# Resize the disk? By default it's a 2GB HDD
RESIZE_DISK=true
DISK_SIZE=10G

echo "$(date -R) Cleaniung up..."

rm -rf $IMAGE
cp $1 $IMAGE

echo "$(date -R) Modifying the image..."

guestfish -a $IMAGE -i --network --selinux > image.log <<_EOF_
# Load selinux policy
sh "/usr/sbin/load_policy -i"
# Remove cloud-init
sh "yum -y remove cloud-init"
# Update the system
sh "yum -y update"
# Install Docker and Open vSwitch and bridge-utils and DHCPd
sh "yum -y install docker-io openvswitch bridge-utils dhcp"
# Disable the docker0 bridge creation
sh "echo -e '.include /usr/lib/systemd/system/docker.service\n\n[Service]\nExecStart=\nExecStart=/usr/bin/docker -d -b=none' > /etc/systemd/system/docker.service"
# Run Docker on boot
ln-s /usr/lib/systemd/system/docker.service /etc/systemd/system/multi-user.target.wants/docker.service
# Run Open vSwitch on boot
ln-s /usr/lib/systemd/system/openvswitch.service /etc/systemd/system/multi-user.target.wants/openvswitch.service
# Create fedora user
sh "useradd -m fedora"
# Reset the fedora user password
sh "echo 'fedora:fedora' | chpasswd"
# Give the fedora users administrative rights
sh "echo 'fedora ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/fedora"
# Add the fedora user to docker group
sh "usermod -a -G docker fedora"
# Upload the network configuration script
upload network.sh /home/fedora/network.sh
sh "chmod +x /home/fedora/network.sh"
_EOF_

if $RESIZE_DISK; then
  echo "$(date -R) Resizing the disk..."

  virt-filesystems --long -h --all -a $IMAGE >> image.log
  qemu-img create -f qcow2 -o preallocation=metadata $IMAGE.new $DISK_SIZE >> image.log
  virt-resize --quiet --expand /dev/sda1 $IMAGE $IMAGE.new >> image.log
  mv $IMAGE.new $IMAGE
fi

echo "$(date -R) Image '$IMAGE' created!"

