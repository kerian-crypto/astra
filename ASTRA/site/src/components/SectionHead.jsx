export default function SectionHead({ id, eyebrow, title, children, className = '' }) {
  return (
    <div className={`section-head ${className}`} data-reveal>
      <p className="eyebrow">{eyebrow}</p>
      <h2 id={id}>{title}</h2>
      {children ? <p className="lead">{children}</p> : null}
    </div>
  )
}
