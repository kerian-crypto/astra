import test from 'node:test'
import assert from 'node:assert/strict'
import { CLIENT_APP, NAV_LINKS } from '../src/data/content.js'
import { ROUTES, findRoute } from '../src/data/routes.js'
import { LEGAL_DOCS, PRIVACY_POLICY, ACCOUNT_DELETION } from '../src/data/legal/index.js'
import { buildJsonLd } from '../src/data/jsonLd.js'
import { CONTACT_EMAIL, SITE_URL } from '../src/config.js'

const textOf = (doc) => doc.sections.flatMap((s) => s.content.flat()).join('\n')

test('chaque route est unique, titrée, décrite et sur le domaine du site', () => {
  const paths = ROUTES.map((r) => r.path)
  assert.strictEqual(new Set(paths).size, paths.length)
  for (const route of ROUTES) {
    assert.ok(route.title && route.description, `${route.path} sans titre ou description`)
    assert.ok(route.url.startsWith(SITE_URL), `${route.path} hors domaine`)
  }
})

test('les liens de navigation et les pages légales pointent vers des routes existantes', () => {
  for (const { href } of NAV_LINKS) assert.ok(findRoute(href), `${href} absent des routes`)
  for (const { path } of LEGAL_DOCS) assert.ok(findRoute(path), `${path} absent des routes`)
})

test('les pages légales ont des sections identifiées de façon unique et une date', () => {
  for (const { path, doc } of LEGAL_DOCS) {
    assert.ok(doc.updated, `${path} sans date`)
    const ids = doc.sections.map((s) => s.id)
    assert.strictEqual(new Set(ids).size, ids.length, `${path} : ids de sections en double`)
    for (const section of doc.sections) assert.ok(section.content.length > 0, `${path}#${section.id} vide`)
  }
})

test('la politique de confidentialité couvre ce que Google Play exige', () => {
  const ids = PRIVACY_POLICY.sections.map((s) => s.id)
  for (const id of ['controller', 'app-data', 'purposes', 'sharing', 'retention', 'security', 'rights']) {
    assert.ok(ids.includes(id), `section ${id} manquante`)
  }
  const text = textOf(PRIVACY_POLICY)
  assert.match(text, /Astra Client/)
  assert.ok(text.includes(CONTACT_EMAIL), 'contact absent')
  assert.match(text, /Firebase/, 'le prestataire de notifications doit être nommé')
})

test('la page de suppression de compte explique la démarche, le supprimé et le conservé', () => {
  const ids = ACCOUNT_DELETION.sections.map((s) => s.id)
  assert.deepStrictEqual(ids.slice(0, 3), ['request', 'deleted', 'kept'])
  assert.ok(textOf(ACCOUNT_DELETION).includes(CONTACT_EMAIL))
})

test('la page Astra Client décrit les fonctions et l’accès', () => {
  assert.ok(CLIENT_APP.features.length >= 4)
  assert.ok(CLIENT_APP.access.length >= 1)
})

test('buildJsonLd donne un nœud de page par route', () => {
  for (const route of ROUTES) {
    const types = buildJsonLd(route.path)['@graph'].map((n) => n['@type'])
    assert.ok(types.includes('ProfessionalService'))
    assert.ok(types.includes(route.schema), `${route.path} : ${route.schema} attendu`)
  }
  assert.ok(buildJsonLd('/')['@graph'].some((n) => n['@type'] === 'FAQPage'))
  assert.ok(buildJsonLd('/faq')['@graph'].some((n) => n['@type'] === 'FAQPage'))
})
