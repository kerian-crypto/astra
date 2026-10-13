import { CONTACT_EMAIL, FORM_ENDPOINT } from '../config.js'

export const EMPTY_FORM = Object.freeze({
  nom: '',
  organisation: '',
  secteur: '',
  telephone: '',
  email: '',
  besoin: '',
})

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/
const MIN_PHONE_DIGITS = 8
const MIN_NEED_LENGTH = 10

export const ERROR_MESSAGES = Object.freeze({
  nom: 'Indiquez votre nom pour que nous sachions à qui répondre.',
  telephone: 'Ce numéro semble incomplet. Vérifiez-le ou laissez le champ vide.',
  email: 'Cette adresse e-mail n’est pas valide.',
  joignable: 'Laissez-nous au moins un numéro ou une adresse e-mail pour vous répondre.',
  besoin: 'Décrivez votre besoin en une ou deux phrases.',
})

// Renvoie un objet { champ: message } ; vide si le formulaire est valide.
export function validateContact(values) {
  const nom = values.nom.trim()
  const telephone = values.telephone.trim()
  const email = values.email.trim()
  const besoin = values.besoin.trim()
  const phoneDigits = telephone.replace(/\D/g, '')

  return {
    ...(nom ? {} : { nom: ERROR_MESSAGES.nom }),
    ...(telephone && phoneDigits.length < MIN_PHONE_DIGITS ? { telephone: ERROR_MESSAGES.telephone } : {}),
    ...(email && !EMAIL_PATTERN.test(email) ? { email: ERROR_MESSAGES.email } : {}),
    ...(!telephone && !email ? { joignable: ERROR_MESSAGES.joignable } : {}),
    ...(besoin.length >= MIN_NEED_LENGTH ? {} : { besoin: ERROR_MESSAGES.besoin }),
  }
}

function buildMailto(values) {
  const lines = [
    `Nom : ${values.nom}`,
    `Organisation : ${values.organisation || 'non précisée'}`,
    `Secteur : ${values.secteur || 'non précisé'}`,
    `Téléphone / WhatsApp : ${values.telephone || 'non précisé'}`,
    `E-mail : ${values.email || 'non précisé'}`,
    '',
    values.besoin,
  ]
  const subject = `Demande de diagnostic : ${values.organisation || values.nom}`
  return `mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(lines.join('\n'))}`
}

// Envoie la demande. Renvoie 'sent' (envoi serveur) ou 'mailto' (messagerie ouverte). Lève une erreur sinon.
export async function sendContact(values) {
  const payload = Object.fromEntries(Object.entries(values).map(([key, value]) => [key, value.trim()]))

  if (!FORM_ENDPOINT) {
    window.location.href = buildMailto(payload)
    return 'mailto'
  }

  const response = await fetch(FORM_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(payload),
  })
  if (!response.ok) {
    throw new Error(`Envoi refusé (${response.status})`)
  }
  return 'sent'
}
