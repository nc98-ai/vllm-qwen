## Documentation

- `docs/FONCTIONNEL.md`
- `docs/DEVELOPPEMENT.md`
- `docs/SECURITE.md`

### Variables GitHub attendues

- `ENV_NAME`
- `MODEL_NAME`
- `MAX_MODEL_LEN`
- `GPU_MEMORY_UTILIZATION`
- `NGINX_HTTPS_LISTEN_PORT`

### Secrets GitHub attendus

- `VLLM_API_KEY`
- `NGINX_SSL_KEY` ou `NGINX_SSL_KEY_B64`
- `NGINX_SSL_CERT` ou `NGINX_SSL_CERT_B64`
- `NGINX_SSL_FULLCHAIN` ou `NGINX_SSL_FULLCHAIN_B64`

### Comportement de demarrage

- `vllm` est considere pret quand `GET /v1/models` repond
- `nginx` attend cette readiness avant de demarrer
- `nginx` envoie ensuite une petite requete de warmup au backend avant de s'ouvrir
- l'acces externe est uniquement en HTTPS
- toutes les requetes API doivent fournir `Authorization: Bearer $VLLM_API_KEY`

### Deploiement DEV sur un hote

```bash
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.yml/dispatches \
  -d '{"ref":"env-developpement","inputs":{"target_env":"ENV_DEV-OPTNC"}}'
```


## Verifications fonctionnelles

### Verifier les modeles exposes

```bash
curl -k https://127.0.0.1:443/v1/models \
  -H "Authorization: Bearer $VLLM_API_KEY"
```

### Verifier une completion

```bash
curl -k https://127.0.0.1:443/v1/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d '{
    "model": "Qwen/Qwen3.5-2B",
    "prompt": "Qui est Napoleon ?",
    "temperature": 0.2,
    "max_tokens": 80
  }'
```
```bash
#pour prise en compte du non affochage des balises <think> si au démarrage du serveur --default-chat-template-kwargs {"enable_thinking": false} 
curl -k https://127.0.0.1:443/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d '{
    "model": "Qwen/Qwen3.5-2B",
    "messages": [
      {
        "role": "user",
        "content": "Qui est Napoleon ? Réponds en français."
      }
    ],
    "temperature": 0.2,
    "max_tokens": 80
  }'  
```
