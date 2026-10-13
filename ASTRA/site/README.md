# Site vitrine Astra

React 19 + Vite 8, pré-rendu statique : chaque build produit un `dist/index.html` complet (texte, offres, FAQ, données structurées) lisible par les moteurs de recherche, que React hydrate ensuite pour les animations et le formulaire.

## Commandes

```bash
npm install
npm run dev      # développement sur http://localhost:5173
npm run build    # build client + rendu serveur + injection dans dist/index.html
npm run preview  # sert dist/ sur http://localhost:4173
npm test         # tests unitaires (validation du formulaire)
```

## Avant la mise en ligne

1. **Domaine** : `https://webastra.digital-get.com`, déclaré dans `src/config.js` et `index.html` (`astra.digital-get.com` est l'API, pas le site). `sitemap.xml` et `robots.txt` sont générés au build.
2. **E-mail de contact** : défini dans `src/config.js` (`CONTACT_EMAIL`), repris dans toutes les pages légales. Vérifier qu'il reçoit bien le courrier : les demandes de suppression de compte y arrivent.
3. **Formulaire** : créer un point d'envoi (Formspree, Getform ou API maison) et le déclarer dans `.env` (`VITE_FORM_ENDPOINT=...`, voir `.env.example`). Sans cela, le formulaire ouvre la messagerie du visiteur avec la demande pré-remplie.
4. **Google Search Console** : déclarer le domaine et soumettre `sitemap.xml`.
5. **Fiche Google Business** : la créer à l'adresse réelle de Douala, puis compléter `address` dans `src/data/jsonLd.js` (rue, quartier, téléphone).

## Où modifier quoi

| Contenu | Fichier |
|---|---|
| Pages du site : chemin, titre, description (routeur, `<head>`, JSON-LD, sitemap) | `src/data/routes.js` |
| Textes des sections, offres, étapes, FAQ, application Astra Client | `src/data/content.js` |
| Pages légales (une par fichier) et date de mise à jour | `src/data/legal/` |
| Données structurées schema.org (générées depuis le contenu) | `src/data/jsonLd.js` |
| Titre, description, Open Graph | `index.html` |
| Couleurs, typographies, espacements | `src/styles/base.css` (tokens `:root`) |
| Style d'une section | `src/components/<Section>.css` |

Le catalogue d'offres schema.org est généré à partir de `content.js` : modifier une offre suffit à mettre le SEO à jour.

## Hébergement

`dist/` est un site statique, hébergé sur Apache : téléverser **tout** le contenu de `dist/` (dossiers des pages, `404.html` et `.htaccess` compris), sinon chaque URL renvoie la page d'accueil. En-têtes conseillés : `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, et une CSP autorisant `fonts.googleapis.com` / `fonts.gstatic.com` ainsi que le domaine du formulaire.
