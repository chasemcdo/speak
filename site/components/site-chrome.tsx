import Image from "next/image";
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
            <Image
              src="/speak-mark.svg"
              alt=""
              aria-hidden
              className="brand-mark-icon"
              width={26}
              height={26}
            />
            <span>Speak</span>
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
          <p>Speak is a free, open-source native macOS app built with Swift.</p>
          <p>GNU GPL v3</p>
        </div>
      </footer>
    </div>
  );
}
