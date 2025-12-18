job "kmip-test" {
  datacenters = ["dc1"]
  type        = "batch"

  group "kmip-client" {
    count = 1

    task "verify-kmip" {
      driver = "docker"

      config {
        image = "python:3.9-slim"
        command = "/bin/bash"
        args    = ["local/run_test.sh"]
      }

      template {
        data = <<EOF
#!/bin/bash
set -e

# Install dependencies
apt-get update && apt-get install -y build-essential libssl-dev libffi-dev

# Install PyKMIP
pip install pykmip

# Create certificate files from Nomad Variables
{{ with nomadVar "nomad/jobs/kmip-test" }}
cat > local/ca.pem <<'EOFCA'
{{ .ca_pem }}
EOFCA

cat > local/client.pem <<'EOFCERT'
{{ .client_cert_pem }}
EOFCERT

cat > local/key.pem <<'EOFKEY'
{{ .client_key_pem }}
EOFKEY

export VAULT_ADDR="{{ .vault_addr }}"
{{ end }}

# Extract hostname from VAULT_ADDR (remove https:// and port)
VAULT_HOST=$(echo $VAULT_ADDR | sed -e 's|^https\?://||' -e 's|:.*$||')
KMIP_PORT=5696

echo "===================================================="
echo "KMIP Connection Details:"
echo "Vault Host: $VAULT_HOST"
echo "KMIP Port: $KMIP_PORT"
echo "===================================================="

# Test basic connectivity first
echo "Testing connectivity to $VAULT_HOST:$KMIP_PORT..."
timeout 5 bash -c "cat < /dev/null > /dev/tcp/$VAULT_HOST/$KMIP_PORT" && echo "Port is OPEN" || echo "WARNING: Port appears CLOSED or unreachable"

echo ""
echo "Certificate info:"
openssl x509 -in local/client.pem -noout -subject -issuer -dates

echo ""
echo "Configuring PyKMIP..."
cat <<PYCONF > local/pykmip.conf
[client]
host=$VAULT_HOST
port=$KMIP_PORT
cert_reqs=CERT_REQUIRED
ssl_version=PROTOCOL_TLSv1_2
ca_certs=local/ca.pem
do_handshake_on_connect=True
suppress_ragged_eofs=True
keyfile=local/key.pem
certfile=local/client.pem
PYCONF

echo "Running PyKMIP Test..."
cat <<PYSCRIPT > local/test_kmip.py
import sys
import socket
from kmip.pie.client import ProxyKmipClient
from kmip.core import enums

print("Testing KMIP connection...")
print(f"Reading config from: local/pykmip.conf")

try:
    # Test raw socket connection first
    print("Testing raw TCP connection...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    
    with open('local/pykmip.conf', 'r') as f:
        for line in f:
            if line.startswith('host='):
                host = line.split('=')[1].strip()
            if line.startswith('port='):
                port = int(line.split('=')[1].strip())
    
    result = sock.connect_ex((host, port))
    if result == 0:
        print(f"✓ TCP connection to {host}:{port} successful")
        sock.close()
    else:
        print(f"✗ Cannot connect to {host}:{port} (error code: {result})")
        print("KMIP listener may not be configured or port not open")
        sys.exit(1)
    
    # Now try KMIP client
    print("Initializing KMIP client...")
    client = ProxyKmipClient(config_file="local/pykmip.conf")
    
    print("Opening KMIP connection...")
    client.open()
    print("✓ Successfully connected to Vault KMIP!")
    
    # Create a Symmetric Key with unique name
    import time
    import random
    unique_name = f"test-key-{int(time.time())}-{random.randint(1000, 9999)}"
    
    print(f"Creating symmetric AES-256 key with name: {unique_name}...")
    key_id = client.create(
        enums.CryptographicAlgorithm.AES,
        256,
        name=unique_name
    )
    print(f"✓ Created Symmetric Key with ID: {key_id}")
    
    # Get the key back
    print("Retrieving key...")
    key = client.get(key_id)
    print(f"✓ Retrieved Key successfully")
    
    client.close()
    print("✓ KMIP test completed successfully!")
    
except socket.timeout:
    print("✗ Connection timed out - KMIP listener not responding")
    sys.exit(1)
except socket.gaierror as e:
    print(f"✗ DNS resolution failed: {e}")
    sys.exit(1)
except Exception as e:
    print(f"✗ Error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYSCRIPT

python3 local/test_kmip.py

echo "---------------------------------------------------"
echo "KMIP Test Complete!"
echo "Note: PKCS#11 testing requires RHEL and Vault PKCS#11 Provider"
echo "See: https://developer.hashicorp.com/vault/docs/enterprise/pkcs11-provider"
exit 0

EOF
        destination = "local/run_test.sh"
        perms       = "755"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
