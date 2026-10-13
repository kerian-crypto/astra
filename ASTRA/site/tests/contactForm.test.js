import { test } from 'node:test'
import assert from 'node:assert/strict'
import { EMPTY_FORM, ERROR_MESSAGES, validateContact } from '../src/lib/contactForm.js'

const valid = { ...EMPTY_FORM, nom: 'Awa Ngono', telephone: '+237 6 99 00 11 22', besoin: 'Nos inscriptions se font au guichet.' }

test('accepte un formulaire complet', () => {
  assert.deepEqual(validateContact(valid), {})
})

test('exige un nom et un besoin détaillé', () => {
  const errors = validateContact({ ...valid, nom: '  ', besoin: 'site' })
  assert.equal(errors.nom, ERROR_MESSAGES.nom)
  assert.equal(errors.besoin, ERROR_MESSAGES.besoin)
})

test('exige au moins un moyen de contact', () => {
  const errors = validateContact({ ...valid, telephone: '', email: '' })
  assert.equal(errors.joignable, ERROR_MESSAGES.joignable)
})

test('refuse un numéro trop court et un e-mail mal formé', () => {
  const errors = validateContact({ ...valid, telephone: '6990', email: 'awa@' })
  assert.equal(errors.telephone, ERROR_MESSAGES.telephone)
  assert.equal(errors.email, ERROR_MESSAGES.email)
})

test('accepte un e-mail seul, sans téléphone', () => {
  assert.deepEqual(validateContact({ ...valid, telephone: '', email: 'awa@ecole.cm' }), {})
})

test('ne modifie pas les valeurs reçues', () => {
  const input = Object.freeze({ ...valid, nom: '  Awa  ' })
  assert.doesNotThrow(() => validateContact(input))
})
