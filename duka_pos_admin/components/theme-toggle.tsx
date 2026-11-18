'use client';

import { useTheme } from './theme-provider';

export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  return (
    <select
      value={theme}
      onChange={(e) => setTheme(e.target.value as 'light' | 'dark' | 'system')}
      className="rounded-md border border-base-300 bg-white px-2 py-1 text-xs text-base-700 focus:outline-none focus:ring-2 focus:ring-accent-600 dark:bg-base-800 dark:text-base-200 dark:border-base-600"
      aria-label="Theme"
    >
      <option value="light">Light</option>
      <option value="dark">Dark</option>
      <option value="system">System</option>
    </select>
  );
}
