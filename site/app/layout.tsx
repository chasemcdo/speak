import type { Metadata } from "next";
import { IBM_Plex_Sans, IBM_Plex_Mono } from "next/font/google";
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
    "Speak is a free, open-source native macOS dictation app powered by Apple's on-device SpeechAnalyzer. No cloud, no subscription — just fast, private voice-to-text.",
  metadataBase: new URL(siteUrl),
  openGraph: {
    title: "Speak",
    description:
      "A free, native macOS dictation app. Powered by Apple's on-device speech engine — no cloud, no Whisper, no subscription.",
    url: "/",
    siteName: "Speak",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Speak",
    description:
      "Free native macOS dictation powered by Apple's on-device SpeechAnalyzer. No cloud, no subscription.",
    site: "@get_speak",
    creator: "@get_speak",
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
      </body>
    </html>
  );
}
