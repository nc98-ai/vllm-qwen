FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04

# Certificat racine personnalisé (optionnel) via secret BuildKit/Podman
RUN --mount=type=secret,id=ca_chain \
    if [ -f /run/secrets/ca_chain ]; then \
      cp /run/secrets/ca_chain /usr/local/share/ca-certificates/opt_ca_chain.crt && \
      chmod 644 /usr/local/share/ca-certificates/opt_ca_chain.crt && \
      update-ca-certificates; \
    else \
      echo "No custom CA chain provided"; \
    fi



ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Pacific/Noumea
ENV PATH="/opt/venv/bin:$PATH"
ENV HF_HUB_ENABLE_REMOTE_CODE=1
ENV HF_HUB_DISABLE_XET=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    python3 python3-venv python3-dev build-essential \
    git curl ca-certificates \
    procps nano \
    && rm -rf /var/lib/apt/lists/*

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN update-ca-certificates

RUN python3 -m venv /opt/venv
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

RUN pip install --no-cache-dir \
  "requests>=2.32,<3" "charset-normalizer<4" python-dotenv certifi \
  fastapi "uvicorn[standard]" pydantic PyYAML Jinja2 colorama ollama \
  langchain langchain-community langchain-openai langchain-huggingface \
  langchain-text-splitters langgraph semantic-router \
  sentence-transformers transformers torch \
  faiss-cpu rank-bm25

# RUN python - <<EOF
RUN SSL_CERT_FILE=${REQUESTS_CA_BUNDLE} \
    REQUESTS_CA_BUNDLE=${REQUESTS_CA_BUNDLE} \
    CURL_CA_BUNDLE=${REQUESTS_CA_BUNDLE} \
    HF_HUB_DISABLE_XET=1 \
    python - <<EOF

from langchain_huggingface import HuggingFaceEmbeddings

model_kwargs = {
    "device": "cpu",
    "trust_remote_code": True,
    "revision": "d9cfe58bd70941b8642f2b97c5949041dc829d08",
}
encode_kwargs = {"normalize_embeddings": True}
HuggingFaceEmbeddings(
    model_name="OrdalieTech/Solon-embeddings-base-0.1",
    model_kwargs=model_kwargs,
    encode_kwargs=encode_kwargs,
)
EOF

# RUN python - <<EOF
RUN SSL_CERT_FILE=${REQUESTS_CA_BUNDLE} \
    REQUESTS_CA_BUNDLE=${REQUESTS_CA_BUNDLE} \
    CURL_CA_BUNDLE=${REQUESTS_CA_BUNDLE} \
    HF_HUB_DISABLE_XET=1 \
    python - <<EOF
from sentence_transformers import CrossEncoder

CrossEncoder(
    "BAAI/bge-reranker-v2-m3",
    revision="953dc6f6f85a1b2dbfca4c34a2796e7dde08d41e",
    trust_remote_code=True,
)
EOF

WORKDIR /app

RUN mkdir -p BM25 FAISSdb logs prompts conversations

COPY .pylintrc .env .env_api ./
COPY prompts/prompts.yaml prompts/prompts.yaml
COPY fastapi_ai_gateway_multiquery.v2.py fastapi_ai_gateway.py
COPY my_functions.py .

RUN apt-get update && apt-get install -y age && rm -rf /var/lib/apt/lists/*

CMD ["uvicorn", "fastapi_ai_gateway:app", "--host", "0.0.0.0", "--port", "8030"]
