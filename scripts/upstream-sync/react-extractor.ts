// @ts-nocheck
import type { ReactContract, ReactSurface } from './types.ts'
import { fileAtRev, listFilesAtRev } from './git.ts'

export function extractReactContract(rev: string): ReactContract {
  const generatedAt = new Date().toISOString()
  const surfaces: ReactSurface[] = []
  // Find relevant frontend files: packages/client/** and apps/web/**
  const allFiles = [
    ...listFilesAtRev(rev, 'packages/client'),
    ...listFilesAtRev(rev, 'apps/web'),
    ...listFilesAtRev(rev, 'packages/api'),
  ].filter(p => p.endsWith('.ts') || p.endsWith('.tsx'))

  for (const file of allFiles) {
    const content = fileAtRev(rev, file)
    if (!content) continue
    // Look for API usages: session/, settings/, llm/, workspace/, etc.
    const apiUses = [...content.matchAll(/['"](session\/[^'"]+|settings\/[^'"]+|workspace\/[^'"]+|llm\/[^'"]+|pluginInventory\/[^'"]+|agentPresets\/[^'"]+|host\/[^'"]+|remote\/[^'"]+|credentials\/[^'"]+)['"]/g)].map(m => m[1])
    const fetchUses = [...content.matchAll(/_postTypert\(\s*['"]([^'"]+)['"]/g)].map(m => m[1])
    const typertCalls = [...content.matchAll(/callMethod\(\s*['"]([^'"]+)['"]/g)].map(m => m[1])
    const combinedApis = [...new Set([...apiUses, ...fetchUses, ...typertCalls])]
    if (combinedApis.length === 0 && !content.includes('use') && !content.includes('event') && !content.includes('stream')) {
      // still may be surface if it's a component
      if (!file.includes('/ui-') && !file.includes('/client/')) continue
    }

    // Extract models/events/streams
    const models = [...content.matchAll(/model[A-Za-z]*|llm\.|provider/gi)].map(m => m[0]).slice(0, 3)
    const events = [...content.matchAll(/session\/event|session\/queue|session\/jobs|approval\/requested|question\/requested|host\/session/gi)].map(m => m[0]).slice(0, 3)
    const streams = [...content.matchAll(/events\.mux|events\.host|session\/follow|remote\.mux/gi)].map(m => m[0]).slice(0, 3)
    const stateSourceMatch = content.match(/use\w+Store|use\w+Provider|connectionState|liveSync|projection/gi)
    const lifecycle = content.match(/useEffect|useMemo|onOpen|handshake/gi) ? 'hooks lifecycle' : null

    // Only create surface if file looks like client/ui
    if (file.startsWith('packages/client/') || file.startsWith('apps/web/')) {
      const id = file.replace(/\//g, '.').replace(/\.[^.]+$/, '')
      surfaces.push({
        id,
        sourceFile: file,
        apiUsed: combinedApis.slice(0, 10),
        requestShape: extractShape(content, 'request'),
        responseShape: extractShape(content, 'response'),
        modelUsed: [...new Set(models)].slice(0, 5),
        eventUsed: [...new Set(events)].slice(0, 5),
        streamUsed: [...new Set(streams)].slice(0, 5),
        stateSource: stateSourceMatch ? stateSourceMatch[0] : null,
        currentValueSource: content.includes('current') || content.includes('cursor') || content.includes('throughSeq') ? 'snapshot cursor' : null,
        fallbackBehavior: content.includes('catch') || content.includes('fallback') || content.includes('retry') ? 'fallback present' : null,
        errorBehavior: content.includes('error') ? 'error handled' : null,
        lifecycle,
      })
    }
  }

  // Also specifically check client connection and host describe flows
  // Add a surface for key known patterns if not already captured
  const knownSurfaces: ReactSurface[] = [
    { id: 'session.list', sourceFile: 'packages/client/connection/src', apiUsed: ['session/list'], requestShape: '{}', responseShape: '{items: SessionSummary[]}', modelUsed: [], eventUsed: [], streamUsed: [], stateSource: 'connection', currentValueSource: null, fallbackBehavior: null, errorBehavior: 'throws RemoteMethodException', lifecycle: 'unary' },
    { id: 'session.page', sourceFile: 'packages/client/connection/src', apiUsed: ['session/page'], requestShape: '{address, throughSeq, beforeSeq}', responseShape: '{records, projections}', modelUsed: [], eventUsed: ['session/event'], streamUsed: ['session/follow'], stateSource: 'LiveHistory', currentValueSource: 'snapshot.cursor throughSeq', fallbackBehavior: 'no synthetic cursor', errorBehavior: 'requires cursor', lifecycle: 'follow snapshot' },
    { id: 'settings.describe', sourceFile: 'packages/client/ui-settings/src', apiUsed: ['settings/describe'], requestShape: '{}', responseShape: '{namespaces: List}', modelUsed: [], eventUsed: ['settings/updated'], streamUsed: [], stateSource: 'SettingsScope', currentValueSource: 'describe namespaces', fallbackBehavior: 'List vs Map handling', errorBehavior: null, lifecycle: 'describe then mutate' },
  ]
  for (const ks of knownSurfaces) {
    if (!surfaces.some(s => s.id === ks.id)) surfaces.push(ks as ReactSurface)
  }

  surfaces.sort((a, b) => a.id.localeCompare(b.id))
  return {
    generatedAt,
    rev,
    surfaces,
    totalSurfaces: surfaces.length,
  }
}

function extractShape(content: string, which: string): string | null {
  const m = content.match(new RegExp(`${which}[^\\{]{0,40}\\{[^\\}]{0,120}\\}`, 'i'))
  return m ? m[0].slice(0, 180) : null
}
