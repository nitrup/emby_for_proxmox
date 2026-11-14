# emby_for_proxmox

Script Bash de mise à jour d'**Emby Server** vers la dernière release GitHub
([MediaBrowser/Emby.Releases](https://github.com/MediaBrowser/Emby.Releases)),
pensé pour un container LXC Debian/Ubuntu sous Proxmox.

## Fonctionnalités

- Détection automatique de l'architecture (`amd64`, `arm64`, `armhf`)
- Comparaison de versions fiable via `dpkg --compare-versions`
- Installation par `apt-get install ./emby.deb` : les dépendances sont résolues
- Interface `whiptail` (confirmation, jauge d'installation, résumé) avec repli
  automatique en mode texte coloré hors terminal interactif
- Spinner pendant l'interrogation de l'API GitHub, barre de progression `wget`
- Téléchargement dans un dossier temporaire nettoyé automatiquement
- Redémarrage et vérification du service `emby-server` après installation
- Journal dans `/var/log/emby-update.log`

## Lancement direct (sans installer)

Dans le container (en root) :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/nitrup/emby_for_proxmox/main/install_emby_lastest.sh)"
```

Pour passer des options, ajouter un nom de programme puis les options :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/nitrup/emby_for_proxmox/main/install_emby_lastest.sh)" emby-update -y --stable
```

> Ne pas utiliser `curl … | bash` : l'entrée standard ne serait plus le terminal
> et l'interface `whiptail` / la confirmation ne pourraient pas s'afficher.

## Installation locale

Dans le container (en root) :

```bash
wget -O /usr/local/bin/emby-update \
  https://raw.githubusercontent.com/nitrup/emby_for_proxmox/main/install_emby_lastest.sh
chmod +x /usr/local/bin/emby-update
```

Dépendances : `curl`, `wget`, `dpkg`, `apt-get` (présents de base).
Optionnel : `jq` (nécessaire pour `--stable`) et `whiptail` (interface graphique, présent dans les templates Debian/Ubuntu de Proxmox).

```bash
apt-get install -y jq whiptail
```

## Utilisation

```bash
emby-update              # interactif, bêtas incluses
emby-update --stable     # ignore les pré-releases (requiert jq)
emby-update -y           # sans confirmation, mode texte (cron, hook Proxmox)
emby-update --no-ui      # force le mode texte même en interactif
emby-update -h           # aide
```

| Option      | Effet                                              |
|-------------|----------------------------------------------------|
| `-y`, `--yes` | Ne pose aucune question, pas de `whiptail`       |
| `--stable`  | Ignore les versions bêta (`prerelease: true`)      |
| `--no-ui`   | Désactive `whiptail`, garde la sortie colorée      |
| `-h`, `--help` | Affiche l'aide                                  |

### Mise à jour automatique

Exemple de cron hebdomadaire (dimanche 4h) :

```cron
0 4 * * 0 /usr/local/bin/emby-update -y --stable >> /var/log/emby-update.log 2>&1
```

## Codes de retour

| Code | Signification                                        |
|------|------------------------------------------------------|
| `0`  | À jour, mise à jour réussie ou annulée par l'utilisateur |
| `1`  | Erreur (réseau, téléchargement, installation, droits) |
| `2`  | Option inconnue                                      |
