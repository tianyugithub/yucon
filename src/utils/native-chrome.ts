const isEditable = (target: EventTarget | null): target is HTMLElement => {
  if (!(target instanceof HTMLElement)) {
    return false
  }
  const tag = target.tagName
  return tag === 'INPUT' || tag === 'TEXTAREA' || target.isContentEditable
}

export const bindNativeChrome = (): void => {
  if (typeof document === 'undefined') {
    return
  }

  const viewport = document.querySelector('meta[name="viewport"]')
  if (viewport) {
    const content = viewport.getAttribute('content') || ''
    if (!content.includes('interactive-widget')) {
      viewport.setAttribute(
        'content',
        'width=device-width, initial-scale=1.0, viewport-fit=cover, interactive-widget=resizes-content'
      )
    }
  }

  document.addEventListener('focusin', (event) => {
    if (!isEditable(event.target)) {
      return
    }
    const target = event.target
    window.setTimeout(() => {
      target.scrollIntoView({ block: 'center', inline: 'nearest' })
    }, 320)
  })
}
