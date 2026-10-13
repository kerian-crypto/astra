import { CONTACT_EMAIL } from '../../config.js'
import { LEGAL_UPDATED } from './updated.js'

export const PROJECT_DATA = {
  title: 'Données de vos projets',
  subtitle: 'Nos engagements quand nous concevons, hébergeons ou maintenons une plateforme pour votre entreprise.',
  updated: LEGAL_UPDATED,
  sections: [
    {
      id: 'scope',
      title: 'Qui fait quoi',
      content: [
        'Quand Astra réalise un site, une boutique, une application ou un logiciel pour vous, votre entreprise reste responsable des données de ses propres clients, élèves ou usagers. Astra agit comme prestataire technique : nous traitons ces données uniquement pour exécuter le contrat et selon vos instructions.',
        'Ces engagements complètent votre contrat, qui précise le périmètre exact (hébergement, maintenance, sauvegardes).',
      ],
    },
    {
      id: 'confidentiality',
      title: 'Confidentialité',
      content: [
        'Vos fichiers clients, chiffres, tarifs, stratégies, codes sources et accès restent confidentiels. Seules les personnes qui travaillent sur votre projet y ont accès, et elles sont tenues au secret, y compris après la fin de leur mission.',
      ],
    },
    {
      id: 'security',
      title: 'Sécurité des plateformes livrées',
      content: [
        [
          'HTTPS sur toutes les pages et toutes les API.',
          'Mots de passe hachés avec un algorithme adapté (Argon2 ou bcrypt), jamais stockés en clair.',
          'Protections contre les failles courantes : injections SQL, XSS, CSRF, vol de session.',
          'Comptes d’administration limités au strict nécessaire.',
          'Environnements de test séparés de la production, sans copie de données réelles quand ce n’est pas indispensable.',
        ],
      ],
    },
    {
      id: 'end-users',
      title: 'Les données de vos utilisateurs',
      content: [
        'Nous n’utilisons pas les données de vos utilisateurs pour nous-mêmes : pas d’analyse pour notre compte, pas de revente, pas de croisement avec les données d’autres clients, pas de régie publicitaire.',
        'Par défaut, les plateformes que nous livrons ne déposent que les cookies nécessaires à leur fonctionnement (session, sécurité), avec les attributs HttpOnly, Secure et SameSite. Si vous souhaitez un outil de mesure d’audience ou de publicité, nous ajoutons un bandeau qui permet de refuser aussi facilement que d’accepter.',
      ],
    },
    {
      id: 'payments',
      title: 'Paiements Mobile Money',
      content: [
        'Les paiements passent par les API officielles des opérateurs (MTN Mobile Money, Orange Money) ou d’agrégateurs agréés. Nos plateformes n’enregistrent jamais de code PIN ni de numéro de carte complet ; elles gardent seulement la référence de transaction nécessaire au rapprochement comptable.',
      ],
    },
    {
      id: 'backups',
      title: 'Sauvegardes',
      content: [
        'Lorsque l’hébergement et la maintenance sont inclus au contrat, les bases de données et fichiers sont sauvegardés chaque jour, avec une copie hors du serveur principal. Nous vérifions régulièrement que ces sauvegardes se restaurent réellement.',
      ],
    },
    {
      id: 'incidents',
      title: 'En cas d’incident',
      content: [
        'Si un incident touche la sécurité de votre plateforme ou de vos données, nous vous prévenons dans les 72 heures après l’avoir constaté, avec ce que nous savons : ce qui s’est passé, les données concernées et les mesures prises. Nous vous aidons ensuite à informer vos utilisateurs si c’est nécessaire.',
      ],
    },
    {
      id: 'reversibility',
      title: 'Fin de contrat',
      content: [
        'À la fin du contrat, nous vous remettons vos données et, selon le contrat, le code source, dans des formats standards. Nous effaçons ensuite les copies que nous détenons dans les 30 jours, sauf obligation légale de conservation.',
      ],
    },
    {
      id: 'contact',
      title: 'Contact',
      content: [`Pour toute question sur la sécurité d’une plateforme ou pour demander un audit : ${CONTACT_EMAIL}.`],
    },
  ],
}
