import { SITE_URL, CONTACT_EMAIL } from '../config.js'
import { SECTORS, EXTRAS, FAQ } from './content.js'
import { findRoute } from './routes.js'

const ORG_ID = `${SITE_URL}/#organisation`

function serviceOffer(name, category) {
  return {
    '@type': 'Offer',
    itemOffered: { '@type': 'Service', name, ...(category ? { category } : {}) },
  }
}

function catalogOffers() {
  const sectorOffers = SECTORS.flatMap((sector) =>
    sector.tiers.map((tier) => serviceOffer(`${tier.name}, ${sector.tab.toLowerCase()}`, sector.tab)),
  )
  const extraOffers = EXTRAS.map((extra) => serviceOffer(extra.title))
  return [...sectorOffers, ...extraOffers]
}

export function buildJsonLd(url = '/') {
  const baseGraph = [
    {
      '@type': 'ProfessionalService',
      '@id': ORG_ID,
      name: 'Astra',
      url: `${SITE_URL}/`,
      logo: `${SITE_URL}/assets/icon-512.png`,
      image: `${SITE_URL}/assets/og-astra.jpg`,
      slogan: 'Construire ce qui manque.',
      description:
        'Agence web et digitale basée à Douala, Cameroun : création de sites internet, développement d’applications mobiles, intégration Mobile Money, marketing digital, branding, données, intelligence artificielle et cybersécurité.',
      email: CONTACT_EMAIL,
      address: {
        '@type': 'PostalAddress',
        addressLocality: 'Douala',
        addressRegion: 'Littoral',
        addressCountry: 'CM',
      },
      areaServed: [
        { '@type': 'City', name: 'Douala' },
        { '@type': 'Country', name: 'Cameroun' },
      ],
      knowsAbout: [
        'Création de site web',
        'Création de site internet',
        'Développement web',
        'Marketing digital',
        'Développement d’applications mobiles',
        'Intégration Mobile Money',
        'Cybersécurité',
        'Intelligence artificielle',
        'Branding',
        'SEO local',
        'CRM',
        'E-commerce',
      ],
      hasOfferCatalog: {
        '@type': 'OfferCatalog',
        name: 'Offres Astra par secteur',
        itemListElement: catalogOffers(),
      },
    },
  ]

  const route = findRoute(url)
  if (route) baseGraph.push(pageNode(route))
  if (url === '/' || url === '/faq') baseGraph.push(faqPage())

  return {
    '@context': 'https://schema.org',
    '@graph': baseGraph,
  }
}

function faqPage() {
  return {
    '@type': 'FAQPage',
    mainEntity: FAQ.map(({ q, a }) => ({
      '@type': 'Question',
      name: q,
      acceptedAnswer: { '@type': 'Answer', text: a },
    })),
  }
}

function pageNode(route) {
  if (route.schema === 'WebSite') {
    return {
      '@type': 'WebSite',
      '@id': `${SITE_URL}/#site`,
      url: route.url,
      name: 'Astra',
      inLanguage: 'fr-CM',
      publisher: { '@id': ORG_ID },
    }
  }
  return {
    '@type': route.schema,
    '@id': `${route.url}#page`,
    url: route.url,
    name: route.title,
    description: route.description,
    isPartOf: { '@id': `${SITE_URL}/#site` },
  }
}
