job "apache" {
  datacenters = ["remote-site1"]
  namespace = "NS1"
  type = "service"

  group "webserver" {
    disconnect {
      lost_after  = "12h"
      reconcile   = "keep_original"
    }

    count = 3
    
    # Blue/Green deployment strategy
    update {
      max_parallel     = 1
      canary           = 3
      min_healthy_time = "10s"
      healthy_deadline = "3m"
      auto_revert      = true
      auto_promote     = false
    }
    
    network {
      port "http" {
        to = 80
      }
    }

    service {
      provider = "nomad" 
      name = "apache-webserver"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.apache.rule=PathPrefix(`/apache`)",
        "traefik.http.routers.apache.entrypoints=web",
        "traefik.http.middlewares.apache-strip.stripprefix.prefixes=/apache",
        "traefik.http.routers.apache.middlewares=apache-strip"
      ]
      port = "http"
      
      # Only route to healthy instances
      canary_tags = [
        "traefik.enable=true",
        "traefik.http.routers.apache-canary.rule=PathPrefix(`/`)",
        "traefik.http.routers.apache-canary.entrypoints=web",
        "canary"
      ]
      
      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    restart {
      attempts = 2
      interval = "30m"
      delay = "15s"
      mode = "fail"
    }

    task "apache" {
      driver = "docker"
      
      env {
        APP_VERSION = "2.0.0"
        APP_COLOR   = "blue"
      }
      
      template {
        data = <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Apache Server v{{ env "APP_VERSION" }}</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 50%, #7e22ce 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 24px;
            box-shadow: 0 25px 70px rgba(0,0,0,0.4);
            padding: 50px;
            max-width: 900px;
            width: 100%;
            border: 1px solid rgba(255,255,255,0.3);
        }
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        h1 {
            color: #1e293b;
            margin-bottom: 15px;
            font-size: 3em;
            font-weight: 800;
            letter-spacing: -1px;
        }
        .version-badge {
            display: inline-block;
            background: linear-gradient(135deg, #3b82f6 0%, #8b5cf6 100%);
            color: white;
            padding: 12px 30px;
            border-radius: 30px;
            font-weight: 700;
            font-size: 1.1em;
            margin: 10px 0;
            box-shadow: 0 4px 15px rgba(59, 130, 246, 0.4);
        }
        .color-indicator {
            display: inline-block;
            width: 20px;
            height: 20px;
            border-radius: 50%;
            background: {{ env "APP_COLOR" }};
            margin-left: 10px;
            vertical-align: middle;
            border: 3px solid white;
            box-shadow: 0 2px 8px rgba(0,0,0,0.2);
        }
        .deployment-type {
            background: #10b981;
            color: white;
            padding: 8px 20px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: 600;
            display: inline-block;
            margin-top: 10px;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-top: 40px;
        }
        .info-card {
            background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%);
            border-left: 5px solid #3b82f6;
            padding: 24px;
            border-radius: 12px;
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }
        .info-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: linear-gradient(135deg, transparent 0%, rgba(59, 130, 246, 0.1) 100%);
            opacity: 0;
            transition: opacity 0.3s ease;
        }
        .info-card:hover {
            transform: translateY(-8px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.15);
        }
        .info-card:hover::before {
            opacity: 1;
        }
        .info-label {
            font-weight: 700;
            color: #475569;
            font-size: 0.85em;
            text-transform: uppercase;
            letter-spacing: 1.5px;
            margin-bottom: 10px;
            position: relative;
        }
        .info-value {
            color: #1e293b;
            font-size: 1.05em;
            word-break: break-all;
            font-family: 'Courier New', monospace;
            font-weight: 600;
            position: relative;
        }
        .status-section {
            text-align: center;
            margin: 30px 0;
            padding: 20px;
            background: linear-gradient(135deg, #ecfdf5 0%, #d1fae5 100%);
            border-radius: 12px;
            border: 2px solid #10b981;
        }
        .status-badge {
            font-size: 1.2em;
            font-weight: 700;
            color: #047857;
        }
        .footer {
            text-align: center;
            margin-top: 40px;
            padding-top: 30px;
            border-top: 2px solid #e2e8f0;
            color: #64748b;
            font-size: 0.95em;
            font-weight: 500;
        }
        .icon {
            font-size: 2em;
            margin-bottom: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="icon">🚀</div>
            <h1>Apache Web Server</h1>
            <div class="version-badge">
                Version {{ env "APP_VERSION" }}
                <span class="color-indicator"></span>
            </div>
            <div class="deployment-type">Blue/Green Deployment</div>
        </div>
        
        <div class="status-section">
            <div class="status-badge">✓ HEALTHY & RUNNING</div>
        </div>
        
        <div class="info-grid">
            <div class="info-card">
                <div class="info-label">🆔 Allocation ID</div>
                <div class="info-value">{{ env "NOMAD_ALLOC_ID" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">📛 Allocation Name</div>
                <div class="info-value">{{ env "NOMAD_ALLOC_NAME" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">💼 Job Name</div>
                <div class="info-value">{{ env "NOMAD_JOB_NAME" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">📦 Task Group</div>
                <div class="info-value">{{ env "NOMAD_GROUP_NAME" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">🏷️ Namespace</div>
                <div class="info-value">{{ env "NOMAD_NAMESPACE" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">🌍 Datacenter</div>
                <div class="info-value">{{ env "NOMAD_DC" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">🖥️ Node ID</div>
                <div class="info-value">{{ env "node.unique.id" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">🌐 IP Address</div>
                <div class="info-value">{{ env "NOMAD_IP_http" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">🔌 Port</div>
                <div class="info-value">{{ env "NOMAD_PORT_http" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">⚡ CPU Limit</div>
                <div class="info-value">{{ env "NOMAD_CPU_LIMIT" }} MHz</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">💾 Memory Limit</div>
                <div class="info-value">{{ env "NOMAD_MEMORY_LIMIT" }} MB</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">🗺️ Region</div>
                <div class="info-value">{{ env "NOMAD_REGION" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">🎨 Deployment Color</div>
                <div class="info-value">{{ env "APP_COLOR" }}</div>
            </div>
            
            <div class="info-card">
                <div class="info-label">📊 App Version</div>
                <div class="info-value">{{ env "APP_VERSION" }}</div>
            </div>
        </div>
        
        <div class="footer">
            <p><strong>Traefik Load Balancer</strong> • HashiCorp Nomad Orchestration</p>
            <p style="margin-top: 8px; font-size: 0.85em;">Refresh to see load balancing in action</p>
        </div>
    </div>
</body>
</html>
EOF
        destination = "local/index.html"
      }
      
      config {
        image = "httpd:latest"
        ports = ["http"]
        volumes = [
          "local/index.html:/usr/local/apache2/htdocs/index.html"
        ]
      }
    }
  }
}
