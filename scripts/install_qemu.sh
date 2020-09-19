#!/bin/sh
# Execute this in ~/
diroutput="$1"
apt-get install libcap-dev libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev libglib2.0-dev libpixman-1-dev libseccomp-dev -y
git clone https://github.com/qemu/qemu.git $diroutput
cd $diroutput
mkdir build 
cd build
../configure --target-list=x86_64-softmmu
make
cd ../..
modprobe vhost_vsock
