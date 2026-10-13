import { useRef, useState } from 'react'
import SectionHead from './SectionHead.jsx'
import { SECTORS, EXTRAS, FEATURED_TIER_INDEX } from '../data/content.js'
import './Offers.css'

function Tier({ tier, index }) {
  const isFeatured = index === FEATURED_TIER_INDEX
  return (
    <article className={isFeatured ? 'tier tier-featured' : 'tier'} style={{ '--d': index }}>
      <p className="tier-step">
        Palier {index + 1}
        {isFeatured ? <span className="badge">Pour démarrer</span> : null}
      </p>
      <h4>{tier.name}</h4>
      <ul>
        {tier.items.map((item) => <li key={item}>{item}</li>)}
      </ul>
      <div className="tier-foot">
        {tier.monthly ? <p className="tier-note">Abonnement mensuel{'\u00A0'}: {tier.monthly}</p> : null}
        <a className="tier-link" href="#contact">Demander ce palier</a>
      </div>
    </article>
  )
}

export default function Offers() {
  const [activeId, setActiveId] = useState(SECTORS[0].id)
  const tabRefs = useRef({})

  // Navigation clavier du motif « onglets » (WAI-ARIA) : flèches, Début, Fin.
  const onKeyDown = (event) => {
    const index = SECTORS.findIndex((s) => s.id === activeId)
    const keyMoves = {
      ArrowRight: index + 1,
      ArrowLeft: index - 1,
      Home: 0,
      End: SECTORS.length - 1,
    }
    if (!(event.key in keyMoves)) return
    event.preventDefault()
    const next = SECTORS[(keyMoves[event.key] + SECTORS.length) % SECTORS.length]
    setActiveId(next.id)
    tabRefs.current[next.id]?.focus()
  }

  return (
    <section className="section offers" id="offres" aria-labelledby="offres-title">
      <div className="wrap">
        <SectionHead id="offres-title" eyebrow="Offres" title="Une offre pensée pour votre métier." className="offers-head">
          Chaque secteur a ses propres blocages. Nos offres partent de ceux que nous rencontrons le plus souvent
          à Douala, en trois paliers{'\u00A0'}: chacun reprend le précédent et va plus loin.
        </SectionHead>

        <div className="tabs" data-reveal>
          <div className="tablist" role="tablist" aria-label="Choisissez votre secteur" onKeyDown={onKeyDown}>
            {SECTORS.map((sector) => {
              const isActive = sector.id === activeId
              return (
                <button
                  key={sector.id}
                  ref={(el) => { tabRefs.current[sector.id] = el }}
                  type="button"
                  role="tab"
                  id={`tab-${sector.id}`}
                  aria-controls={`panel-${sector.id}`}
                  aria-selected={isActive}
                  tabIndex={isActive ? 0 : -1}
                  onClick={() => setActiveId(sector.id)}
                >
                  {sector.tab}
                </button>
              )
            })}
          </div>

          {/* Tous les panneaux restent dans le HTML pour être indexés ; seuls les inactifs sont masqués. */}
          {SECTORS.map((sector) => (
            <div
              key={sector.id}
              className="panel"
              role="tabpanel"
              id={`panel-${sector.id}`}
              aria-labelledby={`tab-${sector.id}`}
              tabIndex={0}
              hidden={sector.id !== activeId}
            >
              <h3 className="panel-title">{sector.title}</h3>
              <p className="panel-problem">{sector.problem}</p>
              <div className="tiers">
                {sector.tiers.map((tier, index) => <Tier key={tier.name} tier={tier} index={index} />)}
              </div>
            </div>
          ))}
        </div>

        <p className="offers-note">Chaque projet est chiffré après un premier diagnostic, selon votre situation et vos priorités.</p>

        <div className="extras">
          {EXTRAS.map((extra) => (
            <article className="extra" key={extra.title} data-reveal>
              <h3>{extra.title}</h3>
              <p>{extra.text}</p>
              <a className="tier-link" href="#contact">En parler</a>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}
