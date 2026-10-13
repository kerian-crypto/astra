import SectionHead from './SectionHead.jsx'
import { REALITIES } from '../data/content.js'
import './Terrain.css'

export default function Terrain() {
  return (
    <section className="section terrain" aria-labelledby="terrain-title">
      <div className="wrap terrain-grid">
        <SectionHead id="terrain-title" eyebrow="Pensé depuis l’Afrique" title="Les contraintes deviennent des paramètres de conception." className="terrain-head">
          Un outil conçu pour Paris ou San Francisco ne tient pas compte de la façon dont on paie, vend et
          communique à Douala. Nous partons de vos réalités, puis nous construisons autour.
        </SectionHead>
        <dl className="realities">
          {REALITIES.map((item, index) => (
            <div className="reality" key={item.constraint} data-reveal style={{ '--d': index }}>
              <dt>{item.constraint}</dt>
              <dd>{item.answer}</dd>
            </div>
          ))}
        </dl>
      </div>
    </section>
  )
}
