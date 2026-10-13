import { CONTACT_EMAIL } from '../../config.js'
import { LEGAL_UPDATED } from './updated.js'

export const ACCOUNT_DELETION = {
  title: 'Suppression de compte',
  subtitle: 'Comment supprimer votre compte Astra Client et ce qu’il advient de vos données.',
  updated: LEGAL_UPDATED,
  sections: [
    {
      id: 'request',
      title: 'Demander la suppression',
      content: [
        'Depuis l’application : ouvrez l’onglet Plus, puis Sécurité, et touchez « Supprimer mon compte ». Confirmez avec votre mot de passe : la suppression est immédiate et vous êtes déconnecté de tous vos appareils.',
        `Sans accès à l’application : envoyez un e-mail à ${CONTACT_EMAIL} depuis l’adresse liée à votre compte, avec pour objet « Suppression de compte Astra Client », en précisant le nom de votre entreprise. Si vous n’avez plus accès à cette adresse, dites-le : nous vérifierons votre identité autrement, par exemple auprès d’un responsable de votre entreprise. Nous confirmons la suppression par e-mail sous 30 jours au plus.`,
      ],
    },
    {
      id: 'deleted',
      title: 'Ce qui est supprimé',
      content: [
        [
          'Votre profil : nom, e-mail, téléphone et fonction.',
          'Votre mot de passe, vos sessions et les jetons de notification de vos appareils.',
          'Vos notifications et l’historique des modifications de votre profil. Dans l’historique des projets, votre nom est remplacé par « Compte supprimé ».',
          'Si vous étiez le seul compte de votre entreprise et qu’aucun contrat n’est en cours : l’entreprise elle-même, avec ses questionnaires de cadrage, messages et documents.',
        ],
      ],
    },
    {
      id: 'kept',
      title: 'Ce qui est conservé, et pourquoi',
      content: [
        [
          'Factures, déclarations de paiement et justificatifs : 10 ans, au titre des obligations comptables (droit OHADA).',
          'Messages et documents échangés dans le cadre d’un projet en cours : ils font partie du dossier de votre entreprise et restent accessibles à ses autres comptes. Vous pouvez demander leur suppression ; nous l’effectuons dès qu’ils ne sont plus nécessaires au contrat.',
          'Journaux techniques du serveur : 12 mois au plus, pour la sécurité.',
        ],
        'Si des copies de sauvegarde contiennent encore ces données, elles ne sont plus utilisées et sont écrasées lors du renouvellement des sauvegardes.',
      ],
    },
    {
      id: 'partial',
      title: 'Supprimer seulement certaines données',
      content: [
        'Vous pouvez modifier vos informations de profil à tout moment dans l’application (onglet Profil). Pour faire effacer une donnée précise sans supprimer votre compte, écrivez-nous à la même adresse en indiquant ce que vous souhaitez voir supprimé.',
      ],
    },
  ],
}
