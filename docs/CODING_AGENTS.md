# Coding Agents

Agents de coding compatibles avec la stack `ai-local-dev` (proxy OpenAI-compatible sur `http://127.0.0.1:8081/v1` pour le 27B et `http://127.0.0.1:11435/v1` pour le 35B). Ce document recense les agents testés, le retour d'expérience, et la configuration de l'agent retenu (Pi).

## Agents testés

| Agent | Éditeur / licence | Langue | Modèles locaux | Verdict (juin 2026) |
|---|---|---|---|---|
| **Pi** (`@earendil-works/pi-coding-agent`) | earendil-works / MIT | TypeScript | Oui (OpenAI-compatible) | ✅ **Retenu** — le mieux pour l'instant |
| **Goose** | Block → AAIF (Linux Foundation) / Apache-2.0 | Rust | Oui (Ollama, LM Studio, llama.cpp, endpoint custom) | Testé, correct mais pas retenu |
| **Qwen Code** (`@qwen-code/qwen-code`) | QwenLM (Alibaba) / Apache-2.0 | TypeScript | Oui (Ollama, vLLM, endpoint OpenAI-compatible) | Testé, correct mais pas retenu |
| **Hermes** (`NousResearch/hermes-agent`) | Nous Research / MIT | Python | Oui (OpenAI-compatible, Ollama, vLLM, llama.cpp) | 🔜 À tester — config préparée pour la stack (voir ci-dessous) |
| **Warp** (option modèle local) | Warp / propriétaire | Rust | Non réellement | ⚠️ Pas implémenté pour le local — voir ci-dessous |

## Retour d'expérience

### Pi (retenu)
Harness terminal minimal, model-agnostic. On déclare les providers OpenAI-compatibles dans `~/.pi/agent/models.json` (voir [Configuration Pi](#configuration-pi)). Léger, rapide à configurer, et le format `openai-completions` + `compat` gère bien les serveurs locaux type llama.cpp. C'est l'agent utilisé actuellement avec la stack `ai-local-dev`.

### Goose
Agent open-source robuste (Rust, ~50K★), désormais sous l'Agentic AI Foundation à la Linux Foundation. Supporte 30+ providers dont Ollama, LM Studio, Docker Model Runner, et tout endpoint OpenAI-compatible. Desktop app + CLI. Testé et fonctionnel avec la stack locale, mais interface plus lourde que Pi pour un usage purement terminal.

### Qwen Code
Agent terminal open-source d'Alibaba (~25K★), optimisé pour les modèles Qwen mais multi-protocole (OpenAI / Anthropic / Gemini + tout endpoint OpenAI-compatible local). Config via `~/.qwen/settings.json`. Bonne intégration Qwen (notamment `enable_thinking` natif), mais pour l'instant Pi suffit et reste plus léger.

### Hermes
Agent open-source de Nous Research (~200K★, Python, MIT). Particularité : boucle d'apprentissage intégrée (création de skills autonomes, mémoire persistante, modélisation utilisateur cross-session), multi-plateformes (CLI, Telegram, Discord, Slack, WhatsApp…), six backends terminal (local, Docker, SSH, Modal, Daytona, Singularity), et support first-class des endpoints OpenAI-compatibles locaux (llama.cpp, Ollama, vLLM) — y compris sans API key (PR #38572 merged juin 2026). Config dans `~/.hermes/config.yaml` (settings) + `~/.hermes/.env` (secrets). **Pas encore testé** avec la stack ai-local-dev — config préparée ci-dessous pour A/B-tester avec Pi.

Contrainte notoire : Hermes exige **64K tokens de contexte minimum** (rejet au startup sinon). Le 27B (ctx 64K) passe juste, le 35B (ctx 128K) est confortable.

### Warp (option modèle local)
Warp expose une option « custom inference endpoint » (Settings → inference endpoint), mais **à date de juin 2026, l'endpoint local n'est pas vraiment implémenté** :
- La validation côté client **rejette `localhost`, `127.0.0.1` et les IP privées** et **exige HTTPS** (`app/src/settings_view/custom_inference_modal.rs`).
- Les requêtes sont **routées via les serveurs Warp**, pas en direct client→endpoint, donc l'endpoint doit être publiquement reachable.
- Le workaround officiel est d'exposer le serveur local via **ngrok** (ou Cloudflare Tunnel / Tailscale Funnel) et de mettre l'URL `https://*.ngrok-free.app/v1` comme base URL.
- En pratique ça marche assez mal (latence, stabilité du tunnel, état de conversation qui peut rester bloqué `InProgress` — voir issue `warpdotdev/warp#11662`).

Références :
- Doc officielle : https://docs.warp.dev/agent-platform/inference/custom-inference-endpoint/
- Issues ouvertes (suivi du gap local) : `warpdotdev/warp#11589`, `#12142`, `#9303`, `#9368`

En attendant que Warp supporte nativement le local, on reste sur Pi pour l'agent de coding local.

## Configuration Pi

Pi charge les providers custom depuis `~/.pi/agent/models.json` (rechargé à chaque ouverture de `/model`, pas besoin de restart). Les settings globaux (modèle/provider/thinking par défaut) sont dans `~/.pi/agent/settings.json`.

### Providers déclarés pour la stack ai-local-dev

Deux providers pointant vers les proxies no-think de la stack (qui gèrent `enable_thinking` / `preserve_thinking` côté serveur via `chat_template_kwargs`) :

- `ai-local-35b` → `http://127.0.0.1:11435/v1` (35B-A3B, 128k ctx, thinking)
- `ai-local-27b` → `http://127.0.0.1:8081/v1` (27B dense, 64k ctx, thinking)

### Exemple `~/.pi/agent/models.json`

```json
{
  "providers": {
    "ai-local-35b": {
      "baseUrl": "http://127.0.0.1:11435/v1",
      "api": "openai-completions",
      "apiKey": "sk-local-no-auth",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false,
        "maxTokensField": "max_tokens"
      },
      "models": [
        {
          "id": "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf",
          "name": "Qwen3.6-35B-A3B (local, thinking)",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": 131072,
          "maxTokens": 32000,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "thinkingLevelMap": { "off": null }
        }
      ]
    },
    "ai-local-27b": {
      "baseUrl": "http://127.0.0.1:8081/v1",
      "api": "openai-completions",
      "apiKey": "sk-local-no-auth",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false,
        "maxTokensField": "max_tokens"
      },
      "models": [
        {
          "id": "Qwen3.6-27B-UD-Q4_K_XL.gguf",
          "name": "Qwen3.6-27B (local, thinking)",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": 65536,
          "maxTokens": 32000,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "thinkingLevelMap": { "off": null }
        }
      ]
    }
  }
}
```

### Exemple `~/.pi/agent/settings.json`

```json
{
  "theme": "dark",
  "defaultProvider": "ai-local-35b",
  "defaultModel": "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf",
  "defaultThinkingLevel": "medium"
}
```

### Notes importantes

- **Un seul modèle à la fois sur le M3 Max 48GB** : `AI_LOCAL_SINGLE_MODEL_MODE=1` dans `config/.qwen-local.conf` arrête l'autre famille au démarrage. Donc si `ai-local 27b-thinking` tourne, le 35B est down (et inversement). Bascule avec `ai-local 27b-thinking` / `ai-local 35b-thinking`.
- **Thinking toujours on** : les deux modèles sont lancés en mode `-thinking`, et `thinkingLevelMap: { "off": null }` masque le réglage off dans Pi pour rester cohérent.
- **Switch de modèle dans Pi** : `Ctrl+L` (sélecteur) ou `pi --provider ai-local-27b --model Qwen3.6-27B-UD-Q4_K_XL.gguf` en CLI.
- **`compat`** : `supportsDeveloperRole: false` (le serveur llama.cpp ne comprend pas le rôle `developer`), `supportsReasoningEffort: false`, `maxTokensField: "max_tokens"` (au lieu de `max_completion_tokens`).
- **`apiKey`** : la stack locale n'authentifie pas, n'importe quelle valeur fonctionne (`sk-local-no-auth` par convention).

### Pour ajouter un nouveau modèle plus tard

1. Démarrer le stack correspondant côté `ai-local-dev` (ex. un nouveau GGUF).
2. Ajouter une entrée dans `models` du provider pertinent (ou un nouveau provider si l'endpoint/port diffère) dans `~/.pi/agent/models.json`.
3. Changer le défaut dans `~/.pi/agent/settings.json` si besoin, ou sélectionner via `Ctrl+L` dans Pi.
4. `/reload` dans Pi si la session est déjà ouverte (les models.json sont aussi rechargés automatiquement à l'ouverture de `/model`).

### Références Pi

- Doc custom providers : https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/custom-provider.md
- Doc models : https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md
- Doc settings : https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/settings.md

## Configuration Hermes

Hermes se configure dans `~/.hermes/config.yaml`. Pour les endpoints locaux, le schéma officiel est **`custom_providers:` (une liste)** — chaque entrée a `name`, `base_url`, `api_mode`, et un sous-dict `models`. C'est ce que le model picker CLI/TUI lit pour afficher les groupes sélectionnables.

⚠️ Ne pas confondre avec `providers.<slug>:` (un dict) — c'est une alternative **non documentée** (issue `NousResearch/hermes-agent#44513`) que le picker ne lit pas de façon fiable. Utiliser `custom_providers:`.

On déclare deux named providers puisque le 27B et le 35B exposent des ports différents (8081 et 11435), comme pour Pi.

### Installation

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.zshrc
hermes --version    # vérifie l'install
```

### `~/.hermes/config.yaml` (extrait — à fusionner avec le fichier existant)

Remplacer le block `model:` existant et ajouter la liste `custom_providers:`. Garder le reste du fichier (agent, terminal, toolsets, etc.) intact.

```yaml
model:
  default: Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
  provider: custom:ai-local-35b        # syntaxe custom:<name> pour pointer vers un named provider
  base_url: http://127.0.0.1:11435/v1
  api_key: sk-local-no-auth             # n'importe quelle valeur, la stack locale n'authentifie pas
  context_length: 131072               # requis : Hermes impose >= 64K

custom_providers:
  - name: ai-local-35b
    base_url: http://127.0.0.1:11435/v1
    # api_key omis → Hermes utilise "no-key-required" pour les serveurs locaux keyless
    api_mode: chat_completions          # default pour OpenAI-compatible ; peut être omis
    models:
      Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf:
        context_length: 131072
  - name: ai-local-27b
    base_url: http://127.0.0.1:8081/v1
    api_mode: chat_completions
    models:
      Qwen3.6-27B-UD-Q4_K_XL.gguf:
        context_length: 65536           # pile le minimum 64K imposé par Hermes
```

### Appliquer la config (depuis le terminal, hors session Hermes)

```bash
# 1. Démarrer le stack local voulu (PENSER au suffixe -thinking !)
ai-local 35b-thinking      # ou 27b-thinking

# 2. Vérifier que le proxy répond avant de configurer Hermes
curl -s http://127.0.0.1:11435/health    # doit renvoyer {"status":"ok"}

# 3. Éditer ~/.hermes/config.yaml (remplacer model: + ajouter custom_providers:)
hermes config edit
#   ou : $EDITOR ~/.hermes/config.yaml

# 4. Valider que Hermes voit les providers
hermes doctor               # ne doit pas afficher "Unknown provider"

# 5. Lancer une session — le picker /model doit montrer les deux groupes
hermes --tui
#   puis /model  → doit lister ai-local-35b et ai-local-27b
```

### Config alternative via wizard interactif (un seul endpoint)

```bash
hermes model          # → Custom endpoint → http://127.0.0.1:11435/v1 → model id → ctx 131072
```

Le wizard ne configure qu'un seul `model:` block (pas de `custom_providers:`). Pour avoir les **deux** groupes dans le picker, éditer `config.yaml` à la main comme ci-dessus.

### Switch entre 27B et 35B

```bash
# En session (hot-swap) — syntaxe triple pour les named custom providers :
/model custom:ai-local-27b:Qwen3.6-27B-UD-Q4_K_XL.gguf
/model custom:ai-local-35b:Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf

# Auto-detect du modèle si un seul est chargé sur l'endpoint :
/model custom:ai-local-27b

# Ou changer le défaut depuis le terminal (nouvelles sessions) :
hermes model
```

### Notes importantes

- **⚠️ Thinking ON = obligation de démarrer avec `-thinking`** : les ports 8081 (27B) et 11435 (35B) sont les **mêmes** quelle que soit le mode. Ce qui bascule le thinking, c'est la commande de démarrage côté `ai-local-dev`, pas la config Hermes :
  - `ai-local 35b-thinking` (ou `27b-thinking`) → exporte `AI_LOCAL_FORCE_THINK=1` avant le chargement de config → le proxy n'injecte pas `enable_thinking: false`, et llama-server tourne avec `--chat-template-kwargs {"preserve_thinking": true}` → **thinking ON**, blocs `<think>` visibles et préservés dans l'historique multi-tours.
  - `ai-local 35b` (sans suffixe) → `AI_LOCAL_FORCE_THINK=0` (défaut dans `config/.qwen-local.conf`) → le proxy force `enable_thinking: false` **et strip les blocs `<think>` de l'output** → **no-think**, même si la config Hermes est identique.
  - Donc : toujours démarrer avec `ai-local 35b-thinking` / `27b-thinking`. Sans le suffixe, tu récupères le no-think que tu trouvais mauvais, indépendamment de ce qui est écrit dans `~/.hermes/config.yaml`.
- **Un seul modèle à la fois sur le M3 Max 48GB** : `AI_LOCAL_SINGLE_MODEL_MODE=1` dans `config/.qwen-local.conf` arrête l'autre famille au démarrage. Démarrer le stack voulu **avant** de switcher dans Hermes, sinon le `/model` pointera vers un endpoint down.
- **Thinking géré côté serveur, pas côté Hermes** : le proxy ai-local-dev gère `enable_thinking` / `preserve_thinking` via `chat_template_kwargs`. Ne pas activer `agent.reasoning_effort` dans Hermes (réservé OpenRouter/Nous Portal, ignoré sur les custom endpoints).
- **Timeouts auto** : Hermes détecte les endpoints locaux et relâche le streaming timeout (120s → 1800s) + désactive le stale-stream detector. Si souci sur long context, `HERMES_STREAM_READ_TIMEOUT=1800` dans `~/.hermes/.env`.
- **`model.default` raw id** : doit matcher exactement l'id retourné par `GET /v1/models` (le nom du GGUF pour llama-server). Mettre `ai-local-35b/Qwen3.6-...` casserait le marqueur "currently selected" du picker.
- **`discover_models: false`** : recommandé car les proxies ai-local-dev ne servent pas toujours `/v1/models` de façon fiable ; on déclare les modèles explicitement.
- **`apiKey`** : la stack locale n'authentifie pas, `sk-local-no-auth` par convention (comme Pi).
- **Auxiliary models** : par défaut (`auxiliary.*.provider: auto`) Hermes route vision/compression/web-extract vers le main model. Aucune clé cloud → ça marche, mais ces tâches vont tirer sur le modèle local. Si lenteur sur le compression, override avec un petit modèle local dédié.

### Références Hermes

- Doc custom endpoints : https://hermes-agent.nousresearch.com/docs/integrations/providers
- Doc configuration : https://hermes-agent.nousresearch.com/docs/user-guide/configuration
- Pattern providers.<slug> pour le picker (issue) : `NousResearch/hermes-agent#44513`
- Fix endpoint local sans API key (PR) : `NousResearch/hermes-agent#38572`

## Hermes distant via reverse SSH tunnel

Cas d'usage : Hermes tourne sur un serveur distant (ex. OVH) qui n'est pas assez puissant pour charger un modèle, mais on veut quand même utiliser les modèles Qwen du MacBook. Solution : un **reverse SSH tunnel** (`ssh -R`) qui forward les ports 8081/11435 du MacBook vers le loopback du serveur distant. Du point de vue du Hermes distant, l'endpoint est « local » — aucune config spécifique, juste du routage TCP au niveau du tunnel.

⚠️ Ne pas confondre avec la doc « OAuth over SSH » de Hermes, qui documente `ssh -L` (local forward, pour les callbacks OAuth du remote vers le navigateur local) — c'est l'**inverse** de ce dont on a besoin ici.

### Principe

```
MacBook (modèles)                Serveur OVH (Hermes, pas de GPU)
  llama-server :8081   ──SSH──►  127.0.0.1:8081  ──►  Hermes custom:ai-local-27b
  llama-server :11435  ──SSH──►  127.0.0.1:11435 ──►  Hermes custom:ai-local-35b
```

Le Hermes sur le OVH ne fait que des appels HTTP vers `127.0.0.1` ; le tunnel SSH les renvoie vers le MacBook. Pas de modèle à télécharger sur le serveur, pas de GPU requis côté OVH — juste la CLI Hermes (Python).

### Setup en une commande : `ai-local-tunnel setup`

Le script `bin/ai-local-tunnel` automatise **toute** la procédure côté distant en une seule commande. Il détecte d'abord **le modèle actuellement lancé sur le Mac** (27B ou 35B) en lisant l'environnement du proxy (`AI_LOCAL_FORCE_THINK`), puis : ouverture du tunnel (réutilisé s'il tourne déjà), vérification depuis le distant, détection d'Hermes, backup + merge de `~/.hermes/config.yaml` (le `model.default` pointe vers le modèle détecté, `custom_providers:` déclare les deux — **idempotent**), lint YAML + `hermes doctor`, et test chat end-to-end (le token attendu reflète le modèle : `TUNNEL_OK_27B` ou `TUNNEL_OK_35B`).

Le script **n'exige pas un modèle précis** : il accepte n'importe quel modèle local qui tourne, **à condition qu'il soit en thinking** (`AI_LOCAL_FORCE_THINK=1`). Si un modèle tourne en no-think, il aborte avec un message clair (« Le 35B tourne mais en mode NO-THINK… relancer en thinking ») — car sans le suffixe `-thinking`, le proxy force no-think + strip les blocs `<think>`, ce qui n'a pas d'intérêt ici.

**Prérequis (à faire une seule fois, pas à chaque setup)** :
1. Un modèle tourne sur le Mac **en mode thinking** : `ai-local 27b-thinking` ou `ai-local 35b-thinking` (au choix — le script s'adapte à celui qui tourne).
2. L'alias SSH `ovh-eriador` (ou `user@host`) est joignable : `ssh ovh-eriador echo ok`.
3. Hermes est installé sur le distant : `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash` puis **se reconnecter** en SSH (le `.bashrc` recharge le PATH — `hermes` n'est pas dans le PATH d'une session SSH non-interactive, le script gère ça via un `export PATH` explicite).
4. Côté distant, `AllowTcpForwarding yes` dans `/etc/ssh/sshd_config` (c'est le défaut Ubuntu/OVH ; si ça a été désactivé, le repasser à `yes` et `sudo systemctl reload sshd`).

**Lancer le setup** :

```bash
ai-local-tunnel setup ovh-eriador
#   → détecte le modèle actif (ex: 35b → Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf)
#   → tunnel ouvert (background, PID file + log file)
#   → config Hermes mergée sur le distant (model.default = modèle détecté)
#   → YAML OK, pas d'Unknown provider, chat end-to-end OK (TUNNEL_OK_35B)
```

Options : `--ssh-port N` (port SSH custom), `-i ~/.ssh/key` (clé custom), `--no-chat` (skipper le test chat si le modèle est lent à froid).

**En sortie du setup, tout est prêt** — il ne reste plus qu'à lancer Hermes en interactif sur le distant :

```bash
ssh ovh-eriador      # puis : hermes --tui   (/model → ai-local-27b & ai-local-35b)
```

Le setup est **idempotent** : le relancer ne casse rien (le merge remplace le block `custom_providers:` existant au lieu de le dupliquer, le tunnel est réutilisé s'il tourne). À utiliser après chaque changement de model id/ports côté Mac.

### Gestion du tunnel (start / stop / status)

`setup` ouvre le tunnel en background. Pour le gérer sans re-merger la config :

```bash
ai-local-tunnel ovh-eriador              # ouvrir le tunnel seul + afficher la config à coller
ai-local-tunnel ovh-eriador --fg         # foreground (Ctrl+C pour fermer)
ai-local-tunnel stop ovh-eriador         # fermer le tunnel
ai-local-tunnel status                   # tunnels actifs + état des modèles locaux (27B/35B up?)
```

Le script forward toujours les **deux** ports (8081 et 11435). Avec `AI_LOCAL_SINGLE_MODEL_MODE=1`, un seul modèle tourne à la fois sur le Mac, donc un seul répond sur le distant — celui lancé avec `ai-local 27b-thinking` / `35b-thinking`.

PID files : `~/.local/state/ai-local-dev/run/tunnel-<host>.pid` — logs : `~/.local/state/ai-local-dev/log/tunnel-<host>.log`.

### Détails : ce que le setup fait sur le distant (pour référence / debug)

Si `setup` échoue à une étape, voici exactement ce qu'il fait, pour debug à la main :

1. **Tunnel** : `ssh -N -p 22 -R 8081:127.0.0.1:8081 -R 11435:127.0.0.1:11435 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes ovh-eriador` (background).
2. **Vérif tunnel** : `ssh ovh-eriador 'curl -s --max-time 5 http://127.0.0.1:8081/health'` → doit renvoyer `{"status":"ok"}`.
3. **Hermes dans le PATH** : en SSH non-interactif `.bashrc` n'est pas sourcé, donc `command -v hermes` échoue. Le script force `export PATH="$HOME/.hermes/hermes-agent/venv/bin:$HOME/.local/bin:$PATH"`. À la main : `ssh ovh-eriador 'export PATH=$HOME/.hermes/hermes-agent/venv/bin:$HOME/.local/bin:$PATH; hermes --version'`.
4. **Backup + merge config** : `cp ~/.hermes/config.yaml ~/.hermes/config.yaml.bak-$(date +%Y%m%d-%H%M%S)` puis un script Python remplace le block `model:` et ajoute/rafraîchit `custom_providers:` (préserve tout le reste du fichier : toolsets, agent, memory…).
5. **Validation** : `python3 -c 'import yaml,os; yaml.safe_load(open(os.path.expanduser("~/.hermes/config.yaml")))'` + `hermes doctor | grep -i 'Unknown provider'` (ne doit rien sortir).
6. **Test chat** : `hermes chat -Q -q 'Reply with exactly the token TUNNEL_OK_27B and nothing else.'` (one-shot, `-Q` supprime le banner, `-q` passe la query). Doit renvoyer `TUNNEL_OK_27B`.

### Config Hermes distante (résultat du merge)

Le setup produit dans `~/.hermes/config.yaml` sur le distant (identique à la config Mac, puisque via le tunnel `127.0.0.1:8081`/`11435` résolvent vers le Mac) :

```yaml
model:
  default: Qwen3.6-27B-UD-Q4_K_XL.gguf
  provider: custom:ai-local-27b
  base_url: http://127.0.0.1:8081/v1
  api_key: sk-local-no-auth
  context_length: 65536

custom_providers:
  - name: ai-local-35b
    base_url: http://127.0.0.1:11435/v1
    api_mode: chat_completions
    models:
      Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf:
        context_length: 131072
  - name: ai-local-27b
    base_url: http://127.0.0.1:8081/v1
    api_mode: chat_completions
    models:
      Qwen3.6-27B-UD-Q4_K_XL.gguf:
        context_length: 65536
```

### Points d'attention

- **Prérequis absolu** : un modèle **thinking** doit tourner sur le Mac avant le setup (`setup` aborte si le 27B est down). Sans le suffixe `-thinking`, le proxy force no-think + strip les blocs `<think>` — le thinking se gère côté Mac, pas dans la config Hermes distante.
- **Single-model mode sur le Mac** : `AI_LOCAL_SINGLE_MODEL_MODE=1` (voir `config/.qwen-local.conf`) signifie qu'un seul des deux modèles (27B ou 35B) tourne à la fois sur le MacBook. Donc tous les Hermes distants qui pointent vers le Mac partagent le **même** modèle (celui lancé avec `ai-local 27b-thinking` ou `35b-thinking`). Impossible d'avoir un OVH sur le 27B et l'autre sur le 35B simultanément.
- **Le Mac doit rester allumé** + le tunnel ouvert pendant toute la session OVH. Fermer le laptop ou perdre le réseau → les Hermes distants perdent leur modèle. `ai-local-tunnel status` pour vérifier.
- **Latence** : le streaming de tokens fait un aller-retour SSH par chunk. Acceptable pour de l'agentic, mais ressenti vs un appel local direct. Sur une fibre correcte c'est <50ms, donc ok pour de l'agent (pas pour du chat temps réel fluide).
- **`sshd_config` côté OVH** : par défaut `AllowTcpForwarding yes` et `GatewayPorts no` — c'est exactement ce qu'il faut (le `-R` bind sur le loopback du OVH, pas d'exposition publique). Si `AllowTcpForwarding no`, le passer à `yes` dans `/etc/ssh/sshd_config` et `sudo systemctl reload sshd`.
- **Sécurité** : le tunnel ne met le modèle à disposition que sur `127.0.0.1` du OVH — pas exposé à internet. Tant qu'on ne met pas `GatewayPorts yes` (à éviter), c'est limité aux utilisateurs connectés en SSH sur le OVH.
- **Switch 27B ↔ 35B** : démarrer l'autre stack sur le Mac (`ai-local 35b-thinking`), puis en session Hermes distante : `/model custom:ai-local-35b:Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf` (le tunnel forward déjà le port 11435).

### Tunnel persistant (optionnel)

Pour ne pas gérer un terminal ouvert à la main :

```bash
# autossh relance le tunnel automatiquement s'il tombe
brew install autossh
autossh -M 0 -N \
  -R 8081:127.0.0.1:8081 \
  -R 11435:127.0.0.1:11435 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  user@ovh-server-1
```

Pour un démarrage au boot : wrapper launchd (macOS) ou systemd (Linux) autour d'`autossh`.

### Alternative : Tailscale

Si le roaming du MacBook (changement de réseau) casse trop souvent le tunnel SSH, Tailscale met le Mac et les OVH sur le même mesh network. La config `base_url` sur le OVH pointe alors vers l'IP Tailscale du Mac (ex. `http://100.x.y.z:8081/v1`) au lieu de `127.0.0.1` — plus robuste au roaming, mais ça change la config et le llama-server doit binder sur l'interface Tailscale (pas seulement `127.0.0.1`).

### Références tunnel

- Doc Hermes « OAuth over SSH » (`ssh -L`, l'inverse) : https://hermes-agent.nousresearch.com/docs/guides/oauth-over-ssh
- man ssh (section `-R` reverse port forwarding)
- autossh : https://github.com/AutoSSH/autossh
