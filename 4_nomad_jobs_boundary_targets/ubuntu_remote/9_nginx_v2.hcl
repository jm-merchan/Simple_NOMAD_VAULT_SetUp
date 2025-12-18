job "nginx-web" {
  datacenters = ["remote-site1"]
  namespace = "NS1"

  group "demo" {
    count = 3

    disconnect {
      lost_after  = "12h"
      reconcile   = "keep_original"
    }
    
    # Canary deployment strategy
    update {
      max_parallel      = 1
      canary            = 1
      min_healthy_time  = "60s"
      healthy_deadline  = "10m"
      auto_revert       = true
      auto_promote      = false
      progress_deadline = "15m"
      health_check      = "checks"
      stagger           = "60s"
    }

    network {
      port "http" {
        to = 80
      }
    }

    service {
      provider = "nomad"
      name = "nginx-webapp"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.nginx.rule=PathPrefix(`/nginx`)",
        "traefik.http.routers.nginx.entrypoints=web",
        "traefik.http.middlewares.nginx-strip.stripprefix.prefixes=/nginx",
        "traefik.http.routers.nginx.middlewares=nginx-strip",
        "traefik.http.services.nginx-webapp.loadbalancer.passhostheader=true"
      ]
      port = "http"
      
      canary_tags = [
        "traefik.enable=true",
        "traefik.http.routers.nginx-canary.rule=PathPrefix(`/nginx`) && Headers(`X-Canary`, `true`)",
        "traefik.http.routers.nginx-canary.entrypoints=web",
        "traefik.http.middlewares.nginx-canary-strip.stripprefix.prefixes=/nginx",
        "traefik.http.routers.nginx-canary.middlewares=nginx-canary-strip",
        "traefik.http.services.nginx-webapp.loadbalancer.passhostheader=true",
        "canary"
      ]

      check {
        type     = "http"
        path     = "/"
        interval = "15s"
        timeout  = "5s"
      }
    }

    task "nginx" {
      driver = "docker"
      
      env {
        APP_VERSION = "2.5.0"
        APP_COLOR   = "orange"
      }
      
      template {
        data = <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Demo WebApp v{{ env "APP_VERSION" }}</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #ea580c 0%, #f97316 50%, #fb923c 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
            animation: gradientShift 10s ease infinite;
            background-size: 200% 200%;
        }
        @keyframes gradientShift {
            0%, 100% { background-position: 0% 50%; }
            50% { background-position: 100% 50%; }
        }
        .container {
            background: rgba(255, 255, 255, 0.98);
            backdrop-filter: blur(20px);
            border-radius: 30px;
            box-shadow: 0 30px 80px rgba(0,0,0,0.3);
            padding: 60px;
            max-width: 950px;
            width: 100%;
            border: 2px solid rgba(249, 115, 22, 0.3);
            animation: float 6s ease-in-out infinite;
        }
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-10px); }
        }
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        h1 {
            color: #7c2d12;
            margin-bottom: 15px;
            font-size: 3.5em;
            font-weight: 900;
            letter-spacing: -2px;
            background: linear-gradient(135deg, #ea580c, #f97316);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        .version-badge {
            display: inline-block;
            background: linear-gradient(135deg, #f97316 0%, #fb923c 100%);
            color: white;
            padding: 15px 35px;
            border-radius: 40px;
            font-weight: 800;
            font-size: 1.2em;
            margin: 10px 0;
            box-shadow: 0 6px 20px rgba(249, 115, 22, 0.5);
            animation: pulse 2s ease infinite;
        }
        @keyframes pulse {
            0%, 100% { transform: scale(1); }
            50% { transform: scale(1.05); }
        }
        .color-indicator {
            display: inline-block;
            width: 24px;
            height: 24px;
            border-radius: 50%;
            background: {{ env "APP_COLOR" }};
            margin-left: 12px;
            vertical-align: middle;
            border: 4px solid white;
            box-shadow: 0 3px 10px rgba(0,0,0,0.3);
        }
        .deployment-type {
            background: linear-gradient(135deg, #7c3aed, #a78bfa);
            color: white;
            padding: 10px 25px;
            border-radius: 25px;
            font-size: 1em;
            font-weight: 700;
            display: inline-block;
            margin-top: 12px;
            box-shadow: 0 4px 15px rgba(124, 58, 237, 0.4);
        }
        .canary-notice {
            background: linear-gradient(135deg, #fef3c7, #fde68a);
            border: 2px solid #f59e0b;
            padding: 20px;
            border-radius: 15px;
            margin: 20px 0;
            text-align: center;
        }
        .canary-notice h3 {
            color: #92400e;
            margin-bottom: 10px;
            font-size: 1.3em;
        }
        .canary-notice p {
            color: #78350f;
            font-weight: 600;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 24px;
            margin-top: 40px;
        }
        .info-card {
            background: linear-gradient(135deg, #fff7ed 0%, #fed7aa 100%);
            border-left: 6px solid #f97316;
            padding: 26px;
            border-radius: 15px;
            transition: all 0.4s ease;
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
            background: linear-gradient(135deg, transparent 0%, rgba(249, 115, 22, 0.2) 100%);
            opacity: 0;
            transition: opacity 0.4s ease;
        }
        .info-card:hover {
            transform: translateY(-10px) scale(1.02);
            box-shadow: 0 15px 35px rgba(249, 115, 22, 0.3);
        }
        .info-card:hover::before {
            opacity: 1;
        }
        .info-label {
            font-weight: 800;
            color: #9a3412;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 2px;
            margin-bottom: 12px;
            position: relative;
        }
        .info-value {
            color: #7c2d12;
            font-size: 1.1em;
            word-break: break-all;
            font-family: 'Courier New', monospace;
            font-weight: 700;
            position: relative;
        }
        .status-section {
            text-align: center;
            margin: 30px 0;
            padding: 25px;
            background: linear-gradient(135deg, #fed7aa 0%, #fdba74 100%);
            border-radius: 15px;
            border: 3px solid #f97316;
            box-shadow: 0 8px 20px rgba(249, 115, 22, 0.2);
        }
        .status-badge {
            font-size: 1.4em;
            font-weight: 800;
            color: #9a3412;
        }
        .footer {
            text-align: center;
            margin-top: 45px;
            padding-top: 35px;
            border-top: 3px solid #fed7aa;
            color: #ea580c;
            font-size: 1em;
            font-weight: 600;
        }
        .icon {
            font-size: 3em;
            margin-bottom: 15px;
            animation: bounce 2s ease infinite;
        }
        @keyframes bounce {
            0%, 100% { transform: translateY(0); }
            50% { transform: translateY(-15px); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="icon">🔥</div>
            <h1>Demo WebApp</h1>
            <div class="version-badge">
                Version {{ env "APP_VERSION" }}
                <span class="color-indicator"></span>
            </div>
            <div class="deployment-type">🎯 Canary Deployment</div>
        </div>
        
        <div class="canary-notice">
            <h3>⚠️ Canary Deployment Strategy</h3>
            <p>🚀 One instance deployed first • ✅ Validated before full rollout • 🔄 Progressive traffic shift</p>
        </div>
        
        <div class="status-section">
            <div class="status-badge">✓ NGINX RUNNING SMOOTHLY</div>
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
            <p><strong>⚡ Traefik Load Balancer</strong> • <strong>🚀 HashiCorp Nomad Orchestration</strong></p>
            <p style="margin-top: 10px; font-size: 0.9em;">🔄 Refresh to see load balancing in action</p>
        </div>
    </div>
</body>
</html>
EOF
        destination = "local/index.html"
      }
      
      config {
        image = "nginx:alpine"
        ports = ["http"]
        volumes = [
          "local/index.html:/usr/share/nginx/html/index.html"
        ]
      }
    }
  }
}
