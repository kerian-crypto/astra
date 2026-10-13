// Domaine public du site (l'API vit sur astra.digital-get.com, pas le site).
export const SITE_URL = 'https://webastra.digital-get.com'
export const SITE_HOST = new URL(SITE_URL).host
export const CONTACT_EMAIL = 'contact@astra.digital-get.com'

// Fiche Google Play de l'application Astra Client (active une fois l'app publiée).
export const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.astra.astra_client'

// Point d'envoi du formulaire (voir .env.example). Vide : repli sur la messagerie du visiteur.
export const FORM_ENDPOINT = import.meta.env?.VITE_FORM_ENDPOINT ?? ''
