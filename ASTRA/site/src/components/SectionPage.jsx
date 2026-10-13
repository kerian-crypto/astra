import { Link } from './Router.jsx'
import { useRevealOnScroll } from '../hooks/useRevealOnScroll.js'
import './SectionPage.css'

// Page autonome d'une ou plusieurs sections de l'accueil, suivie d'un appel au diagnostic.
export default function SectionPage({ sections, withCta = true }) {
  useRevealOnScroll()

  return (
    <div className="section-page">
      {sections.map((Section) => <Section key={Section.name} />)}
      {withCta ? (
        <aside className="section-page-cta" aria-labelledby="section-cta-title">
          <div className="wrap">
            <div className="section-cta-box">
              <h2 className="section-cta-title" id="section-cta-title">Un projet en tête ?</h2>
              <p className="lead section-cta-lead">
                Décrivez-nous votre activité et ce qui vous freine. Nous revenons vers vous avec une première lecture
                de la situation, sans engagement.
              </p>
              <div className="section-cta-actions">
                <Link className="btn" href="/contact">Demander un diagnostic</Link>
              </div>
            </div>
          </div>
        </aside>
      ) : null}
    </div>
  )
}
