# Schéma du processus RGPD

## Architecture du système

```mermaid
flowchart TD
    A[Base Production<br/>rgpd_production] --> B{Analyse des données}
    B --> C[Données < 3 ans<br/>Restent actives]
    B --> D[Données 3-10 ans<br/>À anonymiser]
    B --> E[Données > 10 ans<br/>À supprimer]
    
    C --> F[Clients actifs]
    D --> G[Processus d'anonymisation]
    E --> H[Suppression définitive]
    
    G --> I[Base Archive<br/>rgpd_archive]
    I --> J[Données anonymisées]
    
    F --> K[Génération rapports<br/>CA production]
    J --> L[Génération rapports<br/>CA archive]
    
    K --> M[Rapport consolidé]
    L --> M
    
    style A fill:#e1f5fe
    style I fill:#f3e5f5
    style M fill:#e8f5e8
    style H fill:#ffebee
```

## Flux de données détaillé

```mermaid
graph LR
    subgraph "Base Production"
        CP[Clients Production]
        FP[Factures Production]
    end
    
    subgraph "Processus d'anonymisation"
        PA[Identification<br/>données anciennes]
        PH[Génération hash<br/>anonyme]
        PR[Extraction région<br/>depuis adresse]
    end
    
    subgraph "Base Archive"
        CA[Clients Anonymisés]
        FA[Factures Anonymisées]
        LA[Logs Anonymisation]
    end
    
    subgraph "Rapports"
        RP[Rapport Production]
        RA[Rapport Archive]
        RC[Rapport Consolidé]
    end
    
    CP --> PA
    FP --> PA
    PA --> PH
    PA --> PR
    PH --> CA
    PR --> CA
    FP --> FA
    
    CP --> RP
    FP --> RP
    CA --> RA
    FA --> RA
    RP --> RC
    RA --> RC
    
    PA --> LA
```

## Calendrier d'exécution

```mermaid
gantt
    title Tâches automatisées RGPD
    dateFormat  HH:mm
    axisFormat %H:%M
    
    section Quotidien
    Vérification mensuelle :milestone, m1, 01:00, 0m
    Anonymisation quotidienne :crit, active, 02:00, 30m
    Nettoyage logs :done, 03:00, 15m
    
    section Annuel
    Rapport annuel automatique :milestone, 04:00, 0m
```

## Conformité RGPD

### Durées de conservation

| Type de donnée | Durée | Base légale | Action |
|---|---|---|---|
| Données personnelles clients actifs | < 3 ans | Relation contractuelle | Conservation production |
| Données personnelles clients inactifs | 3-10 ans | Obligation comptable | Anonymisation → Archive |
| Données comptables anonymisées | 10 ans max | Code commerce | Suppression définitive |

### Processus d'anonymisation

1. **Identification** : Sélection des données selon critères temporels
2. **Anonymisation** : 
   - Hash SHA-256 des identifiants
   - Généralisation géographique (région vs adresse complète)
   - Suppression liens vers données personnelles
3. **Archivage** : Transfert vers base dédiée
4. **Suppression** : Effacement données personnelles originales
5. **Traçabilité** : Enregistrement logs d'audit

### Garanties techniques

- **Irréversibilité** : Impossible de retrouver l'identité depuis les données anonymisées
- **Isolation** : Bases de données séparées (production/archive)
- **Chiffrement** : Mots de passe hashés SHA-256
- **Audit** : Logs complets des opérations d'anonymisation
- **Automatisation** : Processus sans intervention humaine