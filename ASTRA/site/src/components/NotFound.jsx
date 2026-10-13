import { Link } from './Router.jsx'
import './SectionPage.css'

export default function NotFound() {
  return (
    <div className="section-page">
      <section className="section" aria-labelledby="not-found-title">
        <div className="wrap">
          <p className="eyebrow">Erreur 404</p>
          <h1 id="not-found-title">Cette page n’existe pas.</h1>
          <p className="lead">Le lien est peut-être ancien ou mal recopié.</p>
          <div className="section-cta-actions">
            <Link className="btn" href="/">Revenir à l’accueil</Link>
          </div>
        </div>
      </section>
    </div>
  )
}
