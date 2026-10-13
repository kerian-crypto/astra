import { useEffect, useState } from 'react'

const QUERY = '(prefers-reduced-motion: reduce)'

// Renvoie true côté serveur et au premier rendu : les animations ne démarrent qu'une fois la préférence connue.
export function useReducedMotion() {
  const [reduced, setReduced] = useState(true)

  useEffect(() => {
    const media = window.matchMedia(QUERY)
    const update = () => setReduced(media.matches)
    update()
    media.addEventListener('change', update)
    return () => media.removeEventListener('change', update)
  }, [])

  return reduced
}
