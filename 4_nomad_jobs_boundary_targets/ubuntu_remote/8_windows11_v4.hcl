job "windows11" {
  datacenters = ["remote-site1"]
  type        = "service"
  priority    = "100"
  
  group "windows11-vm" {
    disconnect {
      lost_after  = "12h"
      reconcile   = "keep_original"
    }
    
    # Blue/Green deployment configuration
    update {
      max_parallel     = 1
      canary           = 1
      min_healthy_time = "60s"
      healthy_deadline = "10m"
      auto_revert      = true
      auto_promote     = false
      progress_deadline = "15m"
    }
    
    # Restart policy
    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }
    
    # Network configuration for VNC and RDP access
    network {
      mode = "host"
      port "vnc" {
        static = 5907  # Different port from v1 (5905) and v2 (5906)
      }
      port "rdp" {
        static = 3392  # Different port from v1 (3390) and v2 (3391)
      }
    }
    
    # Service registration for VNC access
    service {
      name     = "windows11-vnc"
      port     = "vnc"
      provider = "nomad"
      tags     = ["vnc", "windows11", "remote-desktop", "v4", "usb-wireless", "nat"]
    }
    
    # Service registration for RDP access
    service {
      name     = "windows11-rdp"
      port     = "rdp"
      provider = "nomad"
      tags     = ["rdp", "windows11", "remote-desktop", "v4", "usb-wireless", "nat"]
    }
    
    # Prestart task to create TPM directory and start swtpm in background
    task "setup-tpm" {
      driver = "raw_exec"
      
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }
      
      template {
        data = <<EOF
#!/bin/bash
mkdir -p /tmp/win11-installed-v4-tpm-{{ env "NOMAD_ALLOC_ID" }}
/usr/bin/swtpm socket \
  --tpmstate dir=/tmp/win11-installed-v4-tpm-{{ env "NOMAD_ALLOC_ID" }} \
  --ctrl type=unixio,path=/tmp/win11-installed-v4-swtpm-{{ env "NOMAD_ALLOC_ID" }}.sock \
  --tpm2 \
  --log level=20
EOF
        destination = "local/start-tpm.sh"
        perms       = "755"
      }
      
      config {
        command = "/bin/bash"
        args    = ["local/start-tpm.sh"]
      }
      
      resources {
        cpu    = 100
        memory = 128
      }
    }
    
    # Main QEMU task to run Windows 11 VM (V4 with bridge networking)
    task "windows11" {
      driver = "qemu"
      
      # Download the disk image with Windows 11 already installed (V2)
      artifact {
        source      = "http://localhost:8000/windows11-disk-v3.qcow2"
        destination = "local/windows11-disk.qcow2"
        mode        = "file"
      }
      
      # Download UEFI code file (Secure Boot firmware)
      artifact {
        source      = "http://localhost:8000/OVMF_CODE.fd"
        destination = "local/OVMF_CODE.fd"
        mode        = "file"
      }
      
      # Download UEFI variables file
      artifact {
        source      = "http://localhost:8000/win11-efivars.fd"
        destination = "local/win11-efivars.fd"
        mode        = "file"
      }
      
      config {
        image_path        = "local/windows11-disk.qcow2"
        accelerator       = "kvm"
        graceful_shutdown = true
        port_map {
          vnc = 5907
          rdp = 3392
        }
        args = [
          "-enable-kvm",
          "-machine", "type=q35",
          "-m", "8192",
          "-smp", "8",
          "-cpu", "host",
          # UEFI firmware for Secure Boot
          "-drive", "if=pflash,format=raw,readonly=on,file=local/OVMF_CODE.fd",
          "-drive", "if=pflash,format=raw,file=local/win11-efivars.fd",
          # AHCI controller for SATA devices
          "-device", "ahci,id=ahci",
          # Main disk is automatically added by image_path
          # TPM 2.0 emulation - socket in /tmp with unique ID
          "-chardev", "socket,id=chrtpm,path=/tmp/win11-installed-v4-swtpm-${NOMAD_ALLOC_ID}.sock",
          "-tpmdev", "emulator,id=tpm0,chardev=chrtpm",
          "-device", "tpm-tis,tpmdev=tpm0",
          # USB Controller (XHCI for USB 3.0 support)
          "-device", "qemu-xhci,id=xhci",
          # USB Wireless Adapter Passthrough (Realtek RTL8188EUS) for WiFi
          "-device", "usb-host,vendorid=0x0bda,productid=0x8179,bus=xhci.0",
          # User mode networking with RDP port forwarding (Ethernet)
          "-netdev", "user,id=net0,hostfwd=tcp::3392-:3389",
          "-device", "e1000,netdev=net0",
          # VNC display
          "-vnc", "0.0.0.0:7",
          "-display", "none"
        ]
      }
      
      # Resource allocation for the VM
      resources {
        cpu    = 8000  # 8 CPU cores
        memory = 8192  # 8GB RAM
      }
      
      # Environment variables for documentation
      env {
        VM_TYPE        = "Windows 11 Pro (V4 - NAT + USB WiFi)"
        VNC_PORT       = "5907"
        RDP_PORT       = "3392"
        VERSION        = "4.0"
        NETWORK_MODE   = "user-nat"
        USB_DEVICE     = "Realtek RTL8188EUS (0bda:8179) for WiFi"
      }
    }
  }
}
