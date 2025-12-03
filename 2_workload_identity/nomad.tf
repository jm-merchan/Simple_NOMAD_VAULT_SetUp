resource "nomad_job" "app" {
  jobspec = file("${path.module}/template/mongo_nomad-ec2.hcl")
  depends_on = [ vault_jwt_auth_backend.jwt-nomad, vault_kv_secret_v2.secret_example ]
}