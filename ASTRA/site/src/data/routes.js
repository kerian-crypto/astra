import { SITE_URL } from '../config.js'
import { LEGAL_DOCS } from './legal/index.js'

// Source unique des pages : routeur, balises <head>, JSON-LD et sitemap en découlent.
// `kind` : home | section | legal. `schema` : type schema.org de la page.
const PAGES = [
  {
    path: '/',
    kind: 'home',
    schema: 'WebSite',
    title: 'Astra, agence web et digitale à Douala, Cameroun',
    description: 'Création de site web, applications mobiles, Mobile Money et cybersécurité à Douala. Astra, agence digitale au Cameroun, construit des outils qui durent.',
  },
  {
    path: '/expertises',
    kind: 'section',
    title: 'Expertises : du site web à l’infrastructure | Astra',
    description: 'Développement web et mobile, branding, cybersécurité, données, automatisation et intelligence artificielle, à Douala.',
  },
  {
    path: '/offres',
    kind: 'section',
    title: 'Offres par secteur | Astra',
    description: 'Trois paliers par secteur : éducation, services professionnels, commerce, immobilier, transport et logistique.',
  },
  {
    path: '/methode',
    kind: 'section',
    title: 'Notre méthode | Astra',
    description: 'Du problème observé sur le terrain jusqu’à l’outil qui tient la charge : les huit étapes d’un projet Astra.',
  },
  {
    path: '/vision',
    kind: 'section',
    schema: 'AboutPage',
    title: 'Vision | Astra',
    description: 'Pourquoi Astra construit des produits numériques pensés depuis le Cameroun et l’Afrique.',
  },
  {
    path: '/faq',
    kind: 'section',
    title: 'Questions fréquentes | Astra',
    description: 'Prix d’un site web à Douala, Mobile Money, cybersécurité, abonnement : les réponses aux questions qu’on nous pose.',
  },
  {
    path: '/contact',
    kind: 'section',
    schema: 'ContactPage',
    title: 'Contact et diagnostic | Astra',
    description: 'Décrivez votre activité et ce qui vous freine : nous revenons vers vous avec une première lecture de la situation.',
  },
  {
    path: '/clients',
    kind: 'section',
    title: 'Astra Client, l’application de suivi de projet | Astra',
    description: 'Avancement, documents, factures et échanges avec l’équipe Astra, dans une application mobile réservée à nos clients.',
  },
  ...LEGAL_DOCS.map(({ path, doc }) => ({
    path,
    kind: 'legal',
    title: `${doc.title} | Astra`,
    description: doc.subtitle,
  })),
]

export const ROUTES = PAGES.map((page) => ({ schema: 'WebPage', ...page, url: `${SITE_URL}${page.path === '/' ? '/' : page.path}` }))

export const NOT_FOUND = {
  path: '/404',
  title: 'Page introuvable | Astra',
  description: 'Cette page n’existe pas ou a été déplacée.',
}

export function findRoute(path) {
  return ROUTES.find((route) => route.path === path)
}
