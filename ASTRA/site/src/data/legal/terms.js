import { CONTACT_EMAIL, SITE_HOST } from '../../config.js'
import { LEGAL_UPDATED } from './updated.js'

export const TERMS_OF_SERVICE = {
  title: 'Conditions d’utilisation',
  subtitle: `Les règles d’utilisation du site ${SITE_HOST} et de l’application Astra Client.`,
  updated: LEGAL_UPDATED,
  sections: [
    {
      id: 'scope',
      title: 'Objet',
      content: [
        `Ces conditions s’appliquent au site ${SITE_HOST} et à l’application mobile Astra Client. En utilisant l’un ou l’autre, vous les acceptez.`,
        'Les prestations réalisées pour votre entreprise (prix, délais, livrables, propriété du code, maintenance) sont régies par le devis ou le contrat signé avec Astra. En cas de différence, ce document contractuel l’emporte sur les présentes conditions.',
      ],
    },
    {
      id: 'publisher',
      title: 'Éditeur et hébergement',
      content: [
        `Le site et l’application sont édités par Astra, Douala, Cameroun. Contact : ${CONTACT_EMAIL}.`,
        'Le serveur de l’application est hébergé par Amazon Web Services EMEA SARL, 38 avenue John F. Kennedy, L-1855 Luxembourg, dans sa région de Paris (France).',
      ],
    },
    {
      id: 'account',
      title: 'Votre compte',
      content: [
        'Un compte Astra Client est créé soit par Astra, qui vous transmet un lien d’activation pour choisir votre mot de passe, soit par vous-même depuis l’application lorsque vous présentez un nouveau projet.',
        [
          'Vous devez avoir au moins 18 ans et utiliser l’application pour le compte d’une entreprise ou d’une organisation.',
          'Les informations que vous fournissez doivent être exactes.',
          'Vos identifiants sont personnels. Prévenez-nous sans attendre si vous pensez qu’ils ont été compromis.',
          'Ce que chaque compte peut voir ou faire (factures, validation des livrables, gestion des collègues…) dépend des droits attribués par Astra ou par votre entreprise.',
        ],
      ],
    },
    {
      id: 'acceptable-use',
      title: 'Utilisation acceptable',
      content: [
        'Vous vous engagez à ne pas :',
        [
          'tenter d’accéder aux données d’une autre entreprise ou de contourner les droits de votre compte ;',
          'perturber le service, le surcharger par des requêtes automatisées ou chercher à en exploiter les failles ;',
          'envoyer des contenus illicites, trompeurs, injurieux ou dont vous ne détenez pas les droits ;',
          'utiliser le service pour envoyer des fichiers malveillants.',
        ],
        'En cas de manquement grave, Astra peut suspendre le compte concerné, en prévenant l’entreprise cliente dès que possible.',
      ],
    },
    {
      id: 'content',
      title: 'Les contenus que vous envoyez',
      content: [
        'Les messages, fichiers et documents que vous déposez restent la propriété de votre entreprise. Vous autorisez Astra à les stocker et à les traiter dans la seule mesure nécessaire pour mener votre projet et faire fonctionner le service.',
      ],
    },
    {
      id: 'payments',
      title: 'Factures et paiements',
      content: [
        'L’application affiche vos factures et vous permet de déclarer un paiement effectué par ailleurs (Mobile Money, virement, espèces…). Elle ne réalise elle-même aucune transaction.',
        'Une déclaration de paiement n’est prise en compte qu’après vérification et confirmation par Astra. Les frais et la bonne exécution des transferts relèvent de l’opérateur ou de la banque utilisés.',
      ],
    },
    {
      id: 'availability',
      title: 'Disponibilité et mises à jour',
      content: [
        'Nous faisons notre possible pour que le service reste accessible, sans pouvoir garantir une disponibilité permanente : maintenances, pannes de réseau ou incidents chez nos prestataires peuvent l’interrompre. Les maintenances prévues sont annoncées à l’avance quand c’est possible.',
        'Nous publions régulièrement des mises à jour de l’application. Certaines peuvent être nécessaires pour continuer à l’utiliser.',
      ],
    },
    {
      id: 'intellectual-property',
      title: 'Propriété intellectuelle',
      content: [
        'Le site, l’application, leur code, leurs textes et la marque Astra appartiennent à Astra. Vous pouvez les utiliser pour le suivi de vos projets, sans les copier, les modifier ni les redistribuer.',
        'La propriété des livrables réalisés pour votre entreprise est réglée par votre contrat.',
      ],
    },
    {
      id: 'liability',
      title: 'Responsabilité',
      content: [
        'Astra n’est pas responsable des dommages indirects ni de ceux causés par une mauvaise utilisation du compte, par la divulgation de vos identifiants ou par un événement hors de son contrôle (coupure générale du réseau, défaillance d’un opérateur). Rien dans ces conditions ne limite les droits que la loi vous accorde de façon impérative.',
      ],
    },
    {
      id: 'termination',
      title: 'Fin d’utilisation',
      content: [
        'Vous pouvez cesser d’utiliser l’application à tout moment et supprimer votre compte depuis l’application (Plus › Sécurité) ou sur demande (voir la page « Suppression de compte »). Lorsqu’une entreprise cliente est désactivée, les comptes qui lui sont rattachés le sont aussi.',
      ],
    },
    {
      id: 'law-disputes',
      title: 'Droit applicable et litiges',
      content: [
        'Ces conditions sont soumises au droit camerounais. En cas de désaccord, nous cherchons d’abord une solution amiable ; à défaut dans les 30 jours, les tribunaux de Douala sont compétents.',
        'Nous pouvons faire évoluer ces conditions ; la date en haut de page indique la version en vigueur. Les changements importants vous sont signalés dans l’application.',
      ],
    },
  ],
}
