import { useEffect } from 'react'

// Appelle onProgress(0..1) selon la traversée de l'élément dans le viewport, au rythme des frames.
// `version` force une nouvelle mesure quand la géométrie de l'élément change.
export function useScrollProgress(ref, onProgress, { start = 0.85, end = 0.35, version = 0 } = {}) {
  useEffect(() => {
    const el = ref.current
    if (!el) return undefined

    let frame = 0
    const measure = () => {
      frame = 0
      const rect = el.getBoundingClientRect()
      const vh = window.innerHeight
      const startY = vh * start
      const endY = vh * end
      const travelled = startY - rect.top
      const distance = rect.height + (startY - endY)
      const progress = Math.min(1, Math.max(0, travelled / distance))
      onProgress(progress)
    }
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(measure)
    }

    measure()
    window.addEventListener('scroll', schedule, { passive: true })
    window.addEventListener('resize', schedule)
    return () => {
      cancelAnimationFrame(frame)
      window.removeEventListener('scroll', schedule)
      window.removeEventListener('resize', schedule)
    }
  }, [ref, onProgress, start, end, version])
}
