import { CONTACT_EMAIL, SITE_HOST } from '../../config.js'
import { LEGAL_UPDATED } from './updated.js'

// Une chaîne = un paragraphe ; un tableau = une liste à puces.
export const PRIVACY_POLICY = {
  title: 'Politique de confidentialité',
  subtitle: `Ce que nous collectons sur le site ${SITE_HOST} et dans l’application Astra Client, pourquoi, et ce que vous pouvez en faire.`,
  updated: LEGAL_UPDATED,
  sections: [
    {
      id: 'controller',
      title: 'Qui est responsable de vos données',
      content: [
        `Astra, agence web et digitale basée à Douala (Cameroun), est responsable des données collectées sur le site ${SITE_HOST} et dans l’application mobile Astra Client (Android et iOS).`,
        `Pour toute question : ${CONTACT_EMAIL}.`,
      ],
    },
    {
      id: 'site-data',
      title: 'Ce que collecte le site',
      content: [
        'Le site ne demande aucun compte. Nous recevons des données seulement si vous nous écrivez :',
        [
          'Formulaire de diagnostic : nom, entreprise, secteur, téléphone ou WhatsApp, e-mail et la description de votre besoin. La demande nous parvient par e-mail.',
          'Journaux de l’hébergeur : adresse IP, date, page demandée et type de navigateur, enregistrés automatiquement par le serveur pour sa sécurité.',
          'Polices de caractères : elles sont chargées depuis les serveurs de Google Fonts, qui reçoivent à cette occasion votre adresse IP et les informations de votre navigateur.',
        ],
        'Le site n’utilise ni cookie, ni outil de mesure d’audience, ni pixel publicitaire.',
      ],
    },
    {
      id: 'app-data',
      title: 'Ce que collecte l’application Astra Client',
      content: [
        'Astra Client permet aux entreprises clientes de suivre leurs projets avec Astra. Pour fonctionner, elle traite :',
        [
          'Votre compte : nom complet, adresse e-mail, téléphone, fonction et mot de passe (conservé uniquement sous forme chiffrée irréversible).',
          'Votre entreprise : nom, pays ou adresse, site web, secteur et logo.',
          'Ce que vous envoyez : messages et pièces jointes, demandes d’assistance, réponses au questionnaire de cadrage d’un projet, validations ou demandes de modification sur les livrables.',
          'Vos paiements déclarés : montant, date, moyen de paiement, référence et justificatif que vous joignez. L’application n’encaisse rien et ne demande jamais de code PIN Mobile Money ni de numéro de carte.',
          'Données techniques : jeton de notification de votre appareil et son système (Android ou iOS), date de dernière connexion, historique des actions effectuées sur le compte, et journaux du serveur (adresse IP, date, requête) utilisés pour la sécurité et la limitation des tentatives de connexion.',
        ],
        'L’application n’accède ni à votre position, ni à vos contacts, ni à votre micro. Elle n’ouvre vos photos et fichiers que lorsque vous choisissez vous-même un document à joindre. Elle ne contient aucune publicité ni aucun outil de mesure d’audience.',
      ],
    },
    {
      id: 'purposes',
      title: 'Pourquoi nous les utilisons',
      content: [
        [
          'Fournir le service : vous connecter, afficher vos projets, documents et factures, acheminer vos messages et vous notifier des nouveautés. C’est l’exécution du service que vous utilisez.',
          'Répondre à une demande de diagnostic ou à une inscription : vous recontacter pour comprendre votre besoin, à votre demande.',
          'Protéger les comptes et le service : détecter les connexions suspectes, limiter les tentatives répétées, enquêter sur un incident. C’est notre intérêt légitime.',
          'Respecter nos obligations : conserver les factures et les pièces comptables.',
        ],
        'Nous ne faisons aucun profilage publicitaire et aucune décision automatisée ayant un effet sur vous.',
      ],
    },
    {
      id: 'sharing',
      title: 'Qui y a accès',
      content: [
        [
          'Les membres de l’équipe Astra qui travaillent sur votre projet ou gèrent la relation avec votre entreprise.',
          'Les autres comptes de votre entreprise, selon les droits que votre entreprise leur a donnés. Les données d’une entreprise ne sont jamais visibles par une autre.',
          'Amazon Web Services, qui héberge le serveur et la base de données de l’application, dans sa région de Paris (France).',
          'Google Firebase Cloud Messaging, qui achemine les notifications : il reçoit le jeton de votre appareil ainsi que le titre et le texte de la notification.',
          'L’hébergeur du site, pour ses journaux techniques.',
        ],
        'Ces prestataires agissent pour notre compte et n’utilisent pas vos données à leurs propres fins. Nous ne vendons, ne louons et ne cédons vos données à personne. Nous ne les communiquons à une autorité que si la loi nous y oblige.',
      ],
    },
    {
      id: 'retention',
      title: 'Combien de temps nous les gardons',
      content: [
        [
          'Compte et contenus de l’application : tant que le compte est actif. Après suppression du compte, ils sont effacés sous 30 jours, sauf ce qui suit.',
          'Factures, déclarations de paiement et justificatifs : 10 ans, durée de conservation des pièces comptables imposée par le droit OHADA.',
          'Demandes de diagnostic et inscriptions qui n’aboutissent pas à un projet : 3 ans après notre dernier échange.',
          'Sessions de connexion : elles expirent d’elles-mêmes au bout de 30 jours au plus.',
          'Journaux techniques du serveur : 12 mois au plus.',
        ],
      ],
    },
    {
      id: 'security',
      title: 'Comment nous les protégeons',
      content: [
        [
          'Toutes les communications entre l’application, le site et nos serveurs sont chiffrées (HTTPS).',
          'Les mots de passe sont hachés avec Argon2 ; personne chez Astra ne peut les lire.',
          'Les sessions sont courtes, renouvelées automatiquement et révocables ; un compte désactivé perd immédiatement l’accès.',
          'Le disque du serveur est chiffré et les accès d’administration sont réservés à quelques personnes.',
          'Sur votre téléphone, la session est conservée dans le stockage sécurisé du système (Keystore Android, trousseau iOS).',
        ],
      ],
    },
    {
      id: 'rights',
      title: 'Vos droits',
      content: [
        'Vous pouvez à tout moment :',
        [
          'consulter et corriger vos informations de profil directement dans l’application (onglet Profil) ;',
          'obtenir une copie de vos données ;',
          'supprimer votre compte depuis l’application (Plus › Sécurité › Supprimer mon compte) ou faire effacer vos données (voir la page « Suppression de compte ») ;',
          'vous opposer à un traitement ou en demander la limitation ;',
          'désactiver les notifications dans les réglages de votre téléphone.',
        ],
        `Écrivez-nous à ${CONTACT_EMAIL} depuis l’adresse liée à votre compte. Nous répondons sous 30 jours au plus.`,
        'Ces droits découlent de la loi camerounaise n° 2024/017 du 23 décembre 2024 relative à la protection des données à caractère personnel et, pour les personnes situées dans l’Union européenne, du RGPD. Vous pouvez aussi saisir l’autorité de protection des données de votre pays.',
      ],
    },
    {
      id: 'minors',
      title: 'Mineurs',
      content: [
        'Astra Client est un outil professionnel destiné aux entreprises. Il ne s’adresse pas aux personnes de moins de 18 ans.',
      ],
    },
    {
      id: 'changes',
      title: 'Modifications',
      content: [
        'Nous mettrons cette page à jour si nos pratiques changent, en modifiant la date indiquée en haut. Si un changement modifie sensiblement l’usage de vos données, nous vous en informerons dans l’application avant qu’il ne s’applique.',
      ],
    },
  ],
}
