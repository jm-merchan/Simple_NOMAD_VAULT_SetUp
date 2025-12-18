path "secret/data/windows11" {
  capabilities = ["read"]
}

path "secret/data/ipmi/*" {
  capabilities = ["read"]
}

path "secret/metadata/ipmi/*" {
  capabilities = ["list"]
}
