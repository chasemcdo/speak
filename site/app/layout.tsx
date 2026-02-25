import type { Metadata } from "next";
import { IBM_Plex_Sans, IBM_Plex_Mono } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import "./globals.css";

const plexSans = IBM_Plex_Sans({
  variable: "--font-plex-sans",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

const plexMono = IBM_Plex_Mono({
  variable: "--font-plex-mono",
  subsets: ["latin"],
  weight: ["400", "500"],
});

const siteUrl = process.env.NEXT_PUBLIC_DOCS_BASE_URL ?? "https://getspeak.vercel.app";

export const metadata: Metadata = {
  title: {
    default: "Speak",
    template: "%s | Speak",
  },
  description:
    "Speak is a free, open-source macOS dictation app powered by Apple's on-device speech engine.",
  metadataBase: new URL(siteUrl),
  openGraph: {
    title: "Speak",
    description:
      "A free macOS dictation app that works on-device with a fast, clean workflow.",
    url: "/",
    siteName: "Speak",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Speak",
    description:
      "A free macOS dictation app powered by on-device transcription.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${plexSans.variable} ${plexMono.variable}`}>
        {children}
        <Analytics />
      </body>
    </html>
  );
}
