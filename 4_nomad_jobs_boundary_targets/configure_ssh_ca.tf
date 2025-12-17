# Nomad variables for EC2 SSH CA configuration
resource "nomad_variable" "configure_ssh_ca_ec2" {
  path = "nomad/jobs/configure-ssh-ca-ec2"

  items = {
    vault_ca_public_key = vault_ssh_secret_backend_ca.boundary.public_key
  }
}

# Nomad variables for Ubuntu SSH CA configuration
resource "nomad_variable" "configure_ssh_ca_ubuntu" {
  path = "nomad/jobs/configure-ssh-ca-ubuntu"

  items = {
    vault_ca_public_key = vault_ssh_secret_backend_ca.boundary.public_key
  }
}

# Deploy EC2 SSH CA configuration job
resource "nomad_job" "configure_ssh_ca_ec2" {
  jobspec = file("${path.module}/ec2/7_configure_ssh_ca.hcl")

  depends_on = [
    vault_ssh_secret_backend_ca.boundary,
    nomad_variable.configure_ssh_ca_ec2
  ]
}

# Deploy Ubuntu SSH CA configuration job
resource "nomad_job" "configure_ssh_ca_ubuntu" {
  jobspec = file("${path.module}/ubuntu_remote/12_configure_ssh_ca.hcl")

  depends_on = [
    vault_ssh_secret_backend_ca.boundary,
    nomad_variable.configure_ssh_ca_ubuntu
  ]
}
