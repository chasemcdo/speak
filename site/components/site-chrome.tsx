import Link from "next/link";

type SiteChromeProps = {
  children: React.ReactNode;
};

export function SiteChrome({ children }: SiteChromeProps) {
  return (
    <div className="site-shell">
      <header className="site-header">
        <div className="site-container nav-row">
          <Link href="/" className="brand-mark">
            Speak
          </Link>
          <nav className="main-nav">
            <Link href="/docs">Docs</Link>
            <Link href="/privacy">Privacy</Link>
            <a href="https://github.com/chasemcdo/speak">GitHub</a>
          </nav>
        </div>
      </header>
      <main>{children}</main>
      <footer className="site-footer">
        <div className="site-container footer-row">
          <p>Speak is free, open source, and designed for macOS.</p>
          <p>GNU GPL v3</p>
        </div>
      </footer>
    </div>
  );
}
