# Procédure

1. generation de certificats autosignée pour nginx
```bash
chmod +x docker/nginx/generate-selfsigned-cert.sh
cd docker/nginx/
./generate-selfsigned-cert.sh
```

2. secrets GitHub attendus pour le workflow self-hosted
- `GHCR_PAT` (obligatoire si images privees sur GHCR, utilisé pour démarrer le workflow via API)
- `VLLM_API_KEY` (obligatoire)
- `NGINX_SSL_KEY` ou `NGINX_SSL_KEY_B64`
- `NGINX_SSL_CERT` ou `NGINX_SSL_CERT_B64`
- `NGINX_SSL_FULLCHAIN` ou `NGINX_SSL_FULLCHAIN_B64`

3. deploiement via GitHub Actions (self-hosted runner)
- workflow: `.github/workflows/deploy-self-hosted.yml`
- lancement manuel avec `workflow_dispatch`

A FAIRE


4. Test 
- de base via nginx
curl -k https://127.0.0.1:443/v1/models

- Q/A via nginx
curl -k https://127.0.0.1:443/v1/completions   -H "Content-Type: application/json"   -d '{
    "model": "Qwen/Qwen3.5-2B",
    "prompt": "Qui est napoleon?",
    "temperature": 0.2,
    "max_tokens": 80
  }'