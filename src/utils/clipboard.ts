export const copyText = (text: string): Promise<void> =>
  new Promise((resolve, reject) => {
    if (!text) {
      reject(new Error('没有可复制的内容'))
      return
    }

    const copyWithTextarea = (): boolean => {
      if (typeof document === 'undefined') {
        return false
      }
      const textarea = document.createElement('textarea')
      textarea.value = text
      textarea.setAttribute('readonly', '')
      textarea.style.position = 'fixed'
      textarea.style.top = '0'
      textarea.style.left = '-9999px'
      document.body.appendChild(textarea)
      textarea.focus()
      textarea.select()
      textarea.setSelectionRange(0, text.length)
      const copied = document.execCommand('copy')
      document.body.removeChild(textarea)
      return copied
    }

    const copyWithClipboardApi = async (): Promise<boolean> => {
      if (typeof navigator === 'undefined' || !navigator.clipboard?.writeText) {
        return false
      }
      await navigator.clipboard.writeText(text)
      return true
    }

    uni.setClipboardData({
      data: text,
      showToast: false,
      success: () => resolve(),
      fail: () => {
        copyWithClipboardApi()
          .then((ok) => {
            if (ok) {
              resolve()
              return
            }
            if (copyWithTextarea()) {
              resolve()
              return
            }
            reject(new Error('复制失败'))
          })
          .catch(() => {
            if (copyWithTextarea()) {
              resolve()
              return
            }
            reject(new Error('复制失败'))
          })
      }
    })
  })
