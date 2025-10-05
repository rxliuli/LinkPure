import { useState, useRef } from 'react'
import { ulid } from 'ulid'
import { Plus, Trash2, Edit, Download, Upload, Settings } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Textarea } from '@/components/ui/textarea'
import { Rule } from '@/lib/native/types'
import { isWails, native } from '@/lib/native'
import { CheckStatus } from '../../bindings/linkpure/internal/rules/models'
import { toast } from 'sonner'
import { useQuery, useMutation } from '@tanstack/react-query'
import { FaDiscord } from 'react-icons/fa'
import { Browser } from '@wailsio/runtime'

export function HomePage() {
  const [editingRule, setEditingRule] = useState<Rule | null>(null)
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [isSettingsOpen, setIsSettingsOpen] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  // Load rules using React Query
  const rulesQuery = useQuery({
    queryKey: ['rules'],
    queryFn: async () => {
      try {
        return await native().store.getRules()
      } catch (error) {
        console.error('Failed to load rules:', error)
        toast.error('Failed to load rules')
        throw error
      }
    },
  })
  const rules = rulesQuery.data ?? []

  // Load notification setting
  const notificationEnabledQuery = useQuery({
    queryKey: ['notificationEnabled'],
    queryFn: native().notification.getEnabled,
  })

  const [testUrl, setTestUrl] = useState('')
  const [testResult, setTestResult] = useState<string>('')
  useQuery({
    queryKey: [
      'testRule',
      editingRule?.from,
      editingRule?.to,
      editingRule?.enabled,
      testUrl,
    ],
    queryFn: async () => {
      if (!editingRule || !testUrl) {
        return undefined
      }

      const result = await native().rule.checkRuleChain(editingRule, testUrl)

      let testResult = ''
      switch (result.status) {
        case CheckStatus.StatusMatched:
          testResult = result.urls[result.urls.length - 1] || 'Matched'
          break
        case CheckStatus.StatusNotMatched:
          testResult = 'No match'
          break
        case CheckStatus.StatusCircularRedirect:
          testResult = `Circular redirect: ${result.urls.join(' → ')}`
          break
        case CheckStatus.StatusInfiniteRedirect:
          testResult = `Infinite redirect: ${result.urls.join(' → ')}`
          break
        default:
          testResult = 'Unknown status'
      }
      setTestResult(testResult)
      return testResult
    },
    enabled: !!editingRule && !!testUrl,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: false,
    retry: false,
  })

  const handleAddRule = () => {
    setEditingRule({
      id: ulid(),
      from: '',
      to: '',
      enabled: true,
    })
    setTestUrl('')
    setIsDialogOpen(true)
  }

  const handleEditRule = (rule: Rule) => {
    setEditingRule({ ...rule })
    setTestUrl('')
    setIsDialogOpen(true)
  }

  const deleteRuleMutation = useMutation({
    mutationFn: (id: string) => native().store.deleteRule(id),
    onSuccess: () => {
      rulesQuery.refetch()
      toast.success('Rule deleted')
    },
    onError: (error) => {
      console.error('Failed to delete rule:', error)
      toast.error('Failed to delete rule')
    },
  })

  const handleDeleteRule = (id: string) => {
    deleteRuleMutation.mutate(id)
  }

  const toggleRuleMutation = useMutation({
    mutationFn: (rule: Rule) => {
      const updated = { ...rule, enabled: !rule.enabled }
      return native().store.updateRule(updated)
    },
    onSuccess: () => {
      rulesQuery.refetch()
    },
    onError: (error) => {
      console.error('Failed to toggle rule:', error)
      toast.error('Failed to toggle rule')
    },
  })

  const handleToggleRule = (rule: Rule) => {
    toggleRuleMutation.mutate(rule)
  }

  const saveRuleMutation = useMutation({
    mutationFn: async ({
      rule,
      isUpdate,
    }: {
      rule: Rule
      isUpdate: boolean
    }) => {
      if (isUpdate) {
        await native().store.updateRule(rule)
        return 'updated'
      } else {
        await native().store.newRule(rule)
        return 'added'
      }
    },
    onSuccess: (action) => {
      rulesQuery.refetch()
      toast.success(`Rule ${action}`)
      setIsDialogOpen(false)
      setEditingRule(null)
    },
    onError: (error) => {
      console.error('Failed to save rule:', error)
      toast.error('Failed to save rule')
    },
  })

  const handleSaveRule = () => {
    if (!editingRule) return

    // Validate regex
    try {
      new RegExp(editingRule.from)
    } catch (error) {
      toast.error('Invalid regex pattern')
      return
    }

    if (!editingRule.from || !editingRule.to) {
      toast.error('From and To fields are required')
      return
    }

    const existingRule = rules.find((r) => r.id === editingRule.id)
    saveRuleMutation.mutate({ rule: editingRule, isUpdate: !!existingRule })
  }

  const handleExportRules = async () => {
    try {
      const dataStr = JSON.stringify(rules, null, 2)
      const fileName = `LinkPure-${new Date().toISOString().split('T')[0]}.json`
      const success = await native().dialog.saveJsonFile(dataStr, fileName)
      if (!success) {
        // User cancelled the dialog
        return
      }
      setIsSettingsOpen(false)
      toast.success('Rules exported successfully')
    } catch (error) {
      console.error('Failed to export rules:', error)
      toast.error('Failed to export rules')
    }
  }

  const handleImportRules = async () => {
    const str = await native().dialog.openJsonFile()
    if (!str) {
      // User cancelled the dialog
      return
    }
    const importedRules = JSON.parse(str) as Rule[]
    try {
      // Validate imported rules
      if (!Array.isArray(importedRules)) {
        toast.error('Invalid file format: expected an array of rules')
        return
      }

      for (const rule of importedRules.reverse()) {
        if (!rule.from || !rule.to) {
          toast.error('Invalid rule format: missing required fields')
          return
        }
        try {
          new RegExp(rule.from)
        } catch {
          toast.error(`Invalid regex pattern in rule: ${rule.from}`)
          return
        }
      }

      // Generate new IDs for imported rules to avoid conflicts
      const rulesWithNewIds = importedRules.map((rule) => ({
        ...rule,
        id: ulid(),
      }))

      // Save all imported rules
      for (const rule of rulesWithNewIds) {
        await native().store.newRule(rule)
      }

      rulesQuery.refetch()
      setIsSettingsOpen(false)
      toast.success(`Successfully imported ${rulesWithNewIds.length} rules`)
    } catch (error) {
      console.error('Failed to import rules:', error)
      toast.error('Failed to import rules: invalid JSON format')
    } finally {
      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
    }
  }

  const toggleNotificationMutation = useMutation({
    mutationFn: async (enabled: boolean) => {
      // Check if we're enabling notifications
      if (enabled) {
        // Check current permission
        const hasPermission = await native().notification.checkPermission()
        if (!hasPermission) {
          await native().notification.requestPermission()
        }
      }

      // Save the setting
      await native().notification.setEnabled(enabled)
      return enabled
    },
    onSuccess: (enabled) => {
      notificationEnabledQuery.refetch()
      if (enabled) {
        toast.info('Please allow notification permission in the system prompt')
        return
      }
      toast('Notifications disabled')
    },
    onError: (error: Error) => {
      console.error('Failed to toggle notifications:', error)
      if (error.message === 'Permission denied') {
        toast.error('Notification permission denied')
      } else {
        toast.error('Failed to change notification setting')
      }
    },
  })

  const handleToggleNotification = (enabled: boolean) => {
    toggleNotificationMutation.mutate(enabled)
  }

  return (
    <div className="min-h-screen bg-background p-6">
      <div className="max-w-4xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold">LinkPure</h1>
            <p className="text-muted-foreground">
              Apply custom URL rewrite rules automatically.
            </p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={handleAddRule}>
              <Plus />
              Add Rule
            </Button>
            <Button
              variant="outline"
              size="icon"
              onClick={() => setIsSettingsOpen(true)}
            >
              <Settings />
            </Button>
            <a
              href={'https://discord.gg/fErBc3wYrC'}
              target="_blank"
              rel="noreferrer"
              onClick={(ev) => {
                if (isWails()) {
                  ev.preventDefault()
                  Browser.OpenURL(ev.currentTarget.href)
                }
              }}
            >
              <Button
                className={'bg-blue-600 text-white hover:bg-blue-700'}
                size="sm"
              >
                <FaDiscord />
              </Button>
            </a>
          </div>
        </div>

        <div className="space-y-4">
          {!rules.length ? (
            <Card>
              <CardContent className="flex flex-col items-center justify-center py-12">
                <p className="text-muted-foreground mb-4">
                  No rules yet. Add your first rule to get started.
                </p>
                <Button onClick={handleAddRule}>
                  <Plus />
                  Add Rule
                </Button>
              </CardContent>
            </Card>
          ) : (
            rules.map((rule) => (
              <Card key={rule.id}>
                <CardHeader>
                  <div className="flex items-start justify-between">
                    <div className="flex-1 min-w-0">
                      <CardTitle className="font-mono text-sm break-all">
                        {rule.from}
                      </CardTitle>
                      <CardDescription className="font-mono text-xs break-all mt-1">
                        → {rule.to}
                      </CardDescription>
                    </div>
                    <div className="flex items-center gap-2 ml-4">
                      <Switch
                        checked={rule.enabled}
                        onCheckedChange={() => handleToggleRule(rule)}
                      />
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => handleEditRule(rule)}
                      >
                        <Edit />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => handleDeleteRule(rule.id)}
                      >
                        <Trash2 />
                      </Button>
                    </div>
                  </div>
                </CardHeader>
              </Card>
            ))
          )}
        </div>

        {/* Settings Dialog */}
        <Dialog open={isSettingsOpen} onOpenChange={setIsSettingsOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Settings</DialogTitle>
              <DialogDescription>
                Configure application preferences
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label htmlFor="notifications">Show Notifications</Label>
                  <p className="text-sm text-muted-foreground">
                    Get notified when URLs are rewritten
                  </p>
                </div>
                <Switch
                  id="notifications"
                  checked={notificationEnabledQuery.data ?? false}
                  onCheckedChange={handleToggleNotification}
                  disabled={toggleNotificationMutation.isPending}
                />
              </div>
              <div className="border-t pt-4 space-y-2">
                <Label className={'block'}>Import & Export</Label>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    onClick={handleImportRules}
                    className="flex-1"
                  >
                    <Upload />
                    Import
                  </Button>
                  <Button
                    variant="outline"
                    onClick={handleExportRules}
                    disabled={!rules.length}
                    className="flex-1"
                  >
                    <Download />
                    Export
                  </Button>
                </div>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Edit/Add Rule Dialog */}
        <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>
                {editingRule && rules.find((r) => r.id === editingRule.id)
                  ? 'Edit Rule'
                  : 'Add Rule'}
              </DialogTitle>
              <DialogDescription>
                Configure your URL redirect rule using regular expressions.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="from">From (Regex Pattern)</Label>
                <Textarea
                  id="from"
                  placeholder="^https://www\.google\.com/search\?q=(.*)$"
                  value={editingRule?.from || ''}
                  onChange={(e) =>
                    setEditingRule((prev) =>
                      prev ? { ...prev, from: e.target.value.trim() } : null,
                    )
                  }
                  className="font-mono text-sm"
                  rows={3}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="to">To (Replacement)</Label>
                <Textarea
                  id="to"
                  placeholder="https://duckduckgo.com/?q=$1"
                  value={editingRule?.to || ''}
                  onChange={(e) =>
                    setEditingRule((prev) =>
                      prev ? { ...prev, to: e.target.value.trim() } : null,
                    )
                  }
                  className="font-mono text-sm"
                  rows={3}
                />
              </div>

              <div className="flex items-center space-x-2">
                <Switch
                  id="enabled"
                  checked={editingRule?.enabled || false}
                  onCheckedChange={(checked) =>
                    setEditingRule((prev) =>
                      prev ? { ...prev, enabled: checked } : null,
                    )
                  }
                />
                <Label htmlFor="enabled">Enable this rule</Label>
              </div>

              <div className="border-t pt-4 space-y-2">
                <Label htmlFor="testUrl">Test URL (Live Preview)</Label>
                <Input
                  id="testUrl"
                  type={'url'}
                  placeholder="https://www.google.com/search?q=test"
                  value={testUrl}
                  onChange={(e) => setTestUrl(e.target.value)}
                  className="font-mono text-sm"
                />
                {testUrl && testResult && (
                  <div className="mt-2 p-3 rounded-md bg-muted">
                    <p className="text-xs text-muted-foreground mb-1">
                      Result:
                    </p>
                    <p className="font-mono text-sm break-all">{testResult}</p>
                  </div>
                )}
              </div>
            </div>

            <DialogFooter>
              <Button variant="outline" onClick={() => setIsDialogOpen(false)}>
                Cancel
              </Button>
              <Button onClick={handleSaveRule}>Save</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </div>
  )
}
