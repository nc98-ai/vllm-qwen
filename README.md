# Procédure

1. generation de certificats autosignée pour nginx
```bash
chmod +x docker/nginx/generate-selfsigned-cert.sh
cd docker/nginx/
./generate-selfsigned-cert.sh
```

2. secrets GitHub attendus pour le workflow self-hosted
- `VLLM_API_KEY` (obligatoire)
- `NGINX_SSL_KEY` ou `NGINX_SSL_KEY_B64`
- `NGINX_SSL_CERT` ou `NGINX_SSL_CERT_B64`
- `NGINX_SSL_FULLCHAIN` ou `NGINX_SSL_FULLCHAIN_B64`

3. VARIABLES D'ENVIRONNEMENTS GitHub pour le workflow self-hosted
- ENV_NAME (soit dev, qul ou prd)
- GPU_MEMORY_UTILIZATION (une valeur comprise entre 0.1 et 0.95)

4. deploiement via GitHub Actions (self-hosted runner)
- workflow: `.github/workflows/deploy-self-hosted.yml`
- lancement manuel ou call API avec `workflow_dispatch`

- Copier/coller la procedure du runner sur la machine cible puis exécuter les 2 commandes suivante:

```bash
./run.sh # demarrer le runner (en écoute )
```
```bash
# dans une autre console pour déployer l'env de DEV
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST   -H "Accept: application/vnd.github+json"   -H "Authorization: Bearer $GITHUB_TOKEN"   https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.yml/dispatches   -d '{"ref":"env-developpement","inputs":{"target_env":"ENV_DEV-OPTNC"}}'

# dans une autre console pour déployer l'env de PROD
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST   -H "Accept: application/vnd.github+json"   -H "Authorization: Bearer $GITHUB_TOKEN"   https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.yml/dispatches   -d '{"ref":"main","inputs":{"target_env":"ENV_PRD-OPTNC"}}'
```


5. Tests
- Liste les modeles via nginx
```bash
curl -k -H "Authorization: Bearer $VLLM_API_KEY" https://127.0.0.1:443/v1/models
```

- Q/A via nginx
```bash
curl -k https://127.0.0.1:443/v1/completions   -H "Content-Type: application/json"   -H "Authorization: Bearer $VLLM_API_KEY"   -d '{
    "model": "Qwen/Qwen3.5-2B",
    "prompt": "Qui est Napoleon ?",
    "temperature": 0.2,
    "max_tokens": 80
  }'
```