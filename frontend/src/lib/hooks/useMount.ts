import { useEffectOnce } from './useEffectOnce'

const useMount = (fn: () => void) => {
  useEffectOnce(() => {
    fn()
  })
}

export { useMount }
