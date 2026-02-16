FROM registry.access.redhat.com/ubi9/python-312:latest

# Metadata labels
LABEL name="vertex-openai-proxy" \
      summary="LiteLLM proxy: OpenAI API to Google Vertex AI" \
      description="Receives LLM requests in the OpenAI API format and proxies them to Google Cloud Vertex AI models (Gemini, Claude, etc.) via LiteLLM." \
      io.k8s.display-name="Vertex OpenAI Proxy" \
      io.k8s.description="LiteLLM-based proxy translating OpenAI API calls to Vertex AI" \
      io.openshift.tags="ai,llm,proxy,litellm,vertexai,openai" \
      io.openshift.expose-services="8080:http"

# Switch to root to install system dependencies
USER 0

RUN dnf install -y --nodocs gcc python3.12-devel && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Switch back to default non-root user (OpenShift compatible)
USER 1001

# Set working directory
WORKDIR /app

# Install Python dependencies
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /app/requirements.txt

# Copy application files
COPY litellm_config.yaml /app/litellm_config.yaml
COPY entrypoint.sh /app/entrypoint.sh

# Make entrypoint executable (already non-root, so use USER 0 temporarily)
USER 0
RUN chmod +x /app/entrypoint.sh && \
    chown -R 1001:0 /app && \
    chmod -R g=u /app
USER 1001

# Create writable temp directory for credentials at runtime
RUN mkdir -p /tmp/gcloud && chmod 775 /tmp/gcloud

# Expose the proxy port
EXPOSE 8080

# Environment variable defaults
ENV LITELLM_PORT=8080 \
    VERTEX_LOCATION=us-east5

ENTRYPOINT ["/app/entrypoint.sh"]
