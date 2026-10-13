import { SITE_HOST } from '../../config.js'
import { LEGAL_UPDATED } from './updated.js'

export const COOKIE_POLICY = {
  title: 'Cookies et traceurs',
  subtitle: `Ce que le site ${SITE_HOST} et l’application Astra Client enregistrent sur votre appareil.`,
  updated: LEGAL_UPDATED,
  sections: [
    {
      id: 'definition',
      title: 'De quoi parle-t-on',
      content: [
        'Un cookie est un petit fichier qu’un site enregistre dans votre navigateur. D’autres techniques jouent le même rôle : stockage local du navigateur, identifiants publicitaires du téléphone, pixels de suivi. Cette page couvre l’ensemble.',
      ],
    },
    {
      id: 'site',
      title: 'Sur le site',
      content: [
        'Le site ne dépose aucun cookie et n’enregistre rien dans le stockage de votre navigateur. Il n’intègre ni outil de mesure d’audience, ni pixel de réseau social, ni publicité.',
        'Seule exception à signaler : les polices de caractères sont chargées depuis Google Fonts. Cela ne dépose pas de cookie, mais Google reçoit votre adresse IP au moment du chargement.',
        'C’est pourquoi aucun bandeau ne vous demande votre consentement : il n’y a rien à accepter.',
      ],
    },
    {
      id: 'app',
      title: 'Dans l’application Astra Client',
      content: [
        [
          'Aucun cookie, aucun identifiant publicitaire, aucun outil de mesure d’audience.',
          'Vos jetons de session sont gardés dans le stockage sécurisé du téléphone, pour que vous restiez connecté. Ils sont effacés quand vous vous déconnectez.',
          'Les documents que vous ouvrez sont copiés dans le cache privé de l’application pour pouvoir les afficher. Le système peut vider ce cache à tout moment ; il est effacé quand vous désinstallez l’application.',
        ],
      ],
    },
    {
      id: 'changes',
      title: 'Si cela change',
      content: [
        'Si nous ajoutions un jour un outil qui nécessite votre accord, cette page serait mise à jour et votre consentement vous serait demandé avant tout dépôt, avec la possibilité de refuser aussi simplement que d’accepter.',
      ],
    },
    {
      id: 'browser-management',
      title: 'Gérer les cookies dans votre navigateur',
      content: [
        'Vous pouvez à tout moment bloquer ou effacer les cookies depuis les réglages de votre navigateur :',
        [
          'Chrome : Paramètres › Confidentialité et sécurité › Cookies tiers.',
          'Firefox : Paramètres › Vie privée et sécurité › Cookies et données de sites.',
          'Safari (iPhone) : Réglages › Safari › Avancé.',
          'Edge : Paramètres › Cookies et autorisations de site.',
        ],
      ],
    },
  ],
}
