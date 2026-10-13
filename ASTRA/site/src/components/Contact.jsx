import { useState } from 'react'
import Field from './Field.jsx'
import { FORM_SECTORS } from '../data/content.js'
import { CONTACT_EMAIL } from '../config.js'
import { EMPTY_FORM, validateContact, sendContact } from '../lib/contactForm.js'
import './Contact.css'

const STATUS_MESSAGES = {
  sending: 'Envoi en cours…',
  sent: 'Demande envoyée. Nous revenons vers vous rapidement.',
  mailto: 'Votre messagerie s’ouvre avec la demande pré-remplie. Il ne reste qu’à l’envoyer.',
  error: `L’envoi n’a pas abouti. Réessayez ou écrivez-nous directement à ${CONTACT_EMAIL}.`,
  invalid: 'Certains champs sont à corriger avant l’envoi.',
}

export default function Contact() {
  const [values, setValues] = useState(EMPTY_FORM)
  const [errors, setErrors] = useState({})
  const [status, setStatus] = useState('idle')

  const update = (event) => {
    const { name, value } = event.target
    setValues((current) => ({ ...current, [name]: value }))
  }

  const onSubmit = async (event) => {
    event.preventDefault()
    const found = validateContact(values)
    setErrors(found)
    if (Object.keys(found).length > 0) {
      setStatus('invalid')
      const firstField = event.currentTarget.querySelector('[aria-invalid="true"]')
      firstField?.focus()
      return
    }

    setStatus('sending')
    try {
      const outcome = await sendContact(values)
      setStatus(outcome)
      if (outcome === 'sent') setValues(EMPTY_FORM)
    } catch (error) {
      console.error('Formulaire de contact :', error)
      setStatus('error')
    }
  }

  const describedBy = (name) => (errors[name] ? `f-${name}-err` : undefined)
  const invalid = (name) => (errors[name] ? true : undefined)

  return (
    <section className="section contact" id="contact" aria-labelledby="contact-title">
      <div className="wrap contact-grid">
        <div className="section-head contact-head" data-reveal>
          <p className="eyebrow">Diagnostic</p>
          <h2 id="contact-title">Parlons de votre problème. La technologie viendra ensuite.</h2>
          <p className="lead">
            Décrivez votre activité et ce qui vous freine aujourd’hui. Nous revenons vers vous avec une première
            lecture de la situation et le palier qui vous correspond.
          </p>
          <ul className="contact-facts">
            <li><span>Basés à</span> Douala, Cameroun</li>
            <li><span>Écrire</span> <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a></li>
          </ul>
        </div>

        <form className="form" noValidate onSubmit={onSubmit} data-reveal>
          <Field id="f-nom" label="Nom complet" error={errors.nom}>
            <input id="f-nom" name="nom" type="text" autoComplete="name" maxLength={120} required
              value={values.nom} onChange={update} aria-invalid={invalid('nom')} aria-describedby={describedBy('nom')} />
          </Field>
          <Field id="f-organisation" label="Entreprise ou organisation">
            <input id="f-organisation" name="organisation" type="text" autoComplete="organization" maxLength={160}
              value={values.organisation} onChange={update} />
          </Field>
          <Field id="f-secteur" label="Secteur">
            <select id="f-secteur" name="secteur" value={values.secteur} onChange={update}>
              <option value="">Choisir un secteur</option>
              {FORM_SECTORS.map((sector) => <option key={sector}>{sector}</option>)}
            </select>
          </Field>
          <div className="field-row">
            <Field id="f-telephone" label="Téléphone ou WhatsApp" error={errors.telephone}>
              <input id="f-telephone" name="telephone" type="tel" autoComplete="tel" inputMode="tel" maxLength={30}
                placeholder="+237 6XX XX XX XX" value={values.telephone} onChange={update}
                aria-invalid={invalid('telephone')} aria-describedby={describedBy('telephone')} />
            </Field>
            <Field id="f-email" label="E-mail" error={errors.email}>
              <input id="f-email" name="email" type="email" autoComplete="email" maxLength={160}
                value={values.email} onChange={update}
                aria-invalid={invalid('email')} aria-describedby={describedBy('email')} />
            </Field>
          </div>
          {errors.joignable ? <p className="field-error field-error-global">{errors.joignable}</p> : null}
          <Field id="f-besoin" label="Ce qui vous freine aujourd’hui" error={errors.besoin}>
            <textarea id="f-besoin" name="besoin" rows={5} maxLength={2000} required
              placeholder="Par exemple : nos inscriptions se font encore au guichet et les paiements sont difficiles à suivre."
              value={values.besoin} onChange={update}
              aria-invalid={invalid('besoin')} aria-describedby={describedBy('besoin')} />
          </Field>
          <button className="btn btn-submit" type="submit" disabled={status === 'sending'}>
            Envoyer ma demande
          </button>
          <p className={`form-status is-${status}`} role="status" aria-live="polite">
            {STATUS_MESSAGES[status] ?? ''}
          </p>
        </form>
      </div>
    </section>
  )
}
