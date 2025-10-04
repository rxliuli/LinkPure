import { App } from '@/App'
import { createRootRoute, createRoute } from '@tanstack/react-router'
import { createRouter } from '@tanstack/react-router'
import { HomePage } from './routes'

const rootRoute = createRootRoute({
  component: App,
})

const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  component: HomePage,
})

const routeTree = rootRoute.addChildren([indexRoute])

export const router = createRouter({ routeTree })

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}
