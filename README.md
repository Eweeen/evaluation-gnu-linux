# Évaluation GNU/Linux - Projet Complet

Ce dépôt contient la solution complète aux deux exercices d'administration système GNU/Linux, couvrant la conformité RGPD et la configuration d'un reverse proxy sécurisé.

## 🏗️ Structure du projet

```
gnu-linux/
├── README.md                    # Ce fichier
├── consignes.md                 # Énoncés des exercices
├── exercice1/                   # Conformité RGPD
│   ├── README.md               # Guide complet RGPD
│   ├── scripts/
│   │   ├── setup_database.sql  # Création BDD + données test
│   │   ├── anonymize_data.sh   # Anonymisation automatique
│   │   ├── generate_report.sh  # Rapports consolidés
│   │   ├── setup_cron.sh       # Configuration tâches cron
│   └── documentation/
│       └── schema_rgpd.md      # Schémas et flux de données
└── exercice2/                   # Reverse Proxy + Sécurité
    ├── README.md               # Guide complet installation
    ├── webapp/
    │   └── app.py              # Application Flask complète
    ├── config/
    │   ├── Caddyfile           # Configuration reverse proxy
    │   ├── webapp.conf         # Jail fail2ban
    │   ├── webapp-filter.conf  # Filtres fail2ban
    │   └── webapp.service      # Service systemd
    └── scripts/
        ├── install.sh          # Installation automatique
        └── test_fail2ban.sh    # Test protection IP
```

## 🛡️ Exercice 1 : Conformité RGPD

### Objectif

Automatiser la conformité RGPD d'une base de données MySQL avec anonymisation des données personnelles et génération de rapports commerciaux.

### Solutions implémentées

**🔍 Analyse des données personnelles**

- Identification des données selon durées légales (3 ans / 10 ans)
- Classification : actives, à anonymiser, à supprimer
- Processus de conformité documenté avec schémas

**⚙️ Automatisation complète**

- Script d'anonymisation avec hash SHA-256 irréversible
- Génération de rapports consolidés (production + archive)
- Tâches cron automatisées (quotidien + annuel le 22/12)
- Logs d'audit complets pour traçabilité

**🗄️ Architecture technique**

- Base production : clients actifs (< 3 ans)
- Base archive : données anonymisées (3-10 ans)
- Suppression automatique (> 10 ans)
- Rapports CA consolidés toutes périodes

### Installation rapide

```bash
cd exercice1
mysql -u root -p < scripts/setup_database.sql
sudo ./scripts/setup_cron.sh
```

### Utilisation

```bash
# Test anonymisation
sudo /usr/local/bin/rgpd_anonymize_wrapper.sh

# Rapport mensuel
sudo /usr/local/bin/rgpd_report_wrapper.sh 2024-01

# Rapport annuel
sudo /usr/local/bin/rgpd_report_wrapper.sh 2024
```

## 🌐 Exercice 2 : Reverse Proxy Sécurisé

### Objectif

Déployer un site web avec authentification, reverse proxy Caddy et protection fail2ban contre les intrusions.

### Solutions implémentées

**🖥️ Application web Flask**

- Interface moderne avec authentification sécurisée
- 3 comptes de test : admin/admin123, user/password, test/test123
- Zone privée accessible après connexion
- Sessions sécurisées avec timeout automatique

**🔄 Reverse Proxy Caddy**

- HTTPS automatique avec certificats auto-signés
- Headers de sécurité (HSTS, XSS, CSRF)
- Logs détaillés pour monitoring
- Configuration haute disponibilité

**🛡️ Protection fail2ban**

- Bannissement automatique après 5 tentatives échouées
- Intégration nftables pour firewall
- Jail personnalisée pour l'application
- Tests automatisés de sécurité

### Installation automatique

```bash
cd exercice2
sudo ./scripts/install.sh
```

### Test de la protection

```bash
# Test complet fail2ban
webapp-test-fail2ban

# Monitoring temps réel
webapp-monitor

# Statut des services
sudo systemctl status webapp caddy fail2ban
```

### Accès à l'application

- **URL principale** : http://localhost
- **Zone privée** : http://localhost/private
- **API status** : http://localhost/api/status

## 🔧 Prérequis système

### Exercice 1 (RGPD)

- Debian/Ubuntu avec utilisateur sudo
- MySQL Server installé et actif
- Client MySQL (mysql-client)
- Outils système : bc, cron

### Exercice 2 (Reverse Proxy)

- Debian/Ubuntu avec utilisateur sudo
- Python 3.8+ avec pip
- nftables installé et activé
- Accès Internet (installation Caddy)

## 📊 Fonctionnalités avancées

### Exercice 1

- **Conformité légale** : Respect Code Commerce (10 ans) + RGPD (3 ans)
- **Sécurité** : Anonymisation irréversible par hash cryptographique
- **Automatisation** : Tâches cron avec gestion des erreurs et logs
- **Rapports** : CA mensuel/annuel consolidé toutes sources
- **Audit** : Traçabilité complète des opérations d'anonymisation

### Exercice 2

- **Sécurité web** : Protection XSS, CSRF, injection SQL
- **High Availability** : Health checks et restart automatique
- **Performance** : Rate limiting et optimisations Caddy
- **Monitoring** : Métriques temps réel et alerting
- **Compliance** : Logs d'audit et bannissement IP

## 📈 Tests et validation

### Validation Exercice 1

```bash
# Vérifier la conformité RGPD
cd exercice1
./scripts/diagnostic.sh

# Tester l'anonymisation
sudo /usr/local/bin/rgpd_anonymize_wrapper.sh

# Générer rapport de test
sudo /usr/local/bin/rgpd_report_wrapper.sh 2024
```

### Validation Exercice 2

```bash
# Test complet de sécurité
cd exercice2
webapp-test-fail2ban

# Vérifier les services
curl -s http://localhost/api/status | jq .

# Test authentification
curl -X POST http://localhost/login \
  -d "username=admin&password=admin123" \
  -c cookies.txt
```

## 🚀 Démarrage rapide

### Installation complète (30 minutes)

```bash
# Cloner le dépôt
git clone <url-du-depot>
cd gnu-linux

# Exercice 1 - RGPD
cd exercice1
mysql -u root -p < scripts/setup_database.sql
sudo ./scripts/setup_cron.sh

# Exercice 2 - Reverse Proxy
cd ../exercice2
sudo ./scripts/install.sh

# Tests de validation
cd ../exercice1 && ./scripts/diagnostic.sh
cd ../exercice2 && webapp-test-fail2ban
```

## 📚 Documentation technique

- **[Guide RGPD complet](exercice1/README.md)** : Architecture, installation, utilisation
- **[Guide Reverse Proxy](exercice2/README.md)** : Configuration, sécurité, monitoring
- **[Schémas techniques](exercice1/documentation/schema_rgpd.md)** : Flux de données et conformité

## 🔍 Monitoring et maintenance

### Logs importants

```bash
# RGPD
tail -f /var/log/rgpd_anonymization.log
tail -f /var/log/rgpd_reports.log

# Reverse Proxy
tail -f /var/log/webapp/app.log
tail -f /var/log/caddy/webapp.log
tail -f /var/log/fail2ban.log
```

### Commandes utiles

```bash
# Statut global
systemctl status mysql webapp caddy fail2ban

# IP bannies
sudo fail2ban-client status webapp

# Rapports RGPD disponibles
ls -la /var/reports/rgpd/

# Métriques Caddy
curl http://localhost:2019/metrics
```

## ✅ Conformité et sécurité

- **RGPD** : Anonymisation conforme, durées légales respectées
- **Sécurité** : Chiffrement, sessions, protection fail2ban
- **Audit** : Logs complets, traçabilité, monitoring
- **Performance** : Optimisations, cache, haute disponibilité
- **Maintenance** : Scripts automatisés, backup, recovery
