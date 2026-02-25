import Link from "next/link";
import { SiteChrome } from "@/components/site-chrome";
import { siteConfig } from "@/lib/site-config";

const features = [
  {
    title: "Local-first speech pipeline",
    description:
      "Powered by Apple's SpeechAnalyzer and FoundationModels. Audio capture, transcription, and text cleanup all run on-device.",
  },
  {
    title: "Global hotkey control loop",
    description:
      "Trigger from any app, stream partial results live, then commit into the focused text field in one motion.",
  },
  {
    title: "Live volatile + final rendering",
    description:
      "See rapid in-progress text and stable final segments so dictation feels responsive without being noisy.",
  },
  {
    title: "Inspectable and scriptable",
    description:
      "Open source by default. Clone it, build it, and evolve the workflow for your own team.",
  },
];

export default function Home() {
  return (
    <SiteChrome>
      <section className="hero">
        <div className="site-container hero-grid">
          <div>
            <p className="eyebrow">Native macOS App</p>
            <h1>Native macOS dictation that never leaves your machine.</h1>
            <p className="hero-copy">
              Speak wraps Apple&apos;s on-device speech APIs in a fast command-loop:
              hold <code>fn</code>, dictate, release, and your text lands where
              you were already working.
            </p>
            <div className="cta-row">
              <a className="button button-primary" href={siteConfig.latestDmgUrl}>
                Download for Mac
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
          <div className="hero-visual-wrap">
            <div className="hero-orb hero-orb-a" />
            <div className="hero-orb hero-orb-b" />
            <aside className="hero-card hero-card-visual">
              <div className="visual-topbar">
                <span />
                <span />
                <span />
              </div>
              <div className="visual-title">Live Session / Speak Overlay</div>
              <div className="visual-line visual-line-1" />
              <div className="visual-line visual-line-2" />
              <div className="visual-line visual-line-3" />
              <div className="wave-row">
                <span />
                <span />
                <span />
                <span />
                <span />
                <span />
              </div>
              <div className="visual-footer">
                <p>Input: MacBook Pro Microphone</p>
                <p>Engine: SpeechAnalyzer (on-device)</p>
              </div>
            </aside>
            <div className="hero-reflection" aria-hidden />
          </div>
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

      <section className="under-the-hood-section">
        <div className="site-container">
          <h2>Under the hood</h2>
          <div className="under-the-hood-card">
            <ul className="under-the-hood-list">
              <li>
                <strong>SpeechAnalyzer</strong> — Apple&apos;s on-device
                speech-to-text engine (no Whisper, no cloud transcription)
              </li>
              <li>
                <strong>FoundationModels</strong> — Apple&apos;s on-device LLM
                for context-aware text cleanup
              </li>
              <li>
                <strong>Accessibility APIs</strong> — reads surrounding text for
                spelling and formatting context
              </li>
            </ul>
            <p className="under-the-hood-note">
              Most dictation tools send audio to cloud APIs. Speak runs entirely
              on your Mac — no network required, no data leaves the device.
            </p>
          </div>
        </div>
      </section>

      <section className="faq-section">
        <div className="site-container faq-grid">
          <article className="faq-card">
            <h3>Will audio be uploaded?</h3>
            <p>
              No. Speak uses Apple&apos;s SpeechAnalyzer for transcription and
              FoundationModels for text processing — both run entirely on your
              Mac. No audio or text is sent to any server.
            </p>
          </article>
          <article className="faq-card">
            <h3>What if macOS blocks launch?</h3>
            <p>
              Open System Settings &gt; Privacy &amp; Security and click{" "}
              <strong>Open Anyway</strong> for Speak.
            </p>
          </article>
          <article className="faq-card">
            <h3>Can I build from source?</h3>
            <p>
              Yes. Clone, run <code>make app</code>, and ship your own fork.
            </p>
          </article>
        </div>
      </section>
      <section className="platform-strip">
        <div className="site-container strip-row">
          <p>Built for engineers, writers, and anyone who needs fast, private dictation across any app.</p>
          <Link href="/docs/quickstart">Read setup docs</Link>
        </div>
      </section>
    </SiteChrome>
  );
}
