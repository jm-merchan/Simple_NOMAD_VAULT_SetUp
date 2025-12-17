# List audit backends
# https://developer.hashicorp.com/vault/api-docs/system/audit#list-enabled-audit-devices
path "/sys/audit" {
  capabilities = ["sudo", "read","list"]
}

# Read specific audit backends
path "/sys/audit/*" {
  capabilities = ["sudo","read"]
}

# Read specific audit backends
# https://developer.hashicorp.com/vault/api-docs/system/config-auditing
path "/sys/config/auditing/*" {
  capabilities = ["sudo","read","list"]
}

# namespace details => https://developer.hashicorp.com/vault/api-docs#namespaces
# List namespaces in any namespace
# https://developer.hashicorp.com/vault/api-docs/system/namespaces#list-namespaces
path "/sys/namespaces" {
  capabilities = ["list"]
}

path "+/sys/namespaces" {
  capabilities = ["list"]
}


# Read namespace information in any namespace
# https://developer.hashicorp.com/vault/api-docs/system/namespaces#read-namespace-information
path "/sys/namespaces/*" {
  capabilities = ["read","list"]
}
path "+/sys/namespaces/*" {
  capabilities = ["read","list"]
}


# List Policies in any namespace
# https://developer.hashicorp.com/vault/api-docs/system/policies#list-acl-policies
# https://developer.hashicorp.com/vault/api-docs/system/policies#list-rgp-policies
# https://developer.hashicorp.com/vault/api-docs/system/policies#list-egp-policies
path "/sys/policies/*" {
    capabilities = ["read","list"]
}

path "+/sys/policies/*" {
    capabilities = ["read","list"]
}

# Read Specific Polcies in any namespace
# https://developer.hashicorp.com/vault/api-docs/system/policies#read-acl-policy
# https://developer.hashicorp.com/vault/api-docs/system/policies#read-rgp-policy
# https://developer.hashicorp.com/vault/api-docs/system/policies#read-egp-policy
path "/sys/policies/+/*" {
    capabilities = ["read"]
}
path "+/sys/policies/+/*" {
    capabilities = ["read"]
}

# List Authentication Backends in any namespace
# https://developer.hashicorp.com/vault/api-docs/system/auth#list-auth-methods
path "/sys/auth" {
  capabilities = ["sudo","read","list"]
}
path "+/sys/auth" {
  capabilities = ["sudo","read","list"]
}

path "/auth/*" {
  capabilities = ["read","list"]
}

path "+/auth/*" {
  capabilities = ["read","list"]
}

# Read Specific Audit Backends in any namespace
# https://developer.hashicorp.com/vault/api-docs/system/auth#read-auth-method-configuration
path "/sys/auth/*" {
  capabilities = ["sudo","read"]
}

path "+/sys/auth/*" {
  capabilities = ["sudo","read"]
}

# Read Auth Method Tuning in any namespace
# https://developer.hashicorp.com/vault/api-docs/system/auth#read-auth-method-tuning
path "/sys/auth/+/tune" {
  capabilities = ["sudo","read"]
}
path "+/sys/auth/+/tune" {
  capabilities = ["sudo","read"]
}

# Hash values to compare with audit logs
# https://developer.hashicorp.com/vault/api-docs/system/audit-hash
path "/sys/audit-hash/*" {
  capabilities = ["create"]
}

# Read HMAC configuration for redacting headers
# https://developer.hashicorp.com/vault/api-docs/system/config-auditing#read-all-audited-request-headers
path "/sys/config/auditing/request-headers" {
  capabilities = ["read", "sudo"]
}

# Configure HMAC for redacting headers
# https://developer.hashicorp.com/vault/api-docs/system/config-auditing#read-single-audit-request-header
path "/sys/config/auditing/request-headers/*" {
  capabilities = ["read", "list", "create", "update", "sudo"]
}

# Get Storage Key Status
path "/sys/key-status" {
  capabilities = ["read"]
}

# Policy to allow listing secrets engines
# https://developer.hashicorp.com/vault/api-docs/system/mounts#list-mounted-secrets-engines
path "/sys/mounts" {
  capabilities = ["read", "list"]
}
path "+/sys/mounts" {
  capabilities = ["read", "list"]
}

# Read Specific Mount point for any namespace
# https://developer.hashicorp.com/vault/api-docs/system/mounts#get-the-configuration-of-a-secret-engine
path "/sys/mounts/*" {
  capabilities = ["read"]
}
path "+/sys/mounts/*" {
  capabilities = ["read"]
}

# Get tune details from specific Engine
# https://developer.hashicorp.com/vault/api-docs/system/mounts#read-mount-configuration
path "/sys/mounts/+/tune" {
  capabilities = ["read"]
}
path "+/sys/mounts/+/tune" {
  capabilities = ["read"]
}

# Audit details from KvV2 engines for any namespace
# https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2#list-secrets
# https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2#read-secret-metadata

path "+/metadata/*" {
  capabilities = ["read","list"]
}
path "+/+/metadata/*" {
  capabilities = ["read","list"]
}