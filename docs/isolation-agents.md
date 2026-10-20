# Isolation des agents IA (`agent-session`)

Ce document décrit comment le terminal permet de faire travailler un agent IA
(opencode par défaut, ou toute autre commande) **sans lui confier les
identifiants de l'utilisateur**, les choix faits pour y parvenir sur SSP Cloud et
leurs limites.

- [Objectif et menace](#objectif-et-menace)
- [Utilisation](#utilisation)
- [Ce qu'expose un pod Onyxia](#ce-quexpose-un-pod-onyxia)
- [Options étudiées](#options-étudiées)
- [Architecture retenue](#architecture-retenue)
- [Récupérer le travail de l'agent](#récupérer-le-travail-de-lagent)
- [Vérifications](#vérifications)
- [Limites et compromis](#limites-et-compromis)
- [Évolutions possibles](#évolutions-possibles)

## Objectif et menace

On veut pouvoir laisser un agent IA modifier du code, lancer des tests, installer
des paquets… sans qu'il puisse, par erreur ou parce qu'il a été manipulé (*prompt
injection* via le contenu d'un dépôt, d'une page web, d'une dépendance) :

- lire ou utiliser les identifiants de l'utilisateur : S3 (MinIO), Vault, git,
  compte de service Kubernetes, **ni même la clé d'API du LLM** ;
- modifier autre chose que sa copie de travail (dépôt d'origine, autres projets,
  configuration de l'utilisateur) ;
- pousser vers le dépôt distant (GitHub/GitLab) ;
- joindre n'importe quel site : l'accès à internet passe par un **proxy à liste
  blanche**, et **chaque requête est visible**.

Hors périmètre : un attaquant capable d'exploiter une faille du noyau partagé
(l'agent tourne dans le même pod), et l'exfiltration via le LLM lui-même (voir
[Limites](#limites-et-compromis)).

## Utilisation

```bash
cd ~/work/mon-projet
agent-session                   # opencode dans un nouvel onglet tmux « agent:mon-projet »
agent-session -n essai -- bash  # un shell dans une session nommée « essai »
```

Ou, avec la souris : clic droit dans le terminal → **Session agent isolée**.

| Commande | Effet |
|---|---|
| `agent-session [-n NOM] [-r DÉPÔT] [--here] [-- cmd…]` | ouvre la session (onglet orange `agent:NOM`) ; `--here` : dans le panneau courant |
| `agent-session log [-f]` | requêtes du proxy (domaines autorisés / refusés) et appels LLM |
| `agent-session allow DOMAINE…` / `deny DOMAINE…` / `allow --list` | gère la liste blanche (`*.exemple.org` accepté), appliquée immédiatement |
| `agent-session fetch NOM` | dans votre dépôt : récupère les commits de l'agent (branches `agent-NOM/*`) |
| `agent-session push NOM` | envoie votre branche courante à l'agent (`upstream/<branche>` chez lui) |
| `agent-session list` | sessions existantes et leur dernier commit |

Fichiers, tous sur le volume persistant :

```
~/work/agents/allow.txt        liste blanche (éditable à la main, l'agent ne peut pas la lire)
~/work/agents/<nom>/           copie de travail de l'agent (dépôt git sans remote)
~/work/agents/.home/<nom>/     son dossier personnel (sessions opencode, caches uv/npm…)
```

Exemple de journal (`agent-session log`) :

```
Oct 20 07:32:00 REQ   CONNECT pypi.org:443
Oct 20 07:32:02 REQ   CONNECT files.pythonhosted.org:443
Oct 20 07:32:00 REQ   CONNECT example.com:443
Oct 20 07:32:00 REFUS example.com
--- appels LLM
2026-10-20T07:32:21+00:00 LLM POST /p0/chat/completions 200 11255o 0.992s
```

## Ce qu'expose un pod Onyxia

Constat fait dans un service SSP Cloud (octobre 2026), qui guide tous les choix :

| Élément | Constat | Conséquence |
|---|---|---|
| Variables d'environnement | ~24 secrets (`AWS_*`, `VAULT_*`, `GIT_PERSONAL_ACCESS_TOKEN`, `KUBERNETES_*`, `OPENAI_API_KEY`…) | un processus du même utilisateur peut les lire dans `/proc/<pid>/environ` : **retirer les variables avant de lancer l'agent ne suffit pas** |
| Compte de service | jeton monté dans `/var/run/secrets/kubernetes.io/serviceaccount`, droits `admin` sur le namespace (`pods/exec`, créer des pods…) | accès complet au namespace pour qui lit ce fichier |
| sudo | `onyxia ALL=(ALL) NOPASSWD: ALL` | tout processus de l'utilisateur peut devenir root |
| Fichiers | `~/.aws`, `~/.kube`, `~/.git-credentials`… écrits par le script d'init | lisibles par l'utilisateur |
| Espaces de noms utilisateur | `unshare -Ur` fonctionne, seccomp non confiné | — |
| **AppArmor** | profil `cri-containerd.apparmor.d` (enforce) : **tout `mount` est refusé**, même dans un namespace utilisateur | bubblewrap, nsjail, `unshare -m`… sont **inutilisables** (`bwrap: Failed to make / slave: Permission denied`) |
| **Landlock** | ABI 6 disponible (noyau 6.12), non bloqué par AppArmor, sans privilège | restriction des fichiers par chemin et des connexions TCP par port |
| RuntimeClass (gVisor, Kata) | non listables / non disponibles | pas de bac à sable « VM légère » |
| NetworkPolicy | création autorisée ; celles d'Onyxia ne filtrent que l'entrée ; application du filtrage en **sortie** non vérifiée (dépend du CNI) | pas fiable pour filtrer le réseau d'un pod sans test préalable |
| `dev.tty.legacy_tiocsti` | `0` | un processus ne peut pas injecter de frappes dans le terminal de l'utilisateur |

## Options étudiées

| | A. bubblewrap dans le pod | B. Pod « agent » séparé | C. Conteneur annexe (sidecar) | **D. Autre utilisateur + Landlock (retenu)** |
|---|---|---|---|---|
| Secrets | masqués (env vide, `/proc` neuf, jeton absent) | jamais montés | env séparé, mais jeton du compte de service monté dans tous les conteneurs | env propre (sudo), `/proc` des processus de l'utilisateur illisible (autre uid), fichiers interdits par Landlock |
| Réseau | coupé (`--unshare-net`) + ponts vers les proxys | NetworkPolicy (si le CNI l'applique) | réseau du pod, non filtrable | TCP sortant limité par port (Landlock) aux deux proxys |
| Copie de travail | montée, en direct | volume séparé, synchronisation git par `kubectl exec` | volume partagé | dossier du volume persistant, échanges par `git bundle` |
| Coût / UX | instantané | un second pod (quota, démarrage), un autre service à lancer | modification du chart | instantané, un onglet tmux |
| Robustesse | namespaces noyau | la plus forte disponible | la plus faible | uid + Landlock (noyau partagé) |
| Statut | **impossible** : AppArmor refuse `mount` (autoriser `Unconfined` affaiblirait tout le pod et n'est probablement pas permis par la plateforme) | possible, plus lourd | écarté | **retenu** |

Points qui ont fait pencher pour D :

- c'est la seule option **dans le pod** qui fonctionne avec le profil AppArmor imposé ;
- un utilisateur distinct règle d'un coup les problèmes de l'environnement, de
  `/proc` et de sudo, sans privilège particulier (l'utilisateur onyxia a déjà sudo
  pour créer la session) ;
- Landlock complète ce que l'uid ne couvre pas : fichiers lisibles par « les
  autres » (le jeton du compte de service, `~/.bashrc`…) et réseau ;
- l'expérience reste celle d'un terminal : un onglet de plus, rien à déployer.

Pour la visibilité réseau, deux niveaux ont été comparés : **noms de domaine
seulement** (tinyproxy, sans certificat) ou **URL complètes** (mitmproxy, qui
déchiffre le HTTPS avec sa propre autorité de certification). Le premier a été
choisi pour sa simplicité : rien à installer côté outils, pas de certificat à
faire accepter, aucun outil cassé par l'interception.

## Architecture retenue

```
 onyxia (votre session)                         agent (uid 2000, Landlock)
 ─────────────────────                          ──────────────────────────
 identifiants, sudo, ~/.aws, jeton k8s          env minimal, ni sudo ni identifiants
                                                 fichiers : ~/work/agents/<nom>  (rwx)
 agent-session ──sudo -u agent── landrun ──────▶          ~/work/agents/.home/<nom> (rwx)
      │                                                   /usr /opt (rx), /etc /proc (r), /dev
      │ démarre                                  TCP sortant : ports 8888 et 4000 uniquement
      ▼
 tinyproxy 127.0.0.1:8888  ◀── HTTP(S)_PROXY ── opencode, uv, npm, git, curl…
   liste blanche + journal ──▶ internet (domaines autorisés)
 nginx     127.0.0.1:4000  ◀── baseURL LLM ──── opencode (clé factice « sandbox »)
   ajoute la vraie clé ─────▶ LLM (llm.lab.sspcloud.fr…)
```

### Utilisateur `agent`

Créé dans l'image (`useradd --uid 2000 --user-group`), sans sudo (ni dans le
groupe `sudo`, ni dans `/etc/sudoers`). La session est lancée par
`sudo -u agent` : `env_reset` vide l'environnement et `use_pty` donne à l'agent
son **propre pseudo-terminal**. Conséquences : il ne voit ni les variables de
l'utilisateur, ni ses processus (`/proc/<pid>/environ` réservé au même uid), ni
ses sockets privées (tmux dans `/tmp/tmux-1000`, ttyd dans `/tmp/onyxia-terminal`,
dossiers en 700).

`~` (`/home/onyxia`, en 750) reçoit le droit de **traversée** `o+x` : l'agent peut
atteindre `~/work/agents/…` sans pouvoir lister le dossier ; Landlock lui interdit
de toute façon tout ce qui n'est pas explicitement autorisé.

### Landlock (via landrun)

[landrun](https://github.com/Zouuup/landrun) applique un domaine Landlock puis lance
la commande ; le domaine est hérité par tous les processus fils et ne peut pas être
levé. Règles :

| Accès | Chemins |
|---|---|
| lecture + exécution | `/usr`, `/opt`, `/bin`, `/sbin`, `/lib`, `/lib64` |
| lecture | `/etc`, `/proc` |
| lecture + écriture | `/dev` |
| lecture + écriture + exécution | la copie de travail et le dossier personnel de la session |
| connexion TCP sortante | ports 8888 (proxy HTTP) et 4000 (proxy LLM) |
| tout le reste | refusé : `~onyxia`, `/var/run/secrets`, `/tmp`, les autres sessions… |

Landlock positionne `no_new_privs` : les binaires setuid (sudo) ne donnent plus de
droits. `TMPDIR` pointe vers `~/tmp` de la session puisque `/tmp` est interdit.

landrun 0.1.17 vise l'ABI Landlock 9 ; il est lancé en `--best-effort`, et
`agent-session` vérifie d'abord que le noyau fournit **au moins l'ABI 4** (réseau),
sinon il refuse de démarrer. L'ABI 6 du cluster couvre fichiers, ports TCP et
isolation des signaux / sockets abstraites.

### Proxy HTTP(S) : tinyproxy

- Lancé par onyxia à la demande, sur `127.0.0.1:8888`, configuration et journal dans
  `/tmp/onyxia-agents` (700).
- `FilterDefaultDeny Yes` + `FilterType fnmatch` : seuls les domaines de
  `~/work/agents/allow.txt` passent (par défaut : pypi.org, files.pythonhosted.org,
  registry.npmjs.org, github.com, codeload.github.com, objects.githubusercontent.com,
  raw.githubusercontent.com) ; `CONNECT` limité aux ports 443 et 80.
- `agent-session allow/deny` modifie la liste puis recharge tinyproxy (`SIGUSR1`).
- `LogLevel Info` : chaque `CONNECT hôte:port`, chaque requête HTTP en clair et
  chaque refus sont journalisés ; `agent-session log` les met en forme.
- Côté agent : `HTTP(S)_PROXY` / `http(s)_proxy` pointent vers le proxy. Un outil qui
  les ignore n'a simplement **pas de réseau** (Landlock refuse la connexion directe).

### Proxy LLM : nginx

- `agent-session-config.py` lit la configuration opencode de l'utilisateur
  (`~/.config/opencode/opencode.json[c]`, générée par le chart ou écrite à la main)
  et `OPENAI_BASE_URL` / `OPENAI_API_KEY`.
- Chaque fournisseur devient une route `http://127.0.0.1:4000/p<n>/` (et `/env/`
  pour les variables) qui ajoute l'en-tête `Authorization: Bearer <vraie clé>` et
  vérifie le certificat du serveur (`proxy_ssl_verify`, profondeur 4).
- L'agent reçoit une **copie nettoyée** de la configuration : `apiKey` remplacée par
  `sandbox`, `baseURL` vers le proxy ; les fichiers annexes (AGENTS.md, commandes,
  skills) sont copiés, pas les sauvegardes.
- Chaque appel est journalisé (méthode, chemin, statut, taille, durée).

### Durcissement associé : ttyd

Le terminal web lui-même (ttyd) écoutait sur `127.0.0.1:7682` **sans
authentification propre** (nginx fait l'authentification devant). Tout processus
partageant le réseau du pod aurait pu y ouvrir un shell complet. ttyd écoute
désormais sur une **socket unix** dans `/tmp/onyxia-terminal` (700) ; nginx y relaie
(`proxy_pass http://unix:…`). Même sans Landlock, l'utilisateur `agent` ne peut pas
l'atteindre.

## Récupérer le travail de l'agent

```
 dépôt distant  ◀── push / PR ──  votre dépôt (identifiants)  ◀── git bundle ──  copie de l'agent (sans remote)
```

1. **Démarrage** : `agent-session` copie la branche courante dans
   `~/work/agents/<nom>` via un `git bundle`, puis retire le remote. L'agent ne
   connaît donc pas l'adresse du dépôt et n'a de toute façon aucun identifiant.
2. **Travail** : l'agent commite sous l'auteur `agent <nom>`
   (`agent-<nom>@sandbox.invalid`).
3. **Récupération** : dans votre dépôt, `agent-session fetch <nom>` →
   branches `agent-<nom>/*`. Relire : `git log -p HEAD..agent-<nom>/main`.
4. **Intégration** : poussez une branche et ouvrez une PR / MR (`gh pr create`,
   `glab mr create`) pour que la CI et la revue s'appliquent ; ou fusionnez
   localement. Un *squash merge* ou un `Co-authored-by` garde la trace de l'auteur.
5. **Mise à jour de l'agent** : `agent-session push <nom>`.

Seuls des objets et des références git circulent : ni hooks, ni `.git/config`.

**Règles de sécurité à respecter :**

- **Ne lancez pas le code de l'agent dans votre session** : tests, `make`,
  `uv run`, scripts `npm install`, hooks `pre-commit` définis dans le dépôt,
  `.envrc`… s'exécuteraient avec vos identifiants. Lancez-les dans la session agent.
- **La CI est l'autre canal d'exfiltration** : une PR qui modifie
  `.github/workflows` ou `.gitlab-ci.yml` peut viser les secrets de CI. Protégez ces
  fichiers (CODEOWNERS, approbation obligatoire des workflows pour les contributeurs)
  et relisez ces diffs en premier.

## Vérifications

Faites le 20 octobre 2026 sur un pod SSP Cloud construit par la CI, depuis une session
agent (`agent-session -n … --here -- bash -s < checks.sh`) :

| Contrôle | Résultat |
|---|---|
| variables secrètes dans l'environnement | 0 ; `OPENAI_API_KEY=sandbox` |
| vraie clé dans la configuration opencode de l'agent | absente |
| `ls /home/onyxia`, `cat ~onyxia/.bashrc`, autre dépôt de `~/work` | refusé |
| jeton du compte de service | refusé |
| `/proc/<pid onyxia>/environ` | refusé |
| `ls /tmp` | refusé |
| `sudo` | refusé (`no new privileges`) |
| `git remote -v` | vide |
| pypi.org via le proxy, `uvx pycowsay` | OK |
| example.com (non autorisé) | 403 du proxy, refus dans `agent-session log` ; 200 après `allow` |
| connexion directe (`curl --noproxy '*'`) | refusée (Landlock) |
| ancien port de ttyd `127.0.0.1:7682` | injoignable |
| LLM via le proxy (`/env/models`), requête opencode réelle | 200, réponse correcte, appels journalisés |
| commit dans la copie de travail puis `agent-session fetch` | commit récupéré dans `agent-<nom>/main` |
| clic droit → Session agent isolée | onglet orange `agent:demo` avec opencode |

## Limites et compromis

| Limite | Détail | Atténuation |
|---|---|---|
| Filtrage TCP **par port**, pas par hôte | l'agent peut joindre n'importe quel hôte sur les ports 8888 et 4000 | ports peu courants ; un pod séparé + NetworkPolicy filtrerait par IP |
| **UDP non filtré** | résolutions DNS possibles, donc exfiltration lente par requêtes DNS, et tout protocole UDP | limite de Landlock (ABI ≤ 6) |
| Domaines seulement | les chemins et contenus des requêtes HTTPS ne sont pas visibles | mitmproxy (voir évolutions) |
| Domaines autorisés = canaux de sortie | un domaine permettant l'écriture anonyme (pastebin, issues publiques…) sert à exfiltrer | liste blanche courte, relire `agent-session log` |
| Le LLM est un canal de sortie | le code envoyé au modèle sort du pod | inhérent ; le proxy permettrait d'ajouter quotas et limites de débit |
| Noyau partagé | une faille noyau permettrait de sortir de l'uid et de Landlock | pod séparé, ou runtime type gVisor si la plateforme en propose |
| Dépend de Landlock | ABI ≥ 4 requise ; vérifiée au lancement | refus explicite si absente |
| Sockets unix nommées | Landlock (ABI 6) ne filtre pas `connect()` sur une socket nommée ; la protection repose sur les permissions (dossiers 700, autre uid) | landrun `--unix` avec l'ABI 9 |
| Outils qui ignorent `HTTP(S)_PROXY` | pas de réseau du tout (connexion directe refusée) | variables propres à l'outil (`NODE_USE_ENV_PROXY=1`, `pip --proxy`…) |
| `models.opencode.ai` | opencode y cherche son catalogue de modèles ; refusé par défaut, sans gêne constatée | `agent-session allow models.opencode.ai` si besoin |
| Serveurs locaux | un serveur lancé par l'agent ne peut être joint que sur les ports autorisés (connexion TCP limitée à 8888 et 4000) | ajouter des ports `--connect-tcp` / `--bind-tcp` dans `agent-session.sh` si un projet en a besoin |
| Une seule identité pour toutes les sessions | toutes les sessions tournent sous l'uid `agent` ; Landlock les cloisonne entre elles par chemin | — |
| Code de l'agent exécuté chez vous | annule l'isolation | règle de travail ci-dessus |

## Évolutions possibles

- **URL complètes et contenus** : remplacer tinyproxy par mitmproxy (interface web
  derrière la connexion du terminal, injection de la clé LLM dans le même proxy) ;
  impose une autorité de certification acceptée par les outils de l'agent.
- **Pod agent séparé** pour une isolation maximale : jamais de secret monté,
  `automountServiceAccountToken: false`, NetworkPolicy de sortie (à valider sur le
  CNI de SSP Cloud), échanges git par `kubectl exec` (`ext::` ou `git bundle`).
- **Quotas LLM** dans le proxy nginx (`limit_req`, plafond par session).
- **Landlock plus récent** (sockets unix nommées, ABI 9) quand les nœuds l'offriront.
- **bubblewrap** si la plateforme autorise un profil AppArmor permettant les
  montages ; un prototype (réseau on/off/proxy) a été écrit puis mis de côté.
