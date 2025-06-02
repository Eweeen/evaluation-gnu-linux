# Exercice 2 : Configuration d'un reverse proxy avec Caddy

## 1. Vue d'ensemble

Cette solution met en place un site web sécurisé avec authentification et un reverse proxy Caddy, incluant une protection fail2ban contre les tentatives d'intrusion.

### Architecture

```
Internet → Caddy (Reverse Proxy) → Application Web → Authentification
                ↓
            fail2ban → nftables (Bannissement IP)
```

## 2. Composants de la solution

### Application Web (Flask)

- **Framework** : Flask (Python)
- **Fonctionnalités** :
  - Page d'accueil publique
  - Endpoint `/login` avec authentification
  - Page `/private` accessible uniquement après connexion
  - Sessions sécurisées
  - Logs détaillés des tentatives de connexion

### Reverse Proxy (Caddy)

- **Serveur** : Caddy v2
- **Configuration** :
  - HTTPS automatique avec Let's Encrypt (ou certificats auto-signés)
  - Reverse proxy vers l'application Flask
  - Headers de sécurité
  - Logs d'accès détaillés

### Protection fail2ban

- **Service** : fail2ban
- **Fonctionnalités** :
  - Surveillance des logs d'authentification
  - Bannissement automatique des IP suspectes
  - Intégration avec nftables
  - Jail personnalisée pour l'application

## 3. Installation et configuration

### Prérequis système

```bash
# Vérification des prérequis
sudo systemctl status nftables
groups $USER | grep sudo
```

### Installation automatique

```bash
# Exécuter le script d'installation
chmod +x scripts/install.sh
sudo ./scripts/install.sh
```

### Installation manuelle

#### Étape 1 : Installation des dépendances

```bash
# Python et Flask
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv

# Caddy
sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update
sudo apt-get install -y caddy

# fail2ban
sudo apt-get install -y fail2ban
```

#### Étape 2 : Configuration de l'application web

```bash
# Création de l'environnement virtuel
python3 -m venv /opt/webapp-env
source /opt/webapp-env/bin/activate
pip install flask

# Déploiement de l'application
sudo cp webapp/app.py /opt/webapp/
sudo systemctl enable --now webapp
```

#### Étape 3 : Configuration de Caddy

```bash
# Configuration du reverse proxy
sudo cp config/Caddyfile /etc/caddy/
sudo systemctl reload caddy
```

#### Étape 4 : Configuration de fail2ban

```bash
# Installation de la jail personnalisée
sudo cp config/webapp.conf /etc/fail2ban/jail.d/
sudo cp config/webapp-filter.conf /etc/fail2ban/filter.d/
sudo systemctl restart fail2ban
```

## 4. Utilisation

### Accès à l'application

- **URL publique** : `http://localhost` ou `https://votre-domaine.com`
- **Page de connexion** : `/login`
- **Zone privée** : `/private`

### Comptes utilisateurs

| Utilisateur | Mot de passe | Rôle |
|-------------|--------------|------|
| admin | admin123 | Administrateur |
| user | password | Utilisateur standard |
| test | test123 | Utilisateur test |

> **Sécurité** : Ces credentials sont stockés en dur pour la démonstration. En production, utiliser une base de données sécurisée.

### Tests de sécurité

#### Test d'authentification

```bash
# Connexion valide
curl -X POST http://localhost/login \
  -d "username=admin&password=admin123" \
  -c cookies.txt

# Accès à la zone privée
curl -b cookies.txt http://localhost/private
```

#### Test de protection fail2ban

```bash
# Exécuter le script de test
./scripts/test_fail2ban.sh
```

Le script effectue :
1. 5 tentatives de connexion échouées rapides
2. Vérification du bannissement IP
3. Test d'accès bloqué
4. Débannissement automatique après expiration

## 5. Monitoring et logs

### Logs de l'application

```bash
# Logs Flask
tail -f /var/log/webapp/app.log

# Logs Caddy
sudo tail -f /var/log/caddy/access.log

# Logs fail2ban
sudo tail -f /var/log/fail2ban.log
```

### Commandes de surveillance

```bash
# Statut des services
sudo systemctl status webapp caddy fail2ban

# IP bannies actuellement
sudo fail2ban-client status webapp

# Règles nftables actives
sudo nft list ruleset | grep "webapp"
```

### Métriques de sécurité

```bash
# Nombre de tentatives bloquées
sudo grep "Failed login" /var/log/webapp/app.log | wc -l

# IP les plus agressives
sudo grep "Failed login" /var/log/webapp/app.log | \
  grep -oP 'from \K[\d.]+' | sort | uniq -c | sort -nr
```

## 6. Configuration avancée

### Personnalisation de fail2ban

Modifier `/etc/fail2ban/jail.d/webapp.conf` :

```ini
# Seuil de bannissement (défaut: 5 tentatives)
maxretry = 3

# Durée de bannissement (défaut: 10 minutes)
bantime = 1800

# Fenêtre de temps pour compter les tentatives (défaut: 10 minutes)
findtime = 600
```

### Configuration HTTPS avec certificat personnalisé

```caddyfile
# Dans /etc/caddy/Caddyfile
votre-domaine.com {
    tls /path/to/cert.pem /path/to/key.pem
    reverse_proxy localhost:5000
}
```

### Sécurisation supplémentaire

```bash
# Limitation du taux de requêtes avec Caddy
# Ajouter dans Caddyfile :
rate_limit {
    zone webapp 10r/s
    key {remote_host}
}
```

## 7. Dépannage

### Problèmes courants

#### Application inaccessible

```bash
# Vérifier le statut des services
sudo systemctl status webapp caddy

# Vérifier les ports
sudo netstat -tlnp | grep -E ':(80|443|5000)'

# Tester l'application directement
curl http://localhost:5000
```

#### fail2ban ne fonctionne pas

```bash
# Vérifier la configuration
sudo fail2ban-client -t

# Tester le filtre manuellement
sudo fail2ban-regex /var/log/webapp/app.log /etc/fail2ban/filter.d/webapp.conf

# Redémarrer fail2ban
sudo systemctl restart fail2ban
```

#### Certificats HTTPS

```bash
# Régénérer les certificats Caddy
sudo caddy reload --config /etc/caddy/Caddyfile

# Vérifier les certificats
sudo caddy list-certificates
```

## 8. Sécurité et bonnes pratiques

> **Headers de sécurité** : Caddy ajoute automatiquement les headers HSTS, X-Content-Type-Options, et X-Frame-Options.

> **Logs sécurisés** : Tous les événements d'authentification sont loggés avec horodatage et adresse IP source.

> **Isolation** : L'application fonctionne dans un environnement virtuel Python dédié.

> **Principe de moindre privilège** : fail2ban n'a accès qu'aux logs nécessaires.

## Scripts fournis

- `scripts/install.sh` : Installation automatique complète
- `scripts/test_fail2ban.sh` : Test de la protection fail2ban
- `scripts/monitor.sh` : Script de surveillance en temps réel
- `scripts/cleanup.sh` : Nettoyage et désinstallation

## Structure des fichiers

```
exercice2/
├── README.md
├── webapp/
│   ├── app.py              # Application Flask
│   └── templates/          # Templates HTML
├── config/
│   ├── Caddyfile          # Configuration Caddy
│   ├── webapp.conf        # Jail fail2ban
│   ├── webapp-filter.conf # Filtre fail2ban
│   └── webapp.service     # Service systemd
└── scripts/
    ├── install.sh         # Installation automatique
    ├── test_fail2ban.sh   # Test de sécurité
    ├── monitor.sh         # Surveillance
    └── cleanup.sh         # Nettoyage
```