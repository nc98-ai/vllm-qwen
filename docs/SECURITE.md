# Documentation Securite

## Objectif

Ce document recense les principaux mecanismes de protection du projet et les bonnes pratiques associees.

## Mesures de securite en place

### 1. Exposition HTTPS

Le service `nginx` expose l'API en HTTPS uniquement.

Mesures appliquees :

- activation TLS 1.2 et TLS 1.3
- durcissement des suites de chiffrement
- en-tetes de securite HTTP

Fichier concerne :

- `docker/nginx/nginx.conf.template`

### 2. Controle d'acces par cle API

L'acces a l'API exposee par `nginx` est protege par un header :

`Authorization: Bearer <cle>`

La cle attendue provient du secret `VLLM_API_KEY`, monte dans `nginx` au runtime.

Sans cette cle, `nginx` doit repondre `401 Unauthorized`.

### 3. Secrets non commites

Le projet s'appuie sur les secrets GitHub Actions et evite de commiter les secrets runtime.

Secrets attendus :

- `VLLM_API_KEY`
- `NGINX_SSL_KEY` ou `NGINX_SSL_KEY_B64`
- `NGINX_SSL_CERT` ou `NGINX_SSL_CERT_B64`
- `NGINX_SSL_FULLCHAIN` ou `NGINX_SSL_FULLCHAIN_B64`

### 4. Stockage runtime hors du depot

Les fichiers de runtime sont deposes hors du checkout GitHub Actions dans :

`~/SELFHOSTEDRUNNERS/<nom_depot>-<ENV_NAME>`

Interets :

- eviter les erreurs de permission dans le workspace Git
- limiter le risque d'exposition accidentelle des fichiers runtime
- mieux isoler les donnees persistantes du code source

### 5. Limitation d'abus

`nginx` applique un `limit_req` sur les appels API.

Objectif :

- limiter certains abus simples
- reduire l'impact de rafales de requetes

## Risques residuels

### 1. Certificats autosignes

Les certificats autosignes sont pratiques en environnement de test, mais ils ne constituent pas une solution adequate pour une exposition publique.

Recommandation :

- utiliser un certificat emis par une autorite de confiance en production

### 2. Secrets presents en memoire et sur disque

Les secrets sont ecrits dans des fichiers runtime pour etre montes dans les conteneurs.

Recommandations :

- proteger strictement le compte systeme du runner
- limiter les droits sur `~/SELFHOSTEDRUNNERS`
- purger les anciens environnements inutilises

### 3. Host self-hosted unique

Le runner et les conteneurs tournent sur la meme machine.

Risques :

- concentration des responsabilites
- exposition plus forte si la machine est compromise

Recommandations :

- reserver la machine a ce type de deploiement
- appliquer les mises a jour systeme et Docker
- restreindre les acces SSH

### 4. Journalisation

Les logs applicatifs peuvent contenir des informations sensibles si les prompts ou les erreurs remontent certaines donnees.

Recommandations :

- verifier regulierement les logs
- ne pas journaliser de secrets applicatifs
- limiter l'acces aux sorties Docker et GitHub Actions

## Bonnes pratiques operationnelles

### Rotation des secrets

- changer regulierement `VLLM_API_KEY`
- renouveler les certificats TLS avant expiration
- revoquer toute cle soupconnee compromise

### Verification apres deploiement

Verifier systematiquement :

- que `/v1/models` repond uniquement avec une cle API valide
- que l'appel sans header `Authorization` renvoie `401`
- que `vllm` et `nginx` sont `healthy` ou `up` selon le comportement attendu

### Tests rapides

#### Appel refuse sans cle

```bash
curl -k https://127.0.0.1:443/v1/models
```

#### Appel autorise avec cle

```bash
curl -k https://127.0.0.1:443/v1/models \
  -H "Authorization: Bearer $VLLM_API_KEY"
```

## Recommandations futures

- remplacer les certificats autosignes en production
- ajouter une politique explicite de rotation des secrets
- isoler le runner self-hosted dans un environnement dedie
- ajouter une supervision centralisee des acces et des erreurs
