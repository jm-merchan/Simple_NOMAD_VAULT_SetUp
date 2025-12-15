job "windows-server" {
  datacenters = ["remote-site1"]
  type        = "service"
  priority    = "100"
  
  group "windows-vm" {
    
    # Blue/Green deployment configuration
    update {
      max_parallel      = 1
      canary            = 1
      min_healthy_time  = "60s"
      healthy_deadline  = "30m"  # Allow 30 minutes for ISO download
      progress_deadline = "35m"  # Must be greater than healthy_deadline
      auto_revert       = true
      auto_promote      = false
      health_check      = "task_states"
    }
    
    # Restart policy
    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }
    
    # Network configuration
    # RDP: Remote Desktop Protocol for Windows management
    # VNC: Console access for Windows installation
    network {
      mode = "host"
      port "rdp" {
        static = 3390  # RDP port (changed from 3389 to avoid conflict)
      }
      port "vnc" {
        static = 5901  # VNC port (changed from 5900 to avoid conflict)
      }
    }
    
    # Service registration for RDP access
    service {
      name     = "windows-server-rdp"
      port     = "rdp"
      provider = "nomad"
      tags     = ["rdp", "windows-server", "remote-desktop"]
    }
    
    # Service registration for VNC access
    service {
      name     = "windows-server-vnc"
      port     = "vnc"
      provider = "nomad"
      tags     = ["vnc", "windows-server", "remote-desktop"]
    }
    
    # Prestart task to create the virtual hard disk directly in windows-server task directory
    task "prepare-vm" {
      driver = "raw_exec"
      
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
      
      config {
        command = "/bin/bash"
        args    = ["-c", "mkdir -p ${NOMAD_ALLOC_DIR}/windows-server/local && qemu-img create -f qcow2 ${NOMAD_ALLOC_DIR}/windows-server/local/windows-disk.qcow2 60G"]
      }
    }
    
    # Main QEMU task to run Windows Server VM
    task "windows-server" {
      driver = "qemu"
      
      # Download the Windows Server Evaluation ISO
      # Served from local HTTP server for faster deployment
      artifact {
        source      = "http://localhost:8000/SERVER_EVAL_x64FRE_en-us.iso"
        destination = "local/windows-server.iso"
        mode        = "file"
      }
      
      # Download a dummy qcow2 image to create initial disk
      artifact {
        source      = "http://localhost:8000/windows-disk.qcow2"
        destination = "local/windows-disk.qcow2"
        mode        = "file"
      }
      
      config {
        image_path        = "local/windows-disk.qcow2"
        accelerator       = "kvm"
        graceful_shutdown = true
        args = [
          "-m", "4096",
          "-smp", "2",
          "-cpu", "host",
          "-boot", "once=d",
          "-cdrom", "local/windows-server.iso",
          "-net", "nic,model=e1000",
          "-net", "user,hostfwd=tcp::${NOMAD_PORT_rdp}-:3389",
          "-vnc", "0.0.0.0:1",
          "-display", "none"
        ]
      }
      
      # Resource allocation for the VM
      resources {
        cpu    = 2000  # 2 CPU cores
        memory = 4096  # 4GB RAM
      }
    }
  }
}
