import Link from "next/link";
import { SiteChrome } from "@/components/site-chrome";

type DocsShellProps = {
  title: string;
  intro: string;
  children: React.ReactNode;
};

const docsLinks = [
  { href: "/docs/quickstart", label: "Quick Start" },
  { href: "/docs/permissions", label: "Permissions" },
  { href: "/docs/troubleshooting", label: "Troubleshooting" },
];

export function DocsShell({ title, intro, children }: DocsShellProps) {
  return (
    <SiteChrome>
      <section className="docs-section">
        <div className="site-container docs-grid">
          <aside className="docs-nav">
            <p>Docs</p>
            {docsLinks.map((link) => (
              <Link key={link.href} href={link.href}>
                {link.label}
              </Link>
            ))}
          </aside>
          <article className="docs-card">
            <h1>{title}</h1>
            <p className="docs-intro">{intro}</p>
            {children}
          </article>
        </div>
      </section>
    </SiteChrome>
  );
}
