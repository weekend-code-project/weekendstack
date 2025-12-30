# This directory contains auto-generated SSL certificates for local HTTPS

## Files (auto-generated)
- `ca-cert.pem` - Certificate Authority certificate (trust this in your browser/system)
- `ca-key.pem` - CA private key (keep secure!)
- `cert.pem` - Wildcard certificate for *.lab domains
- `key.pem` - Server private key

## Setup
See [../../../docs/local-https-setup.md](../../../docs/local-https-setup.md) for instructions on trusting the CA certificate.

## Regeneration
To regenerate certificates:
```bash
rm *.pem
docker compose up cert-generator
```

Then re-trust the NEW ca-cert.pem in your browser/system.
