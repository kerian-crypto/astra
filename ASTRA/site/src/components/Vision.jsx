import { useCallback, useRef, useState } from 'react'
import { PRINCIPLES } from '../data/content.js'
import { CONTACT_EMAIL } from '../config.js'
import { useReducedMotion } from '../hooks/useReducedMotion.js'
import { useScrollProgress } from '../hooks/useScrollProgress.js'
import './Vision.css'

const NB = ' '

function Manifesto() {
  const ref = useRef(null)
  const reducedMotion = useReducedMotion()
  const [lit, setLit] = useState(PRINCIPLES.length)

  // Les mots s'allument un à un pendant la traversée du bloc.
  const onProgress = useCallback(
    (progress) => setLit(reducedMotion ? PRINCIPLES.length : Math.round(progress * PRINCIPLES.length)),
    [reducedMotion],
  )
  useScrollProgress(ref, onProgress, { start: 0.9, end: 0.5 })

  return (
    <p className="manifesto" ref={ref}>
      <span className="sr-only">La technologie doit être rapide, compréhensible, accessible, fiable et flexible.</span>
      {PRINCIPLES.map((word, index) => (
        <span key={word} aria-hidden="true" className={index < lit ? 'is-lit' : undefined}>{word}</span>
      ))}
    </p>
  )
}

export default function Vision() {
  return (
    <section className="section vision" id="vision" aria-labelledby="vision-title">
      <div className="wrap">
        <div className="vision-grid">
          <div data-reveal>
            <p className="eyebrow">Au-delà du service</p>
            <h2 id="vision-title">Nous construisons aussi nos propres produits.</h2>
          </div>
          <div className="vision-body" data-reveal>
            <p>
              Commerce en ligne, services financiers, éducation numérique, intelligence artificielle{NB}: nous
              testons nos idées dans des conditions réelles, sur les mêmes problèmes que nos clients.
            </p>
            <p>
              Certaines resteront de petits outils internes, d’autres deviendront des produits à part entière.
              Ce que nous apprenons sur ces projets profite directement à ceux de nos clients.
            </p>
          </div>
        </div>

        <Manifesto />

        <p className="reach" data-reveal>
          Un problème rencontré à Douala existe aussi à Lagos. Une solution conçue au Cameroun peut servir au
          Sénégal. Nous commençons ici, sans penser petit.
        </p>

        <aside className="join" aria-labelledby="join-title" data-reveal>
          <div>
            <h3 id="join-title">Astra est encore en construction.</h3>
            <p>
              Ingénieurs, designers, chercheurs, spécialistes de l’IA, experts métier, créatifs{NB}: si vous savez
              repérer un problème que la technologie peut résoudre, nous voulons vous lire.
            </p>
          </div>
          <a className="btn btn-ghost" href={`mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent('Candidature Astra')}`}>
            Proposer sa candidature
          </a>
        </aside>
      </div>
    </section>
  )
}
