#!/bin/bash

# Script de test pour la protection fail2ban
# Auteur: Système automatisé
# Description: Teste le bannissement automatique des IP suspectes

set -euo pipefail

# Configuration
WEBAPP_URL="http://localhost"
LOG_FILE="/var/log/webapp/app.log"
FAIL2BAN_LOG="/var/log/fail2ban.log"
TEST_USER="nonexistent"
TEST_PASS="wrongpassword"
MAX_ATTEMPTS=6
WAIT_TIME=2

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fonction pour obtenir l'IP locale
get_local_ip() {
    hostname -I | awk '{print $1}'
}

# Fonction pour vérifier si une IP est bannie
check_banned_ip() {
    local ip="$1"
    if sudo fail2ban-client status webapp | grep -q "$ip"; then
        return 0
    else
        return 1
    fi
}

# Fonction pour débannir une IP
unban_ip() {
    local ip="$1"
    log_info "Débannissement de l'IP $ip..."
    sudo fail2ban-client set webapp unbanip "$ip" >/dev/null 2>&1 || true
}

# Fonction pour effectuer une tentative de connexion
attempt_login() {
    local username="$1"
    local password="$2"
    local attempt_num="$3"
    
    log_info "Tentative $attempt_num : $username / $password"
    
    # Utilisation de curl pour simuler la connexion
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        -X POST \
        -d "username=$username&password=$password" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        "$WEBAPP_URL/login" || echo "000")
    
    if [ "$response" = "200" ]; then
        log_success "Connexion réussie (code $response)"
        return 0
    else
        log_warning "Connexion échouée (code $response)"
        return 1
    fi
}

# Fonction principale de test
run_fail2ban_test() {
    local local_ip
    local_ip=$(get_local_ip)
    
    echo "=========================================="
    echo "TEST DE PROTECTION FAIL2BAN"
    echo "=========================================="
    echo ""
    echo "IP locale détectée: $local_ip"
    echo "URL de test: $WEBAPP_URL"
    echo "Nombre de tentatives: $MAX_ATTEMPTS"
    echo ""
    
    # Vérification des prérequis
    log_info "Vérification des prérequis..."
    
    if ! systemctl is-active --quiet fail2ban; then
        log_error "fail2ban n'est pas actif"
        exit 1
    fi
    
    if ! systemctl is-active --quiet webapp; then
        log_error "webapp n'est pas actif"
        exit 1
    fi
    
    if ! curl -s "$WEBAPP_URL" >/dev/null; then
        log_error "Application web non accessible à $WEBAPP_URL"
        exit 1
    fi
    
    log_success "Prérequis vérifiés"
    
    # Débannir l'IP au cas où elle serait déjà bannie
    unban_ip "$local_ip"
    
    # Vérifier l'état initial
    if check_banned_ip "$local_ip"; then
        log_warning "IP déjà bannie, débannissement..."
        unban_ip "$local_ip"
        sleep 2
    fi
    
    # Compter les échecs actuels dans les logs
    log_info "État initial des logs..."
    initial_fails=$(grep -c "Failed login attempt" "$LOG_FILE" 2>/dev/null || echo "0")
    log_info "Échecs de connexion dans les logs: $initial_fails"
    
    # Phase 1: Tentatives de connexion échouées
    echo ""
    log_info "=== PHASE 1: Tentatives de connexion échouées ==="
    
    for i in $(seq 1 $MAX_ATTEMPTS); do
        attempt_login "$TEST_USER" "$TEST_PASS" "$i"
        
        if [ $i -lt $MAX_ATTEMPTS ]; then
            log_info "Attente de ${WAIT_TIME}s avant la tentative suivante..."
            sleep $WAIT_TIME
        fi
    done
    
    # Phase 2: Vérification du bannissement
    echo ""
    log_info "=== PHASE 2: Vérification du bannissement ==="
    
    # Attendre que fail2ban traite les logs
    log_info "Attente du traitement par fail2ban (10s)..."
    sleep 10
    
    # Vérifier si l'IP est bannie
    if check_banned_ip "$local_ip"; then
        log_success "IP $local_ip bannie avec succès!"
        
        # Afficher les détails du bannissement
        echo ""
        log_info "Détails du bannissement:"
        sudo fail2ban-client status webapp
        
    else
        log_warning "IP $local_ip non bannie"
        echo ""
        log_info "Vérification des logs fail2ban..."
        sudo tail -10 "$FAIL2BAN_LOG" | grep webapp || log_warning "Aucun log webapp trouvé"
        
        echo ""
        log_info "Vérification de la jail webapp..."
        sudo fail2ban-client status webapp
    fi
    
    # Phase 3: Test d'accès bloqué
    echo ""
    log_info "=== PHASE 3: Test d'accès bloqué ==="
    
    log_info "Tentative d'accès depuis l'IP bannie..."
    
    # Test avec timeout court car la connexion devrait être rejetée
    if timeout 5 curl -s "$WEBAPP_URL" >/dev/null 2>&1; then
        log_warning "Accès toujours possible (peut être normal selon la configuration)"
    else
        log_success "Accès bloqué comme attendu"
    fi
    
    # Phase 4: Statistiques
    echo ""
    log_info "=== PHASE 4: Statistiques ==="
    
    # Compter les nouveaux échecs
    final_fails=$(grep -c "Failed login attempt" "$LOG_FILE" 2>/dev/null || echo "0")
    new_fails=$((final_fails - initial_fails))
    
    echo "Échecs de connexion ajoutés: $new_fails"
    echo "Total des échecs: $final_fails"
    
    # Vérifier les règles nftables
    if command -v nft >/dev/null; then
        log_info "Règles nftables actives:"
        sudo nft list table inet f2b-table 2>/dev/null | grep -A5 "chain f2b-webapp" || log_info "Aucune règle webapp trouvée"
    fi
    
    # Phase 5: Nettoyage optionnel
    echo ""
    log_info "=== PHASE 5: Nettoyage ==="
    
    read -p "Débannir l'IP maintenant? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        unban_ip "$local_ip"
        log_success "IP débannie"
    else
        log_info "IP laissée bannie (débannissement automatique selon configuration)"
        log_info "Pour débannir manuellement: sudo fail2ban-client set webapp unbanip $local_ip"
    fi
}

# Fonction d'aide
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Afficher cette aide"
    echo "  -c, --clean    Nettoyer les IP bannies avant le test"
    echo "  -s, --status   Afficher seulement le statut de fail2ban"
    echo ""
    echo "Ce script teste la protection fail2ban en effectuant plusieurs"
    echo "tentatives de connexion échouées pour déclencher un bannissement."
}

# Fonction pour afficher le statut
show_status() {
    echo "=========================================="
    echo "STATUT FAIL2BAN"
    echo "=========================================="
    echo ""
    
    if systemctl is-active --quiet fail2ban; then
        log_success "Service fail2ban actif"
        
        echo ""
        echo "Jails actives:"
        sudo fail2ban-client status
        
        echo ""
        echo "Jail webapp:"
        sudo fail2ban-client status webapp 2>/dev/null || log_warning "Jail webapp non trouvée"
        
    else
        log_error "Service fail2ban inactif"
    fi
}

# Fonction de nettoyage
clean_bans() {
    echo "=========================================="
    echo "NETTOYAGE DES BANNISSEMENTS"
    echo "=========================================="
    echo ""
    
    log_info "Débannissement de toutes les IP de la jail webapp..."
    
    # Obtenir la liste des IP bannies
    banned_ips=$(sudo fail2ban-client status webapp | grep "Banned IP list:" | cut -d: -f2 | tr -d ' ')
    
    if [ -n "$banned_ips" ]; then
        for ip in $banned_ips; do
            log_info "Débannissement de $ip..."
            sudo fail2ban-client set webapp unbanip "$ip"
        done
        log_success "Toutes les IP ont été débannie"
    else
        log_info "Aucune IP bannie trouvée"
    fi
}

# Traitement des arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -s|--status)
        show_status
        exit 0
        ;;
    -c|--clean)
        clean_bans
        exit 0
        ;;
    "")
        run_fail2ban_test
        ;;
    *)
        echo "Option inconnue: $1"
        show_help
        exit 1
        ;;
esac