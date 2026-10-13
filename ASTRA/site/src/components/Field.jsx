export default function Field({ id, label, error, children }) {
  return (
    <div className={error ? 'field has-error' : 'field'}>
      <label htmlFor={id}>{label}</label>
      {children}
      {error ? <p className="field-error" id={`${id}-err`}>{error}</p> : null}
    </div>
  )
}
