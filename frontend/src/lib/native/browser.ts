import { NativeApi, Rule } from './types'
import {
  CheckResult,
  CheckStatus,
} from '../../../bindings/linkpure/internal/rules/models'
import { saveAs } from 'file-saver'

export function browser(): NativeApi {
  const STORAGE_KEY = 'link-pure-rules'

  const saveRules = (rules: Rule[]) => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(rules))
  }

  const loadRules = (): Rule[] => {
    const data = localStorage.getItem(STORAGE_KEY)
    return data ? JSON.parse(data) : []
  }

  return {
    store: {
      getRules: async () => {
        return loadRules()
      },
      newRule: async (rule: Rule) => {
        const rules = loadRules()
        rules.push(rule)
        saveRules(rules)
      },
      updateRule: async (updated: Rule) => {
        const rules = loadRules()
        const index = rules.findIndex((r) => r.id === updated.id)
        if (index !== -1) {
          rules[index] = updated
          saveRules(rules)
        }
      },
      deleteRule: async (id: string) => {
        const rules = loadRules()
        const filtered = rules.filter((r) => r.id !== id)
        saveRules(filtered)
      },
    },
    rule: {
      checkRuleChain: async (list: Rule[], from: string) => {
        // Simple client-side implementation
        const maxRedirects = 5
        const enabledRules = list.filter((r) => r.enabled)
        const redirectURLs: string[] = []
        let currentURL = from

        for (let i = 0; i < maxRedirects; i++) {
          let matched = false

          for (const rule of enabledRules) {
            try {
              const regex = new RegExp(rule.from)
              if (regex.test(currentURL)) {
                const rewrittenURL = currentURL.replace(regex, rule.to)

                if (
                  rewrittenURL === from ||
                  redirectURLs.includes(rewrittenURL)
                ) {
                  redirectURLs.push(rewrittenURL)
                  return new CheckResult({
                    status: CheckStatus.StatusCircularRedirect,
                    urls: redirectURLs,
                  })
                }

                redirectURLs.push(rewrittenURL)
                currentURL = rewrittenURL
                matched = true
                break
              }
            } catch (e) {
              // Invalid regex
              continue
            }
          }

          if (!matched) {
            if (i === 0) {
              return new CheckResult({
                status: CheckStatus.StatusNotMatched,
                urls: [],
              })
            }
            return new CheckResult({
              status: CheckStatus.StatusMatched,
              urls: redirectURLs,
            })
          }
        }

        return new CheckResult({
          status: CheckStatus.StatusInfiniteRedirect,
          urls: redirectURLs,
        })
      },
    },
    dialog: {
      saveJsonFile: async (content: string, fileName: string) => {
        saveAs(new Blob([content], { type: 'application/json' }), fileName)
        return true
      },
      openJsonFile: async () => {
        return new Promise<string>((resolve, reject) => {
          const input = document.createElement('input')
          input.type = 'file'
          input.accept = '.json,application/json'
          input.onchange = (event: Event) => {
            const target = event.target as HTMLInputElement
            if (target.files && target.files.length > 0) {
              const file = target.files[0]
              const reader = new FileReader()
              reader.onload = (e) => {
                const result = e.target?.result
                if (typeof result === 'string') {
                  resolve(result)
                } else {
                  reject(new Error('Failed to read file'))
                }
              }
              reader.onerror = () => {
                reject(new Error('Failed to read file'))
              }
              reader.readAsText(file)
            } else {
              reject(new Error('No file selected'))
            }
          }
          input.click()
        })
      },
    },
    notification: {
      getEnabled: async () => {
        return Notification.permission === 'granted'
      },
      setEnabled: async (enabled: boolean) => {
        if (enabled) {
          if (Notification.permission !== 'granted') {
            await Notification.requestPermission()
          }
        } else {
          // No direct way to disable notifications, inform user
          alert(
            'To disable notifications, please change the settings in your browser.',
          )
        }
      },
      checkPermission: async () => {
        return Notification.permission === 'granted'
      },
      requestPermission: async () => {
        const permission = await Notification.requestPermission()
        return permission === 'granted'
      },
    },
  }
}
