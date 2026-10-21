# Service « Terminal » pour SSP Cloud / Onyxia

Un service du catalogue qui lance, au choix dans le formulaire :

- **terminal** (par défaut) : un terminal web complet (ttyd + tmux + zsh), avec
  Neovim/LazyVim, opencode, uv, Quarto et des **sessions isolées pour agents IA** ;
- **application** : une seule application graphique affichée dans le navigateur
  via Xpra, pour des logiciels de bureau sans équivalent web :
  - **JDemetra+** : désaisonnalisation (X-13, TRAMO-SEATS) ;
  - **Orange Datamining** : apprentissage automatique visuel, par blocs ;
  - **Archi** : modélisation ArchiMate.

Dans les deux cas : même URL, même mot de passe (celui du service Onyxia), mêmes
intégrations que les IDE officiels (S3, Vault, git, kubectl, script d'init, IA).

Ces images (terminal comme applications) peuvent aussi être lancées **avec le chart
officiel `vscode-python`** (image personnalisée), donc depuis un lien de lancement
Onyxia existant : voir les [cas d'usage](#cas-dusage).

```
images/
  terminal/   onyxia-terminal   : ttyd, tmux, zsh, outils CLI, start.sh (les 2 modes),
                                  page de connexion, agent-session
  xpra/       onyxia-xpra       : terminal + Xpra 6 et son client HTML5
  archi/      onyxia-app-archi  : xpra + Archi (données redirigées vers ~/work)
  jdemetra/   onyxia-app-jdemetra : xpra + JDemetra+ (archive standalone, JRE inclus)
  orange/     onyxia-app-orange : xpra + Orange (environnement uv dans /opt/orange)
  build.sh    construction locale des images, dans l'ordre
chart/terminal/
  values.yaml          launcher.mode / launcher.app, catalogue "apps", bloc "ai"
  values.schema.json   formulaire Onyxia (onglets "Launch", "Terminal", "AI Assistant"…)
  templates/           templates du library-chart + statefulset.yaml + NOTES.txt
docs/
  isolation-agents.md  isolation des agents IA : architecture, choix, compromis
.github/workflows/
  docker.yml           construction et publication des images (GHCR)
local/                 (ignoré par git) valeurs et scripts de test personnels
```

## Cas d'usage

### Faire travailler un agent IA sur un dépôt, sans lui confier vos identifiants

Un service minimal, lancé par un simple lien : pas de S3, pas de Vault, aucun droit
Kubernetes, le dépôt déjà cloné, et l'agent dans une **session isolée** (utilisateur
séparé, Landlock, internet via un proxy à liste blanche, clé du LLM jamais visible).
Même si l'agent est manipulé (*prompt injection* par le contenu du dépôt, d'une page
web, d'une dépendance), il n'a rien à exfiltrer et ne peut rien pousser.

Le lien, à adapter (domaine de l'instance Onyxia, dépôt) :

```
https://datalab.sspcloud.fr/launcher/ide/vscode-python?name=«agent-projet»&autoLaunch=true&service.image.custom.enabled=true&service.image.custom.version=«ghcr.io/micedre/onyxia-terminal:latest»&s3.enabled=false&vault.enabled=false&kubernetes.enabled=false&git.enabled=true&git.repository=«https://github.com/mon-org/projet.git»
```

| Paramètre | Rôle |
|---|---|
| `service.image.custom.*` | lance l'image terminal avec le chart `vscode-python` (voir [§3](#3-lancer-limage-avec-le-chart-vscode-python)) |
| `s3.enabled=false`, `vault.enabled=false` | aucun identifiant S3 ni Vault dans le service |
| `kubernetes.enabled=false` | le compte de service n'a aucun droit sur le namespace |
| `git.enabled=true`, `git.repository=…` | le dépôt est cloné au démarrage dans `~/work/projet` (`git.branch=…` pour une autre branche) |
| `autoLaunch=true`, `name=…` | lancement direct, sans passer par le formulaire |

Le bloc IA (opencode) est repris du profil Onyxia de l'utilisateur. Votre jeton git
l'est aussi s'il est renseigné : il reste dans votre session, jamais dans celle de l'agent.

Puis, dans le terminal :

```bash
cd ~/work/projet
agent-session                        # opencode dans l'onglet orange « agent:projet »
                                     # (ou clic droit → Session agent isolée)
agent-session log -f                 # suivre ses requêtes internet et ses appels au LLM
agent-session allow conda.anaconda.org   # autoriser un domaine (PyPI, npm, GitHub le sont déjà)
agent-session fetch projet           # récupérer ses commits : branches agent-projet/*
git log -p HEAD..agent-projet/main   # relire avant d'intégrer
```

C'est vous qui poussez une branche et ouvrez la PR, avec vos identifiants : l'agent
travaille sur une copie sans remote. Deux règles : ne lancez pas le code de l'agent
(tests, `uv run`, hooks…) dans votre session, mais dans la sienne ; protégez les
fichiers de CI (`.github/workflows`…), autre canal d'exfiltration. Architecture, choix
et limites : [docs/isolation-agents.md](docs/isolation-agents.md).

### Un terminal complet dans le navigateur

Pour qui préfère la ligne de commande à un IDE : sessions tmux qui survivent à la
fermeture de l'onglet, Neovim/LazyVim prêt à l'emploi, uv, Quarto, transferts de
fichiers par glisser-déposer, et aperçu d'une application web lancée dans le terminal
(Streamlit, Shiny, `http.server`…) via `/proxy/PORT/`. Détail [ci-dessous](#le-terminal).

### Un logiciel de bureau sans équivalent web

JDemetra+ (désaisonnalisation), Orange (apprentissage automatique visuel) ou Archi,
affichés dans le navigateur : il suffit de remplacer l'image du lien ci-dessus par
`onyxia-app-jdemetra`, `onyxia-app-orange` ou `onyxia-app-archi` (voir
[§3](#3-lancer-limage-avec-le-chart-vscode-python)).

## Le terminal

| Fonction | Détail |
|---|---|
| Connexion | page « mot de passe seul » (compatible gestionnaires de mots de passe), session de 7 jours par cookie, `/logout` pour se déconnecter |
| Affichage | police JetBrains Mono intégrée à la page, icônes Nerd Font (prompt, LazyVim) servies par nginx, thème clair/sombre selon Onyxia, à basculer avec **Alt+m**, le bouton `[◐]`, le clic droit ou `theme clair\|sombre` (mémorisé par le navigateur, Neovim suit) |
| Plusieurs shells | session tmux `main` (survit à la fermeture de l'onglet) ; Alt+t nouvel onglet, Alt+Entrée / Alt+- diviser, Alt+flèches, Alt+1…9, Alt+z zoom, Alt+w fermer ; boutons cliquables `[+] [⫼] [⊟]` dans la barre d'état |
| Copier / coller | sélection à la souris = copie dans le presse-papiers du navigateur (OSC 52, aussi depuis Neovim), double/triple clic = mot/ligne ; **Ctrl+V** colle |
| Clic droit | menu tmux en français (aide, coller, onglets, découpage, session agent) ; Maj+clic droit = menu du navigateur |
| Aide | **Alt+h**, bouton `[?] aide` ou clic droit → Aide : tous les raccourcis |
| Fichiers | glisser-déposer sur la page (arrive dans le dossier du panneau actif, même si Neovim y tourne), boutons `[↑]` `[↓]` et clic droit (choix des fichiers à télécharger avec fzf), ou `trz` / `tsz <fichier>` ; seul `~/work` est conservé |
| Applications web | un serveur lancé dans le terminal (`localhost:8000`) s'ouvre via `/proxy/8000/` (préfixe retiré) ou `/absproxy/8000/` (préfixe conservé), comme code-server ; cliquer sur l'URL affichée l'ouvre directement ; `ports` liste les ports en écoute et leurs liens |
| Éditeur | Neovim 0.12 + LazyVim préinstallé (plugins et parseurs treesitter inclus, aucun téléchargement au lancement), fichiers cachés (`.github`, `.gitignore`…) affichés dans l'explorateur et les recherches ; `vi`/`vim` = `nvim`, `EDITOR=nvim` |
| IA | opencode configuré par le chart (bloc `ai`, mêmes réglages que les images datascience) |
| **Agents isolés** | `agent-session` : agent IA sans identifiants, internet via un proxy à liste blanche journalisé, copie git sans remote — voir [docs/isolation-agents.md](docs/isolation-agents.md) |
| Outils | uv/uvx, Quarto + Chrome headless (diagrammes Mermaid en docx/pdf), kubectl, helm, aws, git, fzf, zoxide, ripgrep, fd, bat, eza, btop, starship |
| Scripts d'init | les ajouts à `~/.bashrc` (PATH, alias) sont repris par zsh |

## 1. Construire les images

Automatique : le workflow `.github/workflows/docker.yml` construit et publie les
images sur `ghcr.io/<propriétaire>/` à chaque push sur `main` (`latest` + `sha-xxxxxxx`)
et à chaque tag `v*` (version). Les pull requests ne construisent que l'image terminal,
sans la publier.

En local (BuildKit requis, pour le secret optionnel `github_token` de l'installation
d'opencode) :

```bash
REGISTRY=ghcr.io/mon-org VERSION=0.1.0 ./images/build.sh
```

Puis remplacer `ghcr.io/votre-org` dans `values.yaml` (`service.image`, `apps.*.image`)
et dans `values.schema.json` (`service.image`).

Test local :

```bash
docker run --rm -p 7681:7681 -e PASSWORD=test ghcr.io/mon-org/onyxia-terminal:0.1.0
docker run --rm -p 7681:7681 -e PASSWORD=test --shm-size=1g ghcr.io/mon-org/onyxia-app-archi:0.1.0
# http://localhost:7681  (mot de passe "test" dans les deux cas)
```

## 2. Tester le chart sur SSP Cloud

Depuis un service existant lancé avec le rôle Kubernetes `admin` :

```bash
helm repo add inseefrlab-interactive https://inseefrlab.github.io/helm-charts-interactive-services
cd chart/terminal
helm dependency build && helm lint .
helm upgrade --install terminal-test . -f mes-valeurs.yaml
helm get notes terminal-test
```

avec par exemple :

```yaml
service:
  image:
    pullPolicy: Always          # indispensable avec le tag latest
    version: ghcr.io/mon-org/onyxia-terminal:latest
security:
  password: "…"
ingress:
  enabled: true
  hostname: <projet>-terminal-test.user.lab.sspcloud.fr
ai:                             # facultatif : copier le bloc "ai" d'un service vscode existant
  enabled: true
```

Mode application : `--set launcher.mode=application --set launcher.app=jdemetra`
(ou `orange`, `archi`).

## 3. Lancer l'image avec le chart vscode-python

L'image installe un faux `/usr/bin/code-server` : quand le chart `vscode-python`
exécute `code-server … ~/work` sur le port 8080, c'est le terminal qui démarre (nginx sur
8080, `/` répond 200 pour les sondes). Les appels des scripts d'init du type
`code-server --install-extension` sont ignorés. Dans Onyxia, ou en valeurs Helm :

```yaml
service:
  image:
    pullPolicy: Always
    custom:
      enabled: true
      version: ghcr.io/mon-org/onyxia-terminal:latest
```

Un lien de lancement Onyxia de `vscode-python` avec ces deux paramètres
(`service.image.custom.enabled=true`, `service.image.custom.version=…`) ouvre donc
directement le terminal, avec sa configuration S3 / Vault / git / IA habituelle.

Même principe pour les applications : les images d'application héritent du faux
`code-server` et fixent elles-mêmes `LAUNCH_MODE=application` et `APP_COMMAND`, donc
l'application s'ouvre directement (Xpra sur 8080, même mot de passe) :

| `service.image.custom.version` | Ouvre |
|---|---|
| `ghcr.io/mon-org/onyxia-terminal:latest` | le terminal |
| `ghcr.io/mon-org/onyxia-app-jdemetra:latest` | JDemetra+ |
| `ghcr.io/mon-org/onyxia-app-orange:latest` | Orange |
| `ghcr.io/mon-org/onyxia-app-archi:latest` | Archi |

Exemple de lien (à adapter à l'instance Onyxia) :
`https://datalab.sspcloud.fr/launcher/ide/vscode-python?name=jdemetra&autoLaunch=true&service.image.custom.enabled=true&service.image.custom.version=«ghcr.io/micedre/onyxia-app-jdemetra:latest»`

## 4. Ajouter une application

1. Créer `images/<app>/Dockerfile` à partir de `onyxia-xpra`, qui installe l'application
   et définit `ENV APP_COMMAND=...` (voir `images/archi`) : c'est aussi ce qui la fait
   démarrer avec le chart vscode-python, qui ne passe pas cette variable.
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

**Un seul port, nginx en frontal.** Dans les deux modes, nginx écoute sur le port du
service (7681, ou 8080 avec le chart vscode-python) : même ingress, mêmes sondes, et le
mot de passe du service Onyxia protège tout.

```
navigateur ─HTTPS─▶ ingress ─▶ nginx :7681 ─┬─▶ ttyd ─▶ tmux ─▶ zsh     (terminal)
                                            └─▶ Xpra ─▶ application   (application)
```

**Mode terminal.** Après la page de connexion (cookie), nginx passe à ttyd, joignable
seulement par une socket unix privée. ttyd rattache le navigateur à la session tmux
`main`, qui survit à la fermeture de l'onglet. La page de ttyd est enrichie au
démarrage : polices, presse-papiers, clic droit, glisser-déposer de fichiers, thème.
nginx expose aussi les serveurs web lancés dans le terminal (`/proxy/PORT/`), et
`agent-session` isole les agents IA ([docs/isolation-agents.md](docs/isolation-agents.md)).

**Mode application.** nginx sert le client HTML5 d'Xpra et ne passe à Xpra (local,
protégé par le mot de passe) que le WebSocket. Xpra fait tourner un écran X virtuel avec
une seule application, lancée à la première connexion ; la fermer redémarre le
conteneur. Les données de l'application sont redirigées vers `~/work`.

**Briques utilisées :**

- socle : [Onyxia](https://github.com/InseeFrLab/onyxia), image
  [onyxia-base](https://github.com/InseeFrLab/images-datascience),
  [library-chart](https://github.com/InseeFrLab/helm-charts-interactive-services) ;
- terminal : [ttyd](https://github.com/tsl0922/ttyd), [tmux](https://github.com/tmux/tmux),
  [zsh](https://www.zsh.org/), [nginx](https://nginx.org/), [trzsz](https://trzsz.github.io/),
  [Neovim](https://neovim.io/) + [LazyVim](https://www.lazyvim.org/),
  [starship](https://starship.rs/), [fzf](https://github.com/junegunn/fzf),
  [uv](https://github.com/astral-sh/uv), [Quarto](https://quarto.org/),
  [opencode](https://opencode.ai/) ;
- agents : [Landlock](https://landlock.io/) via [landrun](https://github.com/Zouuup/landrun),
  [tinyproxy](https://tinyproxy.github.io/) ;
- applications : [Xpra](https://xpra.org/) et son client
  [xpra-html5](https://github.com/Xpra-org/xpra-html5),
  [JDemetra+](https://github.com/jdemetra/jdplus-main),
  [Orange Datamining](https://orangedatamining.com/), [Archi](https://www.archimatetool.com/).

Le détail des choix et leurs raisons : [AGENTS.md](AGENTS.md#technical-choices).

## Limites connues

- Terminal : Ctrl+W / Ctrl+T sont interceptés par le navigateur (installer la page
  « en tant qu'application » les libère) ; la session tmux ne survit pas à un
  redémarrage du pod ; après un redémarrage, il faut se reconnecter (nouveau sel).
- Ctrl+V colle au lieu d'être transmis : dans Neovim, Ctrl+Q remplace Ctrl+V pour la
  sélection en bloc.
- La page de connexion exige HTTPS (ou `localhost`).
- Proxy des ports : les applications qui chargent leurs ressources par chemins absolus
  (`/static/…`) demandent `/absproxy/PORT/` et un chemin de base ; une page ouverte via
  le proxy partage l'origine du terminal (comme avec code-server) et pourrait piloter
  le terminal : n'y ouvrir que des applications de confiance.
- Transferts : choisir des fichiers à envoyer et télécharger demandent Chrome ou Edge
  (API File System Access, utilisée par trzsz.js) ; Firefox permet seulement le glisser-déposer.
- Agents isolés : filtrage réseau par port et non par hôte, UDP/DNS non filtré, seuls
  les noms de domaine sont visibles (voir la doc dédiée).
- Rendu graphique logiciel (pas de GPU) : convient à Archi, JDemetra+ et Orange, lent pour la 3D.
- Prévoir au moins 2 Go de mémoire en mode application (JVM + Xpra), davantage pour
  de gros jeux de données dans Orange.
