#!/bin/bash

# Script de configuration des tâches cron pour la conformité RGPD
# Auteur: Système automatisé RGPD
# Description: Configure les tâches automatisées d'anonymisation et de rapports

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER="${SUDO_USER:-$USER}"
CRON_USER="${USER}"

# Fonction de logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Vérification des prérequis
if [ "$EUID" -ne 0 ]; then
    echo "Erreur: Ce script doit être exécuté avec sudo"
    exit 1
fi

log_message "=== CONFIGURATION DES TÂCHES CRON RGPD ==="

# Création des répertoires nécessaires
log_message "Création des répertoires..."
mkdir -p /var/log
mkdir -p /var/reports/rgpd
mkdir -p /var/run

# Configuration des permissions
chown -R "$USER:$USER" /var/reports/rgpd
chmod 755 /var/reports/rgpd

# Vérification que les scripts existent et sont exécutables
log_message "Vérification des scripts..."
if [ ! -f "$SCRIPT_DIR/anonymize_data.sh" ]; then
    echo "Erreur: Script anonymize_data.sh introuvable"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/generate_report.sh" ]; then
    echo "Erreur: Script generate_report.sh introuvable"
    exit 1
fi

# Rendre les scripts exécutables
chmod +x "$SCRIPT_DIR/anonymize_data.sh"
chmod +x "$SCRIPT_DIR/generate_report.sh"

log_message "Scripts trouvés et rendus exécutables"

# Configuration des variables d'environnement pour les scripts
ENV_FILE="/etc/environment.rgpd"
log_message "Configuration des variables d'environnement..."

cat > "$ENV_FILE" << EOF
# Variables d'environnement pour les scripts RGPD
RGPD_DB_USER=rgpd_user
RGPD_DB_PASS=rgpd_secure_password_2025!
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF

chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

# Création du script wrapper pour charger les variables d'environnement
WRAPPER_ANONYMIZE="/usr/local/bin/rgpd_anonymize_wrapper.sh"
WRAPPER_REPORT="/usr/local/bin/rgpd_report_wrapper.sh"

log_message "Création des scripts wrapper..."

cat > "$WRAPPER_ANONYMIZE" << EOF
#!/bin/bash
# Wrapper pour le script d'anonymisation RGPD

# Chargement des variables d'environnement
if [ -f /etc/environment.rgpd ]; then
    set -a
    source /etc/environment.rgpd
    set +a
fi

# Exécution du script d'anonymisation
exec "$SCRIPT_DIR/anonymize_data.sh" "\$@"
EOF

cat > "$WRAPPER_REPORT" << EOF
#!/bin/bash
# Wrapper pour le script de génération de rapports RGPD

# Chargement des variables d'environnement
if [ -f /etc/environment.rgpd ]; then
    set -a
    source /etc/environment.rgpd
    set +a
fi

# Exécution du script de génération de rapports
exec "$SCRIPT_DIR/generate_report.sh" "\$@"
EOF

chmod +x "$WRAPPER_ANONYMIZE"
chmod +x "$WRAPPER_REPORT"

# Configuration des tâches cron
log_message "Configuration des tâches cron..."

# Sauvegarde du crontab existant
crontab -u "$CRON_USER" -l > /tmp/crontab_backup_$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# Récupération du crontab actuel
CURRENT_CRONTAB=$(crontab -u "$CRON_USER" -l 2>/dev/null || echo "")

# Suppression des anciennes tâches RGPD s'il y en a
FILTERED_CRONTAB=$(echo "$CURRENT_CRONTAB" | grep -v "# RGPD" | grep -v "rgpd_anonymize_wrapper" | grep -v "rgpd_report_wrapper" || true)

# Ajout des nouvelles tâches RGPD
NEW_CRONTAB="$FILTERED_CRONTAB

# === TÂCHES AUTOMATISÉES RGPD ===
# Anonymisation quotidienne à 2h du matin
0 2 * * * $WRAPPER_ANONYMIZE >/dev/null 2>&1 # RGPD

# Rapport annuel automatique le 22 décembre à 4h du matin
0 4 22 12 * $WRAPPER_REPORT annual >/dev/null 2>&1 # RGPD

# Vérification mensuelle (1er de chaque mois à 1h)
0 1 1 * * $WRAPPER_ANONYMIZE >/dev/null 2>&1 # RGPD

# Nettoyage des logs anciens (tous les dimanches à 3h)
0 3 * * 0 find /var/log -name '*rgpd*' -mtime +90 -delete >/dev/null 2>&1 # RGPD"

# Installation du nouveau crontab
echo "$NEW_CRONTAB" | crontab -u "$CRON_USER" -

log_message "Tâches cron configurées pour l'utilisateur: $CRON_USER"

# Configuration de logrotate pour les logs RGPD
log_message "Configuration de la rotation des logs..."

cat > /etc/logrotate.d/rgpd << EOF
/var/log/rgpd_*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    create 644 $USER $USER
}
EOF

# Vérification de la configuration cron
log_message "Vérification de la configuration..."

echo ""
echo "=== TÂCHES CRON CONFIGURÉES ==="
crontab -u "$CRON_USER" -l | grep "RGPD" || echo "Aucune tâche RGPD trouvée"

echo ""
echo "=== SCRIPTS INSTALLÉS ==="
echo "Script d'anonymisation: $SCRIPT_DIR/anonymize_data.sh"
echo "Script de rapports: $SCRIPT_DIR/generate_report.sh"
echo "Wrapper anonymisation: $WRAPPER_ANONYMIZE"
echo "Wrapper rapports: $WRAPPER_REPORT"

echo ""
echo "=== RÉPERTOIRES CRÉÉS ==="
echo "Rapports: /var/reports/rgpd"
echo "Logs: /var/log/rgpd_*.log"

# Test de connectivité à la base de données
log_message "Test de connectivité base de données..."

if command -v mysql >/dev/null 2>&1; then
    if systemctl is-active --quiet mysql; then
        echo "✓ Service MySQL actif"
        
        # Test avec les credentials
        set +e
        source /etc/environment.rgpd
        if mysql -u "$RGPD_DB_USER" -p"$RGPD_DB_PASS" -e "SELECT 1;" >/dev/null 2>&1; then
            echo "✓ Connexion base de données OK"
        else
            echo "⚠ Attention: Problème de connexion base de données"
            echo "  Vérifiez que la base est configurée avec setup_database.sql"
        fi
        set -e
    else
        echo "⚠ Attention: Service MySQL non actif"
        echo "  Démarrez MySQL: sudo systemctl start mysql"
    fi
else
    echo "⚠ Attention: Client MySQL non installé"
    echo "  Installez MySQL: sudo apt-get install mysql-client"
fi

# Instructions finales
cat << EOF

=== CONFIGURATION TERMINÉE ===

Les tâches suivantes ont été configurées:

1. ANONYMISATION QUOTIDIENNE (2h00)
   - Anonymise les données 3-10 ans
   - Supprime les données > 10 ans
   - Log: /var/log/rgpd_anonymization.log

2. RAPPORT ANNUEL (22 décembre, 4h00)
   - Génère le rapport annuel automatique
   - Fichier: /var/reports/rgpd/rapport_annuel_[ANNÉE].txt

3. VÉRIFICATION MENSUELLE (1er du mois, 1h00)
   - Contrôle supplémentaire de conformité

COMMANDES MANUELLES DISPONIBLES:

# Anonymisation manuelle
sudo $WRAPPER_ANONYMIZE

# Rapport mensuel (exemple: janvier 2024)
sudo $WRAPPER_REPORT 2024-01

# Rapport annuel (exemple: 2023)
sudo $WRAPPER_REPORT 2023

# Voir les logs
tail -f /var/log/rgpd_anonymization.log

# Voir les rapports
ls -la /var/reports/rgpd/

PROCHAINES ÉTAPES:

1. Vérifiez que MySQL est configuré:
   mysql -u root -p < $SCRIPT_DIR/setup_database.sql

2. Testez l'anonymisation:
   sudo $WRAPPER_ANONYMIZE

3. Testez la génération de rapport:
   sudo $WRAPPER_REPORT 2024

EOF

log_message "=== CONFIGURATION CRON RGPD TERMINÉE ==="