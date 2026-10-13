// Pré-rend chaque route de src/data/routes.js dans dist/, avec ses balises <head>,
// ses données structurées, puis génère sitemap.xml, robots.txt et 404.html.
import { readFile, writeFile, mkdir, rm } from 'node:fs/promises'
import { fileURLToPath, pathToFileURL } from 'node:url'
import path from 'node:path'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const distDir = path.join(root, 'dist')
const templatePath = path.join(distDir, 'index.html')
const ssrDir = path.join(root, 'dist-ssr')

const SITEMAP_PRIORITY = { home: '1.0', section: '0.8', legal: '0.4' }

function escapeAttr(value) {
  return value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;')
}

function setHead(html, { title, description, url, noindex }) {
  const t = escapeAttr(title)
  const d = escapeAttr(description)
  let out = html
    .replace(/<title>[^<]*<\/title>/, `<title>${t}</title>`)
    .replace(/(<meta (?:name="description"|property="og:description"|name="twitter:description") content=")[^"]*"/g, `$1${d}"`)
    .replace(/(<meta (?:property="og:title"|name="twitter:title") content=")[^"]*"/g, `$1${t}"`)
  if (url) {
    out = out
      .replace(/<link rel="canonical" href="[^"]*"/, `<link rel="canonical" href="${url}"`)
      .replace(/<meta property="og:url" content="[^"]*"/, `<meta property="og:url" content="${url}"`)
  } else {
    out = out.replace(/\s*<link rel="canonical"[^>]*>/, '').replace(/\s*<meta property="og:url"[^>]*>/, '')
  }
  if (noindex) {
    out = out.replace(/<meta name="robots" content="[^"]*"/, '<meta name="robots" content="noindex"')
  }
  return out
}

function sitemap(routes, today) {
  const urls = routes.map((route) => [
    '  <url>',
    `    <loc>${route.url}</loc>`,
    `    <lastmod>${today}</lastmod>`,
    `    <priority>${SITEMAP_PRIORITY[route.kind]}</priority>`,
    '  </url>',
  ].join('\n'))
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join('\n')}\n</urlset>\n`
}

async function prerender() {
  const template = await readFile(templatePath, 'utf8')
  if (!template.includes('<!--app-html-->') || !template.includes('<!--json-ld-->')) {
    throw new Error('Marqueurs <!--app-html--> ou <!--json-ld--> introuvables dans dist/index.html')
  }
  const { render, jsonLd, ROUTES, NOT_FOUND, SITE_URL } = await import(
    pathToFileURL(path.join(ssrDir, 'entry-server.js')).href
  )

  const pages = [
    ...ROUTES.map((route) => ({ ...route, dest: route.path === '/' ? 'index.html' : `${route.path.slice(1)}/index.html` })),
    { ...NOT_FOUND, dest: '404.html', noindex: true },
  ]

  for (const page of pages) {
    const ld = page.noindex ? '' : `<script type="application/ld+json">${JSON.stringify(jsonLd(page.path)).replace(/</g, '\\u003c')}</script>`
    const html = setHead(template, page).replace('<!--app-html-->', render(page.path)).replace('<!--json-ld-->', ld)
    const destPath = path.join(distDir, page.dest)
    await mkdir(path.dirname(destPath), { recursive: true })
    await writeFile(destPath, html)
    console.log(`Pré-rendu ${page.path} -> dist/${page.dest}`)
  }

  const today = new Date().toISOString().slice(0, 10)
  await writeFile(path.join(distDir, 'sitemap.xml'), sitemap(ROUTES, today))
  await writeFile(path.join(distDir, 'robots.txt'), `User-agent: *\nAllow: /\n\nSitemap: ${SITE_URL}/sitemap.xml\n`)

  await rm(ssrDir, { recursive: true, force: true })
  console.log(`${pages.length} pages, sitemap.xml et robots.txt générés.`)
}

prerender().catch((error) => {
  console.error('Échec du pré-rendu :', error)
  process.exit(1)
})
