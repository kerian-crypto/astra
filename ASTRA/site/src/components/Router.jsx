import { createContext, useContext, useEffect, useState, useCallback } from 'react'

const RouterContext = createContext({
  path: '/',
  navigate: () => {},
})

export function useRouter() {
  return useContext(RouterContext)
}

function normalizePath(raw) {
  if (!raw) return '/'
  const clean = raw.replace(/\/+$/, '')
  return clean === '' ? '/' : clean
}

export function RouterProvider({ initialPath = '/', children }) {
  const [path, setPath] = useState(() => {
    if (typeof window !== 'undefined') {
      return normalizePath(window.location.pathname)
    }
    return normalizePath(initialPath)
  })

  useEffect(() => {
    const onPop = () => {
      setPath(normalizePath(window.location.pathname))
    }
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])

  const navigate = useCallback((to, { replace = false } = {}) => {
    if (typeof window === 'undefined') return

    // Gestion des liens d'ancre seuls (#offres, #contact)
    if (to.startsWith('#')) {
      if (path === '/') {
        const id = to.slice(1)
        const el = document.getElementById(id)
        if (el) {
          el.scrollIntoView({ behavior: 'smooth' })
          window.history[replace ? 'replaceState' : 'pushState']({}, '', to)
        }
        return
      }
      to = '/' + to
    }

    const [targetPath, hash] = to.split('#')
    const normalized = normalizePath(targetPath)

    if (replace) {
      window.history.replaceState({}, '', to)
    } else {
      window.history.pushState({}, '', to)
    }

    setPath(normalized)

    if (hash) {
      setTimeout(() => {
        const el = document.getElementById(hash)
        if (el) {
          el.scrollIntoView({ behavior: 'smooth' })
        } else {
          window.scrollTo({ top: 0, behavior: 'instant' })
        }
      }, 60)
    } else {
      window.scrollTo({ top: 0, behavior: 'instant' })
    }
  }, [path])

  return (
    <RouterContext.Provider value={{ path, navigate }}>
      {children}
    </RouterContext.Provider>
  )
}

export function Link({ href, children, className, onClick, ...props }) {
  const { navigate } = useRouter()

  const handleClick = (e) => {
    if (onClick) onClick(e)

    if (
      !e.defaultPrevented &&
      e.button === 0 &&
      !e.metaKey &&
      !e.altKey &&
      !e.ctrlKey &&
      !e.shiftKey
    ) {
      // Intercepte uniquement les liens internes
      if (href && (href.startsWith('/') || href.startsWith('#'))) {
        e.preventDefault()
        navigate(href)
      }
    }
  }

  return (
    <a href={href} className={className} onClick={handleClick} {...props}>
      {children}
    </a>
  )
}
