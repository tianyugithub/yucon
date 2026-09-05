const LOCK_CLASS = 'yc-scroll-lock'
const ALLOW_SELECTOR = '.yc-scroll-allow'

let lockCount = 0
let savedTop = 0
let touchStartY = 0

const scrollRoot = (): HTMLElement =>
  (document.scrollingElement as HTMLElement | null) ?? document.documentElement

const lockTargets = (): HTMLElement[] =>
  [
    document.documentElement,
    document.body,
    document.querySelector('uni-page'),
    document.querySelector('uni-page-wrapper'),
    document.querySelector('uni-page-body')
  ].filter((node): node is HTMLElement => Boolean(node))

const canScrollInside = (target: EventTarget | null, deltaY: number): boolean => {
  if (!(target instanceof Element)) {
    return false
  }
  const scroller = target.closest(ALLOW_SELECTOR)
  if (!(scroller instanceof HTMLElement)) {
    return false
  }
  const { scrollTop, scrollHeight, clientHeight } = scroller
  if (scrollHeight <= clientHeight + 1) {
    return false
  }
  if (deltaY < 0) {
    return scrollTop > 0
  }
  if (deltaY > 0) {
    return scrollTop + clientHeight < scrollHeight - 1
  }
  return true
}

const onWheel = (event: WheelEvent): void => {
  if (canScrollInside(event.target, event.deltaY)) {
    return
  }
  event.preventDefault()
}

const onTouchStart = (event: TouchEvent): void => {
  touchStartY = event.touches[0]?.clientY ?? 0
}

const onTouchMove = (event: TouchEvent): void => {
  const currentY = event.touches[0]?.clientY ?? 0
  if (canScrollInside(event.target, touchStartY - currentY)) {
    return
  }
  event.preventDefault()
}

export const lockPageScroll = (): void => {
  if (typeof document === 'undefined') {
    return
  }
  if (lockCount === 0) {
    savedTop = window.scrollY || scrollRoot().scrollTop
    lockTargets().forEach((node) => node.classList.add(LOCK_CLASS))
    document.body.style.position = 'fixed'
    document.body.style.top = `-${savedTop}px`
    document.body.style.left = '0'
    document.body.style.right = '0'
    document.body.style.width = '100%'
    document.addEventListener('wheel', onWheel, { passive: false })
    document.addEventListener('touchstart', onTouchStart, { passive: true })
    document.addEventListener('touchmove', onTouchMove, { passive: false })
  }
  lockCount += 1
}

export const unlockPageScroll = (): void => {
  if (typeof document === 'undefined' || lockCount === 0) {
    return
  }
  lockCount -= 1
  if (lockCount > 0) {
    return
  }
  document.removeEventListener('wheel', onWheel)
  document.removeEventListener('touchstart', onTouchStart)
  document.removeEventListener('touchmove', onTouchMove)
  lockTargets().forEach((node) => node.classList.remove(LOCK_CLASS))
  document.body.style.position = ''
  document.body.style.top = ''
  document.body.style.left = ''
  document.body.style.right = ''
  document.body.style.width = ''
  window.scrollTo(0, savedTop)
}
