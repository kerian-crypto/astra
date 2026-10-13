import { CLIENT_APP } from '../data/content.js'
import { CONTACT_EMAIL, PLAY_STORE_URL } from '../config.js'
import { Link } from './Router.jsx'
import './ClientSpace.css'

export default function ClientSpace() {
  return (
    <div className="client-space-page">
      <section className="section client-hero" aria-labelledby="client-title">
        <div className="wrap">
          <div className="client-hero-content">
            <p className="eyebrow">{CLIENT_APP.eyebrow}</p>
            <h1 className="client-hero-title" id="client-title">{CLIENT_APP.title}</h1>
            <p className="lead client-hero-lead">{CLIENT_APP.lead}</p>
            <div className="cta-actions">
              <a className="btn" href={PLAY_STORE_URL} rel="noopener">Télécharger sur Google Play</a>
              <Link className="btn btn-ghost" href="/contact">Demander un accès</Link>
            </div>
          </div>
        </div>
      </section>

      <section className="section client-pillars-section" aria-labelledby="client-features-title">
        <div className="wrap">
          <div className="section-head client-pillars-head">
            <p className="eyebrow">Dans l’application</p>
            <h2 className="section-title" id="client-features-title">Ce que vous y trouvez</h2>
          </div>
          <div className="client-pillars-grid">
            {CLIENT_APP.features.map((feature, index) => (
              <article key={feature.title} className="client-pillar-card">
                <p className="pillar-tag">{String(index + 1).padStart(2, '0')}</p>
                <h3 className="pillar-title">{feature.title}</h3>
                <p className="pillar-summary">{feature.text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section client-notice-section" aria-labelledby="client-access-title">
        <div className="wrap">
          <div className="client-notice-card">
            <div className="notice-body">
              <p className="eyebrow">Accès</p>
              <h2 className="notice-title" id="client-access-title">Comment obtenir un compte</h2>
              {CLIENT_APP.access.map((item) => (
                <div key={item.title}>
                  <h3 className="pillar-title">{item.title}</h3>
                  <p className="notice-text">{item.text}</p>
                </div>
              ))}
              <p className="notice-text">{CLIENT_APP.privacyNote}</p>
              <p className="notice-text">
                Mot de passe oublié ou besoin d’aide : <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
                {' '}Voir aussi la <Link href="/confidentialite">politique de confidentialité</Link> et
                {' '}la <Link href="/suppression-compte">suppression de compte</Link>.
              </p>
            </div>
          </div>
        </div>
      </section>
    </div>
  )
}
