import { useCallback, useEffect, useRef, useState } from 'react'
import { STATIONS } from '../data/content.js'
import { useReducedMotion } from '../hooks/useReducedMotion.js'
import { useScrollProgress } from '../hooks/useScrollProgress.js'

const STAR_PATH =
  'M0 -11 C1.2 -2.4 2.4 -1.2 11 0 C2.4 1.2 1.2 2.4 0 11 C-1.2 2.4 -2.4 1.2 -11 0 C-2.4 -1.2 -1.2 -2.4 0 -11Z'
const LEAD_IN = 40

// Courbe lisse passant par le centre de chaque point : tangentes verticales, d'où l'effet de trajectoire.
function buildPath(points) {
  if (points.length === 0) return ''
  const [first] = points
  const segments = [`M${first.x} ${first.y - LEAD_IN}`, `L${first.x} ${first.y}`]
  for (let i = 1; i < points.length; i += 1) {
    const prev = points[i - 1]
    const curr = points[i]
    const mid = (curr.y - prev.y) / 2
    segments.push(`C${prev.x} ${prev.y + mid} ${curr.x} ${curr.y - mid} ${curr.x} ${curr.y}`)
  }
  return segments.join(' ')
}

export default function Trajectory() {
  const containerRef = useRef(null)
  const baseRef = useRef(null)
  const liveRef = useRef(null)
  const starRef = useRef(null)
  const geometryRef = useRef({ length: 0, dotYs: [] })
  const [pathD, setPathD] = useState('')
  const [pathLength, setPathLength] = useState(0)
  const [litCount, setLitCount] = useState(STATIONS.length)
  const reducedMotion = useReducedMotion()

  // Recalcule la courbe à partir de la position réelle des points (responsive).
  useEffect(() => {
    const container = containerRef.current
    if (!container) return undefined

    const measure = () => {
      const box = container.getBoundingClientRect()
      const points = [...container.querySelectorAll('.dot')].map((dot) => {
        const r = dot.getBoundingClientRect()
        return { x: r.left + r.width / 2 - box.left, y: r.top + r.height / 2 - box.top }
      })
      geometryRef.current.dotYs = points.map((p) => p.y)
      setPathD(buildPath(points))
    }

    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(container)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    if (!baseRef.current || !pathD) return
    const length = baseRef.current.getTotalLength()
    geometryRef.current.length = length
    setPathLength(length)
  }, [pathD])

  const onProgress = useCallback(
    (progress) => {
      const base = baseRef.current
      const live = liveRef.current
      const star = starRef.current
      const { length, dotYs } = geometryRef.current
      if (!base || !live || !star || !length) return

      const effective = reducedMotion ? 1 : progress
      const drawn = length * effective
      live.style.strokeDasharray = `${length}`
      live.style.strokeDashoffset = `${length - drawn}`

      const point = base.getPointAtLength(drawn)
      star.setAttribute('transform', `translate(${point.x} ${point.y})`)

      const lit = dotYs.filter((y) => y <= point.y + 2).length
      setLitCount(effective === 0 ? 0 : lit)
    },
    [reducedMotion],
  )

  useScrollProgress(containerRef, onProgress, { start: 0.75, end: 0.45, version: pathLength })

  return (
    <div className="trajectory" ref={containerRef}>
      <svg className="trajectory-svg" aria-hidden="true" focusable="false">
        <defs>
          <linearGradient id="trajGrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#4F5BF2" />
            <stop offset="1" stopColor="#38C6F4" />
          </linearGradient>
        </defs>
        <path className="traj-base" ref={baseRef} d={pathD} />
        <path className="traj-live" ref={liveRef} d={pathD} />
        <path className={pathLength ? 'traj-star is-ready' : 'traj-star'} ref={starRef} d={STAR_PATH} />
      </svg>
      <ol className="stations">
        {STATIONS.map((station, index) => (
          <li className={index < litCount ? 'station is-lit' : 'station'} key={station.title}>
            <span className="dot" aria-hidden="true" />
            <div className="station-body">
              <h3>{station.title}</h3>
              <p>{station.text}</p>
            </div>
          </li>
        ))}
      </ol>
    </div>
  )
}
