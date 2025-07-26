<img src="https://cdn.youkyi.fr/u/logoyoukyi.png" class="logo" width="120"/>



# 📦 VPS PBS Backup Scripts

Scripts de sauvegarde et benchmark automatisés pour machines Linux vers Proxmox Backup Server avec chiffrement et notifications Discord.

## 🎯 Description

Cette collection de scripts Bash permet d'effectuer des sauvegardes complètes et chiffrées de machines Linux vers un serveur Proxmox Backup Server (PBS). Les sauvegardes sont créées avec le type "vm" et un ID numérique pour apparaître directement dans l'interface Proxmox VE, permettant l'utilisation du File Restore graphique.

## ✨ Fonctionnalités principales

### 🔐 Script de sauvegarde principal (`vps-backup.sh`)

- **Sauvegarde chiffrée complète** du système
- **Compatible PVE** : apparaît dans l'interface avec File Restore disponible
- **Type VM** avec ID numérique personnalisable (≥9000)
- **Authentification sécurisée** via token API PBS
- **Notifications Discord** détaillées avec erreurs spécifiques
- **Logging avancé** sans doublons, avec horodatage
- **Options flexibles** en ligne de commande
- **Exclusions intelligentes** des répertoires système
- **Progression en temps réel** de la sauvegarde
- **Support clés sans mot de passe** (compatible clés PVE)


### 📊 Script de benchmark (`pbs_benchmark.sh`)

- **Tests de performance** sur différentes tailles de données
- **Mesure de déduplication** et compression
- **Tests de latence réseau**
- **Génération de rapports** détaillés
- **Notifications Discord** des résultats


## 📋 Prérequis

### Logiciels requis

- `proxmox-backup-client` 3.0+ (paquet Proxmox)
- `curl` (pour les webhooks Discord)
- `bash` 4.0+
- `bc` (pour les calculs de performance - optionnel)


### Installation des dépendances

**Ubuntu/Debian :**

```bash
# Ajouter le repository Proxmox
wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
echo "deb http://download.proxmox.com/debian/pbs-client bookworm main" > /etc/apt/sources.list.d/pbs-client.list

# Installer les paquets
apt update
apt install proxmox-backup-client curl bc
```


## 🚀 Installation

1. **Cloner le repository :**
```bash
git clone https://github.com/youkyi/vps-pbs-backup.git
cd vps-pbs-backup
```

2. **Rendre les scripts exécutables :**
```bash
chmod +x vps-backup.sh
chmod +x pbs_benchmark.sh
```

3. **Configurer les scripts :**
```bash
nano vps-backup.sh  # Configuration principale
```


## ⚙️ Configuration

### Configuration du script principal

Modifiez les variables dans `vps-backup.sh` :

```bash
# Serveur PBS et authentification
PBS_SERVER="votre_utilisateur@pbs!TOKEN@votre.serveur.pbs"
PBS_PASSWORD="votre_token_secret_api"
DEFAULT_DATASTORE="votre_datastore"
NAMESPACE="VPS"  # Ou votre namespace
BACKUP_ID="9000"  # ID ≥ 9000 pour éviter les conflits

# Chiffrement (clé PVE existante sans mot de passe)
KEYFILE="/etc/pbs//pbs-encryption.key"
USE_ENCRYPTION_PASSWORD=false

# Notifications Discord
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/VOTRE_WEBHOOK"
VPS_NAME="Nom-de-votre-VPS"
```


### Configuration PBS côté serveur

1. **Créer un token API :**
    - Interface PBS → Configuration → Access Control → API Tokens
    - Créer un token pour votre utilisateur
2. **Permissions requises :**
    - `Datastore.Backup` sur votre datastore
    - `Datastore.Allocate` sur votre datastore
    - Propagation activée pour les namespaces

### Ajouter PBS comme storage dans PVE

Pour voir vos sauvegardes dans l'interface PVE

1. **Datacenter** → **Storage** → **Add** → **Proxmox Backup Server**
2. **Configuration :**
    - **Server** : `votre.serveur.pbs`
    - **Username** : `votre_utilisateur@pbs!TOKEN`
    - **Password** : `votre_token_secret`
    - **Datastore** : `votre_datastore`
    - **Namespace** : `VPS`
    - **Encryption Key** : `/etc/pbs//pbs-encryption.key`

## 📖 Utilisation

### Script de sauvegarde principal

```bash
# Utilisation basique (ID 9000, type vm)
./vps-backup.sh

# Avec ID personnalisé
./vps-backup.sh -b 9001

# Pour un container
./vps-backup.sh -b 9002 -t ct

# Avec namespace et datastore différents
./vps-backup.sh -n "PRODUCTION" -d "backup-storage" -b 9003

# Affichage de l'aide
./vps-backup.sh --help
```


### Options disponibles

| Option | Description | Défaut |
| :-- | :-- | :-- |
| `-d, --datastore` | Datastore PBS | `datastore` |
| `-n, --namespace` | Namespace PBS | `VPS` |
| `-b, --backup-id` | ID numérique (≥9000) | `9000` |
| `-t, --backup-type` | Type : `vm` ou `ct` | `vm` |
| `-p, --password` | Mot de passe clé chiffrement | (auto-détecté) |
| `-h, --help` | Afficher l'aide | - |

### Script de benchmark

```bash
# Benchmark complet
./pbs_benchmark.sh

# Tests rapides seulement
./pbs_benchmark.sh --quick

# Sans notifications Discord
./pbs_benchmark.sh --no-discord
```


## 🔧 Automatisation

### Cron job quotidien

```bash
# Éditer la crontab
crontab -e

# Sauvegarde quotidienne à 2h du matin
0 2 * * * /chemin/vers/vps-backup.sh
```


### Systemd Timer (recommandé)

```ini
# /etc/systemd/system/pbs-backup.service
[Unit]
Description=PBS Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/chemin/vers/vps-backup.sh
User=root

# /etc/systemd/system/pbs-backup.timer
[Unit]
Description=Run PBS Backup Daily
Requires=pbs-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
# Activer et démarrer
systemctl enable --now pbs-backup.timer
systemctl status pbs-backup.timer
```


## 📁 Structure du repository

```
vps-pbs-backup/
├── vps-backup.sh      # Script principal de sauvegarde
├── pbs_benchmark.sh       # Script de benchmark
├── README.md              # Ce fichier
├── LICENSE                # Licence MIT
└── examples/
    ├── crontab.example    # Exemple de crontab
    └── systemd/           # Exemples systemd
        ├── pbs-backup.service
        └── pbs-backup.timer
```


## 📊 Fonctionnalités avancées

### Exclusions automatiques

Le script exclut automatiquement :

- `/proc`, `/sys`, `/dev` - Systèmes virtuels
- `/tmp`, `/var/tmp` - Fichiers temporaires
- `/var/log`, `/var/cache` - Logs et caches
- `/var/lib/docker/overlay2` - Couches Docker
- `*.sock`, `*.pid` - Fichiers de processus


### Notifications Discord enrichies

- 🎨 **Embeds colorés** (vert=succès, rouge=échec)
- 📋 **Erreurs spécifiques** (ENOSPC, authentification, etc.)
- ⏰ **Horodatage automatique**
- 📊 **Informations détaillées** (taille, durée, performances)


### Gestion des clés de chiffrement

- ✅ **Support clés PVE** existantes
- ✅ **Clés avec ou sans mot de passe**
- ✅ **Génération automatique** si absente
- ✅ **Validation de l'intégrité**


## 🐛 Dépannage

### Erreurs courantes

**1. Sauvegarde n'apparaît pas dans PVE :**

- Vérifiez que le backup-type est `vm` ou `ct`
- Confirmez que le storage PBS est ajouté dans PVE
- Vérifiez les permissions du token API

**2. Erreur ENOSPC :**

```
Error: mkstemp failed: ENOSPC: No space left on device
```

**Solution :** Libérez de l'espace sur le serveur PBS

**3. Problème d'authentification :**

```
API token secret must be provided!
```

**Solution :** Vérifiez le token API et le secret dans `PBS_PASSWORD`

**4. Erreur de clé de chiffrement :**

- Vérifiez le chemin vers la clé (`KEYFILE`)
- Confirmez les permissions (600)
- Testez avec `proxmox-backup-client key show`


### Commandes de diagnostic

```bash
# Vérifier la version du client
proxmox-backup-client version

# Tester l'authentification
export PBS_PASSWORD="votre_secret"
proxmox-backup-client status --repository 'votre_repo'

# Vérifier la clé de chiffrement
proxmox-backup-client key show /chemin/vers/cle.key

# Lister les sauvegardes
proxmox-backup-client list --repository 'votre_repo' --ns "VPS"
```


## 📈 Performances typiques

D'après les benchmarks intégrés, performances attendues :


| Taille | Vitesse sauvegarde | Compression | Déduplication |
| :-- | :-- | :-- | :-- |
| 10MB | ~32 MB/s | 72% | Excellente |
| 100MB | ~105 MB/s | 74% | 46% réutilisé |
| 1GB | ~166 MB/s | 75% | 46% réutilisé |

- ✅ **Latence réseau** : < 1ms typique
- ✅ **Compression** : 70-75% moyenne
- ✅ **Déduplication** : Très efficace sur fichiers identiques


## 🔄 Mise à jour

```bash
# Mettre à jour les scripts
git pull origin main

# Ou télécharger la dernière version
wget https://raw.githubusercontent.com/youkyi/vps-pbs-backup/main/vps-backup.sh
```


## 📄 Licence

Ce projet est sous licence MIT. Voir le fichier `LICENSE` pour plus de détails.

## 🤝 Contribution

Les contributions sont les bienvenues !

1. Forkez le projet
2. Créez votre branche (`git checkout -b feature/amelioration`)
3. Committez vos changements (`git commit -am 'Ajout fonctionnalité'`)
4. Poussez vers la branche (`git push origin feature/amelioration`)
5. Ouvrez une Pull Request

## 👤 Auteur

**Youkyi** - Développement et maintenance

## 🙏 Remerciements

- Équipe Proxmox pour PBS et PVE
- Communauté Discord pour l'API webhook
- Contributeurs pour les améliorations


## ⚠️ Important

- **Testez** vos sauvegardes avec des restaurations régulières
- **Surveillez** l'espace disque du serveur PBS
- **Sauvegardez** votre clé de chiffrement séparément
- **Vérifiez** les permissions des tokens API régulièrement

**🆘 Support :** Ouvrez une [issue GitHub](https://github.com/youkyi/vps-pbs-backup/issues) pour signaler des problèmes ou demander des fonctionnalités.

⭐ **Si ce projet vous aide, n'hésitez pas à lui donner une étoile !** ⭐

<div style="text-align: center">⁂</div>

[^1]: image.jpg

[^2]: image.jpg

[^3]: image.jpg

[^4]: image.jpg


