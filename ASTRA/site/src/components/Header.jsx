import { useEffect, useRef, useState } from 'react'
import Wordmark from './Wordmark.jsx'
import { NAV_LINKS } from '../data/content.js'
import { Link, useRouter } from './Router.jsx'
import './Header.css'

export default function Header() {
  const { path } = useRouter()
  const [isOpen, setIsOpen] = useState(false)
  const [isScrolled, setIsScrolled] = useState(false)
  const sentinelRef = useRef(null)

  // Fond opaque dès que le haut de page sort de l'écran, y compris à l'ouverture directe sur une ancre.
  useEffect(() => {
    const sentinel = sentinelRef.current
    if (!sentinel || !('IntersectionObserver' in window)) return undefined
    const observer = new IntersectionObserver(([entry]) => setIsScrolled(!entry.isIntersecting))
    observer.observe(sentinel)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    if (!isOpen) return undefined
    const onKey = (event) => {
      if (event.key === 'Escape') setIsOpen(false)
    }
    document.body.classList.add('menu-open')
    window.addEventListener('keydown', onKey)
    return () => {
      document.body.classList.remove('menu-open')
      window.removeEventListener('keydown', onKey)
    }
  }, [isOpen])

  const close = () => setIsOpen(false)
  const classes = ['site-header', isScrolled && 'is-scrolled', isOpen && 'is-open'].filter(Boolean).join(' ')

  return (
    <>
      <div className="scroll-sentinel" ref={sentinelRef} aria-hidden="true" />
      <header className={classes}>
        <div className="wrap header-inner">
          <Link className="brand" href="/" aria-label="Astra, retour en haut de page" onClick={close}>
            <Wordmark />
          </Link>
          <nav className="nav" id="nav" aria-label="Navigation principale">
            {NAV_LINKS.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className={path === link.href ? 'is-active' : undefined}
                aria-current={path === link.href ? 'page' : undefined}
                onClick={close}
              >
                {link.label}
              </Link>
            ))}
            <Link className="btn btn-small" href="/contact" onClick={close}>Demander un diagnostic</Link>
          </nav>
          <button
            className="menu-toggle"
            type="button"
            aria-expanded={isOpen}
            aria-controls="nav"
            onClick={() => setIsOpen((open) => !open)}
          >
            <span className="sr-only">{isOpen ? 'Fermer le menu' : 'Ouvrir le menu'}</span>
            <span className="menu-bar" aria-hidden="true" />
            <span className="menu-bar" aria-hidden="true" />
          </button>
        </div>
      </header>
    </>
  )
}
