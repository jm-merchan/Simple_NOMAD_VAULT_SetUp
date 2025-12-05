job "windows11-bridge" {
  datacenters = ["remote-site1"]
  type        = "service"
  priority    = "100"
  
  group "windows11-vm" {
    
    # Increase timeout for large ISO download
    # Windows 11 ISO takes significant time to download
    update {
      health_check      = "task_states"
      min_healthy_time  = "30s"
      healthy_deadline  = "30m"  # Allow 30 minutes for ISO download
      progress_deadline = "35m"  # Must be greater than healthy_deadline
    }
    
    # Restart policy - don't restart on failure during testing
    restart {
      attempts = 0
      mode     = "fail"
    }
    
    # Network configuration for VNC and RDP access
    network {
      mode = "host"
      port "vnc" {
        static = 5903  # VNC port for Windows 11
      }
      port "rdp" {
        static = 3389  # RDP port for Windows 11 (enable RDP inside Windows first)
      }
    }
    
    # Service registration for VNC access
    service {
      name     = "windows11-install-vnc"
      port     = "vnc"
      provider = "nomad"
      tags     = ["vnc", "windows11", "install", "remote-desktop"]
    }
    
    # Service registration for RDP access
    service {
      name     = "windows11-install-rdp"
      port     = "rdp"
      provider = "nomad"
      tags     = ["rdp", "windows11", "install", "remote-desktop"]
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
mkdir -p /tmp/win11-tpm-{{ env "NOMAD_ALLOC_ID" }}
/usr/bin/swtpm socket \
  --tpmstate dir=/tmp/win11-tpm-{{ env "NOMAD_ALLOC_ID" }} \
  --ctrl type=unixio,path=/tmp/win11-swtpm-{{ env "NOMAD_ALLOC_ID" }}.sock \
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
    
    # Main QEMU task to run Windows 11 VM
    task "windows11" {
      driver = "qemu"
      
      # Download the Windows 11 ISO
      # Served from local HTTP server for faster deployment
      artifact {
        source      = "http://localhost:8000/Win11_25H2_English_x64.iso"
        destination = "local/windows11.iso"
        mode        = "file"
      }
      
      # Download the disk image (compressed to reduce download size)
      artifact {
        source      = "http://localhost:8000/windows11-disk-tpm.qcow2"
        destination = "local/windows11-disk-tpm.qcow2"
        mode        = "file"
      }
      
      # Download UEFI code file (Secure Boot firmware)
      # Command: sudo cp /usr/share/OVMF/OVMF_CODE_4M.secboot.fd /home/jose/OVMF_CODE.fd && sudo chown jose:jose /home/jose/OVMF_CODE.fd
      artifact {
        source      = "http://localhost:8000/OVMF_CODE.fd"
        destination = "local/OVMF_CODE.fd"
        mode        = "file"
      }
      
      # Download UEFI variables file (for Secure Boot)
      # Command: sudo cp /usr/share/OVMF/OVMF_VARS_4M.fd /home/jose/win11-efivars.fd && sudo chown jose:jose /home/jose/win11-efivars.fd
      artifact {
        source      = "http://localhost:8000/win11-efivars.fd"
        destination = "local/win11-efivars.fd"
        mode        = "file"
      }
      
      config {
        image_path        = "local/windows11-disk-tpm.qcow2"
        accelerator       = "kvm"
        graceful_shutdown = true
        port_map {
          vnc = 5903
          rdp = 3389
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
          # Boot order: try CD-ROM first, then disk
          "-boot", "order=d,menu=on",
          # AHCI controller for SATA devices
          "-device", "ahci,id=ahci",
          # CD-ROM with Windows 11 ISO on ahci.0 with bootindex=0 (highest priority)
          "-drive", "file=local/windows11.iso,media=cdrom,if=none,id=drive-cd",
          "-device", "ide-cd,drive=drive-cd,bus=ahci.0,bootindex=0",
          # Main disk is automatically added by image_path as ide-hd on ahci.1
          # TPM 2.0 emulation - socket in /tmp with unique ID
          "-chardev", "socket,id=chrtpm,path=/tmp/win11-swtpm-${NOMAD_ALLOC_ID}.sock",
          "-tpmdev", "emulator,id=tpm0,chardev=chrtpm",
          "-device", "tpm-tis,tpmdev=tpm0",
          # User mode networking with RDP port forwarding
          "-netdev", "user,id=net0,hostfwd=tcp::3389-:3389",
          "-device", "e1000,netdev=net0",
          # VNC display
          "-vnc", "0.0.0.0:3",
          "-display", "none"
        ]
      }
      
      # Resource allocation for the VM
      resources {
        cpu    = 8000  # 8 CPU cores
        memory = 8192  # 8GB RAM
      }
    }
  }
}
