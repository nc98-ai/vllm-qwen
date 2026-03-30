# Documentation Developpement

## Vue d'ensemble technique

Le projet repose sur deux services Docker :

- `vllm` pour l'inference
- `nginx` pour l'exposition HTTPS et le controle d'acces

Le deploiement cible est automatise via le workflow :

- `.github/workflows/deploy-self-hosted.yml`

## Fichiers importants

### Orchestration

- `docker/docker-compose-vllm-nginx.yml`
- `.github/workflows/deploy-self-hosted.yml`

### nginx

- `docker/nginx/Dockerfile`
- `docker/nginx/docker-entrypoint.sh`
- `docker/nginx/nginx.conf.template`

### Documentation

- `README.md`
- `docs/FONCTIONNEL.md`
- `docs/SECURITE.md`

## Fonctionnement du workflow

Le workflow self-hosted fait les operations suivantes :

1. resolution du nom d'environnement de deploiement
2. validation de `ENV_NAME`
3. validation de `MODEL_NAME`
4. validation de `MAX_MODEL_LEN`
5. validation de `GPU_MEMORY_UTILIZATION`
6. validation de `NGINX_HTTPS_HOST_PORT`
7. creation des repertoires persistants de runtime
8. preparation des secrets
9. generation d'un fichier d'override `docker-compose`
10. build local de l'image `nginx`
11. suppression ciblee des conteneurs du stack courant
12. redeploiement avec `docker compose`

## Variables GitHub attendues

### Variables d'environnement GitHub

- `ENV_NAME`
- `MODEL_NAME`
- `MAX_MODEL_LEN`
- `GPU_MEMORY_UTILIZATION`
- `NGINX_HTTPS_HOST_PORT`

### Secrets GitHub

- `VLLM_API_KEY`
- `NGINX_SSL_KEY` ou `NGINX_SSL_KEY_B64`
- `NGINX_SSL_CERT` ou `NGINX_SSL_CERT_B64`
- `NGINX_SSL_FULLCHAIN` ou `NGINX_SSL_FULLCHAIN_B64`

## Parametres applicatifs importants

### Modele

Le modele actif est defini dans `docker/docker-compose-vllm-nginx.yml`.

Exemple :

```yaml
command:
  - "${MODEL_NAME}"
```

La valeur reelle est injectee depuis la variable GitHub `MODEL_NAME`.

### Longueur maximale du contexte

Le parametre :

```yaml
- "--max-model-len"
- "${MAX_MODEL_LEN}"
```

est injecte depuis la variable GitHub `MAX_MODEL_LEN`.

### VRAM

Le parametre :

```yaml
- "--gpu-memory-utilization"
- "${GPU_MEMORY_UTILIZATION}"
```

est injecte depuis la variable GitHub `GPU_MEMORY_UTILIZATION`.

### Cache HF persistant

Le cache Hugging Face est monte depuis :

`~/SELFHOSTEDRUNNERS/<nom_depot>-<ENV_NAME>/huggingface-cache`

Cela permet :

- d'eviter les retelechargements complets
- de reduire fortement le temps de redemarrage

## Points d'attention en developpement

### 1. Healthchecks

- `vllm` est considere pret quand `/v1/models` repond
- `nginx` attend explicitement ce signal avant de demarrer
- `nginx` envoie ensuite une petite requete de warmup vers `/v1/completions`

### 2. Secrets

Le secret `VLLM_API_KEY` est reutilise par `nginx` pour proteger l'acces externe.

### 3. HTTPS only

Le stack n'expose plus de port HTTP.

Le port public a publier est porte uniquement par :

- `NGINX_HTTPS_HOST_PORT`

Le conteneur `nginx` ecoute en interne sur le port `443`, et le port host est mappe via `NGINX_HTTPS_HOST_PORT`.

### 4. Compatibilite WSL

Les logs indiquent que le runtime tourne sous WSL.

Impact attendu :

- chargement plus lent possible
- `pin_memory=False`
- performances potentiellement inferieures a un Linux natif

### 5. Limites CPU et memoire avec Podman rootless

En mode rootless, Podman ne peut pas toujours acceder aux controleurs cgroup `cpu` et `memory`.
Si le host ne delegue pas ces controleurs au `user.slice`, les options `cpus` et `mem_limit`
provoquent un echec au demarrage des conteneurs.

Dans ce cas, laisser ces lignes commentees dans `docker/docker-compose-vllm-nginx.yml`.



## Deploiement

### Certificat autosigne pour le developpement

```bash
chmod +x docker/nginx/generate-selfsigned-cert.sh
cd docker/nginx/
./generate-selfsigned-cert.sh
```

### Demarrer le runner

```bash
./run.sh
```

### Lancer un deploiement DEV

```bash
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.yml/dispatches \
  -d '{"ref":"env-developpement","inputs":{"target_env":"ENV_DEV-OPTNC"}}'
```

### Lancer un deploiement PROD
Creer un service de lancement du runner dans ~/.config/systemd/user/github-actions-runner.service
```conf
#~/.config/systemd/user/github-actions-runner.service
[Unit]
Description=GitHub Actions Runner (self-hosted)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/podman/vllm-qwen/actions-runner
ExecStart=/bin/bash /opt/podman/vllm-qwen/actions-runner/run.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

```bash
# Active le user lingering (important pour rootless)
loginctl enable-linger $USER

# charger/lancer le service
systemctl --user daemon-reload
systemctl --user enable --now github-actions-runner.service

# verifier 
systemctl --user status github-actions-runner.service
```

Demarrer les conteneurs
```bash
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.yml/dispatches \
  -d '{"ref":"main","inputs":{"target_env":"ENV_PRD-OPTNC"}}'
```


### Inspecter la sante du backend

```bash
docker inspect --format '{{json .State.Health}}' vllm_qwen-dev
```

### Verifier le conteneur nginx

```bash
docker ps --filter name=nginx-vllm-qwen
```

## Evolutions recommandees

- ajouter un document de changelog de deploiement
- centraliser les profils modeles par environnement
- ajouter un `docker compose ps` en fin de workflow
- supprimer les variables runtime inutiles cote `vllm` si elles generent des warnings
