job "windows11" {
  datacenters = ["remote-site1"]
  type        = "service"
  priority    = "100"
  
  group "windows11-vm" {
    
    # Standard update configuration
    update {
      health_check      = "task_states"
      min_healthy_time  = "30s"
      healthy_deadline  = "10m"
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
        static = 5905  # Different port from installation job
      }
      port "rdp" {
        static = 3395  # Windows 11 v2 RDP port
      }
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
mkdir -p /tmp/win11-installed-tpm-{{ env "NOMAD_ALLOC_ID" }}
/usr/bin/swtpm socket \
  --tpmstate dir=/tmp/win11-installed-tpm-{{ env "NOMAD_ALLOC_ID" }} \
  --ctrl type=unixio,path=/tmp/win11-installed-swtpm-{{ env "NOMAD_ALLOC_ID" }}.sock \
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
    
    # Service registration for VNC access
    service {
      name     = "windows11-vnc"
      port     = "vnc"
      provider = "nomad"
      tags     = ["vnc", "windows11", "remote-desktop"]
    }
    
    # Service registration for RDP access
    service {
      name     = "windows11-rdp"
      port     = "rdp"
      provider = "nomad"
      tags     = ["rdp", "windows11", "remote-desktop"]
    }
    
    # Main QEMU task to run Windows 11 VM (already installed)
    task "windows11" {
      driver = "qemu"
      
      # Download the disk image with Windows 11 already installed
      artifact {
        source      = "http://localhost:8000/windows11-disk-installed.qcow2"
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
          vnc = 5905
          rdp = 3395
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
          "-chardev", "socket,id=chrtpm,path=/tmp/win11-installed-swtpm-${NOMAD_ALLOC_ID}.sock",
          "-tpmdev", "emulator,id=tpm0,chardev=chrtpm",
          "-device", "tpm-tis,tpmdev=tpm0",
          # User mode networking with RDP port forwarding
          "-netdev", "user,id=net0,hostfwd=tcp::3395-:3389",
          "-device", "e1000,netdev=net0",
          # VNC display
          "-vnc", "0.0.0.0:5",
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
        VM_TYPE        = "Windows 11 Pro (Installed)"
        VNC_PORT       = "5905"
        RDP_PORT       = "3395"
      }
    }
  }
}
