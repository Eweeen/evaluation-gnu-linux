-- Script de configuration de la base de données pour la conformité RGPD
-- Création des bases de données

CREATE DATABASE IF NOT EXISTS rgpd_production;
CREATE DATABASE IF NOT EXISTS rgpd_archive;

-- Configuration de l'utilisateur pour les scripts
CREATE USER IF NOT EXISTS 'rgpd_user'@'localhost' IDENTIFIED BY 'rgpd_secure_password_2025!';
GRANT SELECT, INSERT, UPDATE, DELETE ON rgpd_production.* TO 'rgpd_user'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON rgpd_archive.* TO 'rgpd_user'@'localhost';

-- Base de production
USE rgpd_production;

CREATE TABLE IF NOT EXISTS clients (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nom VARCHAR(100) NOT NULL,
    prenom VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    adresse TEXT,
    mot_de_passe VARCHAR(255) NOT NULL,
    date_creation DATETIME DEFAULT CURRENT_TIMESTAMP,
    derniere_commande DATETIME,
    INDEX idx_derniere_commande (derniere_commande),
    INDEX idx_date_creation (date_creation)
);

CREATE TABLE IF NOT EXISTS factures (
    id INT PRIMARY KEY AUTO_INCREMENT,
    client_id INT NOT NULL,
    montant_ttc DECIMAL(10,2) NOT NULL,
    date_facture DATE NOT NULL,
    numero_facture VARCHAR(50) UNIQUE,
    FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE,
    INDEX idx_date_facture (date_facture),
    INDEX idx_client_id (client_id)
);

-- Base d'archivage (données anonymisées)
USE rgpd_archive;

CREATE TABLE IF NOT EXISTS clients_anonymises (
    id_anonyme VARCHAR(64) PRIMARY KEY,
    region_code VARCHAR(10),
    date_creation_mois DATE,
    derniere_commande_mois DATE,
    date_anonymisation DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_creation_mois (date_creation_mois),
    INDEX idx_commande_mois (derniere_commande_mois)
);

CREATE TABLE IF NOT EXISTS factures_anonymisees (
    id INT PRIMARY KEY AUTO_INCREMENT,
    client_anonyme VARCHAR(64) NOT NULL,
    montant_ttc DECIMAL(10,2) NOT NULL,
    date_facture DATE NOT NULL,
    date_archivage DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (client_anonyme) REFERENCES clients_anonymises(id_anonyme) ON DELETE CASCADE,
    INDEX idx_date_facture (date_facture),
    INDEX idx_client_anonyme (client_anonyme)
);

-- Table de logs pour traçabilité RGPD
CREATE TABLE IF NOT EXISTS logs_anonymisation (
    id INT PRIMARY KEY AUTO_INCREMENT,
    date_operation DATETIME DEFAULT CURRENT_TIMESTAMP,
    nb_clients_anonymises INT,
    nb_factures_archivees INT,
    nb_clients_supprimes INT,
    commentaire TEXT
);

-- Jeu de données de test
USE rgpd_production;

-- Insertion de clients de test avec dates variées pour tester l'anonymisation
INSERT INTO clients (nom, prenom, email, adresse, mot_de_passe, date_creation, derniere_commande) VALUES
-- Clients récents (< 3 ans) - restent actifs
('Martin', 'Pierre', 'pierre.martin@email.com', '123 Rue de la Paix, Paris', SHA2('password123', 256), '2023-06-15 10:30:00', '2024-01-20 14:15:00'),
('Dubois', 'Marie', 'marie.dubois@email.com', '456 Avenue Victor Hugo, Lyon', SHA2('motdepasse456', 256), '2023-08-20 09:45:00', '2024-02-10 11:30:00'),
('Bernard', 'Jean', 'jean.bernard@email.com', '789 Boulevard Saint-Germain, Marseille', SHA2('secret789', 256), '2024-01-10 16:20:00', '2024-03-05 09:45:00'),

-- Clients anciens (3-10 ans) - à anonymiser
('Lefebvre', 'Sophie', 'sophie.lefebvre@email.com', '321 Rue de Rivoli, Paris', SHA2('password321', 256), '2019-05-12 08:15:00', '2021-12-15 10:30:00'),
('Moreau', 'Paul', 'paul.moreau@email.com', '654 Cours Mirabeau, Aix-en-Provence', SHA2('motdepasse654', 256), '2018-03-08 14:45:00', '2020-11-20 16:15:00'),
('Simon', 'Claire', 'claire.simon@email.com', '987 Place Bellecour, Lyon', SHA2('secret987', 256), '2017-09-25 11:30:00', '2019-08-10 13:45:00'),

-- Clients très anciens (> 10 ans) - à supprimer
('Petit', 'Michel', 'michel.petit@email.com', '147 Rue du Faubourg Saint-Antoine, Paris', SHA2('password147', 256), '2012-04-18 09:00:00', '2013-06-22 15:30:00'),
('David', 'Isabelle', 'isabelle.david@email.com', '258 Avenue de la République, Toulouse', SHA2('motdepasse258', 256), '2011-07-03 10:15:00', '2012-09-14 12:00:00');

-- Insertion de factures correspondantes
INSERT INTO factures (client_id, montant_ttc, date_facture, numero_facture) VALUES
-- Factures clients récents
(1, 150.50, '2024-01-20', 'F2024-001'),
(1, 89.99, '2024-02-15', 'F2024-002'),
(2, 245.75, '2024-02-10', 'F2024-003'),
(2, 167.30, '2024-03-01', 'F2024-004'),
(3, 320.00, '2024-03-05', 'F2024-005'),

-- Factures clients anciens (à anonymiser)
(4, 199.99, '2021-12-15', 'F2021-045'),
(4, 125.50, '2021-10-20', 'F2021-040'),
(5, 89.75, '2020-11-20', 'F2020-089'),
(5, 456.20, '2020-09-15', 'F2020-078'),
(6, 78.90, '2019-08-10', 'F2019-156'),
(6, 234.60, '2019-06-25', 'F2019-134'),

-- Factures clients très anciens (à supprimer avec anonymisation après 10 ans)
(7, 156.78, '2013-06-22', 'F2013-234'),
(7, 89.45, '2013-04-15', 'F2013-189'),
(8, 267.89, '2012-09-14', 'F2012-456'),
(8, 145.32, '2012-07-20', 'F2012-389');

-- Ajout de plus de données pour des tests plus réalistes
INSERT INTO factures (client_id, montant_ttc, date_facture, numero_facture) VALUES
-- Données 2023 pour tests de rapports
(1, 189.50, '2023-12-20', 'F2023-234'),
(2, 267.80, '2023-11-15', 'F2023-198'),
(3, 145.90, '2023-10-10', 'F2023-167'),

-- Données 2022
(4, 298.75, '2022-05-18', 'F2022-089'),
(5, 178.60, '2022-08-22', 'F2022-134'),

-- Données 2021
(4, 234.50, '2021-03-15', 'F2021-012'),
(5, 156.80, '2021-07-20', 'F2021-067'),
(6, 289.90, '2021-09-10', 'F2021-089');

-- Affichage du résumé des données créées
SELECT 'Clients créés' as Information, COUNT(*) as Nombre FROM clients
UNION ALL
SELECT 'Factures créées', COUNT(*) FROM factures
UNION ALL
SELECT 'Clients récents (< 3 ans)', COUNT(*) FROM clients WHERE derniere_commande > DATE_SUB(NOW(), INTERVAL 3 YEAR)
UNION ALL
SELECT 'Clients à anonymiser (3-10 ans)', COUNT(*) FROM clients WHERE derniere_commande BETWEEN DATE_SUB(NOW(), INTERVAL 10 YEAR) AND DATE_SUB(NOW(), INTERVAL 3 YEAR)
UNION ALL
SELECT 'Clients à supprimer (> 10 ans)', COUNT(*) FROM clients WHERE derniere_commande < DATE_SUB(NOW(), INTERVAL 10 YEAR);

FLUSH PRIVILEGES;