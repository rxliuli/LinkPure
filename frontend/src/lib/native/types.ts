import {
  CheckResult,
  LocalRule,
} from '../../../bindings/linkpure/internal/rules/models'

export type Rule = LocalRule

export interface NativeApi {
  store: {
    getRules: () => Promise<Rule[]>
    newRule: (rule: Rule) => Promise<void>
    updateRule: (rule: Rule) => Promise<void>
    deleteRule: (id: string) => Promise<void>
  }
  rule: {
    checkRuleChain: (list: Rule, from: string) => Promise<CheckResult>
  }
  dialog: {
    saveJsonFile: (content: string, fileName: string) => Promise<boolean>
    openJsonFile: () => Promise<string>
  }
  notification: {
    getEnabled: () => Promise<boolean>
    setEnabled: (enabled: boolean) => Promise<void>
    checkPermission: () => Promise<boolean>
    requestPermission: () => Promise<boolean>
  }
}
