import Orbit from './Orbit.jsx'
import './Hero.css'

export default function Hero() {
  return (
    <section className="hero" id="top" aria-labelledby="hero-title">
      <div className="planet" aria-hidden="true" />
      <div className="wrap hero-inner">
        <h1 className="hero-title" id="hero-title">
          <span className="kicker load" style={{ '--i': 0 }}>
            Agence web et digitale à Douala · Sites, applications, données et cybersécurité
          </span>
          <span className="headline">
            <span className="line"><span className="load-line" style={{ '--i': 1 }}>Construire</span></span>
            <span className="line"><span className="load-line" style={{ '--i': 2 }}>ce qui manque.</span></span>
            <Orbit />
          </span>
        </h1>
        <p className="hero-lead load" style={{ '--i': 3 }}>
          Création de sites web, d’applications mobiles et d’outils de gestion pour les entreprises de Douala et
          du Cameroun, avec Mobile Money, WhatsApp et la sécurité intégrés dès le départ. Pensés à partir du
          terrain, construits pour durer.
        </p>
        <div className="hero-actions load" style={{ '--i': 4 }}>
          <a className="btn" href="#contact">Demander un diagnostic</a>
          <a className="btn btn-ghost" href="#offres">Voir les offres</a>
        </div>
      </div>
      <p className="hero-motto wrap load" style={{ '--i': 5 }}>
        <span>Local dans la compréhension.</span>
        <span>Global dans la conception.</span>
      </p>
    </section>
  )
}
