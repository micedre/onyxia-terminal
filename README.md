# Service « Terminal » pour SSP Cloud / Onyxia

Un service du catalogue qui lance, au choix dans le formulaire :

- **terminal** (par défaut) : un terminal web complet (ttyd + tmux + zsh), avec
  Neovim/LazyVim, opencode, uv, Quarto et des **sessions isolées pour agents IA** ;
- **application** : une seule application graphique affichée dans le navigateur
  via Xpra, pour des logiciels de bureau sans équivalent web :
  - **JDemetra+** : désaisonnalisation (X-13, TRAMO-SEATS) ;
  - **Orange** : apprentissage automatique visuel, par blocs ;
  - **Archi** : modélisation ArchiMate.

Dans les deux cas : même URL, même mot de passe (celui du service Onyxia), mêmes
intégrations que les IDE officiels (S3, Vault, git, kubectl, script d'init, IA).

Ces images (terminal comme applications) peuvent aussi être lancées **avec le chart
officiel `vscode-python`** (image personnalisée), donc depuis un lien de lancement
Onyxia existant.

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
`https://datalab.sspcloud.fr/launcher/ide/vscode-python?autoLaunch=true&service.image.custom.enabled=true&service.image.custom.version=«ghcr.io/mon-org/onyxia-app-jdemetra:latest»`

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

| Sujet | Choix |
|---|---|
| Un seul port | nginx (devant ttyd) ou Xpra écoutent sur 7681 (8080 avec le chart vscode-python) : même ingress, mêmes sondes quel que soit le mode |
| Authentification terminal | page de connexion servie par nginx ; le cookie vaut SHA-256(sel:mot de passe), le sel étant tiré à chaque démarrage (le mot de passe n'est stocké ni dans le cookie ni dans la configuration) ; la page exige HTTPS (WebCrypto) |
| Authentification application | Xpra `auth=env,name=PASSWORD,verify-username=no` (défi HMAC, le mot de passe ne circule pas en clair) |
| ttyd | écoute sur une socket unix privée (`/tmp/onyxia-terminal`, 700) et non sur un port local : ni le pod ni une session agent ne peuvent l'atteindre sans passer par nginx |
| Sondes | `tcpSocket` dans le chart ; `/` répond 200 (page qui renvoie vers `terminal/`) pour les sondes HTTP du chart vscode-python, qui suivent les redirections |
| Page du terminal | page d'index de ttyd enrichie au démarrage : police intégrée (data URI), police d'icônes, script `terminal-page.js` (nouvelle mesure des cellules après chargement des polices, OSC 52, Ctrl+V, clic droit) |
| Liste des polices | passée à ttyd en chaîne JSON : ttyd lit les options avec json-c, qui sinon ne garde que le premier nom entre apostrophes |
| Transferts (trzsz) | chaque transfert s'ouvre dans un panneau tmux temporaire (`transfert.sh`) ; au dépôt, trzsz.js envoie Ctrl+C puis `trz` au panneau actif : `terminal-page.js` remplace ce Ctrl+C par une touche tmux (`User0`) qui ouvre le panneau de réception, où arrive le `trz` |
| Thème | palettes dans `themes.json` ; tmux demande le changement à la page par une séquence privée (`OSC 7777`, écrite sur le terminal du client), la page répond par une touche (`User1`/`User2`) qui fixe `@theme` dans tmux et passe `set background` aux Neovim ouverts (`nvim --server`) |
| Proxy des ports | nginx : `/proxy/PORT/` et `/absproxy/PORT/` vers `127.0.0.1:PORT` (repli sur `[::1]`), même cookie que le terminal, WebSocket, réécriture des redirections ; ports du frontal et des proxys agent interdits ; les liens `http://localhost:PORT` cliqués dans le terminal sont réécrits par `terminal-page.js` (enveloppe de `window.open`) |
| Menu du clic droit | `display-menu -O` : sans cette option, le relâchement du bouton (~100 ms après le clic) ferme le menu aussitôt |
| Neovim | archive officielle (celle d'Ubuntu 24.04 est trop ancienne pour LazyVim) ; presse-papiers en OSC 52, collage depuis le registre (lire le presse-papiers en OSC 52 bloquerait sous tmux) |
| opencode | script d'installation d'onyxia-base ; en CI, jeton GitHub passé en secret de build (évite la limite d'API anonyme) ; configuration montée par le chart (`library-chart.secretOpencode`) |
| zsh et scripts d'init | `~/.bashrc` porte un marqueur de fin de configuration ; `~/.zshrc` source ce que les scripts d'init ajoutent après |
| Agents isolés | utilisateur `agent` + Landlock (landrun) + tinyproxy + proxy de clé LLM ; bubblewrap écarté car le profil AppArmor des pods interdit les montages — détail dans [docs/isolation-agents.md](docs/isolation-agents.md) |
| Fin de l'application | `--exit-with-children` : fermer Archi arrête le conteneur, Kubernetes le relance |
| Verrouillage | `--start-new-commands=no` : l'utilisateur ne peut lancer que l'application prévue |
| Données Archi | `Archi.ini` réécrit : préférences, plugins et modèles dans `~/work/.archi` et `~/work/Archi` |
| JDemetra+ | archive « standalone » officielle (JRE 21 inclus) ; `--userdir ~/work/.jdemetra/userdir`, cache dans `/tmp` |
| Orange | `orange3` + PyQt6 dans un environnement uv séparé (`/opt/orange`), pour ne pas toucher aux projets de l'utilisateur ; réglages et extensions dans `~/work/.orange` (`XDG_DATA_HOME`, `XDG_CONFIG_HOME`) ; aide en ligne (QtWebEngine) sans GPU ni bac à sable |
| Xpra | version 6 du dépôt xpra.org (Ubuntu 24.04 ne fournit que la 3.1) |
| Logs ttyd | `--debug 3` : le niveau par défaut écrit des identifiants dans les logs |

## Ce qui a été vérifié

Les tests navigateur sont dans `tests/e2e/` (Playwright) : `tests/e2e/run.sh` les lance
contre la release `terminal-test` (voir `AGENTS.md`).

Sur SSP Cloud (octobre 2026), avec les images construites par la CI :

- chart `terminal` (`helm upgrade --install`) et chart `vscode-python` 2.6.6 avec l'image
  personnalisée : pod prêt, ingress, terminal fonctionnel ;
- page de connexion : redirection sans cookie, mauvais mot de passe signalé, bon mot de
  passe → terminal, WebSocket, `/logout` ; tests automatisés dans Chromium (Playwright) ;
- copier (sélection, OSC 52, Neovim), coller (Ctrl+V), menu du clic droit, aide (Alt+h,
  bouton `[?]`) : tests automatisés dans Chromium ;
- transferts : glisser-déposer (dans un shell et pendant que Neovim tourne), menu et
  boutons `[↑]` `[↓]`, téléchargement via fzf ; tests automatisés dans Chromium
  (sélecteurs de fichiers simulés) ;
- polices et icônes Nerd Font (captures d'écran du prompt et de LazyVim) ;
- Neovim 0.12.6 + LazyVim : 32 plugins et 27 parseurs treesitter présents, aucun
  téléchargement au lancement ;
- uv 0.13, `uvx` ; Quarto 1.10 : `quarto check` OK, rendu docx d'un diagramme Mermaid ;
- opencode configuré par le chart, requêtes réelles vers le LLM de SSP Cloud ;
- `agent-session` : contrôles d'isolation détaillés dans
  [docs/isolation-agents.md](docs/isolation-agents.md#vérifications) ;
- Archi 5.10 sous Xpra 6 : affichage, authentification, données dans `~/work`.

Non vérifié : le formulaire Onyxia du chart `terminal` publié dans un catalogue (testé
uniquement via Helm), Firefox (les tests navigateur sont faits avec Chromium).

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
- Tau-Argus (secret statistique) n'est pas proposé : il n'existe que pour Windows.
- L'URL de téléchargement d'Archi (`archimatetool/archi.io`, tag `5.10`) change à chaque
  version : à mettre à jour dans `images/archi/Dockerfile`.
- Images x86_64 uniquement.
