#!/bin/bash

# Script d'installation automatique pour l'exercice 2
# Auteur: Système automatisé
# Description: Installation complète du site web avec reverse proxy Caddy et protection fail2ban

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USER="${SUDO_USER:-$USER}"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction de logging avec couleurs
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

# Vérification des prérequis
check_prerequisites() {
    log_info "Vérification des prérequis..."
    
    if [ "$EUID" -ne 0 ]; then
        log_error "Ce script doit être exécuté avec sudo"
        exit 1
    fi

    if ! systemctl is-active --quiet nftables; then
        log_warning "nftables n'est pas actif, tentative de démarrage..."
        systemctl start nftables || {
            log_error "Impossible de démarrer nftables"
            exit 1
        }
    fi
    
    log_success "Prérequis vérifiés"
}

# Installation des paquets nécessaires
install_packages() {
    log_info "Mise à jour du système et installation des paquets..."
    
    apt-get update
    
    # Python et outils de développement
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        curl \
        wget \
        gnupg \
        lsb-release \
        ca-certificates \
        apt-transport-https
    
    # Installation de Caddy
    log_info "Installation de Caddy..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy
    
    # Installation de fail2ban
    log_info "Installation de fail2ban..."
    apt-get install -y fail2ban
    
    # Utilitaires système
    apt-get install -y \
        htop \
        netstat-nat \
        tree \
        jq \
        bc
    
    log_success "Paquets installés avec succès"
}

# Configuration de l'application web
setup_webapp() {
    log_info "Configuration de l'application web..."
    
    # Création des répertoires
    mkdir -p /opt/webapp
    mkdir -p /var/log/webapp
    mkdir -p /var/log/caddy
    
    # Configuration des permissions
    chown -R $USER /opt/webapp
    chown -R $USER /var/log/webapp
    chown -R $USER /var/log/caddy
    
    # Création de l'environnement virtuel Python
    log_info "Création de l'environnement virtuel Python..."
    python3 -m venv /opt/webapp-env
    chown -R $USER /opt/webapp-env
    
    # Installation des dépendances Python
    log_info "Installation des dépendances Python..."
    /opt/webapp-env/bin/pip install --upgrade pip
    /opt/webapp-env/bin/pip install flask
    
    # Copie de l'application
    cp "$PROJECT_DIR/webapp/app.py" /opt/webapp/
    chown $USER /opt/webapp/app.py
    chmod +x /opt/webapp/app.py
    
    # Configuration du service systemd
    log_info "Configuration du service systemd..."
    cp "$PROJECT_DIR/config/webapp.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable webapp
    
    log_success "Application web configurée"
}

# Configuration de Caddy
setup_caddy() {
    log_info "Configuration de Caddy..."
    
    # Sauvegarde de la configuration existante
    if [ -f /etc/caddy/Caddyfile ]; then
        cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Installation de la nouvelle configuration
    cp "$PROJECT_DIR/config/Caddyfile" /etc/caddy/
    chown $USER /etc/caddy/Caddyfile
    
    # Test de la configuration
    log_info "Test de la configuration Caddy..."
    if caddy validate --config /etc/caddy/Caddyfile; then
        log_success "Configuration Caddy valide"
    else
        log_error "Configuration Caddy invalide"
        exit 1
    fi
    
    # Activation de Caddy
    systemctl enable caddy
    
    log_success "Caddy configuré"
}

# Configuration de fail2ban
setup_fail2ban() {
    log_info "Configuration de fail2ban..."
    
    # Installation des filtres et jails
    cp "$PROJECT_DIR/config/webapp-filter.conf" /etc/fail2ban/filter.d/webapp.conf
    cp "$PROJECT_DIR/config/webapp.conf" /etc/fail2ban/jail.d/
    
    # Configuration adaptée à nftables
    cat > /etc/fail2ban/jail.d/00-firewall.conf << EOF
[DEFAULT]
banaction = nftables-multiport
banaction_allports = nftables-allports
EOF
    
    # Test de la configuration
    log_info "Test de la configuration fail2ban..."
    if fail2ban-client -t; then
        log_success "Configuration fail2ban valide"
    else
        log_error "Configuration fail2ban invalide"
        exit 1
    fi
    
    # Activation de fail2ban
    systemctl enable fail2ban
    
    log_success "fail2ban configuré"
}

# Démarrage des services
start_services() {
    log_info "Démarrage des services..."
    
    # Démarrage de l'application web
    log_info "Démarrage de l'application web..."
    systemctl start webapp
    sleep 2
    
    if systemctl is-active --quiet webapp; then
        log_success "Application web démarrée"
    else
        log_error "Échec du démarrage de l'application web"
        systemctl status webapp
        exit 1
    fi
    
    # Démarrage de Caddy
    log_info "Démarrage de Caddy..."
    systemctl start caddy
    sleep 2
    
    if systemctl is-active --quiet caddy; then
        log_success "Caddy démarré"
    else
        log_error "Échec du démarrage de Caddy"
        systemctl status caddy
        exit 1
    fi
    
    # Démarrage de fail2ban
    log_info "Démarrage de fail2ban..."
    systemctl restart fail2ban
    sleep 2
    
    if systemctl is-active --quiet fail2ban; then
        log_success "fail2ban démarré"
    else
        log_error "Échec du démarrage de fail2ban"
        systemctl status fail2ban
        exit 1
    fi
    
    log_success "Tous les services sont démarrés"
}

# Tests de connectivité
run_tests() {
    log_info "Exécution des tests de connectivité..."
    
    # Test de l'application directe
    log_info "Test de l'application Flask directe..."
    if curl -s http://127.0.0.1:5000/health | grep -q "healthy"; then
        log_success "Application Flask accessible"
    else
        log_warning "Application Flask non accessible directement"
    fi
    
    # Test du reverse proxy
    log_info "Test du reverse proxy Caddy..."
    sleep 3
    if curl -s -k http://localhost/ | grep -q "Site Web Sécurisé"; then
        log_success "Reverse proxy fonctionnel"
    else
        log_warning "Reverse proxy non accessible"
    fi
    
    # Test de fail2ban
    log_info "Test de fail2ban..."
    if fail2ban-client status webapp >/dev/null 2>&1; then
        log_success "Jail fail2ban webapp active"
    else
        log_warning "Jail fail2ban webapp non active"
    fi
    
    log_success "Tests terminés"
}

# Configuration du firewall (optionnel)
setup_firewall() {
    log_info "Configuration du firewall nftables..."
    
    # Création des règles de base si elles n'existent pas
    if ! nft list table inet filter >/dev/null 2>&1; then
        log_info "Création des règles nftables de base..."
        
        cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy accept;
        
        # Accepter les connexions établies
        ct state established,related accept
        
        # Accepter le loopback
        iifname "lo" accept
        
        # Accepter SSH (important!)
        tcp dport 22 accept
        
        # Accepter HTTP et HTTPS
        tcp dport { 80, 443 } accept
        
        # Accepter ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
    }
    
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
        
        systemctl restart nftables
        log_success "Règles nftables configurées"
    else
        log_info "Table nftables déjà configurée"
    fi
}

# Installation des scripts utilitaires
install_scripts() {
    log_info "Installation des scripts utilitaires..."
    
    # Rendre les scripts exécutables
    chmod +x "$PROJECT_DIR/scripts/"*.sh
    
    # Copier les scripts dans /usr/local/bin pour un accès global
    cp "$PROJECT_DIR/scripts/test_fail2ban.sh" /usr/local/bin/webapp-test-fail2ban
    cp "$PROJECT_DIR/scripts/monitor.sh" /usr/local/bin/webapp-monitor
    
    chmod +x /usr/local/bin/webapp-test-fail2ban
    chmod +x /usr/local/bin/webapp-monitor
    
    log_success "Scripts utilitaires installés"
}

# Affichage des informations finales
show_final_info() {
    echo ""
    echo "=========================================="
    echo "INSTALLATION TERMINÉE AVEC SUCCÈS"
    echo "=========================================="
    echo ""
    echo "Services installés et configurés :"
    echo "  ✓ Application Flask (port 5000)"
    echo "  ✓ Reverse proxy Caddy (ports 80, 443)"
    echo "  ✓ Protection fail2ban"
    echo "  ✓ Firewall nftables"
    echo ""
    echo "Accès à l'application :"
    echo "  URL principale : http://localhost"
    echo "  URL HTTPS : https://localhost (certificat auto-signé)"
    echo "  Zone privée : http://localhost/private"
    echo ""
    echo "Comptes de test :"
    echo "  admin / admin123"
    echo "  user / password"
    echo "  test / test123"
    echo ""
    echo "Commandes utiles :"
    echo "  # Status des services"
    echo "  sudo systemctl status webapp caddy fail2ban"
    echo ""
    echo "  # Logs en temps réel"
    echo "  sudo tail -f /var/log/webapp/app.log"
    echo "  sudo tail -f /var/log/caddy/webapp.log"
    echo "  sudo tail -f /var/log/fail2ban.log"
    echo ""
    echo "  # Test de fail2ban"
    echo "  webapp-test-fail2ban"
    echo ""
    echo "  # Monitoring"
    echo "  webapp-monitor"
    echo ""
    echo "  # IP bannies"
    echo "  sudo fail2ban-client status webapp"
    echo ""
    echo "=========================================="
}

# Fonction principale
main() {
    echo "=========================================="
    echo "INSTALLATION EXERCICE 2"
    echo "Reverse Proxy avec Caddy et fail2ban"
    echo "=========================================="
    echo ""
    
    # check_prerequisites
    # install_packages
    setup_firewall
    setup_webapp
    setup_caddy
    setup_fail2ban
    start_services
    install_scripts
    run_tests
    show_final_info
    
    log_success "Installation complète terminée !"
}

# Exécution du script principal
main "$@"