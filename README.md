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
        └── schema_rgpd.md      # Schémas et flux de données
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
