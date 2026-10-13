import { PRIVACY_POLICY } from './privacy.js'
import { TERMS_OF_SERVICE } from './terms.js'
import { COOKIE_POLICY } from './cookies.js'
import { ACCOUNT_DELETION } from './accountDeletion.js'
import { PROJECT_DATA } from './projectData.js'

export { PRIVACY_POLICY, TERMS_OF_SERVICE, COOKIE_POLICY, ACCOUNT_DELETION, PROJECT_DATA }

// Ordre d'affichage dans le pied de page et la barre des pages légales.
export const LEGAL_DOCS = [
  { path: '/confidentialite', label: 'Confidentialité', doc: PRIVACY_POLICY },
  { path: '/conditions', label: 'Conditions d’utilisation', doc: TERMS_OF_SERVICE },
  { path: '/cookies', label: 'Cookies', doc: COOKIE_POLICY },
  { path: '/suppression-compte', label: 'Suppression de compte', doc: ACCOUNT_DELETION },
  { path: '/confidentialite-clients', label: 'Données de vos projets', doc: PROJECT_DATA },
]

export function findLegalDoc(path) {
  return LEGAL_DOCS.find((entry) => entry.path === path)
}
