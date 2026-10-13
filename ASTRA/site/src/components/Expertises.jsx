import SectionHead from './SectionHead.jsx'
import { SKILLS } from '../data/content.js'
import './Expertises.css'

export default function Expertises() {
  return (
    <section className="section expertises" id="expertises" aria-labelledby="expertises-title">
      <div className="wrap expertises-grid">
        <SectionHead id="expertises-title" eyebrow="Expertises" title="Du logo à l’infrastructure, une seule équipe." className="expertises-head">
          Développeurs web et mobile, designers, spécialistes du marketing digital et de la cybersécurité
          travaillent dans la même équipe. Votre site, vos outils et vos données sont pensés ensemble.
        </SectionHead>
        <div className="skills">
          {SKILLS.map((skill) => (
            <article className="skill" key={skill.title} data-reveal>
              <h3>{skill.title}</h3>
              <p>{skill.text}</p>
              <ul className="tags" aria-label={`Exemples : ${skill.title.toLowerCase()}`}>
                {skill.tags.map((tag) => <li key={tag}>{tag}</li>)}
              </ul>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}
