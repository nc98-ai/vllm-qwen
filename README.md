# Documentation

- `docs/FONCTIONNEL.md`
- `docs/DEVELOPPEMENT.md`
- `docs/SECURITE.md`

## Procedure rapide

### Variables GitHub attendues

- `ENV_NAME`
- `GPU_MEMORY_UTILIZATION`
- `NGINX_HTTPS_LISTEN_PORT`

### Secrets GitHub attendus

- `VLLM_API_KEY`
- `NGINX_SSL_KEY` ou `NGINX_SSL_KEY_B64`
- `NGINX_SSL_CERT` ou `NGINX_SSL_CERT_B64`
- `NGINX_SSL_FULLCHAIN` ou `NGINX_SSL_FULLCHAIN_B64`

### Deploiement DEV

```bash
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.yml/dispatches \
  -d '{"ref":"env-developpement","inputs":{"target_env":"ENV_DEV-OPTNC"}}'
```

### Test API

```bash
curl -k https://127.0.0.1:443/v1/models \
  -H "Authorization: Bearer $VLLM_API_KEY"
```
