#!/bin/bash

set -euo pipefail

# Configuration
DB_USER="${RGPD_DB_USER:-rgpd_user}"
DB_PASS="${RGPD_DB_PASS:-rgpd_secure_password_2025!}"
DB_PROD="rgpd_production"
DB_ARCHIVE="rgpd_archive"
LOG_FILE="/var/log/rgpd_anonymization.log"
LOCK_FILE="/var/run/rgpd_anonymization.lock"

# Fonction de logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Fonction de nettoyage en cas d'erreur
cleanup() {
    rm -f "$LOCK_FILE"
    log_message "ERREUR: Processus d'anonymisation interrompu"
    exit 1
}

# Gestion du verrouillage pour éviter les exécutions simultanées
if [ -f "$LOCK_FILE" ]; then
    log_message "ATTENTION: Processus d'anonymisation déjà en cours"
    exit 1
fi

trap cleanup ERR
echo $$ > "$LOCK_FILE"

log_message "=== DÉBUT DU PROCESSUS D'ANONYMISATION RGPD ==="

# Fonction d'exécution MySQL sécurisée
mysql_execute() {
    local database="$1"
    local query="$2"
    mysql -u "$DB_USER" -p"$DB_PASS" "$database" -e "$query" 2>/dev/null
}

# Fonction pour anonymiser une adresse (garder seulement la région)
anonymize_address() {
    local address="$1"
    # Extraction du code postal ou de la ville pour déterminer la région
    if [[ "$address" == *"Paris"* ]]; then
        echo "ILE_FR"
    elif [[ "$address" == *"Lyon"* ]]; then
        echo "RHONE_ALPES"
    elif [[ "$address" == *"Marseille"* ]] || [[ "$address" == *"Aix-en-Provence"* ]]; then
        echo "PACA"
    elif [[ "$address" == *"Toulouse"* ]]; then
        echo "OCCITANIE"
    else
        echo "AUTRE"
    fi
}

# 1. Identification des clients à anonymiser (3-10 ans)
log_message "Identification des données à anonymiser (3-10 ans)..."

clients_to_anonymize=$(mysql_execute "$DB_PROD" "
    SELECT COUNT(*) as count 
    FROM clients 
    WHERE derniere_commande BETWEEN DATE_SUB(NOW(), INTERVAL 10 YEAR) AND DATE_SUB(NOW(), INTERVAL 3 YEAR)
" | tail -n 1)

log_message "Clients à anonymiser: $clients_to_anonymize"

if [ "$clients_to_anonymize" -gt 0 ]; then
    log_message "Début de l'anonymisation des données (3-10 ans)..."
    
    # Récupération des données à anonymiser
    mysql_execute "$DB_PROD" "
        SELECT 
            id,
            CONCAT(nom, ' ', prenom) as nom_complet,
            email,
            adresse,
            DATE_FORMAT(date_creation, '%Y-%m-01') as creation_mois,
            DATE_FORMAT(derniere_commande, '%Y-%m-01') as commande_mois
        FROM clients 
        WHERE derniere_commande BETWEEN DATE_SUB(NOW(), INTERVAL 10 YEAR) AND DATE_SUB(NOW(), INTERVAL 3 YEAR)
    " | while IFS=$'\t' read -r id nom_complet email adresse creation_mois commande_mois; do
        
        if [ "$id" = "id" ]; then continue; fi  # Skip header
        
        # Génération d'un identifiant anonyme (hash SHA-256)
        id_anonyme=$(echo -n "${nom_complet}${email}" | sha256sum | cut -d' ' -f1)
        
        # Anonymisation de l'adresse (extraction région)
        region_code=$(anonymize_address "$adresse")
        
        # Insertion dans la base d'archive
        mysql_execute "$DB_ARCHIVE" "
            INSERT IGNORE INTO clients_anonymises (id_anonyme, region_code, date_creation_mois, derniere_commande_mois)
            VALUES ('$id_anonyme', '$region_code', '$creation_mois', '$commande_mois')
        "
        
        # Anonymisation des factures associées
        mysql_execute "$DB_PROD" "
            INSERT INTO $DB_ARCHIVE.factures_anonymisees (client_anonyme, montant_ttc, date_facture)
            SELECT '$id_anonyme', montant_ttc, date_facture
            FROM factures 
            WHERE client_id = $id
        "
        
        log_message "Client ID $id anonymisé -> $id_anonyme (région: $region_code)"
    done
    
    # Suppression des données personnelles de la production
    factures_archived=$(mysql_execute "$DB_PROD" "
        SELECT COUNT(*) FROM factures f
        JOIN clients c ON f.client_id = c.id
        WHERE c.derniere_commande BETWEEN DATE_SUB(NOW(), INTERVAL 10 YEAR) AND DATE_SUB(NOW(), INTERVAL 3 YEAR)
    " | tail -n 1)
    
    mysql_execute "$DB_PROD" "
        DELETE f FROM factures f
        JOIN clients c ON f.client_id = c.id
        WHERE c.derniere_commande BETWEEN DATE_SUB(NOW(), INTERVAL 10 YEAR) AND DATE_SUB(NOW(), INTERVAL 3 YEAR)
    "
    
    mysql_execute "$DB_PROD" "
        DELETE FROM clients
        WHERE derniere_commande BETWEEN DATE_SUB(NOW(), INTERVAL 10 YEAR) AND DATE_SUB(NOW(), INTERVAL 3 YEAR)
    "
    
    log_message "Données anonymisées: $clients_to_anonymize clients, $factures_archived factures"
fi

# 2. Suppression définitive des données > 10 ans
log_message "Identification des données à supprimer définitivement (> 10 ans)..."

clients_to_delete=$(mysql_execute "$DB_PROD" "
    SELECT COUNT(*) 
    FROM clients 
    WHERE derniere_commande < DATE_SUB(NOW(), INTERVAL 10 YEAR)
" | tail -n 1)

clients_archive_to_delete=$(mysql_execute "$DB_ARCHIVE" "
    SELECT COUNT(*) 
    FROM clients_anonymises 
    WHERE derniere_commande_mois < DATE_SUB(NOW(), INTERVAL 10 YEAR)
" | tail -n 1)

log_message "Clients production à supprimer: $clients_to_delete"
log_message "Clients archive à supprimer: $clients_archive_to_delete"

if [ "$clients_to_delete" -gt 0 ]; then
    # Suppression en production
    mysql_execute "$DB_PROD" "
        DELETE f FROM factures f
        JOIN clients c ON f.client_id = c.id
        WHERE c.derniere_commande < DATE_SUB(NOW(), INTERVAL 10 YEAR)
    "
    
    mysql_execute "$DB_PROD" "
        DELETE FROM clients
        WHERE derniere_commande < DATE_SUB(NOW(), INTERVAL 10 YEAR)
    "
    
    log_message "Suppression définitive: $clients_to_delete clients et leurs factures"
fi

if [ "$clients_archive_to_delete" -gt 0 ]; then
    # Suppression en archive
    mysql_execute "$DB_ARCHIVE" "
        DELETE FROM factures_anonymisees
        WHERE client_anonyme IN (
            SELECT id_anonyme FROM clients_anonymises
            WHERE derniere_commande_mois < DATE_SUB(NOW(), INTERVAL 10 YEAR)
        )
    "
    
    mysql_execute "$DB_ARCHIVE" "
        DELETE FROM clients_anonymises
        WHERE derniere_commande_mois < DATE_SUB(NOW(), INTERVAL 10 YEAR)
    "
    
    log_message "Suppression archive: $clients_archive_to_delete clients anonymisés"
fi

# 3. Enregistrement dans les logs de traçabilité
mysql_execute "$DB_ARCHIVE" "
    INSERT INTO logs_anonymisation (nb_clients_anonymises, nb_factures_archivees, nb_clients_supprimes, commentaire)
    VALUES ($clients_to_anonymize, ${factures_archived:-0}, $(($clients_to_delete + $clients_archive_to_delete)), 
            'Processus automatique - Anonymisation 3-10 ans, Suppression >10 ans')
"

# 4. Optimisation des bases de données
log_message "Optimisation des bases de données..."
mysql_execute "$DB_PROD" "OPTIMIZE TABLE clients, factures"
mysql_execute "$DB_ARCHIVE" "OPTIMIZE TABLE clients_anonymises, factures_anonymisees, logs_anonymisation"

# 5. Statistiques finales
active_clients=$(mysql_execute "$DB_PROD" "SELECT COUNT(*) FROM clients" | tail -n 1)
archived_clients=$(mysql_execute "$DB_ARCHIVE" "SELECT COUNT(*) FROM clients_anonymises" | tail -n 1)
total_factures_prod=$(mysql_execute "$DB_PROD" "SELECT COUNT(*) FROM factures" | tail -n 1)
total_factures_arch=$(mysql_execute "$DB_ARCHIVE" "SELECT COUNT(*) FROM factures_anonymisees" | tail -n 1)

log_message "=== STATISTIQUES FINALES ==="
log_message "Clients actifs (production): $active_clients"
log_message "Clients anonymisés (archive): $archived_clients"
log_message "Factures production: $total_factures_prod"
log_message "Factures archivées: $total_factures_arch"

# Nettoyage
rm -f "$LOCK_FILE"

log_message "=== PROCESSUS D'ANONYMISATION TERMINÉ AVEC SUCCÈS ==="

# Vérification de la conformité RGPD
log_message "=== VÉRIFICATION CONFORMITÉ RGPD ==="

# Vérifier qu'il n'y a plus de données personnelles anciennes
old_personal_data=$(mysql_execute "$DB_PROD" "
    SELECT COUNT(*) FROM clients 
    WHERE derniere_commande < DATE_SUB(NOW(), INTERVAL 3 YEAR)
" | tail -n 1)

if [ "$old_personal_data" -eq 0 ]; then
    log_message "✓ CONFORMITÉ RGPD: Aucune donnée personnelle > 3 ans en production"
else
    log_message "✗ ALERTE RGPD: $old_personal_data données personnelles anciennes détectées"
fi

# Rotation des logs (garder seulement les 30 derniers jours)
find /var/log -name "rgpd_anonymization.log.*" -mtime +30 -delete 2>/dev/null || true

exit 0