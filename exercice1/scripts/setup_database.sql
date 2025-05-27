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
('Laurent', 'Sophie', 'sophie.laurent@email.com', '111 Avenue des Champs, Paris', SHA2('pass2024', 256), '2023-03-15 14:30:00', '2024-06-15 16:45:00'),
('Rousseau', 'Thomas', 'thomas.rousseau@email.com', '222 Rue de Lyon, Lyon', SHA2('secret2023', 256), '2022-11-20 10:15:00', '2024-05-10 12:30:00'),

-- Clients moyennement anciens (2021-2023) - encore actifs
('Garcia', 'Elena', 'elena.garcia@email.com', '333 Boulevard Haussmann, Paris', SHA2('elena123', 256), '2021-05-10 09:30:00', '2023-12-20 11:45:00'),
('Miller', 'James', 'james.miller@email.com', '444 Cours Lafayette, Lyon', SHA2('james456', 256), '2021-08-15 15:20:00', '2023-11-15 14:30:00'),
('Wilson', 'Emma', 'emma.wilson@email.com', '555 Rue Saint-Antoine, Marseille', SHA2('emma789', 256), '2022-02-28 08:45:00', '2023-10-05 17:15:00'),

-- Clients anciens (3-10 ans) - à anonymiser
('Lefebvre', 'Sophie', 'sophie.lefebvre@email.com', '321 Rue de Rivoli, Paris', SHA2('password321', 256), '2019-05-12 08:15:00', '2021-12-15 10:30:00'),
('Moreau', 'Paul', 'paul.moreau@email.com', '654 Cours Mirabeau, Aix-en-Provence', SHA2('motdepasse654', 256), '2018-03-08 14:45:00', '2020-11-20 16:15:00'),
('Simon', 'Claire', 'claire.simon@email.com', '987 Place Bellecour, Lyon', SHA2('secret987', 256), '2017-09-25 11:30:00', '2019-08-10 13:45:00'),

-- Clients très anciens (> 10 ans) - à supprimer
('Petit', 'Michel', 'michel.petit@email.com', '147 Rue du Faubourg Saint-Antoine, Paris', SHA2('password147', 256), '2012-04-18 09:00:00', '2013-06-22 15:30:00'),
('David', 'Isabelle', 'isabelle.david@email.com', '258 Avenue de la République, Toulouse', SHA2('motdepasse258', 256), '2011-07-03 10:15:00', '2012-09-14 12:00:00');

-- Insertion de factures correspondantes
INSERT INTO factures (client_id, montant_ttc, date_facture, numero_facture) VALUES
-- Factures clients récents 2024
(1, 150.50, '2024-01-20', 'F2024-001'),
(1, 89.99, '2024-02-15', 'F2024-002'),
(1, 310.75, '2024-06-10', 'F2024-015'),
(1, 125.80, '2024-09-05', 'F2024-028'),
(2, 245.75, '2024-02-10', 'F2024-003'),
(2, 167.30, '2024-03-01', 'F2024-004'),
(2, 198.50, '2024-07-22', 'F2024-019'),
(2, 278.90, '2024-11-15', 'F2024-035'),
(3, 320.00, '2024-03-05', 'F2024-005'),
(3, 456.75, '2024-08-18', 'F2024-024'),
(3, 189.60, '2024-12-01', 'F2024-038'),
(4, 234.80, '2024-04-12', 'F2024-008'),
(4, 156.45, '2024-10-30', 'F2024-032'),
(5, 298.70, '2024-05-25', 'F2024-012'),
(5, 167.85, '2024-08-14', 'F2024-023'),

-- Factures 2023
(1, 189.75, '2023-01-15', 'F2023-002'),
(1, 267.40, '2023-04-20', 'F2023-015'),
(1, 134.90, '2023-08-10', 'F2023-031'),
(1, 298.65, '2023-11-25', 'F2023-048'),
(2, 178.30, '2023-02-18', 'F2023-007'),
(2, 345.50, '2023-06-12', 'F2023-024'),
(2, 223.75, '2023-09-08', 'F2023-037'),
(3, 156.80, '2023-03-22', 'F2023-011'),
(3, 278.95, '2023-07-14', 'F2023-028'),
(3, 198.40, '2023-12-05', 'F2023-052'),
(6, 234.60, '2023-05-15', 'F2023-020'),
(6, 167.85, '2023-09-30', 'F2023-040'),
(7, 189.25, '2023-01-28', 'F2023-005'),
(7, 312.70, '2023-08-22', 'F2023-034'),
(8, 145.95, '2023-10-16', 'F2023-043'),

-- Factures 2022
(1, 198.45, '2022-01-12', 'F2022-003'),
(1, 267.80, '2022-05-18', 'F2022-022'),
(1, 178.30, '2022-09-25', 'F2022-041'),
(2, 234.55, '2022-02-14', 'F2022-008'),
(2, 298.70, '2022-06-20', 'F2022-027'),
(2, 156.85, '2022-11-10', 'F2022-048'),
(3, 189.60, '2022-03-08', 'F2022-012'),
(3, 345.25, '2022-07-15', 'F2022-032'),
(3, 223.40, '2022-12-22', 'F2022-055'),
(6, 167.75, '2022-04-25', 'F2022-018'),
(6, 278.90, '2022-08-12', 'F2022-037'),
(7, 198.35, '2022-01-30', 'F2022-006'),
(7, 245.60, '2022-10-05', 'F2022-044'),
(8, 134.85, '2022-06-18', 'F2022-029'),
(8, 298.50, '2022-11-28', 'F2022-051'),

-- Factures 2021
(1, 178.95, '2021-01-15', 'F2021-002'),
(1, 234.70, '2021-04-22', 'F2021-018'),
(1, 298.85, '2021-08-14', 'F2021-035'),
(1, 167.40, '2021-12-08', 'F2021-052'),
(2, 189.25, '2021-02-10', 'F2021-007'),
(2, 345.60, '2021-06-18', 'F2021-028'),
(2, 223.30, '2021-10-25', 'F2021-047'),
(3, 156.75, '2021-03-12', 'F2021-011'),
(3, 267.95, '2021-07-20', 'F2021-032'),
(3, 198.50, '2021-11-15', 'F2021-049'),
(6, 134.80, '2021-01-28', 'F2021-005'),
(6, 278.65, '2021-09-12', 'F2021-041'),
(7, 189.45, '2021-05-30', 'F2021-025'),
(7, 245.85, '2021-12-18', 'F2021-055'),
(8, 167.90, '2021-08-05', 'F2021-036'),

-- Factures clients anciens (à anonymiser)
(9, 199.99, '2021-12-15', 'F2021-056'),
(9, 125.50, '2021-10-20', 'F2021-045'),
(10, 89.75, '2020-11-20', 'F2020-089'),
(10, 456.20, '2020-09-15', 'F2020-078'),
(11, 78.90, '2019-08-10', 'F2019-156'),
(11, 234.60, '2019-06-25', 'F2019-134'),

-- Factures clients très anciens (à supprimer avec anonymisation après 10 ans)
(12, 156.78, '2013-06-22', 'F2013-234'),
(12, 89.45, '2013-04-15', 'F2013-189'),
(13, 267.89, '2012-09-14', 'F2012-456'),
(13, 145.32, '2012-07-20', 'F2012-389');

-- Données supplémentaires pour répartition mensuelle
INSERT INTO factures (client_id, montant_ttc, date_facture, numero_facture) VALUES
-- Répartition mensuelle 2024
(4, 189.50, '2024-01-05', 'F2024-039'),
(5, 267.80, '2024-02-12', 'F2024-040'),
(4, 145.90, '2024-03-18', 'F2024-041'),
(5, 298.75, '2024-04-22', 'F2024-042'),
(4, 178.60, '2024-05-28', 'F2024-043'),
(5, 234.85, '2024-06-14', 'F2024-044'),
(4, 156.90, '2024-07-19', 'F2024-045'),
(5, 289.45, '2024-08-25', 'F2024-046'),
(4, 167.75, '2024-09-12', 'F2024-047'),
(5, 245.60, '2024-10-08', 'F2024-048'),
(4, 198.85, '2024-11-15', 'F2024-049'),
(5, 278.90, '2024-12-20', 'F2024-050'),

-- Répartition mensuelle 2023
(6, 189.35, '2023-01-08', 'F2023-053'),
(7, 234.70, '2023-02-15', 'F2023-054'),
(8, 167.85, '2023-03-22', 'F2023-055'),
(6, 298.50, '2023-04-18', 'F2023-056'),
(7, 156.75, '2023-05-25', 'F2023-057'),
(8, 245.90, '2023-06-14', 'F2023-058'),
(6, 178.65, '2023-07-20', 'F2023-059'),
(7, 289.40, '2023-08-16', 'F2023-060'),
(8, 198.80, '2023-09-22', 'F2023-061'),
(6, 234.55, '2023-10-18', 'F2023-062'),
(7, 167.90, '2023-11-24', 'F2023-063'),
(8, 278.75, '2023-12-28', 'F2023-064');

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
