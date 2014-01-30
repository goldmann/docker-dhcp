#!/bin/bash

if ! [ $# -eq 2 ]; then
  echo "Usage: $0 <disk-file> <host-name>"
  exit 1
fi

# Amount of RAM in MB
MEM=1024
# Number of virtual CPUs
CPUS=2
# Name of the host
NAME=$2
# The disk name
DISK=$NAME.qcow2
# If the domain should be launched afterwards
RUN_AFTER=${RUN_AFTER:-true}

rm -rf $NAME
mkdir -p $NAME

cp $1 $NAME/$DISK

pushd $NAME > /dev/null
  virsh destroy $NAME &>$NAME.log
  virsh undefine $NAME &>>$NAME.log

  echo "$(date -R) Installing the domain and adjusting the configuration..."
  virt-install --import --name $NAME --ram $MEM --vcpus $CPUS --disk $DISK,format=qcow2,bus=virtio,cache=none --network bridge=virbr0,model=virtio --os-type=linux --noreboot --import --noautoconsole &>>$NAME.log
  echo "$(date -R) Domain $NAME registered!"

  if $RUN_AFTER; then
    echo "$(date -R) Launching the $NAME domain..."

    virsh start $NAME &>> $NAME.log

    echo "$(date -R) Domain started, waiting for the IP..."

    mac=`virsh dumpxml $NAME | grep "mac address" | tr -s \' ' '  | awk ' { print $3 } '`

    while true; do
      ip=`arp -na | grep $mac | awk '{ print $2 }' | tr -d \( | tr -d \)`
 
      if [ "$ip" = "" ]; then
        sleep 1
      else
        break
      fi
    done
 
    echo "$(date -R) You can ssh to the $ip host using 'fedora' username and 'fedora' password or use the 'virsh console $NAME' command to directly attach to the console"
  else
    echo "$(date -R) You can launch the domain by using the 'virsh start $NAME --console' command."
  fi

popd > /dev/null

