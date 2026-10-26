import type { Metadata } from 'next';
import './globals.css';

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
      <body className="antialiased">{children}</body>
    </html>
  );
}
