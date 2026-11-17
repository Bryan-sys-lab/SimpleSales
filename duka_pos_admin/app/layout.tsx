import type { Metadata } from 'next';
import './globals.css';
import { AppProviders } from '@/components/app-providers';

export const metadata: Metadata = {
  title: 'Duka POS — Systems Admin',
  description: 'Systems administration dashboard for Duka POS tenant shops',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="font-sans">
      <body className="antialiased"><AppProviders>{children}</AppProviders></body>
    </html>
  );
}
