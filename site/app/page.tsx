import Link from "next/link";
import { SiteChrome } from "@/components/site-chrome";
import { siteConfig } from "@/lib/site-config";

const features = [
  {
    title: "On-device transcription",
    description:
      "Speech stays on your Mac using Apple's speech framework. No cloud pipeline is required.",
  },
  {
    title: "Global hotkey workflow",
    description:
      "Start dictation from any app with a single keypress, then paste directly back into your active field.",
  },
  {
    title: "Live overlay feedback",
    description:
      "Watch words appear in real time while volatile and final segments settle for a predictable UX.",
  },
  {
    title: "Free and open source",
    description:
      "No subscription and no paywalls. Inspect, run, and contribute on GitHub.",
  },
];

export default function Home() {
  return (
    <SiteChrome>
      <section className="hero">
        <div className="site-container hero-grid">
          <div>
            <p className="eyebrow">macOS Dictation</p>
            <h1>Dictate anywhere on Mac. Fast, local, and free.</h1>
            <p className="hero-copy">
              Speak wraps Apple&apos;s on-device speech stack in a focused UX:
              press a hotkey, talk, and paste clean text into any app.
            </p>
            <div className="cta-row">
              <a className="button button-primary" href={siteConfig.releasesUrl}>
                Download Latest Release
              </a>
              <a className="button button-secondary" href={siteConfig.githubRepo}>
                View Source
              </a>
            </div>
            <p className="subnote">
              Requires macOS 26+. Microphone and Accessibility permissions are
              required for full workflow.
            </p>
          </div>
          <aside className="hero-card">
            <h2>How it works</h2>
            <ol>
              <li>
                Press your hotkey (<code>fn</code> by default)
              </li>
              <li>Speak while the floating overlay streams text</li>
              <li>Confirm and paste into your active app</li>
            </ol>
            <Link href="/docs/quickstart">Read quick start</Link>
          </aside>
        </div>
      </section>

      <section className="feature-section">
        <div className="site-container">
          <h2>Built for everyday dictation</h2>
          <div className="feature-grid">
            {features.map((feature) => (
              <article key={feature.title} className="feature-card">
                <h3>{feature.title}</h3>
                <p>{feature.description}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="faq-section">
        <div className="site-container faq-grid">
          <article className="faq-card">
            <h3>Will audio be uploaded?</h3>
            <p>
              No. Speak is built around Apple&apos;s local speech APIs and is
              designed to run on-device.
            </p>
          </article>
          <article className="faq-card">
            <h3>What if macOS blocks launch?</h3>
            <p>
              Unsigned builds may require right-clicking the app and choosing{" "}
              <strong>Open</strong> on first launch.
            </p>
          </article>
          <article className="faq-card">
            <h3>Can I build from source?</h3>
            <p>
              Yes. Full source and build steps are in the repository README and
              docs.
            </p>
          </article>
        </div>
      </section>
    </SiteChrome>
  );
}
