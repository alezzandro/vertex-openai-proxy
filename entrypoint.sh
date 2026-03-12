#!/bin/bash
set -euo pipefail

CREDS_DIR="/tmp/gcloud"
CREDS_FILE="${CREDS_DIR}/application_default_credentials.json"

mkdir -p "${CREDS_DIR}"

# --- Build Google Application Default Credentials ---
# Option 1: Full JSON passed directly (service account or authorized_user)
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS_JSON:-}" ]; then
    echo "${GOOGLE_APPLICATION_CREDENTIALS_JSON}" > "${CREDS_FILE}"
    CRED_TYPE=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('type','unknown'))" "${CREDS_FILE}" 2>/dev/null || echo "unknown")
    echo "INFO: Wrote credentials from GOOGLE_APPLICATION_CREDENTIALS_JSON (type: ${CRED_TYPE})."

# Option 2: Individual fields for authorized_user (OAuth) credentials
elif [ -n "${GOOGLE_REFRESH_TOKEN:-}" ]; then
    cat > "${CREDS_FILE}" <<EOF
{
    "account": "",
    "client_id": "${GOOGLE_CLIENT_ID:?ERROR: GOOGLE_CLIENT_ID is required}",
    "client_secret": "${GOOGLE_CLIENT_SECRET:?ERROR: GOOGLE_CLIENT_SECRET is required}",
    "quota_project_id": "${GOOGLE_QUOTA_PROJECT_ID:-${VERTEX_PROJECT_ID:-}}",
    "refresh_token": "${GOOGLE_REFRESH_TOKEN}",
    "type": "authorized_user",
    "universe_domain": "googleapis.com"
}
EOF
    echo "INFO: Built authorized_user credentials from individual env vars."

else
    echo "ERROR: No Google credentials provided."
    echo ""
    echo "Provide credentials using ONE of these methods:"
    echo ""
    echo "  Method 1 - Full JSON (service account or authorized_user):"
    echo "    GOOGLE_APPLICATION_CREDENTIALS_JSON='{...json...}'"
    echo "    Supports both service_account key files and authorized_user ADC files."
    echo "    The JSON must be on a single line when using --env-file with Podman/Docker."
    echo ""
    echo "  Method 2 - Individual fields (authorized_user only):"
    echo "    GOOGLE_CLIENT_ID=<value>"
    echo "    GOOGLE_CLIENT_SECRET=<value>"
    echo "    GOOGLE_REFRESH_TOKEN=<value>"
    echo "    GOOGLE_QUOTA_PROJECT_ID=<value>  (optional)"
    echo ""
    exit 1
fi

export GOOGLE_APPLICATION_CREDENTIALS="${CREDS_FILE}"

# --- Validate required Vertex AI configuration ---
: "${VERTEX_PROJECT_ID:?ERROR: VERTEX_PROJECT_ID is required}"
export VERTEX_LOCATION="${VERTEX_LOCATION:-us-east5}"

echo "INFO: Vertex AI Project: ${VERTEX_PROJECT_ID}"
echo "INFO: Vertex AI Location: ${VERTEX_LOCATION}"

# --- Handle optional LiteLLM master key ---
# LiteLLM reads LITELLM_MASTER_KEY directly from the environment
if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
    echo "INFO: LiteLLM master key is configured (via LITELLM_MASTER_KEY env var)."
else
    echo "WARN: No LITELLM_MASTER_KEY set. Proxy will be unauthenticated."
fi

LITELLM_PORT="${LITELLM_PORT:-8080}"
echo "INFO: Starting LiteLLM proxy on port ${LITELLM_PORT}..."

exec litellm \
    --config /app/litellm_config.yaml \
    --host 0.0.0.0 \
    --port "${LITELLM_PORT}" \
    "$@"
