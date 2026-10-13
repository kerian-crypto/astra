import { Link } from './Router.jsx'
import { LEGAL_DOCS } from '../data/legal/index.js'
import { CONTACT_EMAIL } from '../config.js'
import './LegalPage.css'

// Un bloc de contenu est un paragraphe (chaîne) ou une liste (tableau de chaînes).
function Block({ block }) {
  if (Array.isArray(block)) {
    return (
      <ul className="legal-list">
        {block.map((item) => <li key={item}>{item}</li>)}
      </ul>
    )
  }
  return <p>{block}</p>
}

export default function LegalPage({ doc, path }) {
  return (
    <article className="legal-page">
      <div className="wrap legal-wrap">
        <nav className="legal-topbar" aria-label="Informations légales">
          <div className="legal-switcher">
            {LEGAL_DOCS.map((entry) => (
              <Link
                key={entry.path}
                href={entry.path}
                className={entry.path === path ? 'legal-switch-btn is-active' : 'legal-switch-btn'}
                aria-current={entry.path === path ? 'page' : undefined}
              >
                {entry.label}
              </Link>
            ))}
          </div>
        </nav>

        <header className="legal-header">
          <p className="eyebrow">Informations légales</p>
          <h1 className="legal-title">{doc.title}</h1>
          <p className="lead legal-subtitle">{doc.subtitle}</p>
          <p className="legal-date">{doc.updated}</p>
        </header>

        <nav className="legal-toc" aria-label="Sommaire">
          <h2 className="toc-title">Sommaire</h2>
          <ol className="toc-list">
            {doc.sections.map((section) => (
              <li key={section.id}><a href={`#${section.id}`}>{section.title}</a></li>
            ))}
          </ol>
        </nav>

        <div className="legal-content">
          {doc.sections.map((section, index) => (
            <section key={section.id} id={section.id} className="legal-section">
              <h2 className="section-heading">{index + 1}. {section.title}</h2>
              <div className="section-body">
                {section.content.map((block, blockIndex) => <Block key={blockIndex} block={block} />)}
              </div>
            </section>
          ))}
        </div>

        <aside className="legal-footer-box">
          <div className="legal-contact-callout">
            <h2 className="callout-title">Une question sur vos données ?</h2>
            <p className="callout-text">Écrivez-nous, nous répondons sous 30 jours au plus.</p>
            <a className="btn btn-ghost btn-small" href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>
          </div>
        </aside>
      </div>
    </article>
  )
}
