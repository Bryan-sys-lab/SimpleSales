import type { Metadata, Viewport } from 'next';
import './globals.css';
import { AppProviders } from '@/components/app-providers';
import { ThemeProvider } from '@/components/theme-provider';
import { ServiceWorkerRegistrar } from '@/components/sw-registrar';

export const metadata: Metadata = {
  title: 'SimplerAnalytics',
  description: 'Mobile-first analytics dashboard for tenant shops',
  applicationName: 'SimplerAnalytics',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'default',
    title: 'SimplerAnalytics',
  },
  formatDetection: { telephone: false },
  other: { 'mobile-web-app-capable': 'yes' },
  icons: {
    icon: '/icon.svg',
    apple: '/icon.svg',
  },
  manifest: '/manifest.webmanifest',
};

export const viewport: Viewport = {
  themeColor: '#a86f0a',
  width: 'device-width',
  initialScale: 1,
  maximumScale: 5,
  userScalable: true,
  viewportFit: 'cover',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="font-sans">
      <body className="antialiased"><ThemeProvider><AppProviders>{children}</AppProviders></ThemeProvider><ServiceWorkerRegistrar /></body>
    </html>
  );
}
