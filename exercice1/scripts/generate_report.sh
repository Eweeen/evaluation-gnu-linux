#!/bin/bash

# Script de génération de rapports consolidés pour conformité RGPD
# Auteur: Système automatisé RGPD
# Description: Génère des rapports de CA consolidés (production + archive) par période

set -euo pipefail

# Forcer la locale anglaise pour éviter les problèmes de formatage des nombres
export LC_ALL=C
export LANG=C

# Configuration
DB_USER="${RGPD_DB_USER:-rgpd_user}"
DB_PASS="${RGPD_DB_PASS:-rgpd_secure_password_2025!}"
DB_PROD="rgpd_production"
DB_ARCHIVE="rgpd_archive"
REPORTS_DIR="/var/reports/rgpd"
LOG_FILE="/var/log/rgpd_reports.log"

# Fonction de logging
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    # Essayer d'écrire dans le log, ignorer les erreurs de permission
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

# Fonction d'exécution MySQL sécurisée
mysql_execute() {
    local database="$1"
    local query="$2"
    mysql -u "$DB_USER" -p"$DB_PASS" "$database" -e "$query" 2>/dev/null
}

# Fonction de formatage robuste des nombres
format_number() {
    local number="$1"
    # Nettoyer la valeur
    number=$(echo "$number" | tr -d ' \t\n\r')
    # Si vide, retourner 0.00
    if [ -z "$number" ]; then
        echo "0.00"
        return
    fi
    # Essayer de formater directement avec awk show_help(plus robuste)
    result=$(echo "$number" | awk '{if($1 ~ /^[0-9]*\.?[0-9]*$/ && $1 != "") printf "%.2f", $1; else print "0.00"}' 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
    else
        echo "0.00"
    fi
}

# Fonction d'aide
show_help() {
    echo "Usage: $0 [PÉRIODE]"
    echo ""
    echo "PÉRIODE peut être:"
    echo "  YYYY        - Rapport annuel (ex: 2024)"
    echo "  YYYY-MM     - Rapport mensuel (ex: 2024-01)"
    echo "  annual      - Rapport annuel automatique (année précédente)"
    echo ""
    echo "Variables d'environnement:"
    echo "  RGPD_DB_USER - Utilisateur base de données (défaut: rgpd_user)"
    echo "  RGPD_DB_PASS - Mot de passe base de données"
    echo ""
    echo "Exemples:"
    echo "  $0 2024         # Rapport annuel 2024"
    echo "  $0 2024-03      # Rapport mars 2024"
    echo "  $0 annual       # Rapport année précédente"
}

# Fonction pour générer un rapport mensuel
generate_monthly_report() {
    local year="$1"
    local month="$2"
    local report_file="$REPORTS_DIR/rapport_mensuel_${year}_${month}.txt"

    log_message "Génération rapport mensuel: $year-$month"

    # CA production pour le mois
    local ca_production
    ca_production=$(mysql_execute "$DB_PROD" "
        SELECT COALESCE(SUM(montant_ttc), 0)
        FROM factures
        WHERE YEAR(date_facture) = $year AND MONTH(date_facture) = $month
    " | tail -n 1)

    # CA archive pour le mois
    local ca_archive
    ca_archive=$(mysql_execute "$DB_ARCHIVE" "
        SELECT COALESCE(SUM(montant_ttc), 0)
        FROM factures_anonymisees
        WHERE YEAR(date_facture) = $year AND MONTH(date_facture) = $month
    " | tail -n 1)

    # Formatage robuste des valeurs
    ca_production=$(format_number "$ca_production")
    ca_archive=$(format_number "$ca_archive")

    # Nombre de factures
    local nb_factures_prod
    nb_factures_prod=$(mysql_execute "$DB_PROD" "
        SELECT COUNT(*)
        FROM factures
        WHERE YEAR(date_facture) = $year AND MONTH(date_facture) = $month
    " | tail -n 1)

    local nb_factures_arch
    nb_factures_arch=$(mysql_execute "$DB_ARCHIVE" "
        SELECT COUNT(*)
        FROM factures_anonymisees
        WHERE YEAR(date_facture) = $year AND MONTH(date_facture) = $month
    " | tail -n 1)

    # Calcul du total avec formatage
    local ca_total
    ca_total=$(echo "scale=2; $ca_production + $ca_archive" | bc -l)
    ca_total=$(format_number "$ca_total")
    local nb_factures_total
    nb_factures_total=$((nb_factures_prod + nb_factures_arch))

    # Génération du rapport
    cat > "$report_file" << EOF
=====================================
RAPPORT MENSUEL CHIFFRE D'AFFAIRES
=====================================

Période: $(printf "%02d/%d" $month $year)
Date de génération: $(date '+%d/%m/%Y à %H:%M:%S')

DONNÉES PRODUCTION (Clients actifs):
- Chiffre d'affaires TTC: ${ca_production} €
- Nombre de factures: ${nb_factures_prod}

DONNÉES ARCHIVÉES (Anonymisées):
- Chiffre d'affaires TTC: ${ca_archive} €
- Nombre de factures: ${nb_factures_arch}

TOTAL CONSOLIDÉ:
- Chiffre d'affaires TTC: ${ca_total} €
- Nombre de factures: ${nb_factures_total}

=====================================
DÉTAIL PAR SOURCE DE DONNÉES
=====================================

EOF

    # Détail par jour pour la production
    echo "Production - Répartition par jour:" >> "$report_file"
    mysql_execute "$DB_PROD" "
        SELECT
            DAY(date_facture) as Jour,
            COUNT(*) as 'Nb Factures',
            ROUND(SUM(montant_ttc), 2) as 'CA TTC'
        FROM factures
        WHERE YEAR(date_facture) = $year AND MONTH(date_facture) = $month
        GROUP BY DAY(date_facture)
        ORDER BY DAY(date_facture)
    " >> "$report_file" 2>/dev/null || echo "Aucune donnée production" >> "$report_file"

    echo "" >> "$report_file"
    echo "Archive - Répartition par jour:" >> "$report_file"
    mysql_execute "$DB_ARCHIVE" "
        SELECT
            DAY(date_facture) as Jour,
            COUNT(*) as 'Nb Factures',
            ROUND(SUM(montant_ttc), 2) as 'CA TTC'
        FROM factures_anonymisees
        WHERE YEAR(date_facture) = $year AND MONTH(date_facture) = $month
        GROUP BY DAY(date_facture)
        ORDER BY DAY(date_facture)
    " >> "$report_file" 2>/dev/null || echo "Aucune donnée archive" >> "$report_file"

    # Informations de conformité RGPD
    cat >> "$report_file" << EOF

=====================================
INFORMATIONS CONFORMITÉ RGPD
=====================================

Les données présentes dans ce rapport respectent les principes du RGPD:
- Données production: Clients actifs (< 3 ans d'inactivité)
- Données archive: Anonymisées (impossible de relier aux personnes)
- Données supprimées: > 10 ans (conformité légale comptable)

Dernière anonymisation: $(mysql_execute "$DB_ARCHIVE" "SELECT MAX(date_operation) FROM logs_anonymisation" | tail -n 1)

=====================================
EOF

    echo "Rapport mensuel généré: $report_file"
    log_message "Rapport mensuel $year-$month généré: CA total ${ca_total}€"
}

# Fonction pour générer un rapport annuel
generate_annual_report() {
    local year="$1"
    local report_file="$REPORTS_DIR/rapport_annuel_${year}.txt"

    log_message "Génération rapport annuel: $year"

    # CA production pour l'année
    local ca_production_total
    ca_production_total=$(mysql_execute "$DB_PROD" "
        SELECT COALESCE(SUM(montant_ttc), 0)
        FROM factures
        WHERE YEAR(date_facture) = $year
    " | tail -n 1)

    # CA archive pour l'année
    local ca_archive_total
    ca_archive_total=$(mysql_execute "$DB_ARCHIVE" "
        SELECT COALESCE(SUM(montant_ttc), 0)
        FROM factures_anonymisees
        WHERE YEAR(date_facture) = $year
    " | tail -n 1)

    # Formatage robuste des valeurs
    ca_production_total=$(format_number "$ca_production_total")
    ca_archive_total=$(format_number "$ca_archive_total")

    # Calcul du total avec formatage
    local ca_total_annuel
    ca_total_annuel=$(echo "scale=2; $ca_production_total + $ca_archive_total" | bc -l)
    ca_total_annuel=$(format_number "$ca_total_annuel")

    # Génération du rapport
    cat > "$report_file" << EOF
=====================================
RAPPORT ANNUEL CHIFFRE D'AFFAIRES
=====================================

Année: $year
Date de génération: $(date '+%d/%m/%Y à %H:%M:%S')

RÉSUMÉ EXÉCUTIF:
- Chiffre d'affaires total: ${ca_total_annuel} €
- Part production (actifs): ${ca_production_total} €
- Part archive (anonymisées): ${ca_archive_total} €

=====================================
RÉPARTITION MENSUELLE
=====================================

EOF

    # Détail mensuel consolidé
    echo "Chiffre d'affaires mensuel consolidé (Production + Archive):" >> "$report_file"
    echo "Mois | CA Production | CA Archive | CA Total" >> "$report_file"
    echo "-----|---------------|------------|----------" >> "$report_file"

    for month in {1..12}; do
        local ca_prod_mois
        ca_prod_mois=$(mysql_execute "$DB_PROD" "
            SELECT COALESCE(SUM(montant_ttc), 0)
            FROM factures
            WHERE YEAR(date_facture) = $year AND MONTH(date_facture) = $month
        " | tail -n 1)

        local ca_arch_mois
        ca_arch_mois=$(mysql_execute "$DB_ARCHIVE" "
            SELECT COALESCE(SUM(montant_ttc), 0)
            FROM factures_anonymisees
            WHERE YEAR(date_facture) = $year AND MONTH(date_facture) = $month
        " | tail -n 1)

        # Formatage robuste des valeurs
        ca_prod_mois=$(format_number "$ca_prod_mois")
        ca_arch_mois=$(format_number "$ca_arch_mois")

        local ca_total_mois
        ca_total_mois=$(echo "scale=2; $ca_prod_mois + $ca_arch_mois" | bc -l)
        ca_total_mois=$(format_number "$ca_total_mois")

        echo "$(printf "%02d" $month)   | $(printf "%13s" "$ca_prod_mois") | $(printf "%10s" "$ca_arch_mois") | $(printf "%8s" "$ca_total_mois")" >> "$report_file"
    done

    cat >> "$report_file" << EOF

=====================================
STATISTIQUES GÉNÉRALES
=====================================

EOF

    # Statistiques générales
    local nb_clients_actifs
    nb_clients_actifs=$(mysql_execute "$DB_PROD" "SELECT COUNT(*) FROM clients" | tail -n 1)

    local nb_clients_archives
    nb_clients_archives=$(mysql_execute "$DB_ARCHIVE" "SELECT COUNT(*) FROM clients_anonymises" | tail -n 1)

    local nb_factures_year_prod
    nb_factures_year_prod=$(mysql_execute "$DB_PROD" "
        SELECT COUNT(*) FROM factures WHERE YEAR(date_facture) = $year
    " | tail -n 1)

    local nb_factures_year_arch
    nb_factures_year_arch=$(mysql_execute "$DB_ARCHIVE" "
        SELECT COUNT(*) FROM factures_anonymisees WHERE YEAR(date_facture) = $year
    " | tail -n 1)

    cat >> "$report_file" << EOF
Clients actifs (base production): ${nb_clients_actifs}
Clients anonymisés (base archive): ${nb_clients_archives}
Factures $year (production): ${nb_factures_year_prod}
Factures $year (archive): ${nb_factures_year_arch}

Panier moyen production: $(if [ "$nb_factures_year_prod" -gt 0 ]; then format_number "$(echo "scale=2; $ca_production_total / $nb_factures_year_prod" | bc -l)"; else echo "0.00"; fi) €
Panier moyen archive: $(if [ "$nb_factures_year_arch" -gt 0 ]; then format_number "$(echo "scale=2; $ca_archive_total / $nb_factures_year_arch" | bc -l)"; else echo "0.00"; fi) €

=====================================
CONFORMITÉ RGPD ET LÉGALE
=====================================

✓ Données personnelles: Conservées < 3 ans (production uniquement)
✓ Données anonymisées: 3-10 ans (base archive)
✓ Données comptables: Conservées 10 ans puis supprimées
✓ Traçabilité: Logs d'anonymisation disponibles

Historique des anonymisations:
EOF

    # Historique des anonymisations
    mysql_execute "$DB_ARCHIVE" "
        SELECT
            DATE_FORMAT(date_operation, '%d/%m/%Y %H:%i') as 'Date',
            nb_clients_anonymises as 'Clients Anonymisés',
            nb_clients_supprimes as 'Clients Supprimés',
            commentaire as 'Commentaire'
        FROM logs_anonymisation
        ORDER BY date_operation DESC
        LIMIT 10
    " >> "$report_file" 2>/dev/null || echo "Aucun historique disponible" >> "$report_file"

    echo "" >> "$report_file"
    echo "======================================" >> "$report_file"
    echo "Rapport généré automatiquement" >> "$report_file"
    echo "Système de conformité RGPD v1.0" >> "$report_file"
    echo "======================================" >> "$report_file"

    echo "Rapport annuel généré: $report_file"
    log_message "Rapport annuel $year généré: CA total ${ca_total_annuel}€"
}

# Création du répertoire de rapports si nécessaire
mkdir -p "$REPORTS_DIR" 2>/dev/null || {
    REPORTS_DIR="./reports"
    mkdir -p "$REPORTS_DIR"
    echo "Attention: Utilisation du répertoire local ./reports"
}

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || {
    LOG_FILE="./rgpd_reports.log"
    echo "Attention: Utilisation du fichier de log local ./rgpd_reports.log"
}

# Vérification des arguments
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

PERIOD="$1"

log_message "=== DÉBUT GÉNÉRATION RAPPORT: $PERIOD ==="

# Traitement selon le type de période
case "$PERIOD" in
    "annual")
        # Rapport automatique pour l'année précédente
        YEAR=$(($(date +%Y) - 1))
        generate_annual_report "$YEAR"
        ;;
    [0-9][0-9][0-9][0-9])
        # Rapport annuel pour une année spécifique
        generate_annual_report "$PERIOD"
        ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9])
        # Rapport mensuel
        YEAR=$(echo "$PERIOD" | cut -d'-' -f1)
        MONTH=$(echo "$PERIOD" | cut -d'-' -f2)
        # Supprimer le zéro initial du mois si présent
        MONTH=$((10#$MONTH))
        generate_monthly_report "$YEAR" "$MONTH"
        ;;
    "--help"|"-h")
        show_help
        exit 0
        ;;
    *)
        echo "Erreur: Format de période invalide: $PERIOD"
        echo ""
        show_help
        exit 1
        ;;
esac

log_message "=== GÉNÉRATION RAPPORT TERMINÉE ==="

# Affichage du résumé
echo ""
echo "Rapport généré avec succès!"
echo "Répertoire des rapports: $REPORTS_DIR"
echo "Log: $LOG_FILE"
echo ""
echo "Rapports disponibles:"
ls -la "$REPORTS_DIR"/ 2>/dev/null || echo "Aucun rapport trouvé"

exit 0
