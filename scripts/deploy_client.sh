#!/bin/sh
# Execute this client node in ~/
qemudir="qemuforvmm"
secret="xxxxxxxx"
cephuser="vmmcephuser"
mon="vmm101"
# install ceph, docker
apt-get update
apt install apt-transport-https ca-certificates curl gnupg2 software-properties-common -y
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
apt update
apt install docker-ce -y
curl --silent --remote-name --location https://github.com/ceph/ceph/raw/octopus/src/cephadm/cephadm
chmod +x cephadm
./cephadm add-repo --release octopus
./cephadm install ceph-common
# compile qemu
apt-get install libcap-dev libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev libglib2.0-dev libpixman-1-dev libseccomp-dev -y
git clone https://github.com/qemu/qemu.git $qemudir
cd $qemudir
mkdir build 
cd build
../configure --target-list=x86_64-softmmu
make
cd ../..
modprobe vhost_vsock
# mount cephs
mkdir –-mode=777 ~/cephfs
mount -t ceph $mon:6789:/ /home/debian/cephfs -o name="$cephuser",secret="$secret"
