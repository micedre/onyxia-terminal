# Service « Terminal » pour SSP Cloud / Onyxia

Un service du catalogue qui lance, au choix dans le formulaire :

- **terminal** (par défaut) : un terminal web complet (ttyd + tmux + zsh) ;
- **application** : une seule application graphique affichée dans le navigateur
  via Xpra (aujourd'hui : **Archi**, l'outil de modélisation ArchiMate).

Dans les deux cas : même URL, même mot de passe (celui du service Onyxia), mêmes
intégrations que les IDE officiels (S3, Vault, git, kubectl, script d'init).

```
images/
  terminal/   onyxia-terminal   : ttyd, tmux, zsh, outils CLI + start.sh (les 2 modes)
  xpra/       onyxia-xpra       : terminal + Xpra 6 et son client HTML5
  archi/      onyxia-app-archi  : xpra + Archi (données redirigées vers ~/work)
  build.sh    construit et pousse les 3 images dans l'ordre
chart/terminal/
  values.yaml          launcher.mode / launcher.app + catalogue "apps"
  values.schema.json   formulaire Onyxia (onglets "Launch" et "Terminal")
  templates/           templates du library-chart + statefulset.yaml + NOTES.txt
```

## 1. Construire les images

```bash
REGISTRY=ghcr.io/mon-org VERSION=0.1.0 ./images/build.sh
```

Puis remplacer `ghcr.io/votre-org` dans `values.yaml` (`service.image`, `apps.archi.image`)
et dans `values.schema.json` (`service.image`).

Tests locaux :

```bash
docker run --rm -p 7681:7681 -e PASSWORD=test ghcr.io/mon-org/onyxia-terminal:0.1.0
docker run --rm -p 7681:7681 -e PASSWORD=test --shm-size=1g ghcr.io/mon-org/onyxia-app-archi:0.1.0
# http://localhost:7681  (terminal : onyxia / test ; Archi : mot de passe "test")
```

## 2. Tester le chart sur SSP Cloud

Depuis un service existant lancé avec le rôle Kubernetes `admin` :

```bash
cd chart/terminal
helm dependency build && helm lint .
helm install archi-test . \
  --set launcher.mode=application --set launcher.app=archi \
  --set ingress.enabled=true \
  --set ingress.hostname=<projet>-archi-test.user.lab.sspcloud.fr \
  --set security.password=$(openssl rand -hex 12)
helm get notes archi-test
```

## 3. Ajouter une application

1. Créer `images/<app>/Dockerfile` à partir de `onyxia-xpra`, qui installe l'application
   et définit `ENV APP_COMMAND=...` (voir `images/archi`).
2. Déclarer l'application dans `values.yaml` :
   ```yaml
   apps:
     monapp:
       image: "ghcr.io/mon-org/onyxia-app-monapp:0.1.0"
       command: "/usr/local/bin/monapp"
   ```
3. Ajouter `monapp` à `launcher.app.listEnum` dans `values.schema.json`.

Le chart refuse de s'installer si l'application choisie n'est pas déclarée dans `apps`.

## Choix techniques

| Sujet | Choix |
|---|---|
| Un seul port | ttyd ou Xpra écoutent sur 7681 : même ingress, mêmes sondes quel que soit le mode |
| Authentification | terminal : auth basique ttyd ; application : `auth=env,name=PASSWORD,verify-username=no` (défi HMAC, le mot de passe ne circule pas en clair) |
| Sondes | `tcpSocket` (ttyd répond 401 à toute requête non authentifiée) |
| Fin de l'application | `--exit-with-children` : fermer Archi arrête le conteneur, Kubernetes le relance |
| Verrouillage | `--start-new-commands=no` : l'utilisateur ne peut lancer que l'application prévue |
| Données Archi | `Archi.ini` réécrit : préférences, plugins et modèles dans `~/work/.archi` et `~/work/Archi` |
| Xpra | version 6 du dépôt xpra.org (Ubuntu 24.04 ne fournit que la 3.1) |
| Logs ttyd | `--debug 3` : le niveau par défaut écrit le mot de passe (base64) dans les logs |

## Ce qui a été vérifié, et ce qui reste à vérifier

Vérifié hors cluster :
- terminal : auth basique, session tmux + zsh via WebSocket, refus des origines étrangères ;
- Archi 5.10 sous Xpra 6.5.4 : affichage (capture d'écran via un client Xpra), auth par
  le mot de passe du service (bon / mauvais / absent), client HTML5 servi sur le port,
  données écrites dans `~/work`, arrêt d'Xpra à la fermeture d'Archi ;
- chart : rendu des templates (sprig + library-chart) dans les modes terminal, application,
  image personnalisée, et échec explicite pour une application inconnue ;
  `values.yaml` conforme à `values.schema.json`.

Non vérifié (outils indisponibles dans l'environnement de préparation) :
- `docker build` des trois images, notamment l'installation d'Xpra depuis xpra.org ;
- `helm lint` / `helm install` réels et l'affichage du formulaire dans Onyxia ;
- la connexion depuis un vrai navigateur au client HTML5 d'Xpra.

## Limites connues

- Rendu graphique logiciel (pas de GPU) : parfait pour Archi, lent pour la 3D.
- Prévoir au moins 2 Go de mémoire en mode application (JVM + Xpra).
- L'URL de téléchargement d'Archi (GitHub `archimatetool/archi.io`, tag `5.10_0`) change
  à chaque version : à mettre à jour dans `images/archi/Dockerfile`, ou héberger l'archive.
- Terminal : Ctrl+W / Ctrl+T sont interceptés par le navigateur (installer la page
  « en tant qu'application » les libère) ; la session tmux ne survit pas à un redémarrage du pod.
- Images x86_64 uniquement.
