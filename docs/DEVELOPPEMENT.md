# Documentation Developpement

## Vue d'ensemble technique

Le projet repose sur deux services Docker :

- `vllm` pour l'inference
- `nginx` pour l'exposition HTTPS et le controle d'acces

Le deploiement cible est automatise via deux workflows CD totalement fonctionnels, testes et valides :

- `.github/workflows/deploy-self-hosted.yml` (compatible `podman compose`)
- `.github/workflows/deploy-self-hosted.quadlet.yml` (compatible `quadlets` sur Rocky Linux 9)

## Fichiers importants

### Orchestration

- `docker/docker-compose-vllm-nginx.yml`
- `.github/workflows/deploy-self-hosted.yml`
- `.github/workflows/deploy-self-hosted.quadlet.yml`
- `docker/quadlets/vllm-qwen.network.template`
- `docker/quadlets/vllm-qwen.container.template`
- `docker/quadlets/nginx-vllm.container.template`

### nginx

- `docker/nginx/Dockerfile`
- `docker/nginx/docker-entrypoint.sh`
- `docker/nginx/nginx.conf.template`

### Documentation

- `README.md`
- `docs/FONCTIONNEL.md`
- `docs/SECURITE.md`

## Fonctionnement des workflows CD utilisant les runners GitHub

### Workflow compose (`deploy-self-hosted.yml`)

Le workflow self-hosted utilise docker/podman compose. Il fait les operations suivantes :

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

### Workflow quadlet (`deploy-self-hosted.quadlet.yml`)

Le workflow self-hosted `quadlet` fait les operations suivantes :

1. resolution du nom d'environnement de deploiement
2. validation de `ENV_NAME`
3. validation de `MODEL_NAME`
4. validation de `MAX_MODEL_LEN`
5. validation de `GPU_MEMORY_UTILIZATION`
6. validation de `NGINX_HTTPS_HOST_PORT`
7. creation des repertoires persistants de runtime
8. preparation des secrets
9. build local de l'image `nginx`
10. generation des fichiers quadlet depuis les templates dans `docker/quadlets`
11. `systemctl --user daemon-reload`
12. redemarrage des services `vllm-qwen-<ENV_NAME>.service` et `nginx-vllm-qwen-<ENV_NAME>.service`
13. verification post-deploiement via appel HTTPS local

## CI de qualification (locale et GitHub)

La CI infra est definie dans `.github/workflows/ci-infra-sanity.yml`.
Elle peut aussi etre executee localement via `bash scripts/ci-infra-sanity-local.sh`.

### Objectif

Valider les fichiers critiques d'infrastructure sans redeployer le service.

### Ce que la CI verifie concretement

1. Scripts shell valides
- analyse `shellcheck` sur les scripts `*.sh` (hors dossier `actions-runner`)
- detection des erreurs de quoting, substitutions risquées, patterns fragiles

2. YAML valide
- analyse `yamllint` sur `.github/workflows` et `docker/docker-compose-vllm-nginx.yml`
- verification de la structure YAML et des erreurs de syntaxe

3. Definition compose exploitable
- execution de `compose config -q` avec variables de test
- verification que la stack est resolvable sans erreur de configuration

4. Image nginx buildable
- build de `docker/nginx/Dockerfile`
- detection des regressions de build

5. Configuration nginx rendue et valide
- rendu de `docker/nginx/nginx.conf.template` via `envsubst`
- verification `nginx -t` sur la configuration generee
- detection des placeholders non resolus et erreurs de syntaxe nginx

6. Impact runtime controle
- aucun `compose up/down`
- aucune suppression de conteneurs de service
- uniquement un conteneur de test ephemere pour le controle `nginx -t`

### Execution locale

Commande standard :

```bash
bash scripts/ci-infra-sanity-local.sh
```

Le nettoyage des anciennes images de test CI locale est actif par defaut.
Pour conserver ces images :

```bash
bash scripts/ci-infra-sanity-local.sh --no-cleanup-images
```

Sur Rocky Linux sans `sudo`, le script fonctionne en rootless avec `podman`.
Si `shellcheck` ou `yamllint` ne sont pas installes localement, le script utilise
automatiquement des images de lint en conteneur.

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

Dans ce cas, laisser ces lignes commentees dans le docker/podman compose.



## Deploiement en DEV - utilisation des runners github

### Certificat autosigne pour le developpement

```bash
chmod +x docker/nginx/generate-selfsigned-cert.sh
cd docker/nginx/
./generate-selfsigned-cert.sh
```
renseigner les variables correspondantes dans l'environnement github

### Demarrer le runner mannuellement

```bash
./run.sh
```

### Lancer un deploiement manuellement
Aller sur github actions

#### Variante podman compose via API

```bash
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.yml/dispatches \
  -d '{"ref":"env-developpement","inputs":{"target_env":"ENV_DEV-OPTNC"}}'
```

#### Variante quadlet (Rocky Linux 9) via API

```bash
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.quadlet.yml/dispatches \
  -d '{"ref":"env-developpement","inputs":{"target_env":"ENV_DEV-OPTNC"}}'
```

### Lancer un deploiement QUAL/PROD - utilisations des runners
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


#### Variante podman compose

```bash
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.yml/dispatches \
  -d '{"ref":"main","inputs":{"target_env":"ENV_PRD-OPTNC"}}'
```

#### Variante quadlet (Rocky Linux 9)

```bash
curl -s -o /dev/null -w "dispatch HTTP %{http_code}\n" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/nc98-ai/vllm-qwen/actions/workflows/deploy-self-hosted.quadlet.yml/dispatches \
  -d '{"ref":"env-qualification","inputs":{"target_env":"ENV_QUL-OPTNC"}}'
```


### Inspecter la sante du backend

```bash
docker inspect --format '{{json .State.Health}}' vllm_qwen-<ENV_NAME>
```

### Verifier le conteneur nginx

```bash
docker ps --filter name=nginx-vllm-qwen-<ENV_NAME>

#logs
journalctl --user -u nginx-vllm-qwen-<ENV_NAME>.service -f
```
### consulter les logs de déploiement sur le serveur
journalctl --user -u vllm-qwen-actions-runner.quadlet.service -f


# Test inférence
```bash

port=4444 #qual
MODEL_NAME=Qwen/Qwen3-4B-AWQ
curl -k "https://127.0.0.1:$port/v1/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d "{
    \"model\": \"${MODEL_NAME}\",
    \"prompt\": \"Qui est Napoleon ?\",
    \"temperature\": 0.2,
    \"max_tokens\": 80
  }"
```

## Evolutions recommandees

- ajouter un document de changelog de deploiement
- centraliser les profils modeles par environnement
- ajouter un `docker compose ps` en fin de workflow
- supprimer les variables runtime inutiles cote `vllm` si elles generent des warnings
