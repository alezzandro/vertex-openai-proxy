# Vertex OpenAI Proxy

A containerized proxy that receives LLM requests in the **OpenAI API format** and translates them to **Google Cloud Vertex AI** API calls. Built on **Red Hat UBI 9** using [LiteLLM](https://github.com/BerriAI/litellm) as the translation engine.

This allows any tool or application that speaks the OpenAI API (e.g., `curl`, Python `openai` SDK, VS Code extensions, etc.) to transparently use models hosted on Vertex AI -- including **Gemini** and **Claude** (via Model Garden).

## Architecture

```
┌──────────────────┐    OpenAI API     ┌──────────────────────┐    Vertex AI API    ┌──────────────────┐
│  Client / Tool   │ ───────────────►  │  vertex-openai-proxy │ ──────────────────► │  Google Cloud    │
│  (OpenAI SDK)    │ ◄───────────────  │  (LiteLLM on UBI 9) │ ◄────────────────── │  Vertex AI       │
└──────────────────┘                   └──────────────────────┘                     └──────────────────┘
```

## Model Mappings

The proxy maps OpenAI model names to Vertex AI models. You can use either the OpenAI-compatible name or the native Vertex AI name:

| OpenAI Model Name    | Vertex AI Model                      | Description                |
|----------------------|--------------------------------------|----------------------------|
| `gpt-4o`             | `gemini-2.0-flash`                   | Fast, capable model        |
| `gpt-4o-mini`        | `gemini-2.0-flash-lite`              | Lightweight, fast model    |
| `gpt-4-turbo`        | `gemini-1.5-pro`                     | High-quality reasoning     |
| `gpt-3.5-turbo`      | `gemini-1.5-flash`                   | Fast, cost-effective       |
| `gemini-2.0-flash`   | `gemini-2.0-flash`                   | Native Gemini name         |
| `gemini-2.0-flash-lite` | `gemini-2.0-flash-lite`           | Native Gemini name         |
| `gemini-1.5-pro`     | `gemini-1.5-pro`                     | Native Gemini name         |
| `gemini-1.5-flash`   | `gemini-1.5-flash`                   | Native Gemini name         |
| `claude-sonnet-4-5`  | `claude-sonnet-4-5@20250929`         | Claude Sonnet 4.5          |
| `claude-3-5-sonnet`  | `claude-3-5-sonnet-v2@20241022`      | Claude 3.5 Sonnet v2       |
| `claude-3-opus`      | `claude-3-opus@20240229`             | Claude 3 Opus              |
| `claude-3-haiku`     | `claude-3-haiku@20240307`            | Claude 3 Haiku             |

> **Note:** Claude models on Vertex AI require the Anthropic Model Garden to be enabled in your GCP project, and the models must be available in your selected region.

---

## Prerequisites

- **Google Cloud project** with Vertex AI API enabled
- **`gcloud` CLI** installed on your laptop ([Install guide](https://cloud.google.com/sdk/docs/install))
- **Podman** (for local testing) or **Docker**
- **OpenShift cluster** (for production deployment) with `oc` CLI

---

## Step 1: Obtain Google Cloud Credentials

The proxy authenticates to Vertex AI using **Application Default Credentials (ADC)**. The simplest method is using your personal OAuth credentials (the same method used by Claude Code with Vertex).

### 1.1 Login with `gcloud`

```bash
# Authenticate your user account
gcloud auth login

# Generate Application Default Credentials
gcloud auth application-default login
```

This creates a credentials file at:

```
~/.config/gcloud/application_default_credentials.json
```

### 1.2 Extract Credential Values

Open the file and note the following fields -- you will need them as environment variables:

```bash
cat ~/.config/gcloud/application_default_credentials.json
```

The file looks like this:

```json
{
    "account": "",
    "client_id": "XXXXXX.apps.googleusercontent.com",
    "client_secret": "d-XXXXXX",
    "quota_project_id": "your-project-id",
    "refresh_token": "1//XXXXXX",
    "type": "authorized_user",
    "universe_domain": "googleapis.com"
}
```

Extract and export these values:

| Environment Variable             | Source Field in JSON   | Required |
|----------------------------------|------------------------|----------|
| `GOOGLE_CLIENT_ID`              | `client_id`            | Yes      |
| `GOOGLE_CLIENT_SECRET`          | `client_secret`        | Yes      |
| `GOOGLE_REFRESH_TOKEN`          | `refresh_token`        | Yes      |
| `GOOGLE_QUOTA_PROJECT_ID`       | `quota_project_id`     | No (defaults to `VERTEX_PROJECT_ID`) |

### 1.3 Identify Your Vertex AI Project and Region

```bash
# List your projects
gcloud projects list

# The project ID with Vertex AI enabled
export VERTEX_PROJECT_ID="your-gcp-project-id"

# The region where your models are available (e.g., us-east5, us-central1, europe-west1)
export VERTEX_LOCATION="us-east5"
```

> **Tip:** To check which regions support your desired models, visit the [Vertex AI model availability documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/learn/model-versions).

### Alternative: Service Account Credentials

For production workloads, a **service account** is recommended instead of personal OAuth credentials:

```bash
# Create a service account
gcloud iam service-accounts create litellm-proxy \
    --display-name="LiteLLM Proxy Service Account"

# Grant Vertex AI User role
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:litellm-proxy@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/aiplatform.user"

# Download the key file
gcloud iam service-accounts keys create sa-key.json \
    --iam-account=litellm-proxy@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Use the full JSON method
export GOOGLE_APPLICATION_CREDENTIALS_JSON=$(cat sa-key.json)
```

---

## Step 2: Build the Container Image

### Build with Podman (local)

```bash
cd vertex-openai-proxy

podman build -t vertex-openai-proxy:latest -f Containerfile .
```

### Build with Docker

```bash
cd vertex-openai-proxy

docker build -t vertex-openai-proxy:latest -f Containerfile .
```

---

## Step 3: Test Locally with Podman

### 3.1 Set Environment Variables

Create a local environment file (do **not** commit this file):

```bash
cat > .env <<'EOF'
VERTEX_PROJECT_ID=your-gcp-project-id
VERTEX_LOCATION=us-east5
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=d-your-client-secret
GOOGLE_REFRESH_TOKEN=1//your-refresh-token
GOOGLE_QUOTA_PROJECT_ID=your-quota-project-id
LITELLM_MASTER_KEY=sk-local-test-key-1234
EOF
```

> **Security:** The `.env` file is in `.gitignore` and should **never** be committed.

### 3.2 Run the Container

```bash
podman run --rm -it \
    --env-file .env \
    -p 8080:8080 \
    --name vertex-proxy \
    vertex-openai-proxy:latest
```

You should see output like:

```
INFO: Wrote authorized_user credentials from individual env vars.
INFO: Vertex AI Project: your-gcp-project-id
INFO: Vertex AI Location: us-east5
INFO: LiteLLM master key is configured.
INFO: Starting LiteLLM proxy on port 8080...
```

### 3.3 Test with curl

Open a new terminal and send a test request.

> **Note:** Use `127.0.0.1` instead of `localhost`. On many Linux systems, `localhost` resolves to IPv6 (`::1`) first, but Podman's port forwarding binds to IPv4 only.

```bash
# Health check (requires auth when LITELLM_MASTER_KEY is set)
curl http://127.0.0.1:8080/health \
    -H "Authorization: Bearer sk-local-test-key-1234"

# List available models
curl http://127.0.0.1:8080/v1/models \
    -H "Authorization: Bearer sk-local-test-key-1234"

# Chat completion (uses Gemini 2.0 Flash via the gpt-4o alias)
curl http://127.0.0.1:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer sk-local-test-key-1234" \
    -d '{
        "model": "gpt-4o",
        "messages": [
            {"role": "user", "content": "Hello! What model are you?"}
        ]
    }'

# Chat completion using a native Vertex AI model name
curl http://127.0.0.1:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer sk-local-test-key-1234" \
    -d '{
        "model": "gemini-2.0-flash",
        "messages": [
            {"role": "user", "content": "Explain Kubernetes in one sentence."}
        ]
    }'

# Test a Claude model on Vertex AI
curl http://127.0.0.1:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer sk-local-test-key-1234" \
    -d '{
        "model": "claude-sonnet-4-5",
        "messages": [
            {"role": "user", "content": "Write a haiku about containers."}
        ]
    }'
```

### 3.4 Test with Python OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-local-test-key-1234",
    base_url="http://127.0.0.1:8080/v1"
)

response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello! What model are you?"}]
)

print(response.choices[0].message.content)
```

---

## Step 4: Deploy on OpenShift

### 4.1 Pre-built Container Image

A pre-built container image is available on Quay.io and ready to use:

```
quay.io/telco-coe-emea/vertex-openai-proxy:latest
```

The OpenShift manifests in `openshift/` already reference this image. No build or push step is required.

> **Tip:** If you prefer to build your own image (e.g., to customize model mappings), follow **Step 2** to build it, then tag and push to your own registry:
>
> ```bash
> podman tag vertex-openai-proxy:latest quay.io/YOUR_ORG/vertex-openai-proxy:latest
> podman push quay.io/YOUR_ORG/vertex-openai-proxy:latest
> ```
>
> Then update the `image` field in `openshift/deployment.yaml` accordingly.

### 4.2 Create the Secret

Edit `openshift/secret.yaml` with your actual credential values, then apply:

```bash
# Edit the secret with real values
vi openshift/secret.yaml

# Apply to your project
oc apply -f openshift/secret.yaml
```

Alternatively, create the secret directly from the command line:

```bash
oc create secret generic vertex-openai-proxy-credentials \
    --from-literal=VERTEX_PROJECT_ID="your-project-id" \
    --from-literal=VERTEX_LOCATION="us-east5" \
    --from-literal=GOOGLE_CLIENT_ID="your-client-id" \
    --from-literal=GOOGLE_CLIENT_SECRET="your-client-secret" \
    --from-literal=GOOGLE_REFRESH_TOKEN="your-refresh-token" \
    --from-literal=GOOGLE_QUOTA_PROJECT_ID="your-quota-project-id" \
    --from-literal=LITELLM_MASTER_KEY="sk-your-production-key"
```

### 4.3 Deploy

```bash
# Apply all OpenShift manifests
oc apply -f openshift/deployment.yaml
oc apply -f openshift/service.yaml
oc apply -f openshift/route.yaml

# Watch the rollout
oc rollout status deployment/vertex-openai-proxy

# Check pod logs
oc logs -f deployment/vertex-openai-proxy
```

### 4.4 Get the Route URL

```bash
PROXY_URL=$(oc get route vertex-openai-proxy -o jsonpath='{.spec.host}')
echo "Proxy is available at: https://${PROXY_URL}"
```

### 4.5 Test the Deployed Proxy

```bash
PROXY_URL=$(oc get route vertex-openai-proxy -o jsonpath='{.spec.host}')

curl "https://${PROXY_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer sk-your-production-key" \
    -d '{
        "model": "gpt-4o",
        "messages": [
            {"role": "user", "content": "Hello from OpenShift!"}
        ]
    }'
```

---

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VERTEX_PROJECT_ID` | **Yes** | - | Google Cloud project ID with Vertex AI enabled |
| `VERTEX_LOCATION` | No | `us-east5` | GCP region for Vertex AI (e.g., `us-east5`, `us-central1`, `europe-west1`) |
| `GOOGLE_CLIENT_ID` | Yes* | - | OAuth client ID from ADC credentials file |
| `GOOGLE_CLIENT_SECRET` | Yes* | - | OAuth client secret from ADC credentials file |
| `GOOGLE_REFRESH_TOKEN` | Yes* | - | OAuth refresh token from ADC credentials file |
| `GOOGLE_QUOTA_PROJECT_ID` | No | Value of `VERTEX_PROJECT_ID` | Quota/billing project ID |
| `GOOGLE_APPLICATION_CREDENTIALS_JSON` | Yes* | - | Full credentials JSON (alternative to individual fields) |
| `LITELLM_MASTER_KEY` | No | - | API key to authenticate clients to the proxy |
| `LITELLM_PORT` | No | `8080` | Port the proxy listens on |

> \* **Authentication**: Provide either `GOOGLE_APPLICATION_CREDENTIALS_JSON` **or** the individual fields (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`).

---

## OpenShift Security

This container is designed to run under OpenShift's **default restricted SCC** (`restricted-v2`):

- Runs as **non-root** user (UID 1001, with support for arbitrary UIDs)
- Listens on **port 8080** (non-privileged)
- **No privilege escalation** allowed
- All Linux **capabilities dropped**
- **seccomp** profile set to `RuntimeDefault`
- Credentials file is written to `/tmp` at runtime (writable by any UID)
- Group ownership set to `root` (GID 0) with group-writable permissions for OpenShift arbitrary UID compatibility

No special SCCs, role bindings, or security configurations are needed.

---

## Customizing Model Mappings

To add or modify model mappings, edit `litellm_config.yaml` before building the container.

Each model entry follows this pattern:

```yaml
- model_name: my-custom-alias          # Name clients will use
  litellm_params:
    model: vertex_ai/actual-model-name # Vertex AI model identifier
    vertex_project: os.environ/VERTEX_PROJECT_ID
    vertex_location: os.environ/VERTEX_LOCATION
```

After editing, rebuild the container image.

---

## Troubleshooting

### Authentication Errors

```
google.auth.exceptions.RefreshError: ('invalid_grant: Token has been expired or revoked')
```

Your refresh token has expired. Re-run:

```bash
gcloud auth application-default login
```

Then update the `GOOGLE_REFRESH_TOKEN` environment variable with the new value.

### Model Not Found

```
Model not found: vertex_ai/claude-sonnet-4-5@20250929
```

- Verify the model is available in your region (`VERTEX_LOCATION`)
- For Claude models, ensure the Anthropic Model Garden is enabled in your GCP project
- Check [Vertex AI model availability](https://cloud.google.com/vertex-ai/generative-ai/docs/learn/model-versions)

### Permission Denied

```
403 Permission denied on resource project
```

Ensure your credentials have the `Vertex AI User` role (`roles/aiplatform.user`) on the target project:

```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="user:your-email@example.com" \
    --role="roles/aiplatform.user"
```

### Pod CrashLoopBackOff on OpenShift

Check the pod logs:

```bash
oc logs deployment/vertex-openai-proxy
```

Common causes:
- Missing or incorrect secret values
- Secret not applied to the namespace
- Image pull errors (check `oc describe pod`)

---

## License

See [LICENSE](LICENSE) for details.
