import SectionHead from './SectionHead.jsx'
import Trajectory from './Trajectory.jsx'
import './Method.css'

const NB = ' '

export default function Method() {
  return (
    <section className="section method" id="methode" aria-labelledby="methode-title">
      <div className="wrap">
        <SectionHead id="methode-title" eyebrow="Méthode" title="Nous commençons par la question qui précède la commande." className="method-head" />

        <div className="contrast" data-reveal>
          <figure className="contrast-item">
            <figcaption>Une agence classique entend</figcaption>
            <blockquote><p>{`«${NB}Voici ce dont nous avons besoin. Construisez-le.${NB}»`}</p></blockquote>
          </figure>
          <figure className="contrast-item contrast-astra">
            <figcaption>Astra demande d’abord</figcaption>
            <blockquote><p>{`«${NB}Quel problème essayons-nous réellement de résoudre${NB}?${NB}»`}</p></blockquote>
          </figure>
        </div>

        <p className="method-intro" data-reveal>
          Chaque projet suit le même parcours, du problème observé sur le terrain jusqu’à l’outil qui tient la charge.
        </p>
        <Trajectory />
      </div>
    </section>
  )
}
