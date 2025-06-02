#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Application Web Flask pour l'exercice 2 - Reverse Proxy avec Caddy
Auteur: Système automatisé
Description: Site web avec authentification et zone privée
"""

from flask import Flask, render_template_string, request, session, redirect, url_for, jsonify, flash
import logging
import os
import hashlib
import datetime
from functools import wraps
import secrets

app = Flask(__name__)

# Configuration sécurisée
app.config['SECRET_KEY'] = secrets.token_hex(32)
app.config['SESSION_COOKIE_SECURE'] = False  # True en production avec HTTPS
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
app.config['PERMANENT_SESSION_LIFETIME'] = datetime.timedelta(hours=1)

# Configuration des logs
LOG_DIR = '/var/log/webapp'
os.makedirs(LOG_DIR, exist_ok=True)

# Configuration du logging pour fail2ban
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'{LOG_DIR}/app.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

# Base de données des utilisateurs (en dur pour la démonstration)
USERS = {
    'admin': {
        'password': hashlib.sha256('admin123'.encode()).hexdigest(),
        'role': 'administrator',
        'name': 'Administrateur'
    },
    'user': {
        'password': hashlib.sha256('password'.encode()).hexdigest(),
        'role': 'user',
        'name': 'Utilisateur Standard'
    },
    'test': {
        'password': hashlib.sha256('test123'.encode()).hexdigest(),
        'role': 'tester',
        'name': 'Utilisateur Test'
    }
}

# Templates HTML intégrés
HOME_TEMPLATE = """
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Site Web Sécurisé - Accueil</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 40px; 
            border-radius: 15px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { 
            color: #fff; 
            text-align: center; 
            margin-bottom: 30px;
            font-size: 2.5em;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .nav { 
            text-align: center; 
            margin: 30px 0; 
        }
        .nav a { 
            color: #fff; 
            text-decoration: none; 
            margin: 0 15px; 
            padding: 12px 25px;
            background: rgba(255,255,255,0.2);
            border-radius: 25px;
            border: 1px solid rgba(255,255,255,0.3);
            transition: all 0.3s ease;
            display: inline-block;
        }
        .nav a:hover { 
            background: rgba(255,255,255,0.3);
            transform: translateY(-2px);
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }
        .features {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin: 40px 0;
        }
        .feature {
            background: rgba(255,255,255,0.1);
            padding: 25px;
            border-radius: 10px;
            border: 1px solid rgba(255,255,255,0.2);
        }
        .feature h3 {
            margin-top: 0;
            color: #ffd700;
        }
        .status {
            background: rgba(0,255,0,0.2);
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            border-left: 4px solid #00ff00;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🛡️ Site Web Sécurisé</h1>
        
        <div class="status">
            <strong>Statut :</strong> Site opérationnel avec protection active
        </div>
        
        <div class="nav">
            <a href="{{ url_for('home') }}">🏠 Accueil</a>
            <a href="{{ url_for('login') }}">🔐 Connexion</a>
            {% if session.get('user') %}
                <a href="{{ url_for('private') }}">🔒 Zone Privée</a>
                <a href="{{ url_for('logout') }}">🚪 Déconnexion</a>
            {% endif %}
        </div>

        <div class="features">
            <div class="feature">
                <h3>🔐 Authentification Sécurisée</h3>
                <p>Système d'authentification avec sessions sécurisées et protection contre les attaques par force brute.</p>
            </div>
            
            <div class="feature">
                <h3>🛡️ Protection fail2ban</h3>
                <p>Bannissement automatique des adresses IP suspectes après plusieurs tentatives de connexion échouées.</p>
            </div>
            
            <div class="feature">
                <h3>🔄 Reverse Proxy Caddy</h3>
                <p>Serveur web moderne avec HTTPS automatique et configuration simplifiée.</p>
            </div>
            
            <div class="feature">
                <h3>📊 Surveillance</h3>
                <p>Logs détaillés et monitoring en temps réel des tentatives d'accès et d'authentification.</p>
            </div>
        </div>

        {% if session.get('user') %}
            <div style="background: rgba(0,255,0,0.2); padding: 15px; border-radius: 8px; margin: 20px 0; text-align: center;">
                <strong>Bienvenue {{ session.user.name }} !</strong><br>
                Vous êtes connecté en tant que <em>{{ session.user.role }}</em>
            </div>
        {% else %}
            <div style="background: rgba(255,255,0,0.2); padding: 15px; border-radius: 8px; margin: 20px 0; text-align: center;">
                <strong>Accès public</strong><br>
                Connectez-vous pour accéder à la zone privée
            </div>
        {% endif %}

        <div style="text-align: center; margin-top: 40px; font-size: 0.9em; opacity: 0.8;">
            Exercice 2 - Configuration reverse proxy avec Caddy<br>
            Dernière mise à jour : {{ current_time }}
        </div>
    </div>
</body>
</html>
"""

LOGIN_TEMPLATE = """
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Site Web Sécurisé - Connexion</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
        .container { 
            max-width: 400px; 
            margin: 100px auto; 
            background: rgba(255,255,255,0.1); 
            padding: 40px; 
            border-radius: 15px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { 
            color: #fff; 
            text-align: center; 
            margin-bottom: 30px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .form-group { 
            margin: 20px 0; 
        }
        label { 
            display: block; 
            margin-bottom: 8px; 
            font-weight: bold;
        }
        input[type="text"], input[type="password"] { 
            width: 100%; 
            padding: 12px; 
            border: 1px solid rgba(255,255,255,0.3); 
            border-radius: 8px;
            background: rgba(255,255,255,0.1);
            color: white;
            font-size: 16px;
            box-sizing: border-box;
        }
        input[type="text"]::placeholder, input[type="password"]::placeholder {
            color: rgba(255,255,255,0.7);
        }
        input[type="text"]:focus, input[type="password"]:focus {
            outline: none;
            border-color: #ffd700;
            background: rgba(255,255,255,0.2);
        }
        button { 
            width: 100%; 
            padding: 12px; 
            background: #ffd700; 
            color: #333; 
            border: none; 
            border-radius: 8px;
            font-size: 16px;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        button:hover { 
            background: #ffed4e;
            transform: translateY(-2px);
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }
        .nav { 
            text-align: center; 
            margin-top: 30px; 
        }
        .nav a { 
            color: #ffd700; 
            text-decoration: none; 
        }
        .nav a:hover { 
            text-decoration: underline; 
        }
        .alert {
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            text-align: center;
        }
        .alert-error {
            background: rgba(255,0,0,0.2);
            border: 1px solid rgba(255,0,0,0.5);
        }
        .alert-success {
            background: rgba(0,255,0,0.2);
            border: 1px solid rgba(0,255,0,0.5);
        }
        .credentials {
            background: rgba(255,255,255,0.1);
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            font-size: 0.9em;
        }
        .credentials h4 {
            margin-top: 0;
            color: #ffd700;
        }
        .cred-item {
            margin: 5px 0;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔐 Connexion</h1>
        
        {% with messages = get_flashed_messages() %}
            {% if messages %}
                {% for message in messages %}
                    <div class="alert alert-error">{{ message }}</div>
                {% endfor %}
            {% endif %}
        {% endwith %}
        
        <form method="POST">
            <div class="form-group">
                <label for="username">Nom d'utilisateur :</label>
                <input type="text" id="username" name="username" placeholder="Entrez votre nom d'utilisateur" required>
            </div>
            
            <div class="form-group">
                <label for="password">Mot de passe :</label>
                <input type="password" id="password" name="password" placeholder="Entrez votre mot de passe" required>
            </div>
            
            <button type="submit">Se connecter</button>
        </form>
        
        <div class="credentials">
            <h4>Comptes de démonstration :</h4>
            <div class="cred-item">admin / admin123</div>
            <div class="cred-item">user / password</div>
            <div class="cred-item">test / test123</div>
        </div>
        
        <div class="nav">
            <a href="{{ url_for('home') }}">← Retour à l'accueil</a>
        </div>
    </div>
</body>
</html>
"""

PRIVATE_TEMPLATE = """
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Site Web Sécurisé - Zone Privée</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            min-height: 100vh;
            color: white;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 40px; 
            border-radius: 15px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { 
            color: #fff; 
            text-align: center; 
            margin-bottom: 30px;
            font-size: 2.5em;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .success-message {
            background: rgba(255,255,255,0.2);
            padding: 30px;
            border-radius: 10px;
            text-align: center;
            font-size: 1.2em;
            margin: 30px 0;
            border: 2px solid rgba(255,255,255,0.3);
        }
        .user-info {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .nav { 
            text-align: center; 
            margin: 30px 0; 
        }
        .nav a { 
            color: #fff; 
            text-decoration: none; 
            margin: 0 15px; 
            padding: 12px 25px;
            background: rgba(255,255,255,0.2);
            border-radius: 25px;
            border: 1px solid rgba(255,255,255,0.3);
            transition: all 0.3s ease;
            display: inline-block;
        }
        .nav a:hover { 
            background: rgba(255,255,255,0.3);
            transform: translateY(-2px);
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .stat-card {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            border: 1px solid rgba(255,255,255,0.2);
        }
        .stat-number {
            font-size: 2em;
            font-weight: bold;
            color: #ffd700;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 Zone Privée</h1>
        
        <div class="success-message">
            <h2>✅ Accès au contenu privé autorisé</h2>
            <p>Félicitations ! Vous avez réussi à vous authentifier et accéder à cette zone sécurisée.</p>
        </div>
        
        <div class="user-info">
            <h3>📋 Informations de session</h3>
            <p><strong>Utilisateur :</strong> {{ session.user.name }}</p>
            <p><strong>Rôle :</strong> {{ session.user.role }}</p>
            <p><strong>Nom d'utilisateur :</strong> {{ session.username }}</p>
            <p><strong>Heure de connexion :</strong> {{ session.login_time }}</p>
            <p><strong>Adresse IP :</strong> {{ user_ip }}</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-number">{{ session_count }}</div>
                <div>Sessions actives</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">{{ current_time.strftime('%H:%M') }}</div>
                <div>Heure actuelle</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">🛡️</div>
                <div>Protection active</div>
            </div>
        </div>
        
        <div style="background: rgba(255,255,255,0.1); padding: 20px; border-radius: 10px; margin: 30px 0;">
            <h3>🔐 Contenu sécurisé</h3>
            <p>Cette zone est protégée par :</p>
            <ul>
                <li>Authentification obligatoire</li>
                <li>Sessions sécurisées avec timeout</li>
                <li>Protection fail2ban contre les attaques</li>
                <li>Reverse proxy Caddy avec HTTPS</li>
                <li>Logs d'audit complets</li>
            </ul>
        </div>
        
        <div class="nav">
            <a href="{{ url_for('home') }}">🏠 Accueil</a>
            <a href="{{ url_for('logout') }}">🚪 Se déconnecter</a>
        </div>
        
        <div style="text-align: center; margin-top: 40px; font-size: 0.9em; opacity: 0.8;">
            Zone privée sécurisée - Accès réservé aux utilisateurs authentifiés
        </div>
    </div>
</body>
</html>
"""

def login_required(f):
    """Décorateur pour protéger les routes nécessitant une authentification"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            flash('Vous devez être connecté pour accéder à cette page.')
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

def get_client_ip():
    """Récupère l'adresse IP réelle du client (en tenant compte du reverse proxy)"""
    # Headers possibles du reverse proxy
    if request.headers.get('X-Forwarded-For'):
        return request.headers.get('X-Forwarded-For').split(',')[0].strip()
    elif request.headers.get('X-Real-IP'):
        return request.headers.get('X-Real-IP')
    else:
        return request.remote_addr

@app.route('/')
def home():
    """Page d'accueil publique"""
    logger.info(f"Access to home page from {get_client_ip()}")
    return render_template_string(HOME_TEMPLATE, 
                                current_time=datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Page de connexion avec gestion des tentatives"""
    client_ip = get_client_ip()
    
    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        
        if not username or not password:
            logger.warning(f"Login attempt with empty credentials from {client_ip}")
            flash('Nom d\'utilisateur et mot de passe requis.')
            return render_template_string(LOGIN_TEMPLATE)
        
        # Vérification des credentials
        if username in USERS:
            password_hash = hashlib.sha256(password.encode()).hexdigest()
            if USERS[username]['password'] == password_hash:
                # Connexion réussie
                session.permanent = True
                session['user'] = USERS[username]
                session['username'] = username
                session['login_time'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                session['login_ip'] = client_ip
                
                logger.info(f"Successful login for user '{username}' from {client_ip}")
                
                # Redirection vers la page demandée ou zone privée
                next_page = request.args.get('next')
                if next_page:
                    return redirect(next_page)
                return redirect(url_for('private'))
        
        # Échec d'authentification - LOG IMPORTANT POUR FAIL2BAN
        logger.warning(f"Failed login attempt for user '{username}' from {client_ip}")
        flash('Nom d\'utilisateur ou mot de passe incorrect.')
        
    return render_template_string(LOGIN_TEMPLATE)

@app.route('/private')
@login_required
def private():
    """Zone privée accessible uniquement après authentification"""
    client_ip = get_client_ip()
    logger.info(f"Access to private area by user '{session['username']}' from {client_ip}")
    
    # Simulation du compteur de sessions (normalement en base de données)
    session_count = 1
    
    return render_template_string(PRIVATE_TEMPLATE,
                                user_ip=client_ip,
                                session_count=session_count,
                                current_time=datetime.datetime.now())

@app.route('/logout')
def logout():
    """Déconnexion et destruction de la session"""
    username = session.get('username', 'unknown')
    client_ip = get_client_ip()
    
    session.clear()
    logger.info(f"User '{username}' logged out from {client_ip}")
    
    flash('Vous avez été déconnecté avec succès.')
    return redirect(url_for('home'))

@app.route('/api/status')
def api_status():
    """API endpoint pour vérifier le statut de l'application"""
    return jsonify({
        'status': 'active',
        'timestamp': datetime.datetime.now().isoformat(),
        'authenticated': 'user' in session,
        'version': '1.0.0'
    })

@app.route('/health')
def health_check():
    """Health check pour monitoring"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.datetime.now().isoformat()
    })

# Gestionnaire d'erreur personnalisé
@app.errorhandler(404)
def page_not_found(e):
    client_ip = get_client_ip()
    logger.warning(f"404 error from {client_ip} - URL: {request.url}")
    return render_template_string("""
    <!DOCTYPE html>
    <html>
    <head>
        <title>404 - Page non trouvée</title>
        <style>
            body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
            .error { color: #e74c3c; font-size: 2em; margin: 20px 0; }
        </style>
    </head>
    <body>
        <div class="error">404</div>
        <h2>Page non trouvée</h2>
        <p>La page que vous cherchez n'existe pas.</p>
        <a href="{{ url_for('home') }}">Retour à l'accueil</a>
    </body>
    </html>
    """), 404

@app.errorhandler(500)
def internal_error(e):
    client_ip = get_client_ip()
    logger.error(f"500 error from {client_ip} - {str(e)}")
    return render_template_string("""
    <!DOCTYPE html>
    <html>
    <head>
        <title>500 - Erreur serveur</title>
        <style>
            body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
            .error { color: #e74c3c; font-size: 2em; margin: 20px 0; }
        </style>
    </head>
    <body>
        <div class="error">500</div>
        <h2>Erreur interne du serveur</h2>
        <p>Une erreur inattendue s'est produite.</p>
        <a href="{{ url_for('home') }}">Retour à l'accueil</a>
    </body>
    </html>
    """), 500

if __name__ == '__main__':
    logger.info("Starting Flask application...")
    
    # Création du répertoire de logs si nécessaire
    os.makedirs(LOG_DIR, exist_ok=True)
    
    # Mode debug uniquement en développement
    debug_mode = os.environ.get('FLASK_ENV') == 'development'
    
    # Port configuré par variable d'environnement ou 5000 par défaut
    port = int(os.environ.get('PORT', 5000))
    
    app.run(
        host='127.0.0.1',  # Écoute seulement en local (reverse proxy)
        port=port,
        debug=debug_mode,
        threaded=True
    )