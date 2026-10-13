import { FAQ } from '../data/content.js'
import './Faq.css'

export default function Faq() {
  return (
    <section className="section faq" id="faq" aria-labelledby="faq-title">
      <div className="wrap faq-grid">
        <div className="section-head" data-reveal>
          <p className="eyebrow">Questions fréquentes</p>
          <h2 id="faq-title">Ce que l’on nous demande avant de commencer.</h2>
        </div>
        <div className="faq-list">
          {FAQ.map((item) => (
            <details key={item.q}>
              <summary>
                <h3>{item.q}</h3>
                <span className="faq-icon" aria-hidden="true" />
              </summary>
              <p>{item.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}
