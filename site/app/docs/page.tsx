import Link from "next/link";
import { SiteChrome } from "@/components/site-chrome";

const pages = [
  {
    href: "/docs/quickstart",
    title: "Quick Start",
    description: "Install Speak, grant permissions, and start dictating in under 5 minutes.",
  },
  {
    href: "/docs/permissions",
    title: "Permissions",
    description: "Understand why microphone, speech recognition, and accessibility are needed.",
  },
  {
    href: "/docs/troubleshooting",
    title: "Troubleshooting",
    description: "Fix common setup and workflow issues quickly.",
  },
];

export default function DocsHomePage() {
  return (
    <SiteChrome>
      <section className="docs-home">
        <div className="site-container">
          <h1>Documentation</h1>
          <p>
            Lightweight setup and support docs for users getting started with
            Speak.
          </p>
          <div className="docs-home-grid">
            {pages.map((page) => (
              <Link className="docs-home-card" key={page.href} href={page.href}>
                <h2>{page.title}</h2>
                <p>{page.description}</p>
              </Link>
            ))}
          </div>
        </div>
      </section>
    </SiteChrome>
  );
}
