import { StrictMode } from 'react'
import { renderToString } from 'react-dom/server'
import App from './App.jsx'
import { buildJsonLd } from './data/jsonLd.js'

export { ROUTES, NOT_FOUND } from './data/routes.js'
export { SITE_URL } from './config.js'

export function render(url = '/') {
  return renderToString(
    <StrictMode>
      <App initialPath={url} />
    </StrictMode>,
  )
}

export function jsonLd(url = '/') {
  return buildJsonLd(url)
}
