# Deploying a 3-node Ceph Cluster
## Introduction
This tutorial explains how to set up a 3-nodes Ceph cluster. We also explain how to configure clients to access the Cephfs. The distributed fs is used by clients to share binaries and files among VMs. These VMs are Toro's guests. We uses the cloud provider OVH with nodes Debian 4.19.37-5+deb10u1 (2019-07-19). At the end of some sections, you will find a link to a script that automates the steps discussed.  You can find more information about this at [Deploying a new Ceph Cluster](https://docs.ceph.com/en/latest/cephadm/install/).
## Nodes

The cluster contains 1 monitor, 3 OSD nodes and 2 clients. Each OSD node has a `sdb` partition of 10Gb which is part of the cluster. The host names, public IP and LAN IP are as follows:

|   Host name   | Private IP      | Role     |
| ---- | ---- | ---- |
|vmm101|10.2.2.127|MON, OSD|
|vmm102|10.2.2.33|OSD|
|vmm103|10.2.0.31|OSD|
|vmm104|10.2.0.75|Client|
|vmm105|10.2.0.171|Client|
## Setup
### Step 1. Prepare all nodes
We are going to configure LAN and the host names and install all the required packages. We are going to use the **debian** user for root access. 

#### Configure LAN IP
On each node, set private LAN IP, netmask and gateway by editing */etc/network/interfaces* (eth1):

```bash
iface eth1 inet static
address 10.2.2.127
netmask 255.255.0.0
gateway 10.2.2.254
ifdown eth1
ifup eth1
```
#### Configure Host File 
Configure hosts so each node is visible by using shortnames. Edit */etc/hosts* and add:
```bash
10.2.2.127      vmm101.xmlrad.local       vmm101
10.2.2.33       vmm102.xmlrad.local       vmm102
10.2.0.31       vmm103.xmlrad.local       vmm103
10.2.0.75       vmm104.xmlrad.local       vmm104
10.2.0.171      vmm105.xmlrad.local       vmm105
```
#### Packages for Monitor
For monitors node, you need docker, LVM2 and Ceph:
```bash
apt-get update
apt install apt-transport-https ca-certificates curl gnupg2 software-properties-common -y
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
apt update
apt install docker-ce -y
apt-get install lvm2 -y
curl --silent --remote-name --location https://github.com/ceph/ceph/raw/octopus/src/cephadm/cephadm`
chmod +x cephadm`
wget -q -O- 'https://download.ceph.com/keys/release.asc' | sudo apt-key add -
echo deb https://download.ceph.com/debian-octopus/ $(lsb_release -sc) main | sudo tee /etc/apt/sources.list.d/ceph.list
apt-get update
./cephadm install cephadm ceph-common
```
Use `scripts/deploy_monitor.sh` at `~/` to automate this step.

#### Packages for OSDs
For OSDs, you need docker, LVM2 and Ceph-common:
```bash
apt-get update
apt install apt-transport-https ca-certificates curl gnupg2 software-properties-common -y
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
apt update
apt install docker-ce -y
apt-get install lvm2 -y
curl --silent --remote-name --location https://github.com/ceph/ceph/raw/octopus/src/cephadm/cephadm
chmod +x cephadm
./cephadm add-repo --release octopus
./cephadm install ceph-common
```
Use `scripts/deploy_osd.sh` at `~/` to automate this step.
### Step 2. Create Monitor Node
In the monitor node, execute:
```bash
mkdir -p /etc/ceph
./cephadm bootstrap --mon-ip $MONIP --ssh-user debian --allow-overwrite
```
Replace $MONIP with the internal ip of the monitor node, e.g., 10.2.2.127. Also, replace debian with a root user. 

### Step 3. Add hosts to the cluster
We are going to add the OSD nodes to the cluster. Before doing this, copy  the public key `/etc/ceph/ceph.pub` into `/root/.ssh/authorized_keys` of OSD nodes. Then, add the nodes from the monitor node:
```bash
ceph orch host add vmm102
ceph orch host add vmm103
# following command is optional and it clean a used partition
ceph orch device zap vmm103 /dev/sdb --force
```
**NOTE** In this step, I have to use the root user instead of **debian**. The reason is that root is hardcoded and I could not changed. This has been fixed in Ceph but it is not upstream yet. I have to modify this step when it hits upstream.  
 ### Step 4. Add OSDs nodes
Add the block devices that will belong to the cluster. In this case, we use the `/dev/sdb` disk of each OSD node:
```bash
ceph orch daemon add osd vmm102:/dev/sdb
ceph orch daemon add osd vmm103:/dev/sdb
ceph orch daemon add osd vmm101:/dev/sdb
```
Since monitors are light-weight, it is possible to run them on the same host as an OSD. We add an OSD in the monitor.
### Step 5. Create CephFS Filesystem
To create the filesystem, use the interface fs volume which creates the pools and msd service automatically. In this case, the name of the fs is **vmmcephfs** and the user is **vmmcephuser**. The second command returns the secret key that must be used by clients. Please store it for later
```bash
ceph fs volume create vmmcephfs
ceph fs authorize vmmcephfs client.vmmcephsuser / rw
```
### Step 6. Prepare and Mount CephFS in clients
In this step, we first prepare the client by installing all the necessary packages and then we mount the CephFS. These steps must be followed for every new client. First, you need docker and ceph-common:
```bash
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
```
We are going to compile  latest QEMU (+5.1)  with support for for microvm, virtiofs and vsocket:
```bash
apt-get install libcap-dev libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev libglib2.0-dev libpixman-1-dev libseccomp-dev -y
git clone https://github.com/qemu/qemu.git qemuforvmm
cd qemuforvmm
mkdir build 
cd build
# TODO: reduce the size of qemu
../configure --target-list=x86_64-softmmu
make
```
You can find **virtiofsd** at `~/qemuforvmm/build/tools/virtiofsd`. Finally, load **vsock** module:

```bash
modprobe vhost_vsock
```
Mount the Cephfs at `/home/debian/cephfs`:
```bash
mkdir –-mode=777 ~/cephfs
mount -t ceph vmm101:6789:/ /home/debian/cephfs -o name=vmmcephuser,secret=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```
For unmount, run `umount ./cephfs`.
To automate this step, execute `scripts/deploy_client.sh` at `~/`.

### Step 8. Add new OSD node 
To add new OSD node, you have just to repeat the steps 1, then step 3 and step 4.

### Step 9. Remove an OSD node
To remove an OSD node, just execute this:

```bash
ceph orch host rm *<hostname>*
```