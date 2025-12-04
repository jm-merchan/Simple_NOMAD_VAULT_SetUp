job "windows-server-bridge" {
  datacenters = ["remote-site1"]
  type        = "service"
  priority    = "100"
  
  group "windows-vm" {
    
    # Increase timeout for large ISO download (~5GB)
    # Windows Server ISO takes significant time to download
    update {
      health_check      = "task_states"
      min_healthy_time  = "30s"
      healthy_deadline  = "30m"  # Allow 30 minutes for ISO download
      progress_deadline = "35m"  # Must be greater than healthy_deadline
    }
    
    # Network configuration for VNC only (VM will get DHCP from network)
    network {
      mode = "host"
      port "vnc" {
        static = 5902  # VNC port (different from NAT version)
      }
    }
    
    # Service registration for VNC access
    service {
      name     = "windows-server-bridge-vnc"
      port     = "vnc"
      provider = "nomad"
      tags     = ["vnc", "windows-server", "bridge", "remote-desktop"]
    }
    
    # Main QEMU task to run Windows Server VM with bridge networking
    task "windows-server" {
      driver = "qemu"
      
      # Download the Windows Server Evaluation ISO (Desktop Experience)
      # Served from local HTTP server for faster deployment
      artifact {
        source      = "http://localhost:8000/SERVER_EVAL_x64FRE_en-us.iso.1"
        destination = "local/windows-server-desktop.iso"
        mode        = "file"
      }
      
      # Download the disk image
      artifact {
        source      = "http://localhost:8000/windows-disk-desktop.qcow2"
        destination = "local/windows-disk-desktop.qcow2"
        mode        = "file"
      }
      
      config {
        image_path        = "local/windows-disk-desktop.qcow2"
        accelerator       = "kvm"
        graceful_shutdown = true
        args = [
          "-m", "4096",
          "-smp", "2",
          "-cpu", "host",
          "-boot", "once=d",
          "-cdrom", "local/windows-server-desktop.iso",
          "-netdev", "bridge,id=net0,br=br0",
          "-device", "e1000,netdev=net0,mac=52:54:00:12:34:57",
          "-vnc", "0.0.0.0:2",
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
