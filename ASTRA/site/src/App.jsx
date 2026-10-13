import { useEffect } from 'react'
import './styles/base.css'
import Header from './components/Header.jsx'
import Hero from './components/Hero.jsx'
import Terrain from './components/Terrain.jsx'
import Expertises from './components/Expertises.jsx'
import Offers from './components/Offers.jsx'
import Method from './components/Method.jsx'
import Vision from './components/Vision.jsx'
import Faq from './components/Faq.jsx'
import Contact from './components/Contact.jsx'
import Footer from './components/Footer.jsx'
import ClientSpace from './components/ClientSpace.jsx'
import LegalPage from './components/LegalPage.jsx'
import SectionPage from './components/SectionPage.jsx'
import NotFound from './components/NotFound.jsx'
import { RouterProvider, useRouter } from './components/Router.jsx'
import { useRevealOnScroll } from './hooks/useRevealOnScroll.js'
import { findRoute, NOT_FOUND } from './data/routes.js'
import { findLegalDoc } from './data/legal/index.js'

// Sections affichées par chaque page de section (titres et descriptions : data/routes.js).
const SECTION_PAGES = {
  '/expertises': [Expertises, Terrain],
  '/offres': [Offers],
  '/methode': [Method],
  '/vision': [Vision],
  '/faq': [Faq],
  '/contact': [Contact],
}

function HomePage() {
  useRevealOnScroll()

  return (
    <>
      <Hero />
      <Terrain />
      <Expertises />
      <Offers />
      <Method />
      <Vision />
      <Faq />
      <Contact />
    </>
  )
}

function Page({ path }) {
  if (path === '/') return <HomePage />
  if (path === '/clients') return <ClientSpace />
  const legal = findLegalDoc(path)
  if (legal) return <LegalPage doc={legal.doc} path={path} />
  const sections = SECTION_PAGES[path]
  if (sections) return <SectionPage sections={sections} withCta={path !== '/contact'} />
  return <NotFound />
}

function MainContent() {
  const { path } = useRouter()
  const route = findRoute(path) ?? NOT_FOUND

  useEffect(() => {
    document.title = route.title
  }, [route.title])

  // La clé remonte la page à chaque navigation : animations et révélations repartent de zéro.
  return <Page key={path} path={path} />
}

export default function App({ initialPath = '/' }) {
  return (
    <RouterProvider initialPath={initialPath}>
      <a className="skip" href="#contenu">Aller au contenu</a>
      <Header />
      <main id="contenu">
        <MainContent />
      </main>
      <Footer />
    </RouterProvider>
  )
}
