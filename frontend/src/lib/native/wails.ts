import { GreetService } from '../../../bindings/linkpure'
import { NativeApi } from './types'

export function wails(): NativeApi {
  return {
    store: {
      getRules: GreetService.GetRules,
      newRule: GreetService.NewRule,
      updateRule: GreetService.UpdateRule,
      deleteRule: GreetService.DeleteRule,
    },
    rule: {
      checkRuleChain: GreetService.CheckRuleChain,
    },
    dialog: {
      saveJsonFile: GreetService.SaveJsonFile,
      openJsonFile: GreetService.OpenJsonFile,
    },
    notification: {
      getEnabled: GreetService.GetNotificationEnabled,
      setEnabled: GreetService.SetNotificationEnabled,
      checkPermission: GreetService.CheckNotificationPermission,
      requestPermission: GreetService.RequestNotificationPermission,
    },
  }
}
