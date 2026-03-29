# Documentation Fonctionnelle

## Objectif

Ce projet expose un modele `vLLM` derriere un proxy `nginx` securise en HTTPS.

L'objectif fonctionnel est de fournir :

- une API compatible OpenAI pour interroger un LLM
- une exposition HTTPS via `nginx`
- un deploiement automatise par GitHub Actions sur un runner self-hosted
- une separation des environnements `dev`, `qul` et `prd`

## Composants fonctionnels

### 1. vLLM

Le service `vllm` charge le modele et expose l'API sur le port interne `8000`.

Fonctions principales :

- chargement du modele Hugging Face configure dans le `docker-compose`
- exposition des routes API `v1/models`, `v1/completions`, `v1/chat/completions`
- gestion du cache local pour eviter les retelechargements complets du modele

### 2. nginx

Le service `nginx` joue le role de reverse proxy HTTPS.

Fonctions principales :

- terminaison TLS
- protection par cle API `Bearer`
- proxy des requetes vers `vllm`
- attente active de la disponibilite du backend avant demarrage
- envoi d'une requete de warmup au backend avant exposition du service

### 3. GitHub Actions

Le workflow de deploiement permet de lancer un redeploiement manuel vers un environnement cible.

Fonctions principales :

- selection de l'environnement GitHub
- preparation des secrets
- generation d'un contexte de runtime persistant sur la machine cible
- build local de l'image `nginx`
- redeploiement par `docker compose`

## Parcours fonctionnel

### Deploiement

1. Un utilisateur declenche le workflow GitHub Actions.
2. Le runner self-hosted recupere le code.
3. Les secrets et variables d'environnement sont resolves.
4. `vllm` est demarre avec le modele configure.
5. `nginx` attend que `vllm` soit joignable sur `/v1/models`.
6. `nginx` envoie une requete de warmup au backend `vllm`.
7. L'API est accessible via HTTPS.

### Appel API

1. Le client appelle `https://<hote>:<port>/v1/models` ou `https://<hote>:<port>/v1/completions`.
2. `nginx` verifie la presence du header `Authorization: Bearer ...`.
3. Si la cle est valide, la requete est transmise a `vllm`.
4. `vllm` repond au format OpenAI-compatible.

## Environnements

Chaque environnement GitHub doit definir :

- `ENV_NAME`
- `MODEL_NAME`
- `MAX_MODEL_LEN`
- `GPU_MEMORY_UTILIZATION`
- `NGINX_HTTPS_HOST_PORT`

Chaque environnement GitHub doit aussi fournir les secrets necessaires :

- `VLLM_API_KEY`
- `NGINX_SSL_KEY` ou `NGINX_SSL_KEY_B64`
- `NGINX_SSL_CERT` ou `NGINX_SSL_CERT_B64`
- `NGINX_SSL_FULLCHAIN` ou `NGINX_SSL_FULLCHAIN_B64`

## Repertoire persistant

Le deploiement cree un repertoire persistant sur la machine cible :

`~/SELFHOSTEDRUNNERS/<nom_depot>-<ENV_NAME>`

Ce repertoire contient :

- le cache Hugging Face
- les secrets runtime generes pour le deploiement
- le fichier d'override `docker-compose`

## Comportement de readiness

La disponibilite du service suit la logique suivante :

- `vllm` doit repondre sur `GET /v1/models`
- `nginx` ne demarre pas tant que ce signal n'est pas present
- apres ce signal, `nginx` effectue une petite requete de warmup pour precharger le backend
- seulement ensuite, `nginx` devient joignable depuis l'exterieur

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
