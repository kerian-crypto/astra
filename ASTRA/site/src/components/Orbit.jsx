import { useReducedMotion } from '../hooks/useReducedMotion.js'

// Étoile à quatre branches reprise du logo.
export const STAR_PATH =
  'M0 -14 C1.5 -3 3 -1.5 14 0 C3 1.5 1.5 3 0 14 C-1.5 3 -3 1.5 -14 0 C-3 -1.5 -1.5 -3 0 -14Z'

const ORBIT_SECONDS = 16

// L'anneau du logo, redessiné autour du titre : moitié arrière sous le texte, moitié avant par-dessus.
export default function Orbit() {
  const reducedMotion = useReducedMotion()

  return (
    <>
      <svg className="orbit orbit-back" viewBox="0 0 1000 300" preserveAspectRatio="none" aria-hidden="true" focusable="false">
        <defs>
          <linearGradient id="orbitGrad" x1="0" x2="1" y1="0" y2="0">
            <stop offset="0" stopColor="#4F5BF2" />
            <stop offset=".55" stopColor="#38C6F4" />
            <stop offset="1" stopColor="#4F5BF2" stopOpacity=".25" />
          </linearGradient>
        </defs>
        <path className="orbit-path" d="M990 150 A490 120 0 0 0 10 150" pathLength="1" />
      </svg>
      <svg className="orbit orbit-front" viewBox="0 0 1000 300" preserveAspectRatio="none" aria-hidden="true" focusable="false">
        <path className="orbit-path orbit-path-front" d="M10 150 A490 120 0 0 0 990 150" pathLength="1" />
        <path id="orbitTrack" d="M990 150 A490 120 0 1 0 10 150 A490 120 0 1 0 990 150" fill="none" stroke="none" />
        {reducedMotion ? (
          <path className="orbit-star" d={STAR_PATH} transform="translate(905 72)" />
        ) : (
          <path className="orbit-star" d={STAR_PATH}>
            <animateMotion dur={`${ORBIT_SECONDS}s`} begin="1.6s" repeatCount="indefinite" fill="freeze">
              <mpath href="#orbitTrack" />
            </animateMotion>
          </path>
        )}
      </svg>
    </>
  )
}
