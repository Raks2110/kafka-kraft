Execute this script with required values to generate certs

#!/bin/bash

set -euo pipefail

# === Configurable Variables ===
CN="kafka"
PASSWORD="test@123"
DAYS_VALID=825
NAMESPACE="default"

# === Output Directory ===
OUTDIR="./certs"
mkdir -p "$OUTDIR"

# === Output Files ===
CA_KEY="$OUTDIR/my-ca.key.pem"
CA_CERT="$OUTDIR/my-ca.cert.pem"
CA_CHAIN="$OUTDIR/ca-chain.cert.pem"

KAFKA_KEY="$OUTDIR/kafka.key.pem"
KAFKA_CSR="$OUTDIR/kafka.csr"
KAFKA_CERT="$OUTDIR/kafka.cert.pem"

PKCS12_FILE="$OUTDIR/pkcs.p12"
KEYSTORE="$OUTDIR/server.keystore.jks"
TRUSTSTORE_SERVER="$OUTDIR/server.truststore.jks"
TRUSTSTORE_CLIENT="$OUTDIR/client.truststore.jks"

# === Step 0: Pre-check for required tools ===
echo "[0/7] Checking required tools..."
for bin in openssl keytool kubectl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "❌ Required tool '$bin' is not installed or not in PATH. Aborting."
    exit 1
  fi
done

# === Step 1: Create a self-signed CA ===
echo "[1/7] Creating self-signed CA..."
openssl genpkey -algorithm RSA -out "$CA_KEY" -pkeyopt rsa_keygen_bits:4096
openssl req -x509 -new -key "$CA_KEY" -sha256 -days 1825 -out "$CA_CERT" -subj "/CN=Kafka-Local-CA"
cp "$CA_CERT" "$CA_CHAIN"

# === Step 2: Create Kafka private key ===
echo "[2/7] Creating Kafka private key..."
openssl genpkey -algorithm RSA -out "$KAFKA_KEY" -pkeyopt rsa_keygen_bits:2048

# === Step 3: Create CSR ===
echo "[3/7] Creating Kafka CSR..."
openssl req -new -key "$KAFKA_KEY" -out "$KAFKA_CSR" -subj "/CN=$CN"

# === Step 4: Sign the CSR ===
echo "[4/7] Signing Kafka certificate with CA..."
openssl x509 -req -in "$KAFKA_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" \
  -CAcreateserial -out "$KAFKA_CERT" -days "$DAYS_VALID" -sha256

# === Step 5: Create PKCS#12 file ===
echo "[5/7] Creating PKCS#12 file..."
openssl pkcs12 -export \
  -in "$KAFKA_CERT" \
  -inkey "$KAFKA_KEY" \
  -out "$PKCS12_FILE" \
  -name "$CN" \
  -password pass:"$PASSWORD"

# === Step 6: Create keystore and truststores ===
echo "[6/7] Creating keystore and truststores..."

keytool -importkeystore \
  -destkeystore "$KEYSTORE" \
  -srckeystore "$PKCS12_FILE" \
  -srcstoretype PKCS12 \
  -alias "$CN" \
  -storepass "$PASSWORD" \
  -srcstorepass "$PASSWORD" \
  -noprompt

for TRUSTSTORE in "$TRUSTSTORE_SERVER" "$TRUSTSTORE_CLIENT"; do
  keytool -keystore "$TRUSTSTORE" \
    -alias CARoot \
    -importcert -file "$CA_CHAIN" \
    -storepass "$PASSWORD" -noprompt
done

# === Step 7: Create Kubernetes Secrets ===
echo "[7/7] Creating Kubernetes secrets..."
kubectl create secret generic keystore --from-file="$KEYSTORE" --namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic truststore --from-file="$TRUSTSTORE_SERVER" --from-file="$TRUSTSTORE_CLIENT" --namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "✅ All done! Certs and keystores are in: $OUTDIR"
