export default function Wordmark({ lazy = false }) {
  return (
    <img
      className="wordmark"
      src="/assets/astra-wordmark.webp"
      alt="Astra"
      width="560"
      height="148"
      loading={lazy ? 'lazy' : 'eager'}
      decoding="async"
    />
  )
}
