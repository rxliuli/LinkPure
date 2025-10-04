import { browser } from './browser'
import { wails } from './wails'

declare global {
  interface Window {
    runtime?: {}
  }
}

export function isWails(): boolean {
  return typeof window !== 'undefined' && 'wails' in window
}

// TODO wails bug, register wails global variable after iife
export const native = () => (isWails() ? wails() : browser())
