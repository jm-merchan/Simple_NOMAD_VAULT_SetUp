# Windows 11 VM Setup with Static IP

## Prerequisites

1. **Create the disk image on the Ubuntu host (192.168.1.36)**

```bash
ssh jose@192.168.1.36
cd /home/jose
qemu-img create -f qcow2 windows11-disk.qcow2 80G
```

2. **Verify the Windows 11 ISO is in place**

```bash
ls -lh /home/jose/Win11_25H2_English_x64.iso
```

3. **Ensure the HTTP server job is running**

The `0_http_server.hcl` job must be running to serve the ISO and disk image.

## Deploy the Windows 11 VM

```bash
nomad job run 7_install_windows11.hcl
```

## Access via VNC

Connect to VNC to perform Windows installation:

```
vnc://192.168.1.36:5903
```

## Configure Static IP in Windows 11

Once Windows 11 is installed and booted:

1. **Open Network Settings**
   - Press `Win + I` to open Settings
   - Go to `Network & Internet` → `Ethernet` (or the network adapter name)
   - Click on the network adapter

2. **Configure IP Settings**
   - Click `Edit` next to IP assignment
   - Select `Manual`
   - Toggle `IPv4` to On
   - Enter the following:
     - **IP address**: `192.168.1.222`
     - **Subnet mask**: `255.255.255.0` (or prefix length: `24`)
     - **Gateway**: `192.168.1.1`
     - **Preferred DNS**: `192.168.1.1`
     - **Alternate DNS**: `8.8.8.8` (optional)
   - Click `Save`

## Alternative: Configure via Command Line (PowerShell as Administrator)

```powershell
# Get the network adapter name
Get-NetAdapter

# Configure static IP (replace "Ethernet" with your adapter name)
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.1.222 -PrefixLength 24 -DefaultGateway 192.168.1.1

# Set DNS servers
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.1.1,8.8.8.8
```

## Verify Network Configuration

```powershell
# Check IP configuration
ipconfig /all

# Test connectivity
ping 192.168.1.1
ping 8.8.8.8
```

## Access via RDP

Once the static IP is configured and RDP is enabled in Windows:

```
rdp://192.168.1.222:3389
```

## VM Specifications

- **CPU**: 4 cores
- **RAM**: 6GB
- **Disk**: 80GB (qcow2, sparse allocation)
- **Network**: Bridge mode (br0) with MAC `52:54:00:12:34:58`
- **Static IP**: 192.168.1.222/24
- **Gateway**: 192.168.1.1
- **VNC Port**: 5903

## Troubleshooting

### Check if VM is running

```bash
ssh jose@192.168.1.36
ps aux | grep qemu | grep windows11
```

### Check network interface

```bash
sudo brctl show br0
ip link show | grep tap
```

### Monitor network traffic

```bash
sudo tcpdump -i tap1 -n icmp
```

### Verify static IP from router

Check your router's DHCP/ARP table or use:

```bash
arp -a | grep 52:54:00:12:34:58
ping 192.168.1.222
```

## Notes

- The MAC address `52:54:00:12:34:58` is unique to this VM
- If you need to bypass Windows 11's TPM/Secure Boot requirements during installation, press `Shift + F10` at the installation screen and run `regedit` to add bypass registry keys
- For better performance, consider using virtio drivers (requires downloading virtio-win ISO)
