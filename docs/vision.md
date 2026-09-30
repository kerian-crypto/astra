# ASTRA HUB — Vision produit

Application mobile interne d'Astra — Flutter + FastAPI + IA.

## 1. Vision générale

ASTRA HUB est l'application mobile interne utilisée exclusivement par les membres d'Astra.
Elle centralise : la communication entre membres, la gestion des projets, la planification,
l'attribution et le suivi des tâches, les réunions et décisions, les documents et livrables,
le suivi de l'activité des membres, la connaissance interne d'Astra et l'assistance d'une IA.

L'objectif n'est pas de créer une application de messagerie ou un gestionnaire de tâches :
ASTRA HUB doit devenir **le système opérationnel interne d'Astra**.

IDÉE → DISCUSSION → DÉCISION → PROJET → PLANIFICATION → TÂCHES → EXÉCUTION → VALIDATION →
ARCHIVAGE → CAPITALISATION.

## 2. Application mobile (Flutter)

Interface principale : connexion, chat, projets, création et modification des tâches,
notifications, calendrier, réunions, documents, dashboard personnel, interaction avec l'IA.
Conçue prioritairement pour mobile, rapide et utilisable avec une connexion internet limitée.

## 3. Backend central (FastAPI)

Cœur métier : authentification, autorisations, membres, projets, tâches, conversations,
fichiers, notifications, réunions, décisions, statistiques, historique, IA, API mobile.
Toutes les règles importantes sont contrôlées côté serveur. Un membre ne doit jamais pouvoir
accéder à des données auxquelles son niveau d'autorisation ne lui donne pas accès.

## 4. Gestion des membres

Profil interne : identité, photo, rôle, niveau d'accès, compétences, spécialités, projets et
tâches actuels, disponibilité, historique de participation, statistiques personnelles.
Exemple : *Développeur Full Stack — Flutter, FastAPI, PostgreSQL, DevOps — disponibilité 70 % —
projets MarketCM, Astra Hub — 4 tâches actives.* Ces informations pourront aider l'IA à
répartir le travail.

## 5. Communication interne

Messages individuels, groupes, canaux, discussions par projet, réponses, mentions, réactions,
partage de fichiers, éventuellement messages vocaux. Canaux types : #général, #développement,
#marketing, #design, #direction, #projets, #annonces. Chaque projet possède automatiquement
son espace de discussion.

## 6. Gestion des projets

Un projet contient : nom, description, objectif, responsable, membres, échéance, budget,
statut, priorité, phases, tâches, documents, réunions, décisions, livrables, historique.
Statuts : IDÉE → PLANIFICATION → ACTIF → REVIEW → TERMINÉ → ARCHIVÉ.

## 7. Planification

Le responsable transforme un objectif en plan d'exécution par phases (ex. Analyse, UX/UI,
Backend, Mobile, Tests, Déploiement). Chaque tâche : responsable, priorité, échéance,
dépendances, description, checklist, fichiers, commentaires, statut.

## 8. Gestion quotidienne — « MON TRAVAIL »

Tâches du jour, en retard, prioritaires, prochaines échéances, réunions, messages importants.
Kanban : À FAIRE → EN COURS → REVIEW → TERMINÉ. Historique des changements : qui a fait quoi,
quand, sur quel projet, avec quel résultat.

## 9. Réunions et décisions

Une réunion : participants, date, ordre du jour, documents, compte rendu, décisions, tâches
générées. Une décision peut générer directement un projet et ses phases : une décision devient
immédiatement une action opérationnelle.

## 10. Documents et connaissances

Zone documentaire par projet (cahiers des charges, spécifications, designs, documents
techniques, contrats, comptes rendus, guides, documentation). Les projets terminés deviennent
la mémoire d'Astra : architecture, décisions, problèmes, solutions, livrables, retours
d'expérience — exploitables ensuite par l'IA.

## 11–16. ASTRA AI

Couche au-dessus du système, accessible via un bouton permanent « ASTRA AI ». Elle ne remplace
pas les membres : **l'IA propose, l'humain décide.**

- **Assistant opérationnel** : travaux prioritaires, projets en retard, dépendances, résumés
  de décisions, membres d'un projet, comptes rendus.
- **Planification** : transformer une idée en objectifs, phases, tâches, dépendances,
  livrables, risques, charge, compétences ; validation par le responsable.
- **Répartition du travail** : proposer des attributions selon compétences, disponibilité,
  charge, expérience et échéances.
- **Réunions** : résumé, décisions, questions ouvertes, tâches, responsables, échéances ;
  validation avant enregistrement.
- **Documentation** : recherche conversationnelle dans les décisions, documents,
  conversations et comptes rendus, avec les sources citées.

## 17. IA et sécurité

L'IA respecte les permissions : un membre ayant accès au projet A ne peut pas obtenir via
l'IA les informations confidentielles du projet B.

MEMBRE → AUTHENTIFICATION → AUTORISATIONS → DONNÉES ACCESSIBLES → MOTEUR IA → RÉPONSE

L'IA ne doit jamais être une porte d'accès supplémentaire aux données.

## 18. Intelligence collective

Détection des projets qui ralentissent, tâches bloquées, dépendances critiques, surcharge,
informations manquantes, décisions non exécutées, échéances à risque, problèmes récurrents —
synthétisés dans un « État de santé d'Astra ».

## 19. Dashboard principal

- **Aujourd'hui** : mes tâches, en retard, réunions, messages importants.
- **Astra** : projets actifs, tâches ouvertes, tâches en retard, projets nécessitant attention.
- **IA** : « Que voulez-vous faire ? » — planifier un projet, analyser mon travail, résumer une
  réunion, rechercher dans Astra.

## 20–21. Architecture et stack cible

MEMBRES → COMMUNICATION → DISCUSSIONS → DÉCISIONS → PROJETS → PLANIFICATION → TÂCHES →
EXÉCUTION → REVIEW → LIVRABLES → ARCHIVAGE → CONNAISSANCE → IA → NOUVELLES DÉCISIONS

- Mobile : Flutter. Backend : FastAPI. Base : PostgreSQL.
- IA hybride : modèle externe pour les tâches lourdes, modèle local pour les opérations
  sensibles, couche de recherche documentaire ne récupérant que les informations autorisées.

## 22. Principe fondamental

ASTRA HUB n'est pas « une application où les membres discutent » mais **le système
d'exploitation interne d'Astra**. Chaque information importante doit pouvoir évoluer vers
une action : Discussion → Décision → Projet → Tâches → Travail → Livrable → Connaissance →
IA → aide à la prochaine décision.
