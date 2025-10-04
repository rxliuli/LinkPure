import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { cn } from '@/lib/utils'
import { ChevronDown, LucideIcon } from 'lucide-react'
import { ReactNode } from 'react'

export interface SplitButtonOption {
  value: string
  label: string
  icon?: LucideIcon
}

interface SplitButtonProps {
  // 主按钮属性
  children: ReactNode
  onDefaultClick: () => void

  // 下拉选项
  options: SplitButtonOption[]
  onOptionClick: (value: string) => void

  // 样式属性
  size?: 'default' | 'sm' | 'lg'
  variant?: 'default' | 'destructive' | 'outline' | 'secondary' | 'ghost' | 'link'
  className?: string
  disabled?: boolean

  // 下拉菜单属性
  align?: 'start' | 'center' | 'end'
  side?: 'top' | 'right' | 'bottom' | 'left'
}

export function SplitButton({
  children,
  onDefaultClick,
  options,
  onOptionClick,
  size = 'default',
  variant = 'outline',
  className,
  disabled = false,
  align = 'end',
  side = 'bottom',
}: SplitButtonProps) {
  return (
    <div className={cn('flex', className)}>
      <Button
        size={size}
        variant={variant}
        className="rounded-r-none border-r-0"
        onClick={onDefaultClick}
        disabled={disabled}
      >
        {children}
      </Button>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            size={size}
            variant={variant}
            className={cn(
              'rounded-l-none px-2',
              size === 'sm' && 'w-7 px-0',
              size === 'default' && 'w-9 px-0',
              size === 'lg' && 'w-11 px-0',
            )}
            disabled={disabled}
          >
            <ChevronDown
              className={cn(size === 'sm' && 'h-3 w-3', size === 'default' && 'h-4 w-4', size === 'lg' && 'h-5 w-5')}
            />
          </Button>
        </DropdownMenuTrigger>

        <DropdownMenuContent align={align} side={side}>
          {options.map((option) => (
            <DropdownMenuItem
              key={option.value}
              onClick={() => onOptionClick(option.value)}
              className="gap-2"
              disabled={disabled}
            >
              {option.icon && <option.icon className="h-4 w-4" />}
              <span>{option.label}</span>
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  )
}
