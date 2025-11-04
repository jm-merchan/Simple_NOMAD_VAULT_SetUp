resource "nomad_job" "app" {
  jobspec = file("${path.module}/template/mongo_nomad.hcl")
}