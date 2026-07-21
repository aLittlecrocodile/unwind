/// <reference types="vite/client" />

interface Window {
  workerBuddy: import('./src/lib/electronApi').WorkerBuddyApi
}
