# Deploying a 3-node Ceph Cluster
## Introduction
In this tutorial, we explain how to deploy a Cephs cluster and how to set up the client to access the cluster and how to install all the tools to launch Toro VMs in some nodes. 

TODO: ssh keys distributions

TODO: There are 3 major kind of scripts :

\- setup the initial cluster with 3 nodes (or any number of nodes, the guy will simply copy/paste inside the script)

\- setup of an additional node

\- setup of a compute node in case the sysadmin decide not to run as hyperconverged but too split storage and compute nodes.

## Nodes

* vmm101, 51.75.15.149, 10.2.2.127, mon, osd
* vmm102, 51.83.109.111, 10.2.2.33, OSD
* vmm103, 51.178.95.20, 10.2.0.31, OSD
* vmm104, 51.210.189.212, 10.2.0.75 , client
* vmm105, 51.210.186.20, 10.2.0.171, client

- OSD nodes have a *sdb* partition of 10GB which is used for the cluster
- The operating system is Debian 4.19.37-5+deb10u1 (2019-07-19) 

## Setup
### Step 1. Configure all nodes
The following steps must be done for each node:

We are going to use the **debian** user that has root access. 

#### Configure LAN IP
1. Edit */etc/network/interfaces* and add:
`iface eth1 inet static`
`address 10.2.2.127`
`netmask 255.255.0.0`
`gateway 10.2.2.254`
2. Then, execute:
`sudo ifdown eth1`
`sudo ifup eth1`

3. Check the ip by doing:
`ip addr show`

Change the address and the gateway depending on the host.

#### Configure Host File 
We are going to configure the hosts so each node is visible by using shornames. 
1. Edit */etc/hosts* and add:

  `10.2.0.75       vmm104.xmlrad.org       vmm104`
  `10.2.2.127      vmm101.xmlrad.org       vmm101`
  `10.2.2.33       vmm102.xmlrad.org       vmm102`
  `10.2.0.31       vmm103.xmlrad.org       vmm103`
  `10.2.0.171      vmm105.xmlrad.org       vmm105`

#### Install Docker (for everyone)
* `sudo apt-get update`
* `sudo apt install apt-transport-https ca-certificates curl gnupg2 software-properties-common -y`
* `curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -`
* `sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"`
* `sudo apt update`
* `sudo apt install docker-ce -y`

#### Install LVM2 (only for OSDs)
```bash
apt-get install lvm2 -y
```

#### Install  Ceph-common (only for Clients and OSD to install the kernel drivers)
```bash
curl --silent --remote-name --location https://github.com/ceph/ceph/raw/octopus/src/cephadm/cephadm
chmod +x cephadm
./cephadm add-repo --release octopus
./cephadm install ceph-common
```

#### Install Ceph (only for Monitor Node)
* `curl --silent --remote-name --location https://github.com/ceph/ceph/raw/octopus/src/cephadm/cephadm`
* `chmod +x cephadm`
* `wget -q -O- 'https://download.ceph.com/keys/release.asc' | sudo apt-key add -`
* `echo deb https://download.ceph.com/debian-octopus/ $(lsb_release -sc) main | sudo tee /etc/apt/sources.list.d/ceph.list`
* `sudo apt-get update`
* `sudo ./cephadm install cephadm ceph-common`

### Step 2. Create Monitor Node
* `sudo mkdir -p /etc/ceph`
* `sudo ./cephadm bootstrap --mon-ip 10.2.2.127 --ssh-user debian --allow-overwrite`

In this step, you can avoid ssh-user and allow overwrite
Since monitors are light-weight, it is possible to run them on the same host as an OSD;

### Step 3. Add hosts to the cluster
For this step, I copy the public key from `/etc/ceph/ceph.pub` and I pasted into `/root/.ssh/authorized_keys`. 

* `ceph orch host add vmm102`
* `ceph orch host add vmm103`
* `ceph orch device zap vmm103 /dev/sdb --force` en el caso que alla particiones llenas `ceph orch device ls`

 ### Step 4. Add OSDs nodes
* `sudo ceph orch daemon add osd vmm102:/dev/sdb`

* `sudo ceph orch daemon add osd vmm103:/dev/sdb`

* `sudo ceph orch daemon add osd vmm101:/dev/sdb`

Since monitors are light-weight, it is possible to run them on the same host as an OSD. We add an OSD in the monitor.

### Step 5. Create CephFS Filesystem
To create the filesystem, uses the interface fs volume which creates the pools and msd service automatically. Optionally, the placement can be passed as a parameter. 

* `sudo ceph fs volume create vmmcephfs`
* Get the secret key by executing: 
`sudo ceph fs authorize vmmcephfs client.vmmcephsuser / rw`
store the key to use it later. 

### Step 6. Mount FS in Clients
In the client execute the following to create a directory that can be accesed from anyone:

`mkdir –-mode=777 ~/cephfs`

`sudo mount -t ceph vmm101:6789:/ /home/debian/cephfs -o name=vmmcephuser,secret=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

The automatic use of the conf files did not work for mount.

`umount ./cephfs`

### Step 7. Compile latest QEMU in Clients and enable VSock
We are going to compile  latest QEMU (+5.1)  with support for for microvm, virtiofs and vsocket. First, we need to install the following libraries:

```bash
apt-get install libcap-dev libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev libglib2.0-dev libpixman-1-dev libseccomp-dev -y
```
Then, clone and compile QEMU:
```bash
git clone https://github.com/qemu/qemu.git qemuforvmm
cd qemuforvmm
mkdir build 
cd build
# TODO: reduce the size of qemu
../configure --target-list=x86_64-softmmu
make
```
You can find **virtiofsd** at `~/qemuforvmm/build/tools/virtiofsd`.
Finally, load **vsock** module:

```bash
modprobe vhost_vsock
```
To automate these steos, use the script `scripts/install_qemu.sh` by passing as parameter the directory in which you want to clone qemu. The script must be executed ar `~/`:
```bash
./scripts/install_qemu.sh ~/qemuforvmm
```