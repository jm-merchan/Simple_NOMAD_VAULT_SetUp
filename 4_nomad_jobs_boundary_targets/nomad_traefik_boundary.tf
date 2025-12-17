# Nomad Namespace for Traefik
resource "nomad_namespace" "ns1" {
  name        = "NS1"
  description = "Namespace for Traefik demo"
}

# Traefik Job
resource "nomad_job" "traefik" {
  jobspec    = file("${path.module}/ubuntu_remote/9_traefik.hcl")
  depends_on = [nomad_namespace.ns1]
}

# Apache Job
resource "nomad_job" "apache" {
  jobspec    = file("${path.module}/ubuntu_remote/10_apache_v2.hcl")
  depends_on = [nomad_namespace.ns1]
}

# Nginx Job
resource "nomad_job" "nginx" {
  jobspec    = file("${path.module}/ubuntu_remote/9_nginx_v2.hcl")
  depends_on = [nomad_namespace.ns1]
}

# Boundary Target for Traefik Web (Port 9999)
resource "boundary_target" "traefik_web" {
  name                 = "traefik-web"
  description          = "Traefik Web Entrypoint (Apache/Nginx)"
  type                 = "tcp"
  default_port         = 9999
  scope_id             = data.boundary_scope.project.id
  egress_worker_filter = "\"ubuntu-remote\" in \"/tags/type\""
  host_source_ids = [
    boundary_host_set_static.ubuntu.id
  ]
}

# Boundary Target for Traefik Admin (Port 9998)
resource "boundary_target" "traefik_admin" {
  name                 = "traefik-admin"
  description          = "Traefik Admin Dashboard"
  type                 = "tcp"
  default_port         = 9998
  scope_id             = data.boundary_scope.project.id
  egress_worker_filter = "\"ubuntu-remote\" in \"/tags/type\""
  host_source_ids = [
    boundary_host_set_static.ubuntu.id
  ]
}

# Boundary Alias for Apache (Points to Traefik Web)
resource "boundary_alias_target" "apache" {
  name           = "apache.http.demo"
  description    = "Alias for Apache"
  scope_id       = "global"
  value          = "lb.nomad.demo"
  destination_id = boundary_target.traefik_web.id
}

# Boundary Alias for Nginx (Points to Traefik Admin as requested)
resource "boundary_alias_target" "nginx" {
  name           = "nginx.http.demo"
  description    = "Alias for Nginx"
  scope_id       = "global"
  value          = "admin.nomad.demo"
  destination_id = boundary_target.traefik_admin.id
}
