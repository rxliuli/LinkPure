import { Outlet } from '@tanstack/react-router'
import { TanStackRouterDevtools } from '@tanstack/react-router-devtools'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import { ThemeProvider } from './components/theme/ThemeProvider'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: Infinity, // Since we're managing our own invalidation
      refetchOnWindowFocus: false,
    },
  },
})

export function App() {
  return (
    <>
      <ThemeProvider>
        <QueryClientProvider client={queryClient}>
          <Outlet />
        </QueryClientProvider>

        <Toaster richColors closeButton />
        {import.meta.env.DEV && <TanStackRouterDevtools />}
      </ThemeProvider>
    </>
  )
}
