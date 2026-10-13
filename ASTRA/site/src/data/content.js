const NB = ' '

export const NAV_LINKS = [
  { href: '/expertises', label: 'Expertises' },
  { href: '/offres', label: 'Offres' },
  { href: '/methode', label: 'Méthode' },
  { href: '/vision', label: 'Vision' },
  { href: '/faq', label: 'Questions' },
  { href: '/clients', label: 'Espace clients' },
]

export const REALITIES = [
  {
    constraint: 'Vos clients paient avec MTN MoMo et Orange Money.',
    answer: 'Nous intégrons ces paiements directement à vos sites, boutiques et portails d’inscription.',
  },
  {
    constraint: 'Ils écrivent sur WhatsApp avant d’écrire un e-mail.',
    answer: 'Commandes, relances et notifications arrivent là où ils répondent vraiment.',
  },
  {
    constraint: 'La connexion n’est pas toujours stable.',
    answer: 'Des pages légères, pensées pour le mobile, qui restent utilisables quand le réseau faiblit.',
  },
  {
    constraint: 'Le français, l’anglais et d’autres langues coexistent.',
    answer: 'Sites bilingues et interfaces écrites pour être comprises du premier coup.',
  },
  {
    constraint: 'Les comptes professionnels piratés sont fréquents.',
    answer: 'Accès sécurisés, sauvegardes et équipes formées à reconnaître les tentatives de fraude.',
  },
]

export const SKILLS = [
  {
    title: 'Produits numériques',
    text: 'Sites internet, plateformes et applications mobiles, simples à prendre en main et entretenus après la mise en ligne.',
    tags: ['Sites vitrines', 'E-commerce', 'Portails', 'Applications mobiles'],
  },
  {
    title: 'Branding et marketing digital',
    text: 'Logo, charte graphique, contenus, réseaux sociaux et référencement local, pour que l’on comprenne vite ce que vous faites.',
    tags: ['Identité visuelle', 'SEO local', 'Community management', 'LinkedIn B2B'],
  },
  {
    title: 'Cybersécurité',
    text: 'Audit, sécurisation des accès, sauvegardes, protection des données clients, formation anti-phishing. Un métier encore rare à Douala.',
    tags: ['Audit', 'Tests d’intrusion', 'Chiffrement', 'Formation des équipes'],
  },
  {
    title: 'Données et automatisation',
    text: 'Tableaux de bord, CRM, relances automatiques, facturation digitale. Ce qui vit aujourd’hui dans des cahiers et des fichiers Excel devient consultable et à jour.',
    tags: ['CRM', 'Gestion de stock', 'Facturation', 'Tableaux de bord'],
  },
  {
    title: 'Intelligence artificielle',
    text: 'Automatiser des tâches, exploiter vos données, créer des assistants conversationnels. En tenant compte des langues et des usages locaux, que les outils courants gèrent mal.',
    tags: ['Assistants', 'Traitement de documents', 'Analyse de données'],
  },
  {
    title: 'Infrastructure',
    text: 'Architectures, API, bases de données, hébergement cloud et supervision des services en production.',
    tags: ['API', 'Cloud', 'Bases de données', 'Supervision'],
  },
]

export const SECTORS = [
  {
    id: 'edu',
    tab: 'Éducation et formation',
    title: 'Écoles, instituts et centres de formation',
    problem: 'Inscriptions au guichet, paiements à relancer, absences et bulletins sur papier, rentrée à remplir chaque année.',
    tiers: [
      {
        name: 'Visibilité',
        items: [
          'Logo et charte graphique de l’établissement',
          `Site vitrine${NB}: filières, équipe, contact`,
          'Fiche Google Business et réseaux sociaux configurés',
          'Une campagne de rentrée scolaire, visuels et publications',
        ],
      },
      {
        name: 'Gestion',
        items: [
          'Tout le palier 1',
          'Portail d’inscription en ligne',
          'Paiement MTN MoMo et Orange Money',
          `Espace parents et élèves${NB}: résultats, absences, annonces`,
          'Notifications SMS et WhatsApp automatiques',
        ],
      },
      {
        name: 'École digitale complète',
        items: [
          'Tout le palier 2',
          `Plateforme e-learning${NB}: cours, devoirs, notes`,
          'Suivi des familles intéressées et relances automatiques',
          'Bulletins et certificats générés automatiquement',
          `Tableau de bord de direction${NB}: effectifs, paiements, résultats`,
        ],
        monthly: 'maintenance et support',
      },
    ],
  },
  {
    id: 'pro',
    tab: 'Services professionnels',
    title: 'Cabinets, conseils et PME de services',
    problem: 'Des clients qui viennent surtout par le bouche-à-oreille, des prospects oubliés faute de suivi, une administration qui mange le temps facturable.',
    tiers: [
      {
        name: 'Image pro',
        items: [
          `Identité visuelle${NB}: logo, charte, signature e-mail`,
          'Site vitrine qui présente votre expertise et vos références',
          'Page LinkedIn optimisée et conseils de prise de parole',
        ],
      },
      {
        name: 'Acquisition',
        items: [
          'Tout le palier 1',
          'CRM simple pour suivre prospects et clients',
          'Formulaire qui qualifie les demandes et relance automatiquement',
          `Contenus B2B${NB}: articles, LinkedIn, newsletter mensuelle`,
        ],
        monthly: 'contenus et suivi',
      },
      {
        name: 'Cabinet digital',
        items: [
          'Tout le palier 2',
          'Facturation digitale et suivi des dossiers clients',
          'Automatisation des tâches administratives récurrentes',
          `Tableau de bord${NB}: dossiers en cours, chiffre d’affaires, pipeline`,
        ],
      },
    ],
  },
  {
    id: 'com',
    tab: 'Commerce et distribution',
    title: 'Boutiques, grossistes et distributeurs',
    problem: 'Une page Facebook pour toute vitrine, des stocks tenus au cahier, des commandes éparpillées dans WhatsApp, des clients qu’on ne relance jamais.',
    tiers: [
      {
        name: 'Vitrine',
        items: [
          'Logo et identité visuelle',
          'Site vitrine avec catalogue produits',
          'Réseaux sociaux configurés et un mois de community management',
        ],
      },
      {
        name: 'Boutique en ligne',
        items: [
          'Tout le palier 1',
          'E-commerce avec paiement Mobile Money intégré',
          'Gestion de stock simple depuis un back-office',
          'Commandes reliées à WhatsApp Business',
        ],
      },
      {
        name: 'Distributeur digital',
        items: [
          'Tout le palier 2',
          `Gestion commerciale complète${NB}: stocks multi-points, commandes, clients`,
          'Relances clients automatiques par WhatsApp et SMS',
          'Tableau de bord des ventes en temps réel',
        ],
        monthly: 'maintenance',
      },
    ],
  },
  {
    id: 'imm',
    tab: 'Immobilier et BTP',
    title: 'Agences immobilières, promoteurs et entreprises du BTP',
    problem: 'Des réalisations que personne ne voit en ligne, des demandes de visite perdues, des devis et des chantiers suivis à la main.',
    tiers: [
      {
        name: 'Visibilité immo',
        items: [
          'Identité visuelle d’agence, de promoteur ou de cabinet',
          'Site portfolio avec galerie de biens et de réalisations',
          'Fiche Google Business et réseaux sociaux',
        ],
      },
      {
        name: 'Acquisition immo',
        items: [
          'Tout le palier 1',
          'CRM des prospects acheteurs et locataires',
          'Demande de devis ou de visite en ligne, avec relance automatique',
          `Référencement local sur des recherches comme «${NB}agence immobilière Douala${NB}»`,
        ],
      },
      {
        name: 'Gestion de projets',
        items: [
          'Tout le palier 2',
          `Suivi des chantiers et des biens${NB}: statut, documents, échéances`,
          'Contrats, plans et devis centralisés',
          'Tableau de bord multi-projets pour la direction',
        ],
      },
    ],
  },
  {
    id: 'log',
    tab: 'Transport et logistique',
    title: 'Transporteurs, transitaires et logisticiens',
    problem: 'Des clients qui appellent pour savoir où en est leur marchandise, une flotte coordonnée par téléphone, des données de fret et de douane mal protégées.',
    tiers: [
      {
        name: 'Visibilité logistique',
        items: [
          'Identité visuelle institutionnelle B2B',
          `Site institutionnel${NB}: services, flotte, zones couvertes, contact`,
        ],
      },
      {
        name: 'Suivi client',
        items: [
          'Tout le palier 1',
          'Suivi des colis et livraisons accessible à vos clients',
          'Notifications automatiques par SMS et WhatsApp',
          'Facturation digitale',
        ],
      },
      {
        name: 'Logistique intégrée',
        items: [
          'Tout le palier 2',
          `Logiciel métier${NB}: affectation de flotte, planification, suivi avancé`,
          'Sécurisation des données de fret, de douane et des accès partenaires',
          `Tableau de bord${NB}: délais, coûts, performance des tournées`,
        ],
        monthly: 'maintenance et sécurité',
      },
    ],
  },
]

// Le palier 2 est mis en avant : le meilleur point de départ pour une PME.
export const FEATURED_TIER_INDEX = 1

export const EXTRAS = [
  {
    title: 'Sécurité et conformité',
    text: 'Audit de cybersécurité, mise aux normes, sécurisation des accès, formation de vos équipes. Pour la finance, la santé, la logistique et les institutions.',
  },
  {
    title: 'Maintenance et marketing continu',
    text: 'Hébergement, mises à jour, sauvegardes, sécurité et community management récurrent, pour tout site déjà en ligne, même s’il n’a pas été réalisé par nous.',
  },
  {
    title: 'Projets sur mesure',
    text: `Santé, hôtellerie, agro-industrie, microfinance, ONG${NB}: application, outil interne et accompagnement marketing, construits autour de votre métier.`,
  },
]

export const STATIONS = [
  { title: 'Problème', text: 'Nous observons comment vous travaillez, vendez et encaissez, avant de parler technologie.' },
  { title: 'Recherche', text: `Utilisateurs, concurrence, contraintes techniques${NB}: nous vérifions ce qui compte vraiment.` },
  { title: 'Idée', text: 'Une réponse précise, chiffrée, avec un périmètre clair et un palier adapté.' },
  { title: 'Prototype', text: 'Une première version testable, montrée tôt pour corriger tôt.' },
  { title: 'Produit', text: 'Développement, contenus et identité visuelle livrés ensemble, cohérents entre eux.' },
  { title: 'Déploiement', text: 'Mise en ligne, paiements et notifications activés, équipes formées.' },
  { title: 'Amélioration', text: 'Mesures, retours du terrain, ajustements réguliers.' },
  { title: 'Échelle', text: 'Quand l’usage grandit, l’architecture suit sans tout reconstruire.' },
]

export const PRINCIPLES = ['Rapide.', 'Compréhensible.', 'Accessible.', 'Fiable.', 'Flexible.']

export const FAQ = [
  {
    q: `Combien coûte la création d’un site internet à Douala${NB}?`,
    a: 'Le budget dépend de votre secteur, du palier choisi et de la complexité du projet : un site vitrine, une boutique en ligne et une plateforme de gestion ne demandent pas le même travail. Après un premier diagnostic, nous vous remettons une proposition détaillée et chiffrée, adaptée à vos priorités.',
  },
  {
    q: `En quoi Astra est-elle différente d’une agence web classique à Douala${NB}?`,
    a: 'Nous commençons par comprendre le problème à résoudre avant de proposer un outil. Ensuite, la même équipe prend en charge le développement web et mobile, le marketing digital et la cybersécurité, ce qui évite de coordonner plusieurs prestataires.',
  },
  {
    q: `Pouvez-vous intégrer MTN Mobile Money et Orange Money à mon site${NB}?`,
    a: `Oui. Boutiques en ligne, portails d’inscription scolaire, réservations${NB}: le paiement MTN MoMo et Orange Money est intégré dès le palier${NB}2 de nos offres.`,
  },
  {
    q: `Travaillez-vous uniquement à Douala${NB}?`,
    a: 'Astra est une agence digitale basée à Douala qui accompagne des entreprises et des organisations dans tout le Cameroun. Nos sites peuvent être bilingues français et anglais, et nos outils sont conçus pour fonctionner ailleurs en Afrique.',
  },
  {
    q: `Que comprend l’abonnement mensuel${NB}?`,
    a: `Hébergement, mises à jour, sauvegardes, sécurité et support. Selon la formule, il peut inclure la création de contenus et le community management.`,
  },
  {
    q: `Pourquoi une PME devrait-elle investir dans la cybersécurité${NB}?`,
    a: 'Parce que les comptes WhatsApp Business et Facebook piratés, les fichiers clients exposés et les sites défigurés touchent aussi les petites structures. Nous sécurisons les accès, mettons en place des sauvegardes et formons les équipes à reconnaître le phishing.',
  },
  {
    q: `Développez-vous aussi des applications mobiles et des logiciels métier${NB}?`,
    a: `Oui${NB}: applications web et mobiles, CRM, gestion de stock, suivi de chantier, planification de flotte, tableaux de bord. Nous partons du problème à résoudre avant de choisir la technologie.`,
  },
]

export const FORM_SECTORS = [
  ...SECTORS.map((s) => s.tab),
  'Santé',
  'Hôtellerie et restauration',
  'Finance et microfinance',
  'Agro-industrie',
  'ONG et institutions',
  'Autre',
]

export const CLIENT_APP = {
  eyebrow: 'Astra Client',
  title: 'Votre projet, suivi depuis votre téléphone.',
  lead: 'Astra Client relie votre entreprise à l’équipe qui travaille sur votre projet. L’avancement, les documents, les factures et les échanges sont au même endroit, plutôt qu’éparpillés entre WhatsApp, e-mails et appels.',
  features: [
    {
      title: 'Avancement des projets',
      text: 'Le statut de chaque projet, son pourcentage d’avancement et ce qui est attendu de vous, mis à jour par l’équipe au fil du travail.',
    },
    {
      title: 'Messages',
      text: 'Une conversation par projet avec les personnes qui le réalisent, pièces jointes comprises. Une notification vous prévient de chaque réponse.',
    },
    {
      title: 'Documents et livrables',
      text: 'Maquettes, contrats, fichiers livrés : vous les consultez, les téléchargez, puis validez un livrable ou demandez des modifications.',
    },
    {
      title: 'Factures et paiements',
      text: 'Vos factures et leur état. Après un paiement par Mobile Money ou virement, vous le déclarez avec son justificatif ; nous le confirmons.',
    },
    {
      title: 'Assistance',
      text: 'Un problème sur un site ou une application déjà livrés ? Vous ouvrez une demande et suivez son traitement.',
    },
    {
      title: 'Nouveau projet',
      text: 'Un questionnaire guidé pour décrire votre besoin, vos délais et vos références. Il sert de base au cahier des charges.',
    },
  ],
  access: [
    {
      title: 'Vous êtes déjà client',
      text: 'Nous créons le compte de votre entreprise et vous envoyons un lien d’activation pour choisir votre mot de passe. Vous pouvez demander un accès pour chaque collègue concerné.',
    },
    {
      title: 'Vous avez un projet',
      text: 'Créez un compte depuis l’application et décrivez votre besoin avec le questionnaire. Nous vous recontactons pour en parler.',
    },
  ],
  privacyNote: 'Chaque entreprise ne voit que ses propres projets. Les échanges sont chiffrés, et l’application ne contient ni publicité ni outil de suivi.',
}
