import Wordmark from './Wordmark.jsx'
import { NAV_LINKS } from '../data/content.js'
import { LEGAL_DOCS } from '../data/legal/index.js'
import { CONTACT_EMAIL } from '../config.js'
import { Link } from './Router.jsx'
import './Footer.css'

export default function Footer() {
  return (
    <footer className="site-footer">
      <div className="wrap footer-inner">
        <div className="footer-brand">
          <Wordmark lazy />
          <p className="footer-sign">Construire ce qui manque.</p>
        </div>
        <nav className="footer-nav" aria-label="Pied de page">
          <Link href="/">Accueil</Link>
          {NAV_LINKS.map((link) => <Link key={link.href} href={link.href}>{link.label}</Link>)}
          <Link href="/contact">Contact</Link>
        </nav>
        <div className="footer-meta">
          <p>Astra, agence web et digitale<br />Douala, Cameroun</p>
          <p><a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a></p>
        </div>
      </div>
      <div className="wrap footer-base">
        <p>© <span suppressHydrationWarning>{new Date().getFullYear()}</span> Astra</p>
        <nav className="footer-legal" aria-label="Informations légales">
          {LEGAL_DOCS.map((entry) => <Link key={entry.path} href={entry.path}>{entry.label}</Link>)}
        </nav>
      </div>
    </footer>
  )
}
